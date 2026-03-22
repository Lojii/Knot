import Foundation
import NIO
import KnotStorage

/// Plugin placeholder for gRPC traffic.
///
/// gRPC detection does not happen at the top-level protocol router — it is
/// identified inside `HTTP2CaptureHandler` by inspecting the `content-type:
/// application/grpc` header on each HTTP/2 stream.  This plugin exists solely
/// to give gRPC a home in the plugin tree and to provide `GRPCRecorder`
/// creation for callers that need it.
public final class GRPCPlugin: ProtocolPlugin {
    public let id = "grpc"
    public let displayName = "gRPC"

    public init() {}

    // MARK: - ProtocolPlugin

    /// Always returns `.no` — gRPC is detected inside `HTTP2CaptureHandler`,
    /// not at the top-level byte-inspection stage.
    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        return .no
    }

    /// No-op: gRPC pipeline setup happens inside `HTTP2CaptureHandler`.
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    /// Creates a `GRPCRecorder` for the given flow.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        let host = context.metadata.innerHost
            ?? context.metadata.sni
            ?? (context.channel.remoteAddress?.description ?? "unknown")
        let port = context.metadata.innerPort ?? context.task.localPort
        let path = (context.metadata.extra["grpcPath"] as? String) ?? "/"
        guard let dbGroup = context.recorder.taskDatabaseGroup else { return nil }
        return GRPCRecorder(flowId: flowId, host: host, port: port, path: path, dbGroup: dbGroup)
    }
}
