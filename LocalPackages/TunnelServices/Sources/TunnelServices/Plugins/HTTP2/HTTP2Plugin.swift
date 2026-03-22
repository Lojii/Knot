import Foundation
import NIO
import KnotStorage

/// Plugin that identifies and handles HTTP/2 traffic.
/// HTTP/2 is detected via ALPN negotiation (alpnResult == "h2"), not byte inspection.
/// Pipeline setup delegates to `HTTP2CaptureBuilder` via a thin bridge handler.
public final class HTTP2Plugin: ProtocolPlugin {
    public let id = "http2"
    public let displayName = "HTTP/2"

    public init() {}

    // MARK: - ProtocolPlugin

    /// HTTP/2 is negotiated via ALPN, not matched by byte prefix.
    /// Returns `.yes(100)` when the ALPN result is "h2", otherwise `.no`.
    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        return context.metadata.alpnResult == "h2" ? .yes(confidence: 100) : .no
    }

    /// Builds the HTTP/2 capture pipeline by installing a bridge handler that
    /// calls `HTTP2CaptureBuilder.addPipeline` once a live
    /// `ChannelHandlerContext` is available.
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let host = context.metadata.innerHost ?? context.metadata.sni ?? "unknown"
        let port = context.metadata.innerPort ?? 443
        let bridge = HTTP2PipelineBridge(recorder: context.recorder, targetHost: host, targetPort: port)
        return context.channel.pipeline.addHandler(bridge, name: "http2.bridge")
    }

    /// HTTP/2 streams create their own recorders internally — no top-level recorder needed.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        return nil
    }
}

// MARK: - HTTP2PipelineBridge

/// A thin channel handler that triggers `HTTP2CaptureBuilder.addPipeline`
/// once it has access to a live `ChannelHandlerContext`.
final class HTTP2PipelineBridge: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    private let recorder: SessionRecorder
    private let targetHost: String
    private let targetPort: Int
    private var installed = false

    init(recorder: SessionRecorder, targetHost: String, targetPort: Int) {
        self.recorder = recorder
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    func channelActive(context: ChannelHandlerContext) {
        guard !installed else {
            context.fireChannelActive()
            return
        }
        installed = true
        HTTP2CaptureBuilder.addPipeline(
            context: context, recorder: recorder,
            targetHost: targetHost, targetPort: targetPort
        ).whenComplete { _ in
            context.pipeline.removeHandler(name: "http2.bridge", promise: nil)
        }
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }
}
