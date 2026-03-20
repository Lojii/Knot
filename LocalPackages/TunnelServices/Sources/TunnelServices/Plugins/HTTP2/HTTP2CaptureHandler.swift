//
//  HTTP2CaptureHandler.swift
//  TunnelServices
//
//  HTTP/2 capture pipeline.
//  Translates HTTP/2 frames to HTTP/1.1 parts for capture and forwarding.
//  Delegates gRPC-specific parsing to GRPCDecoder when content-type matches.
//

import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL

// MARK: - HTTP/2 Pipeline Builder

/// Builds an HTTP/2 capture pipeline for the MITMHandler.
///
/// Strategy: HTTP/2 → HTTP/1.1 translation via NIO codec.
/// Each HTTP/2 stream is handled independently with its own SessionRecorder.
public enum HTTP2CaptureBuilder {

    public static func addPipeline(
        context: ChannelHandlerContext,
        recorder: SessionRecorder
    ) -> EventLoopFuture<Void> {
        let multiplexer = HTTP2StreamMultiplexer(
            mode: .server,
            channel: context.channel
        ) { stream -> EventLoopFuture<Void> in
            let streamRecorder = SessionRecorder(task: recorder.task)
            streamRecorder.session.schemes = "H2"

            return stream.pipeline.addHandler(
                HTTP2FramePayloadToHTTP1ServerCodec(),
                name: "h2.toHTTP1"
            ).flatMap {
                stream.pipeline.addHandler(
                    H2StreamCaptureHandler(recorder: streamRecorder),
                    name: "h2.capture"
                )
            }
        }

        return context.pipeline.addHandler(
            NIOHTTP2Handler(mode: .server),
            name: "h2.handler"
        ).flatMap {
            context.pipeline.addHandler(multiplexer, name: "h2.multiplexer")
        }
    }
}

// MARK: - HTTP/2 Stream Capture

/// Captures a single HTTP/2 stream (translated to HTTP/1.1 parts).
/// Detects gRPC by content-type and delegates body parsing to GRPCDecoder.
final class H2StreamCaptureHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let recorder: SessionRecorder
    private var isGRPC = false
    private var clientChannel: Channel?
    private var request: NetRequest?
    private var connected = false
    private var pendingParts = [HTTPClientRequestPart]()
    private var serverChannel: Channel?

    init(recorder: SessionRecorder) {
        self.recorder = recorder
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        serverChannel = context.channel
        let part = unwrapInboundIn(data)

        switch part {
        case .head(var head):
            // Detect gRPC via content-type
            let contentType = head.headers["content-type"].first ?? ""
            if contentType.hasPrefix("application/grpc") {
                isGRPC = true
                recorder.session.schemes = "gRPC"
            }

            if request == nil {
                request = NetRequest(head)
                request?.ssl = true
            }

            head.headers = NetRequest.removeProxyHead(heads: head.headers)
            recorder.recordRequestHead(head, localAddress: context.channel.remoteAddress, isSSL: true)

            if clientChannel == nil {
                connectToServer(context: context)
            }
            enqueue(.head(head))

        case .body(let body):
            if isGRPC {
                GRPCDecoder.logRequestBody(body, recorder: recorder)
            } else {
                recorder.recordRequestBody(body)
            }
            recorder.addUpload(body.readableBytes)
            enqueue(.body(.byteBuffer(body)))

        case .end(let trailers):
            recorder.recordRequestEnd()
            enqueue(.end(trailers))
        }
    }

    // MARK: - Server Connection

    private func connectToServer(context: ChannelHandlerContext) {
        guard let req = request else { return }

        let responseHandler = H2ResponseRelayHandler(
            recorder: recorder,
            serverChannel: context.channel,
            isGRPC: isGRPC
        )

        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelInitializer { channel in
                let tlsConfig = TLSConfiguration.forClient(applicationProtocols: ["http/1.1"])
                guard let sslCtx = try? NIOSSLContext(configuration: tlsConfig) else {
                    return channel.eventLoop.makeFailedFuture(
                        ServerChannelError(errCode: -1, localizedDescription: "SSL context failed")
                    )
                }
                let sniName = req.host.isIPAddress() ? nil : req.host
                guard let sslHandler = try? NIOSSLClientHandler(context: sslCtx, serverHostname: sniName) else {
                    return channel.eventLoop.makeFailedFuture(
                        ServerChannelError(errCode: -1, localizedDescription: "SSL handler failed")
                    )
                }
                return channel.pipeline.addHandler(sslHandler, name: "h2out.ssl").flatMap {
                    channel.pipeline.addHTTPClientHandlers()
                }.flatMap {
                    channel.pipeline.addHandler(responseHandler, name: "h2out.response")
                }
            }

        bootstrap.connect(host: req.host, port: req.port).whenComplete { [weak self] result in
            switch result {
            case .success(let channel):
                self?.clientChannel = channel
                self?.connected = true
                self?.recorder.recordConnected(remoteAddress: channel.remoteAddress)
                self?.flushPending()
            case .failure(let error):
                self?.recorder.recordConnectionError(error, host: req.host, port: req.port)
                context.close(promise: nil)
            }
        }
    }

    private func enqueue(_ part: HTTPClientRequestPart) {
        if connected, let ch = clientChannel, ch.isActive {
            ch.writeAndFlush(part, promise: nil)
        } else {
            pendingParts.append(part)
        }
    }

    private func flushPending() {
        guard let ch = clientChannel, ch.isActive else { return }
        for p in pendingParts { ch.writeAndFlush(p, promise: nil) }
        pendingParts.removeAll()
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        clientChannel?.close(promise: nil)
        recorder.recordClosed()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        clientChannel?.close(promise: nil)
        context.close(promise: nil)
    }
}

// MARK: - HTTP/2 Response Relay

/// Relays HTTP/1.1 responses from the real server back through the HTTP/2 stream.
final class H2ResponseRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let recorder: SessionRecorder
    private weak var serverChannel: Channel?
    private let isGRPC: Bool

    init(recorder: SessionRecorder, serverChannel: Channel, isGRPC: Bool) {
        self.recorder = recorder
        self.serverChannel = serverChannel
        self.isGRPC = isGRPC
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            recorder.recordResponseHead(head)
            recorder.addDownload(200)
            serverChannel?.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)

        case .body(let body):
            if isGRPC {
                GRPCDecoder.logResponseBody(body, recorder: recorder)
            } else {
                recorder.recordResponseBody(body)
            }
            recorder.addDownload(body.readableBytes)
            serverChannel?.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(body)), promise: nil)

        case .end(let trailers):
            if isGRPC {
                GRPCDecoder.logTrailers(trailers, recorder: recorder)
            }
            recorder.recordResponseEnd()
            serverChannel?.writeAndFlush(HTTPServerResponsePart.end(trailers), promise: nil)
            serverChannel?.close(promise: nil)
            context.close(promise: nil)
        }
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        serverChannel?.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        serverChannel?.close(promise: nil)
        context.close(promise: nil)
    }
}
