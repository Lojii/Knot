//
//  HTTP2CaptureHandler.swift
//  TunnelServices
//
//  HTTP/2 capture pipeline with full H2 proxy support.
//  Client <-H2-> Proxy <-H2-> Server (single shared connection, multiplexed streams).
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
/// Architecture:
/// - Client side: NIOHTTP2Handler(server) -> HTTP2StreamMultiplexer(server) -> per-stream capture
/// - Server side: Single shared H2 connection -> NIOHTTP2Handler(client) -> HTTP2StreamMultiplexer(client)
/// - Each client H2 stream maps to a server H2 stream via H2ServerConnection
public enum HTTP2CaptureBuilder {

    public static func addPipeline(
        context: ChannelHandlerContext,
        recorder: SessionRecorder,
        targetHost: String,
        targetPort: Int = 443
    ) -> EventLoopFuture<Void> {
        // Shared H2 connection to the real server
        let serverConn = H2ServerConnection(host: targetHost, port: targetPort, task: recorder.task)

        let clientMultiplexer = HTTP2StreamMultiplexer(
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
                    H2StreamCaptureHandler(
                        recorder: streamRecorder,
                        serverConnection: serverConn
                    ),
                    name: "h2.capture"
                )
            }
        }

        // Pass client-side multiplexer to server connection for push promise forwarding
        serverConn.clientMultiplexer = clientMultiplexer

        // Set up client-side H2 pipeline
        let pipeline = context.pipeline.addHandler(
            NIOHTTP2Handler(mode: .server),
            name: "h2.handler"
        ).flatMap {
            context.pipeline.addHandler(clientMultiplexer, name: "h2.multiplexer")
        }

        // Initiate server H2 connection in parallel
        serverConn.connect(on: context.eventLoop).whenFailure { error in
            AxLogger.log("[H2ServerConn] Failed to connect to \(targetHost):\(targetPort): \(error)", level: .Error)
            recorder.recordError("H2 server connection failed: \(error)")
        }

        // Close server connection when client disconnects
        context.channel.closeFuture.whenComplete { _ in
            serverConn.close()
        }

        return pipeline
    }
}

// MARK: - H2 Server Connection

/// Manages a single shared HTTP/2 connection to the upstream server.
/// All client H2 streams are multiplexed over this one connection.
final class H2ServerConnection {
    let host: String
    let port: Int
    let task: CaptureTask
    weak var clientMultiplexer: HTTP2StreamMultiplexer?
    private var channel: Channel?
    private var multiplexer: HTTP2StreamMultiplexer?
    private var ready = false
    private var connectFailed = false
    private var pendingStreams: [(initializer: @Sendable (Channel) -> EventLoopFuture<Void>,
                                  promise: EventLoopPromise<Channel>)] = []

    init(host: String, port: Int, task: CaptureTask) {
        self.host = host
        self.port = port
        self.task = task
    }

    func connect(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let sniName = host.isIPAddress() ? nil : host

        let bootstrap = ClientBootstrap(group: eventLoop)
            .channelInitializer { [weak self] channel in
                let tlsConfig = TLSConfiguration.forClient(applicationProtocols: ["h2"])
                guard let sslCtx = try? NIOSSLContext(configuration: tlsConfig),
                      let sslHandler = try? NIOSSLClientHandler(context: sslCtx, serverHostname: sniName) else {
                    return channel.eventLoop.makeFailedFuture(
                        ServerChannelError(errCode: -1, localizedDescription: "H2 outbound SSL setup failed")
                    )
                }

                let h2Handler = NIOHTTP2Handler(mode: .client)
                let mux = HTTP2StreamMultiplexer(mode: .client, channel: channel) { [weak self] serverPushStream in
                    guard let self = self, let clientMux = self.clientMultiplexer else {
                        return serverPushStream.eventLoop.makeSucceededVoidFuture()
                    }
                    let pushRecorder = SessionRecorder(task: self.task)
                    pushRecorder.session.schemes = "H2-Push"

                    return serverPushStream.pipeline.addHandler(
                        HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https),
                        name: "h2push.codec"
                    ).flatMap {
                        serverPushStream.pipeline.addHandler(
                            H2PushRelayHandler(recorder: pushRecorder, clientMultiplexer: clientMux),
                            name: "h2push.relay"
                        )
                    }
                }
                self?.multiplexer = mux

                return channel.pipeline.addHandler(sslHandler, name: "h2out.ssl")
                    .flatMap { channel.pipeline.addHandler(h2Handler, name: "h2out.h2") }
                    .flatMap { channel.pipeline.addHandler(mux, name: "h2out.mux") }
            }

        AxLogger.log("[H2ServerConn] connecting to \(host):\(port)...", level: .Warning)

        return bootstrap.connect(host: host, port: port).map { [weak self] channel in
            AxLogger.log("[H2ServerConn] connected to \(self?.host ?? ""):\(self?.port ?? 0)", level: .Warning)
            self?.channel = channel
            self?.ready = true
            self?.flushPendingStreams()
        }
    }

    /// Creates a new H2 stream on the shared server connection.
    func createStream(
        initializer: @Sendable @escaping (Channel) -> EventLoopFuture<Void>,
        promise: EventLoopPromise<Channel>
    ) {
        if ready, let mux = multiplexer {
            mux.createStreamChannel(promise: promise, initializer)
        } else if connectFailed {
            promise.fail(ServerChannelError(errCode: -2, localizedDescription: "H2 server connection failed"))
        } else {
            pendingStreams.append((initializer, promise))
        }
    }

    func close() {
        channel?.close(mode: .all, promise: nil)
    }

    private func flushPendingStreams() {
        guard let mux = multiplexer else { return }
        for (initializer, promise) in pendingStreams {
            mux.createStreamChannel(promise: promise, initializer)
        }
        pendingStreams.removeAll()
    }
}

// MARK: - H2 Push Relay

/// Handles server push promises received on the upstream H2 connection.
/// Captures the pushed response via SessionRecorder and forwards it to the
/// client through a new stream on the client-side multiplexer.
final class H2PushRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let recorder: SessionRecorder
    private weak var clientMultiplexer: HTTP2StreamMultiplexer?
    private var clientPushChannel: Channel?
    private var pendingParts = [HTTPServerResponsePart]()
    private var connected = false

    init(recorder: SessionRecorder, clientMultiplexer: HTTP2StreamMultiplexer?) {
        self.recorder = recorder
        self.clientMultiplexer = clientMultiplexer
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            recorder.recordResponseHead(head)
            recorder.addDownload(200)
            if clientPushChannel == nil {
                createClientPushStream()
            }
            enqueue(.head(head))

        case .body(let body):
            recorder.recordResponseBody(body)
            recorder.addDownload(body.readableBytes)
            enqueue(.body(.byteBuffer(body)))

        case .end(let trailers):
            recorder.recordResponseEnd()
            enqueue(.end(trailers))
            recorder.recordClosed()
        }
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        clientPushChannel?.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[H2PushRelay] Error from upstream push stream: \(error)", level: .Error)
        recorder.recordError("H2PushRelay error: \(error)")
        clientPushChannel?.close(promise: nil)
        context.close(promise: nil)
    }

    // MARK: - Private

    private func createClientPushStream() {
        clientMultiplexer?.createStreamChannel { stream in
            stream.pipeline.addHandler(
                HTTP2FramePayloadToHTTP1ServerCodec(),
                name: "h2push.client.codec"
            )
        }.whenComplete { [weak self] result in
            switch result {
            case .success(let ch):
                self?.clientPushChannel = ch
                self?.connected = true
                self?.flushPending()
            case .failure(let error):
                AxLogger.log("[H2PushRelay] Failed to create client push stream: \(error)", level: .Error)
                self?.recorder.recordError("H2 push stream creation failed: \(error)")
            }
        }
    }

    private func enqueue(_ part: HTTPServerResponsePart) {
        if connected, let ch = clientPushChannel, ch.isActive {
            ch.writeAndFlush(part, promise: nil)
        } else {
            pendingParts.append(part)
        }
    }

    private func flushPending() {
        guard let ch = clientPushChannel, ch.isActive else { return }
        for p in pendingParts { ch.writeAndFlush(p, promise: nil) }
        pendingParts.removeAll()
    }
}

// MARK: - H2 Stream Capture

/// Captures a single HTTP/2 stream.
/// Records request/response via SessionRecorder, then forwards to a corresponding
/// server H2 stream via H2ServerConnection.
final class H2StreamCaptureHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let recorder: SessionRecorder
    private let serverConnection: H2ServerConnection
    private var isGRPC = false
    private var serverStreamChannel: Channel?
    private var clientStreamChannel: Channel?
    private var request: NetRequest?
    private var connected = false
    private var pendingParts = [HTTPClientRequestPart]()
    fileprivate var responseCompleted = false

    init(recorder: SessionRecorder, serverConnection: H2ServerConnection) {
        self.recorder = recorder
        self.serverConnection = serverConnection
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        clientStreamChannel = context.channel
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
                request?.port = serverConnection.port
                AxLogger.log("[H2Capture] request: \(head.method) \(head.uri) host=\(request?.host ?? "?") port=\(serverConnection.port)", level: .Warning)
            }

            head.headers = NetRequest.removeProxyHead(heads: head.headers)
            recorder.recordRequestHead(head, localAddress: context.channel.remoteAddress, isSSL: true)

            if serverStreamChannel == nil {
                createServerStream(context: context)
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

    // MARK: - Server Stream

    private func createServerStream(context: ChannelHandlerContext) {
        let responseHandler = H2ResponseRelayHandler(
            recorder: recorder,
            clientStreamChannel: context.channel,
            captureHandler: self,
            isGRPC: isGRPC
        )

        let promise = context.eventLoop.makePromise(of: Channel.self)
        serverConnection.createStream(
            initializer: { stream in
                stream.pipeline.addHandler(
                    HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https),
                    name: "h2out.stream.codec"
                ).flatMap {
                    stream.pipeline.addHandler(responseHandler, name: "h2out.stream.relay")
                }
            },
            promise: promise
        )

        promise.futureResult.whenComplete { [weak self] result in
            switch result {
            case .success(let stream):
                AxLogger.log("[H2Capture] server stream created for \(self?.request?.host ?? "")", level: .Warning)
                self?.serverStreamChannel = stream
                self?.connected = true
                self?.recorder.recordConnected(remoteAddress: stream.remoteAddress)
                self?.flushPending()
            case .failure(let error):
                AxLogger.log("[H2Capture] server stream creation FAILED: \(error)", level: .Error)
                self?.recorder.recordError("H2 stream creation failed: \(error)")
                context.close(promise: nil)
            }
        }
    }

    private func enqueue(_ part: HTTPClientRequestPart) {
        if connected, let ch = serverStreamChannel, ch.isActive {
            ch.writeAndFlush(part, promise: nil)
        } else {
            pendingParts.append(part)
        }
    }

    private func flushPending() {
        guard let ch = serverStreamChannel, ch.isActive else { return }
        for p in pendingParts { ch.writeAndFlush(p, promise: nil) }
        pendingParts.removeAll()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        // When client stream's write buffer fills up, stop reading from server stream
        if let serverCh = serverStreamChannel {
            _ = serverCh.setOption(ChannelOptions.autoRead, value: context.channel.isWritable)
        }
        context.fireChannelWritabilityChanged()
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        serverStreamChannel?.close(promise: nil)
        // recordClosed() is called in H2ResponseRelayHandler when the response completes.
        // Only call here as fallback if response never arrived (e.g. connection dropped).
        if !responseCompleted {
            recorder.recordClosed()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[H2Capture] Error for \(request?.host ?? "unknown"): \(error)", level: .Error)
        recorder.recordError("H2Capture error: \(error)")
        serverStreamChannel?.close(promise: nil)
        context.close(promise: nil)
    }
}

// MARK: - HTTP/2 Response Relay

/// Lives in the outbound H2 stream channel.
/// Receives HTTP/2 responses (as HTTP/1.1 parts via codec) and relays back to client stream.
final class H2ResponseRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let recorder: SessionRecorder
    private weak var clientStreamChannel: Channel?
    private weak var captureHandler: H2StreamCaptureHandler?
    private let isGRPC: Bool

    init(recorder: SessionRecorder, clientStreamChannel: Channel,
         captureHandler: H2StreamCaptureHandler, isGRPC: Bool) {
        self.recorder = recorder
        self.clientStreamChannel = clientStreamChannel
        self.captureHandler = captureHandler
        self.isGRPC = isGRPC
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            recorder.recordResponseHead(head)
            recorder.addDownload(200)
            clientStreamChannel?.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)

        case .body(let body):
            if isGRPC {
                GRPCDecoder.logResponseBody(body, recorder: recorder)
            } else {
                recorder.recordResponseBody(body)
            }
            recorder.addDownload(body.readableBytes)
            clientStreamChannel?.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(body)), promise: nil)

        case .end(let trailers):
            if isGRPC {
                GRPCDecoder.logTrailers(trailers, recorder: recorder)
            }
            recorder.recordResponseEnd()
            clientStreamChannel?.writeAndFlush(HTTPServerResponsePart.end(trailers), promise: nil)
            // Response complete -- flush recorded data to storage without closing the stream.
            // H2 streams are managed by the multiplexer; don't force-close them.
            captureHandler?.responseCompleted = true
            recorder.recordClosed()
        }
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        // When server stream's write buffer fills up, stop reading from client stream
        if let clientCh = clientStreamChannel {
            _ = clientCh.setOption(ChannelOptions.autoRead, value: context.channel.isWritable)
        }
        context.fireChannelWritabilityChanged()
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        clientStreamChannel?.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let sslError = error as? NIOSSLError, case .uncleanShutdown = sslError {
            AxLogger.log("[H2ResponseRelay] server closed without TLS close_notify (normal)", level: .Info)
        } else {
            AxLogger.log("[H2ResponseRelay] Error from upstream: \(error)", level: .Error)
            recorder.recordError("H2ResponseRelay error: \(error)")
        }
        clientStreamChannel?.close(promise: nil)
        context.close(promise: nil)
    }
}
