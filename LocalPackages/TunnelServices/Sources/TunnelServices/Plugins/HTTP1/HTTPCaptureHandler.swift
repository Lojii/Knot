//
//  HTTPCaptureHandler.swift
//  TunnelServices
//
//  Unified HTTP request/response capture handler.
//  Replaces the old HTTPHandler + ExchangeHandler pair.
//
//  Flow:
//  1. Receives HTTP request from client (via proxy pipeline)
//  2. Opens connection to real server
//  3. Forwards request to server
//  4. Receives response from server
//  5. Records both request and response via SessionRecorder
//  6. Relays response back to client
//

import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import NIOTLS
import NIOHTTPCompression
import NIOExtras

public final class HTTPCaptureHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private let recorder: SessionRecorder
    private let isSSL: Bool
    private var clientChannel: Channel?      // outbound connection to real server
    private var serverChannel: Channel?      // inbound connection from client
    private var pendingRequestParts = [Any]()
    private var connected = false
    private var request: NetRequest?
    private var wsInterceptor: WebSocketUpgradeInterceptor?
    private var isWebSocketUpgrade = false

    public init(recorder: SessionRecorder, isSSL: Bool) {
        self.recorder = recorder
        self.isSSL = isSSL
    }

    // MARK: - Inbound (from client)

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if serverChannel == nil {
            serverChannel = context.channel
        }

        let part = unwrapInboundIn(data)

        switch part {
        case .head(var head):
            // Extract request info and prepare for forwarding
            if request == nil {
                request = NetRequest(head)
                if isSSL { request?.ssl = true }
            }

            // Remove proxy-specific headers
            head.headers = NetRequest.removeProxyHead(heads: head.headers)

            // Detect WebSocket upgrade
            let connection = head.headers["Connection"].first?.lowercased() ?? ""
            let upgrade = head.headers["Upgrade"].first?.lowercased() ?? ""
            if connection.contains("upgrade") && upgrade == "websocket" {
                isWebSocketUpgrade = true
                wsInterceptor = WebSocketUpgradeInterceptor(recorder: recorder, task: recorder.task, isSSL: isSSL)
                recorder.session.schemes = isSSL ? "WSS" : "WS"
            }

            // Record
            recorder.recordRequestHead(head, localAddress: context.channel.remoteAddress, isSSL: isSSL)
            if !isWebSocketUpgrade {
                if isSSL { recorder.session.schemes = "Https" } else { recorder.session.schemes = "Http" }
            }

            // Fix relative URI for plain HTTP proxy requests
            if !head.uri.starts(with: "/"), let hostStr = head.headers["Host"].first {
                if let newUri = head.uri.components(separatedBy: hostStr).last {
                    head.uri = newUri
                }
            }

            // Start connecting to the real server
            if clientChannel == nil {
                connectToServer(context: context)
            }

            enqueueOrSend(.head(head))

        case .body(let body):
            recorder.recordRequestBody(body)
            enqueueOrSend(.body(.byteBuffer(body)))

        case .end(let trailers):
            recorder.recordRequestEnd()
            enqueueOrSend(.end(trailers))
        }

        context.fireChannelRead(data)
    }

    // MARK: - Server Connection

    private func connectToServer(context: ChannelHandlerContext) {
        guard let req = request, let eventLoop = serverChannel?.eventLoop else { return }

        let responseHandler = ResponseRelayHandler(
            recorder: recorder,
            serverChannel: serverChannel,
            wsInterceptor: wsInterceptor
        )

        var channelInitializer: ((Channel) -> EventLoopFuture<Void>)

        if req.ssl {
            channelInitializer = { [weak self] channel -> EventLoopFuture<Void> in
                let tlsConfig = TLSConfiguration.forClient(applicationProtocols: ["http/1.1"])
                guard let sslContext = try? NIOSSLContext(configuration: tlsConfig) else {
                    return channel.eventLoop.makeFailedFuture(
                        ServerChannelError(errCode: -1, localizedDescription: "SSL context failed")
                    )
                }
                let sniName = req.host.isIPAddress() ? nil : req.host
                guard let sslHandler = try? NIOSSLClientHandler(context: sslContext, serverHostname: sniName) else {
                    return channel.eventLoop.makeFailedFuture(
                        ServerChannelError(errCode: -1, localizedDescription: "SSL handler failed")
                    )
                }

                let alpnHandler = ApplicationProtocolNegotiationHandler { result -> EventLoopFuture<Void> in
                    self?.recorder.recordHandshakeComplete()
                    self?.connected = true
                    return channel.pipeline.addHandler(HTTPRequestEncoder(), name: "client.requestEncoder").flatMap {
                        channel.pipeline.addHandler(
                            ByteToMessageHandler(HTTPResponseDecoder()),
                            name: "client.responseDecoder"
                        )
                    }.flatMap {
                        channel.pipeline.addHandler(
                            NIOHTTPResponseDecompressor(limit: .ratio(10)),
                            name: "client.decompressor"
                        )
                    }.flatMap {
                        channel.pipeline.addHandler(responseHandler, name: "client.responseRelay")
                    }.flatMap { _ -> EventLoopFuture<Void> in
                        self?.flushPendingParts()
                        return channel.pipeline.removeHandler(name: "xxxxxxxxxxxxx")  // dummy to complete chain
                    }
                }

                return channel.pipeline.addHandler(sslHandler, name: "client.ssl").flatMap {
                    channel.pipeline.addHandler(alpnHandler, name: "client.alpn")
                }
            }
        } else {
            channelInitializer = { [weak self] channel -> EventLoopFuture<Void> in
                return channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(
                        NIOHTTPResponseDecompressor(limit: .ratio(10)),
                        name: "client.decompressor"
                    )
                }.flatMap {
                    channel.pipeline.addHandler(responseHandler, name: "client.responseRelay")
                }.map {
                    self?.connected = true
                    self?.flushPendingParts()
                }
            }
        }

        let bootstrap = ClientBootstrap(group: eventLoop)
            .channelInitializer(channelInitializer)

        let future = bootstrap.connect(host: req.host, port: req.port)
        future.whenComplete { [weak self] result in
            switch result {
            case .success(let channel):
                self?.clientChannel = channel
                self?.recorder.recordConnected(remoteAddress: channel.remoteAddress)
                if !req.ssl {
                    self?.connected = true
                    self?.flushPendingParts()
                }
            case .failure(let error):
                self?.recorder.recordConnectionError(error, host: req.host, port: req.port)
                self?.serverChannel?.close(promise: nil)
            }
        }
    }

    // MARK: - Request Forwarding

    private func enqueueOrSend(_ part: HTTPClientRequestPart) {
        if connected, let channel = clientChannel, channel.isActive {
            sendPart(part, to: channel)
        } else {
            pendingRequestParts.append(part)
        }
    }

    private func flushPendingParts() {
        guard let channel = clientChannel, channel.isActive else { return }
        for part in pendingRequestParts {
            if let p = part as? HTTPClientRequestPart {
                sendPart(p, to: channel)
            }
        }
        pendingRequestParts.removeAll()
    }

    private func sendPart(_ part: HTTPClientRequestPart, to channel: Channel) {
        switch part {
        case .head(let head):
            let clientHead = HTTPRequestHead(version: head.version, method: head.method, uri: head.uri, headers: head.headers)
            channel.writeAndFlush(HTTPClientRequestPart.head(clientHead), promise: nil)
            recorder.addUpload(100)  // approximate header size

        case .body(let ioData):
            if case .byteBuffer(let buf) = ioData {
                recorder.addUpload(buf.readableBytes)
            }
            channel.writeAndFlush(HTTPClientRequestPart.body(ioData), promise: nil)

        case .end(let trailers):
            channel.writeAndFlush(HTTPClientRequestPart.end(trailers), promise: nil)
        }
    }

    // MARK: - Lifecycle

    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    public func channelUnregistered(context: ChannelHandlerContext) {
        clientChannel?.close(mode: .all, promise: nil)
        recorder.recordClosed()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        clientChannel?.close(mode: .all, promise: nil)
        context.close(mode: .all, promise: nil)
    }
}

// MARK: - Response Relay (lives in the outbound channel to real server)

/// Receives HTTP responses from the real server and relays them back to the client.
/// Also records response data via SessionRecorder.
/// Detects 101 Switching Protocols to trigger WebSocket upgrade.
final class ResponseRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let recorder: SessionRecorder
    private weak var serverChannel: Channel?
    private var wsInterceptor: WebSocketUpgradeInterceptor?

    init(recorder: SessionRecorder, serverChannel: Channel?,
         wsInterceptor: WebSocketUpgradeInterceptor? = nil) {
        self.recorder = recorder
        self.serverChannel = serverChannel
        self.wsInterceptor = wsInterceptor
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            recorder.recordResponseHead(head)
            recorder.addDownload(200)
            serverChannel?.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)

            // Detect WebSocket upgrade (101 Switching Protocols)
            if head.status == .switchingProtocols {
                AxLogger.log("WebSocket 101 detected, switching to WS mode", level: .Info)
            }

        case .body(let body):
            recorder.recordResponseBody(body)
            recorder.addDownload(body.readableBytes)
            serverChannel?.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(body)), promise: nil)

        case .end(let trailers):
            recorder.recordResponseEnd()

            // If this was a 101 upgrade, switch to WebSocket
            if recorder.session.schemes == "WS" || recorder.session.schemes == "WSS" {
                serverChannel?.writeAndFlush(HTTPServerResponsePart.end(trailers), promise: nil)
                // Trigger WebSocket pipeline transformation
                if let serverCh = serverChannel, let interceptor = wsInterceptor {
                    interceptor.performWebSocketUpgrade(
                        context: context,
                        clientChannel: context.channel
                    )
                }
                return
            }

            let promise = serverChannel?.eventLoop.makePromise(of: Void.self)
            serverChannel?.writeAndFlush(HTTPServerResponsePart.end(trailers), promise: promise)
            promise?.futureResult.whenComplete { [weak self] _ in
                self?.serverChannel?.close(mode: .all, promise: nil)
            }
            context.channel.close(mode: .all, promise: nil)
        }
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        serverChannel?.close(mode: .all, promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        serverChannel?.close(mode: .all, promise: nil)
        context.channel.close(mode: .all, promise: nil)
    }
}
