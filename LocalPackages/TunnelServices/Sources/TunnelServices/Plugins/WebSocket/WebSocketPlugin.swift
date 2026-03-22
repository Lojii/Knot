import Foundation
import NIO
import KnotStorage

/// Plugin for WebSocket traffic (WS / WSS).
///
/// WebSocket connections are initiated by an HTTP/1.x Upgrade request.
/// Detection therefore happens inside `HTTP1Plugin` / `HTTPCaptureHandler`
/// (via `WebSocketUpgradeInterceptor`) rather than at the top-level
/// byte-inspection stage.  This plugin exists to own the WebSocket files
/// in the plugin tree and to provide `WebSocketRecorder` creation.
public final class WebSocketPlugin: ProtocolPlugin {
    public let id = "websocket"
    public let displayName = "WebSocket"

    public init() {}

    // MARK: - ProtocolPlugin

    /// Always returns `.no` — WebSocket is detected via the HTTP Upgrade
    /// header, driven by `HTTP1Plugin`.
    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        return .no
    }

    /// Adds `WebSocketUpgradeInterceptor` to the pipeline.
    /// This is called by HTTP1Plugin when an Upgrade: websocket request is
    /// detected and a dedicated pipeline switch is needed.
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let interceptor = WebSocketUpgradeInterceptor(
            recorder: context.recorder,
            task: context.task,
            isSSL: context.parentProtocol == "tls"
        )
        return context.channel.pipeline.addHandler(interceptor, name: "ws.upgradeInterceptor")
    }

    /// Creates a `WebSocketRecorder` for the given flow.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        let host = context.metadata.innerHost
            ?? context.metadata.sni
            ?? (context.channel.remoteAddress?.description ?? "unknown")
        let port = context.metadata.innerPort ?? context.task.localPort
        let isSecure = context.parentProtocol == "tls"
        let uri = (context.metadata.extra["wsURI"] as? String) ?? ""
        guard let dbGroup = context.recorder.taskDatabaseGroup else { return nil }
        return WebSocketRecorder(flowId: flowId, host: host, port: port,
                                 isSecure: isSecure, uri: uri, dbGroup: dbGroup)
    }
}
