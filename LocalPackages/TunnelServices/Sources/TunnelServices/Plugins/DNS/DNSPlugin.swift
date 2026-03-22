import Foundation
import NIO
import KnotStorage

/// Plugin for DNS traffic.
///
/// Detection is port-based: port 53 → `.yes(95)`.
/// Pipeline setup is a no-op for now (DNS capture is not yet integrated into
/// the NIO pipeline; it is handled outside the proxy path).
public final class DNSPlugin: ProtocolPlugin {
    public let id = "dns"
    public let displayName = "DNS"

    public init() {}

    // MARK: - ProtocolPlugin

    /// Port-based detection: returns `.yes(95)` when `localPort == 53`.
    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        return context.localPort == 53 ? .yes(confidence: 95) : .no
    }

    /// No-op: DNS capture is not yet integrated into the NIO pipeline.
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    /// Creates a `DNSRecorder` for the given flow.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        let serverIp = context.channel.remoteAddress?.description ?? "unknown"
        let serverPort = context.metadata.innerPort ?? context.task.localPort
        let transport: DNSTransport = context.metadata.isEncrypted ? .doh : .udp
        return DNSRecorder(flowId: flowId, transport: transport,
                           serverIp: serverIp, serverPort: serverPort)
    }
}
