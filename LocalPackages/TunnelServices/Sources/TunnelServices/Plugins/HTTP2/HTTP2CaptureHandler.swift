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
import NIOHPACK
import NIOSSL
import NIOConcurrencyHelpers

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
        return addPipeline(
            pipeline: context.pipeline,
            channel: context.channel,
            eventLoop: context.eventLoop,
            recorder: recorder,
            targetHost: targetHost,
            targetPort: targetPort
        )
    }

    /// Overload that accepts a pipeline + channel directly (for use when the originating handler context is detached).
    public static func addPipeline(
        pipeline: ChannelPipeline,
        channel: Channel,
        recorder: SessionRecorder,
        targetHost: String,
        targetPort: Int = 443
    ) -> EventLoopFuture<Void> {
        return addPipeline(
            pipeline: pipeline,
            channel: channel,
            eventLoop: channel.eventLoop,
            recorder: recorder,
            targetHost: targetHost,
            targetPort: targetPort
        )
    }

    private static func addPipeline(
        pipeline: ChannelPipeline,
        channel: Channel,
        eventLoop: EventLoop,
        recorder: SessionRecorder,
        targetHost: String,
        targetPort: Int = 443
    ) -> EventLoopFuture<Void> {
        // Shared H2 connection to the real server
        let serverConn = H2ServerConnection(host: targetHost, port: targetPort, task: recorder.task)

        let clientMultiplexer = HTTP2StreamMultiplexer(
            mode: .server,
            channel: channel
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

        // Pass client-side references to server connection for push promise forwarding
        serverConn.clientMultiplexer = clientMultiplexer
        serverConn.clientH2Channel = channel

        // Set up client-side H2 pipeline — use syncOperations to prevent
        // ALPN unbuffering from racing with handler installation.
        let pipelineFuture: EventLoopFuture<Void>
        do {
            try pipeline.syncOperations.addHandler(
                NIOHTTP2Handler(mode: .server),
                name: "h2.handler"
            )
            try pipeline.syncOperations.addHandler(clientMultiplexer, name: "h2.multiplexer")
            pipelineFuture = eventLoop.makeSucceededVoidFuture()
        } catch {
            pipelineFuture = eventLoop.makeFailedFuture(error)
        }

        // Initiate server H2 connection in parallel
        serverConn.connect(on: eventLoop).whenFailure { error in
            AxLogger.log("[H2ServerConn] Failed to connect to \(targetHost):\(targetPort): \(error)", level: .Error)
            recorder.recordError("H2 server connection failed: \(error)")
        }

        // Close server connection when client disconnects
        channel.closeFuture.whenComplete { _ in
            serverConn.close()
        }

        return pipelineFuture
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
    /// The client-side H2 connection channel — used to write raw H2 frames (e.g. PUSH_PROMISE).
    weak var clientH2Channel: Channel?
    private var channel: Channel?
    private var multiplexer: HTTP2StreamMultiplexer?
    private var ready = false
    private var connectFailed = false
    private var pendingStreams: [(initializer: @Sendable (Channel) -> EventLoopFuture<Void>,
                                  promise: EventLoopPromise<Channel>)] = []
    /// Guards ready/pendingStreams/multiplexer which are accessed from both
    /// the client EventLoop (createStream) and server EventLoop (connect callback).
    private let _stateLock = NIOLock()

    /// Push promise tracking: maps server pushedStreamID → server parentStreamID.
    /// Populated by PushPromiseTracker on the server-side pipeline.
    let pushPromiseTracker = PushPromiseTracker()

    /// Maps server stream ID → client stream channel, so push relay can find
    /// the original client stream to send PUSH_PROMISE on.
    private let _streamMapLock = NIOLock()
    private var _serverToClientStream: [HTTP2StreamID: Channel] = [:]

    /// Next push stream ID for client-facing push promises (even numbers, starting at 2).
    private let _nextPushIDLock = NIOLock()
    private var _nextPushStreamID: Int32 = 2

    init(host: String, port: Int, task: CaptureTask) {
        self.host = host
        self.port = port
        self.task = task
    }

    /// Register a mapping from server stream to client stream channel.
    func registerStreamMapping(serverStreamID: HTTP2StreamID, clientChannel: Channel) {
        _streamMapLock.withLock {
            _serverToClientStream[serverStreamID] = clientChannel
        }
    }

    /// Look up the client stream channel that corresponds to a server stream.
    func clientChannel(forServerStream serverStreamID: HTTP2StreamID) -> Channel? {
        _streamMapLock.withLock {
            _serverToClientStream[serverStreamID]
        }
    }

    /// Allocate the next even-numbered push stream ID for client-facing push promises.
    func allocatePushStreamID() -> HTTP2StreamID {
        _nextPushIDLock.withLock {
            let id = _nextPushStreamID
            _nextPushStreamID += 2
            return HTTP2StreamID(id)
        }
    }

    func connect(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let sniName = host.isIPAddress() ? nil : host

        let bootstrap = ClientBootstrap(group: eventLoop)
            .channelInitializer { [weak self] channel in
                var tlsConfig = TLSConfiguration.forClient(applicationProtocols: ["h2"])
                // MITM proxy does not verify upstream server certificates
                tlsConfig.certificateVerification = .none
                guard let sslCtx = try? NIOSSLContext(configuration: tlsConfig),
                      let sslHandler = try? NIOSSLClientHandler(context: sslCtx, serverHostname: sniName) else {
                    return channel.eventLoop.makeFailedFuture(
                        ServerChannelError(errCode: -1, localizedDescription: "H2 outbound SSL setup failed")
                    )
                }

                let h2Handler = NIOHTTP2Handler(mode: .client)
                let pushTracker = self?.pushPromiseTracker ?? PushPromiseTracker()
                let mux = HTTP2StreamMultiplexer(mode: .client, channel: channel) { [weak self] serverPushStream in
                    guard let self = self else {
                        return serverPushStream.eventLoop.makeSucceededVoidFuture()
                    }
                    let pushRecorder = SessionRecorder(task: self.task)
                    pushRecorder.session.schemes = "H2-Push"

                    // NOTE: Do NOT add HTTP2FramePayloadToHTTP1ClientCodec here.
                    // Push streams receive server responses WITHOUT a preceding client request,
                    // which causes the codec to preconditionFailure ("Expected not to get a
                    // response without having sent a request"). H2PushRelayHandler processes
                    // raw HTTP2Frame.FramePayload directly.
                    return serverPushStream.pipeline.addHandler(
                        H2PushRelayHandler(recorder: pushRecorder, serverConnection: self),
                        name: "h2push.relay"
                    )
                }
                self?.multiplexer = mux

                return channel.pipeline.addHandler(sslHandler, name: "h2out.ssl")
                    .flatMap { channel.pipeline.addHandler(h2Handler, name: "h2out.h2") }
                    // PushPromiseTracker sits between NIOHTTP2Handler and multiplexer
                    // to intercept PUSH_PROMISE frames and record parent stream mappings.
                    .flatMap { channel.pipeline.addHandler(pushTracker, name: "h2out.pushTracker") }
                    .flatMap { channel.pipeline.addHandler(mux, name: "h2out.mux") }
            }

        AxLogger.log("[H2ServerConn] connecting to \(host):\(port)...", level: .Warning)

        let future = bootstrap.connect(host: host, port: port)
        future.whenSuccess { [weak self] channel in
            guard let self = self else { return }
            AxLogger.log("[H2ServerConn] connected to \(self.host):\(self.port)", level: .Warning)
            self._stateLock.withLock {
                self.channel = channel
                self.ready = true
            }
            self.flushPendingStreams()
        }
        future.whenFailure { [weak self] error in
            guard let self = self else { return }
            AxLogger.log("[H2ServerConn] connect FAILED to \(self.host):\(self.port): \(error)", level: .Error)
            self._stateLock.withLock {
                self.connectFailed = true
            }
            self.failPendingStreams(error: error)
        }
        return future.map { _ in }
    }

    /// Fail all pending stream promises (connection failed).
    private func failPendingStreams(error: Error) {
        let pending: [(initializer: @Sendable (Channel) -> EventLoopFuture<Void>,
                        promise: EventLoopPromise<Channel>)]
        _stateLock.lock()
        pending = self.pendingStreams
        self.pendingStreams.removeAll()
        _stateLock.unlock()

        for (_, promise) in pending {
            promise.fail(error)
        }
    }

    /// Creates a new H2 stream on the shared server connection.
    /// Thread-safe: may be called from any EventLoop.
    func createStream(
        initializer: @Sendable @escaping (Channel) -> EventLoopFuture<Void>,
        promise: EventLoopPromise<Channel>
    ) {
        _stateLock.lock()
        if ready, let mux = multiplexer {
            _stateLock.unlock()
            mux.createStreamChannel(promise: promise, initializer)
        } else if connectFailed {
            _stateLock.unlock()
            promise.fail(ServerChannelError(errCode: -2, localizedDescription: "H2 server connection failed"))
        } else {
            pendingStreams.append((initializer, promise))
            _stateLock.unlock()
        }
    }

    func close() {
        channel?.close(mode: .all, promise: nil)
    }

    private func flushPendingStreams() {
        // Drain pendingStreams under the lock, then iterate outside it
        // to avoid holding the lock during multiplexer calls.
        let pending: [(initializer: @Sendable (Channel) -> EventLoopFuture<Void>,
                        promise: EventLoopPromise<Channel>)]
        _stateLock.lock()
        pending = self.pendingStreams
        self.pendingStreams.removeAll()
        let mux = self.multiplexer
        _stateLock.unlock()

        guard let mux = mux else { return }
        for (initializer, promise) in pending {
            mux.createStreamChannel(promise: promise, initializer)
        }
    }
}

// MARK: - H2 Push Relay

// MARK: - Push Promise Tracker

/// Sits between NIOHTTP2Handler and HTTP2StreamMultiplexer on the server-side pipeline.
/// Intercepts PUSH_PROMISE frames to record the parent→pushed stream mapping,
/// which the multiplexer callback doesn't expose.
final class PushPromiseTracker: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTP2Frame
    typealias InboundOut = HTTP2Frame

    private let lock = NIOLock()
    /// Maps server pushedStreamID → server parentStreamID.
    private var mapping: [HTTP2StreamID: HTTP2StreamID] = [:]
    /// Push promise request headers (from PUSH_PROMISE frame).
    private var pushHeaders: [HTTP2StreamID: HPACKHeaders] = [:]

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        if case .pushPromise(let pp) = frame.payload {
            lock.withLock {
                mapping[pp.pushedStreamID] = frame.streamID
                pushHeaders[pp.pushedStreamID] = pp.headers
            }
            AxLogger.log("[PushTracker] PUSH_PROMISE: parent=\(frame.streamID) pushed=\(pp.pushedStreamID)", level: .Info)
        }
        // Always forward to multiplexer
        context.fireChannelRead(data)
    }

    /// Get the parent stream ID for a pushed stream.
    func parentStreamID(forPushed pushed: HTTP2StreamID) -> HTTP2StreamID? {
        lock.withLock { mapping[pushed] }
    }

    /// Get the push request headers (from PUSH_PROMISE) for a pushed stream.
    func requestHeaders(forPushed pushed: HTTP2StreamID) -> HPACKHeaders? {
        lock.withLock { pushHeaders[pushed] }
    }
}

// MARK: - H2 Push Relay

/// Handles server push promises received on the upstream H2 connection.
/// Captures the pushed response via SessionRecorder AND forwards it to the client
/// by writing raw HTTP2Frame objects (PUSH_PROMISE + HEADERS + DATA) on the
/// client H2 connection channel.
///
/// Flow:
/// 1. PushPromiseTracker records server parentStreamID for this push stream
/// 2. H2ServerConnection maps server parentStreamID → client stream channel
/// 3. We allocate a new even push stream ID for the client side
/// 4. Write PUSH_PROMISE frame on client H2 channel (referencing original client stream)
/// 5. Write HEADERS + DATA frames on client H2 channel (on the new push stream)
final class H2PushRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    // Raw H2 frame payload — NOT HTTP1 codec, because push streams have
    // no outgoing request (which causes HTTP2FramePayloadToHTTP1ClientCodec to crash).
    typealias InboundIn = HTTP2Frame.FramePayload

    private let recorder: SessionRecorder
    private weak var serverConnection: H2ServerConnection?

    /// The client-side push stream ID allocated for this push.
    private var clientPushStreamID: HTTP2StreamID?
    /// Whether we successfully sent PUSH_PROMISE to the client.
    private var pushPromiseSent = false
    /// The server-side stream ID of this push stream (captured from first frame context).
    private var serverPushStreamID: HTTP2StreamID?
    /// Whether we've seen the first HEADERS frame.
    private var gotHeaders = false

    init(recorder: SessionRecorder, serverConnection: H2ServerConnection) {
        self.recorder = recorder
        self.serverConnection = serverConnection
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)

        switch payload {
        case .headers(let headerContent):
            recorder.addProtoFlag(.h2ServerPush)
            recorder.markPushStatus(.captureOnly)

            // Build HTTPResponseHead from HPACK headers for recording
            let statusCode = headerContent.headers.first(name: ":status").flatMap { UInt($0) } ?? 200
            var httpHeaders = HTTPHeaders()
            for (name, value, _) in headerContent.headers {
                if !name.hasPrefix(":") { httpHeaders.add(name: name, value: value) }
            }
            let head = HTTPResponseHead(
                version: .http2,
                status: HTTPResponseStatus(statusCode: Int(statusCode))
            )
            recorder.recordResponseHead(head)
            recorder.addDownload(200)
            if !gotHeaders {
                gotHeaders = true
                tryForwardPushPromise(context: context, responseHead: head)
            }

            if headerContent.endStream {
                recorder.recordResponseEnd()
                recorder.recordClosed()
            }

        case .data(let dataContent):
            if case .byteBuffer(let body) = dataContent.data {
                recorder.recordResponseBody(body)
                recorder.addDownload(body.readableBytes)
                forwardData(body, endStream: dataContent.endStream)
            }
            if dataContent.endStream {
                recorder.recordResponseEnd()
                recorder.recordClosed()
            }

        default:
            // RST_STREAM, WINDOW_UPDATE, etc. — ignore for recording
            break
        }
    }

    // MARK: - Push Forwarding

    private func tryForwardPushPromise(context: ChannelHandlerContext, responseHead: HTTPResponseHead) {
        guard let conn = serverConnection,
              let clientH2 = conn.clientH2Channel, clientH2.isActive else {
            AxLogger.log("[H2PushRelay] No client H2 channel, capture-only", level: .Warning)
            recorder.markPushStatus(.failed)
            return
        }

        // Resolve which server stream channel is ours (the push stream)
        // The stream ID is accessible from the channel via HTTP2StreamChannel internals.
        // We use the push promise tracker to find our parent stream.
        let tracker = conn.pushPromiseTracker

        // Try to find our server push stream ID by scanning tracker for recent mappings.
        // Since we're called from the push stream's pipeline, we need the stream ID.
        // Extract it from channel if possible, otherwise use tracker scan.
        let pushStreamID = extractStreamID(from: context.channel)

        guard let serverPushedID = pushStreamID,
              let serverParentID = tracker.parentStreamID(forPushed: serverPushedID) else {
            AxLogger.log("[H2PushRelay] Cannot resolve parent stream for push, capture-only", level: .Warning)
            recorder.markPushStatus(.failed)
            return
        }

        self.serverPushStreamID = serverPushedID

        // Map server parent stream → client parent stream
        guard let clientParentChannel = conn.clientChannel(forServerStream: serverParentID) else {
            AxLogger.log("[H2PushRelay] No client stream found for server parent \(serverParentID), capture-only", level: .Warning)
            recorder.markPushStatus(.failed)
            return
        }

        // Get the original push request headers from PUSH_PROMISE
        let requestHeaders = tracker.requestHeaders(forPushed: serverPushedID)
            ?? synthesizePushRequestHeaders(from: responseHead)

        // Allocate a client-side push stream ID
        let clientPushID = conn.allocatePushStreamID()
        self.clientPushStreamID = clientPushID

        // Get the client parent stream ID
        let clientParentStreamID = extractStreamID(from: clientParentChannel) ?? HTTP2StreamID(1)

        // 1. Write PUSH_PROMISE frame on the client H2 connection channel
        let pushPromise = HTTP2Frame.FramePayload.PushPromise(
            pushedStreamID: clientPushID,
            headers: requestHeaders
        )
        let pushFrame = HTTP2Frame(streamID: clientParentStreamID, payload: .pushPromise(pushPromise))
        clientH2.write(pushFrame, promise: nil)

        // 2. Write response HEADERS on the pushed stream
        var responseHPACK = HPACKHeaders()
        responseHPACK.add(name: ":status", value: "\(responseHead.status.code)")
        for (name, value) in responseHead.headers {
            responseHPACK.add(name: name.lowercased(), value: value)
        }
        let headersPayload = HTTP2Frame.FramePayload.Headers(headers: responseHPACK)
        let headersFrame = HTTP2Frame(streamID: clientPushID, payload: .headers(headersPayload))
        clientH2.writeAndFlush(headersFrame, promise: nil)

        pushPromiseSent = true
        recorder.markPushStatus(.forwarded)
        AxLogger.log("[H2PushRelay] Forwarded PUSH_PROMISE to client: parent=\(clientParentStreamID) pushed=\(clientPushID)", level: .Info)
    }

    private func forwardData(_ body: ByteBuffer, endStream: Bool) {
        guard pushPromiseSent, let pushID = clientPushStreamID,
              let clientH2 = serverConnection?.clientH2Channel, clientH2.isActive else { return }

        let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(body), endStream: endStream)
        let dataFrame = HTTP2Frame(streamID: pushID, payload: .data(dataPayload))
        clientH2.writeAndFlush(dataFrame, promise: nil)
    }

    private func forwardTrailers(_ trailers: HTTPHeaders) {
        guard pushPromiseSent, let pushID = clientPushStreamID,
              let clientH2 = serverConnection?.clientH2Channel, clientH2.isActive else { return }

        var hpack = HPACKHeaders()
        for (name, value) in trailers {
            hpack.add(name: name.lowercased(), value: value)
        }
        let headersPayload = HTTP2Frame.FramePayload.Headers(headers: hpack, endStream: true)
        let headersFrame = HTTP2Frame(streamID: pushID, payload: .headers(headersPayload))
        clientH2.writeAndFlush(headersFrame, promise: nil)
    }

    private func forwardEndStream() {
        guard pushPromiseSent, let pushID = clientPushStreamID,
              let clientH2 = serverConnection?.clientH2Channel, clientH2.isActive else { return }

        let emptyBuf = clientH2.allocator.buffer(capacity: 0)
        let dataPayload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(emptyBuf), endStream: true)
        let endFrame = HTTP2Frame(streamID: pushID, payload: .data(dataPayload))
        clientH2.writeAndFlush(endFrame, promise: nil)
    }

    // MARK: - Helpers

    /// Try to extract the HTTP2 stream ID from a stream channel.
    /// HTTP2StreamChannel stores streamID internally; we access it via the channel option.
    private func extractStreamID(from channel: Channel) -> HTTP2StreamID? {
        // NIOHTTP2 exposes stream ID via channel option
        try? channel.syncOptions?.getOption(HTTP2StreamChannelOptions.streamID)
    }

    /// Synthesize push request headers when the original PUSH_PROMISE headers were not captured.
    private func synthesizePushRequestHeaders(from responseHead: HTTPResponseHead) -> HPACKHeaders {
        var headers = HPACKHeaders()
        headers.add(name: ":method", value: "GET")
        headers.add(name: ":scheme", value: "https")
        if let host = serverConnection?.host {
            headers.add(name: ":authority", value: host)
        }
        headers.add(name: ":path", value: "/")
        return headers
    }

    // MARK: - Lifecycle

    func channelUnregistered(context: ChannelHandlerContext) {
        // Push stream closed on server side — nothing extra to close on client
        // (the pushed stream is managed by the H2 connection, not a stream channel we own).
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[H2PushRelay] Error from upstream push stream: \(error)", level: .Error)
        recorder.recordError("H2PushRelay error: \(error)")
        context.close(promise: nil)
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
    /// Accessed from both client EventLoop (channelUnregistered) and server EventLoop
    /// (H2ResponseRelayHandler sets it on response .end). Use lock for thread safety.
    private let _responseCompletedLock = NIOLock()
    private var _responseCompleted = false
    fileprivate var responseCompleted: Bool {
        get { _responseCompletedLock.withLock { _responseCompleted } }
        set { _responseCompletedLock.withLock { _responseCompleted = newValue } }
    }

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
                recorder.addProtoFlag(.h2Multiplexing)
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
                // Register mapping: server stream → client stream (for push promise forwarding)
                if let clientCh = self?.clientStreamChannel,
                   let serverStreamID = try? stream.syncOptions?.getOption(HTTP2StreamChannelOptions.streamID) {
                    self?.serverConnection.registerStreamMapping(serverStreamID: serverStreamID, clientChannel: clientCh)
                    self?.recorder.setH2StreamId(Int(Int32(serverStreamID)))
                }
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
        recorder.addProtoFlag(.h2FlowControl)
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
        // Safe unwrap: H2 codec may forward IOData (e.g., after RST_STREAM or stream close).
        // We check the NIOAny description cheaply — IOData descriptions start differently
        // from HTTPClientResponsePart. Only do the check on the first few chars.
        let raw = data
        // NIOAny stores .ioData or .other internally. HTTP parts are .other.
        // IOData.byteBuffer makes forceAsByteBuffer succeed, while HTTP parts don't.
        // We use the trick: if tryAsByteBuffer succeeds, it's IOData, not HTTP.
        // NIOAny.forceAsByteBuffer checks case .ioData(.byteBuffer(bb)).
        // But we can't call that from here (it's on _NIOAny).
        // Simplest reliable check: attempt to unwrap, catch fatalError... can't.
        // Alternative: add the data to description once on first IOData encounter.
        //
        // PRAGMATIC FIX: Change InboundIn to HTTP2Frame.FramePayload to bypass
        // the HTTP1 codec entirely. But that requires upstream pipeline changes.
        //
        // FOR NOW: use Mirror on NIOAny to detect IOData type.
        let storageTypeName = String(describing: type(of: (Mirror(reflecting: raw).children.first?.value) ?? raw))
        if storageTypeName.contains("IOData") || storageTypeName.contains("ioData") {
            // IOData from H2 codec — absorb silently
            return
        }

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
