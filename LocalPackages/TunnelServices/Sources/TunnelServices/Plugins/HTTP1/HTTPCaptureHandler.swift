//
//  HTTPCaptureHandler.swift
//  TunnelServices
//
//  Unified HTTP request/response capture handler.
//  Replaces the old HTTPHandler + ExchangeHandler pair.
//
//  Flow:
//  1. Receives HTTP request from client (via proxy pipeline)
//  2. Opens connection to real server (or reuses existing one for keep-alive)
//  3. Forwards request to server
//  4. Receives response from server
//  5. Records both request and response via SessionRecorder
//  6. Relays response back to client
//
//  Supports HTTP/1.1 keep-alive and pipelining:
//  - Outbound connection is reused across requests to the same server
//  - Each request/response cycle gets its own SessionRecorder
//  - Idle timeout closes keep-alive connections after inactivity
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

    private var recorder: SessionRecorder
    private let isSSL: Bool
    private let targetPort: Int?
    private var clientChannel: Channel?      // outbound connection to real server
    private var serverChannel: Channel?      // inbound connection from client
    private var pendingRequestParts = [Any]()
    private var connected = false
    private var request: NetRequest?
    private var wsInterceptor: WebSocketUpgradeInterceptor?
    private var isWebSocketUpgrade = false

    // Keep-alive state
    private var responseRelayHandler: ResponseRelayHandler?
    private weak var _channel: Channel?       // weak ref for idle timeout scheduling
    private var idleTimeoutTask: Scheduled<Void>?
    private var responseCompleted = false      // tracks whether current cycle completed normally
    private var lastCompletedRequest: NetRequest?  // saved for pool checkin after resetForNextRequest clears request

    public init(recorder: SessionRecorder, isSSL: Bool, targetPort: Int? = nil) {
        self.recorder = recorder
        self.isSSL = isSSL
        self.targetPort = targetPort
    }

    // MARK: - Inbound (from client)

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if serverChannel == nil {
            serverChannel = context.channel
            _channel = context.channel
        }

        let part = unwrapInboundIn(data)

        switch part {
        case .head(var head):
            // Cancel idle timeout on new request
            idleTimeoutTask?.cancel()
            idleTimeoutTask = nil
            responseCompleted = false

            // Extract request info and prepare for forwarding
            AxLogger.log("[HTTPCapture] request: \(head.method) \(head.uri) isSSL=\(isSSL)", level: .Warning)
            request = NetRequest(head)
            if isSSL {
                request?.ssl = true
                // NetRequest defaults port to 80 because ssl wasn't set during init.
                // Use the original port from CONNECT request if available,
                // otherwise default to 443 for SSL.
                if let tp = targetPort {
                    request?.port = tp
                } else if request?.port == 80 {
                    request?.port = 443
                }
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

            // Start connecting to the real server (or reuse existing connection).
            // Recorder swap into ResponseRelayHandler is done by resetForNextRequest().
            if clientChannel == nil || !(clientChannel?.isActive ?? false) {
                clientChannel = nil
                connected = false
                responseRelayHandler = nil
                connectToServer(context: context, reuseFromPool: true)
            }

            enqueueOrSend(.head(head))

        case .body(let body):
            recorder.recordRequestBody(body)
            enqueueOrSend(.body(.byteBuffer(body)))

        case .end(let trailers):
            recorder.recordRequestEnd()
            enqueueOrSend(.end(trailers))
        }
    }

    // MARK: - Server Connection

    private func connectToServer(context: ChannelHandlerContext, reuseFromPool: Bool = false) {
        guard let req = request, let eventLoop = serverChannel?.eventLoop else { return }

        let responseHandler = ResponseRelayHandler(
            recorder: recorder,
            serverChannel: serverChannel,
            wsInterceptor: wsInterceptor
        )
        self.responseRelayHandler = responseHandler

        // Set up keep-alive callback.
        // Non-keep-alive closing is handled by ResponseRelayHandler itself.
        responseHandler.onResponseComplete = { [weak self] keepAlive in
            guard let self = self else { return }
            self.responseCompleted = true
            if keepAlive {
                self.resetForNextRequest()
                self.scheduleIdleTimeout()
            }
        }

        // Try to reuse a pooled connection before creating a new one.
        if reuseFromPool {
            let poolKey = ConnectionPoolKey(host: req.host, port: req.port, isSSL: req.ssl)
            if let pooled = recorder.task.connectionPool.checkout(key: poolKey) {
                AxLogger.log("[HTTPCapture] Reusing pooled connection to \(req.host):\(req.port)", level: .Info)
                self.clientChannel = pooled

                // Swap the ResponseRelayHandler in the pooled channel's pipeline.
                // Remove old relay handler (if present) and add the new one.
                pooled.pipeline.removeHandler(name: "client.responseRelay").whenComplete { [weak self] _ in
                    pooled.pipeline.addHandler(responseHandler, name: "client.responseRelay").whenComplete { [weak self] result in
                        guard let self = self else { return }
                        switch result {
                        case .success:
                            self.connected = true
                            self.recorder.recordConnected(remoteAddress: pooled.remoteAddress)
                            self.flushPendingParts()
                        case .failure:
                            // Pipeline swap failed; fall back to new connection
                            AxLogger.log("[HTTPCapture] Pooled channel pipeline swap failed, creating new connection", level: .Warning)
                            self.clientChannel = nil
                            self.connected = false
                            self.connectToServer(context: context, reuseFromPool: false)
                        }
                    }
                }
                return
            }
        }

        var channelInitializer: ((Channel) -> EventLoopFuture<Void>)

        if req.ssl {
            channelInitializer = { [weak self] channel -> EventLoopFuture<Void> in
                AxLogger.log("[HTTPCapture] Setting up outbound TLS to \(req.host):\(req.port)", level: .Warning)
                let tlsConfig = TLSConfiguration.forClient(applicationProtocols: ["http/1.1"])
                guard let sslContext = try? NIOSSLContext(configuration: tlsConfig) else {
                    AxLogger.log("[HTTPCapture] Failed to create outbound SSL context for \(req.host)", level: .Error)
                    return channel.eventLoop.makeFailedFuture(
                        ServerChannelError(errCode: -1, localizedDescription: "SSL context failed")
                    )
                }
                let sniName = req.host.isIPAddress() ? nil : req.host
                guard let sslHandler = try? NIOSSLClientHandler(context: sslContext, serverHostname: sniName) else {
                    AxLogger.log("[HTTPCapture] Failed to create outbound SSL handler for \(req.host)", level: .Error)
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
                    }.map { _ in
                        self?.flushPendingParts()
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

    // MARK: - Keep-Alive Cycle Management

    /// Reset per-request state for the next request on a keep-alive connection.
    /// Creates a new SessionRecorder and swaps it into the ResponseRelayHandler.
    /// The outbound clientChannel is kept open.
    private func resetForNextRequest() {
        // Create new recorder for the next cycle and swap into ResponseRelayHandler
        let newRecorder = SessionRecorder(task: recorder.task)
        self.recorder = newRecorder
        responseRelayHandler?.swapRecorder(newRecorder)

        // Save last request info for pool checkin on disconnect
        lastCompletedRequest = request

        // Clear per-request state
        request = nil
        wsInterceptor = nil
        isWebSocketUpgrade = false
        pendingRequestParts.removeAll()
    }

    /// Schedule an idle timeout. If no new request arrives within the timeout,
    /// close the keep-alive connection.
    private func scheduleIdleTimeout() {
        idleTimeoutTask?.cancel()
        guard let channel = _channel, channel.isActive else { return }
        let timeout = TimeAmount.seconds(ProxyConfig.Connection.keepAliveIdleTimeout)
        idleTimeoutTask = channel.eventLoop.scheduleTask(in: timeout) { [weak self] in
            guard let self = self else { return }
            AxLogger.log("[HTTPCapture] Keep-alive idle timeout, closing connection", level: .Info)
            self.clientChannel?.close(mode: .all, promise: nil)
            self.serverChannel?.close(mode: .all, promise: nil)
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
        idleTimeoutTask?.cancel()
        idleTimeoutTask = nil

        // If the last response completed normally and the outbound channel is still
        // active, return it to the connection pool for reuse by future clients.
        if responseCompleted, let outbound = clientChannel, outbound.isActive, let req = request ?? lastCompletedRequest {
            let poolKey = ConnectionPoolKey(host: req.host, port: req.port, isSSL: req.ssl)
            recorder.task.connectionPool.checkin(key: poolKey, channel: outbound)
        } else {
            clientChannel?.close(mode: .all, promise: nil)
        }

        // Fallback: if the response didn't complete normally, close the current recorder
        if !responseCompleted {
            recorder.recordClosed()
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[HTTPCapture] Error for \(request?.host ?? "unknown"): \(error)", level: .Error)
        recorder.recordError("HTTPCapture error for \(request?.host ?? "unknown"): \(error)")
        idleTimeoutTask?.cancel()
        idleTimeoutTask = nil
        clientChannel?.close(mode: .all, promise: nil)
        context.close(mode: .all, promise: nil)
    }
}

// MARK: - Response Relay (lives in the outbound channel to real server)

/// Receives HTTP responses from the real server and relays them back to the client.
/// Also records response data via SessionRecorder.
/// Detects 101 Switching Protocols to trigger WebSocket upgrade.
/// Supports keep-alive: checks Connection header and HTTP version to decide whether to close.
final class ResponseRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private var recorder: SessionRecorder
    private weak var serverChannel: Channel?
    private var wsInterceptor: WebSocketUpgradeInterceptor?

    // Keep-alive state
    private var responseHead: HTTPResponseHead?
    var onResponseComplete: ((Bool) -> Void)?

    init(recorder: SessionRecorder, serverChannel: Channel?,
         wsInterceptor: WebSocketUpgradeInterceptor? = nil) {
        self.recorder = recorder
        self.serverChannel = serverChannel
        self.wsInterceptor = wsInterceptor
    }

    /// Swap the recorder for a new request/response cycle on a keep-alive connection.
    func swapRecorder(_ newRecorder: SessionRecorder) {
        self.recorder = newRecorder
        self.responseHead = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            responseHead = head
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

            // If this was a 101 upgrade, switch to WebSocket (don't close recorder —
            // WebSocket handler will manage its own recording lifecycle)
            if recorder.session.schemes == "WS" || recorder.session.schemes == "WSS" {
                serverChannel?.writeAndFlush(HTTPServerResponsePart.end(trailers), promise: nil)
                if let interceptor = wsInterceptor {
                    interceptor.performWebSocketUpgrade(
                        context: context,
                        clientChannel: context.channel
                    )
                }
                return
            }

            // Finalize this cycle's recorder
            recorder.recordClosed()

            let keepAlive = shouldKeepAlive()
            serverChannel?.writeAndFlush(HTTPServerResponsePart.end(trailers), promise: nil)

            // Notify HTTPCaptureHandler about cycle completion
            onResponseComplete?(keepAlive)

            if !keepAlive {
                serverChannel?.close(mode: .all, promise: nil)
                context.channel.close(mode: .all, promise: nil)
            }
        }
    }

    /// Determine whether the connection should be kept alive based on HTTP version
    /// and Connection header semantics.
    /// - HTTP/1.1: keep-alive by default unless "Connection: close"
    /// - HTTP/1.0: close by default unless "Connection: keep-alive"
    private func shouldKeepAlive() -> Bool {
        guard let head = responseHead else { return false }

        let connectionHeader = head.headers["Connection"].joined(separator: ",").lowercased()

        if head.version.major == 1 && head.version.minor >= 1 {
            // HTTP/1.1: keep-alive by default
            return !connectionHeader.contains("close")
        } else {
            // HTTP/1.0: close by default
            return connectionHeader.contains("keep-alive")
        }
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        serverChannel?.close(mode: .all, promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // uncleanShutdown is normal — many servers close TCP without TLS close_notify
        if let sslError = error as? NIOSSLError, case .uncleanShutdown = sslError {
            AxLogger.log("[ResponseRelay] server closed without TLS close_notify (normal)", level: .Info)
        } else {
            AxLogger.log("[ResponseRelay] Error from upstream server: \(error)", level: .Error)
            recorder.recordError("ResponseRelay error: \(error)")
        }
        serverChannel?.close(mode: .all, promise: nil)
        context.channel.close(mode: .all, promise: nil)
    }
}
