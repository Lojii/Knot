import Foundation
import NIO

// MARK: - ProtocolRegistry

/// Singleton that owns the root protocol-detection tree.
/// Plugins register themselves as children of the TCP or UDP root nodes.
public final class ProtocolRegistry {

    public static let shared = ProtocolRegistry()

    /// The top-level transport nodes (TCP, UDP).
    public let roots: [ProtocolNode]

    /// Convenience accessor for children of the TCP root.
    public var tcpChildren: [ProtocolNode] {
        roots.first(where: { $0.plugin.id == "tcp" })?.children ?? []
    }

    private init() {
        self.roots = ProtocolRegistry.buildDefault()
    }

    static func buildDefault() -> [ProtocolNode] {
        return [
            // TCP root
            ProtocolNode(plugin: RootPlugin(id: "tcp", displayName: "TCP"), children: [
                ProtocolNode(plugin: HTTP1Plugin(), children: [
                    ProtocolNode(plugin: WebSocketPlugin(), children: []),
                ]),
                ProtocolNode(plugin: TLSPlugin(), children: [
                    ProtocolNode(plugin: HTTP1Plugin(), children: [
                        ProtocolNode(plugin: WebSocketPlugin(), children: []),
                    ]),
                    ProtocolNode(plugin: HTTP2Plugin(), children: [
                        ProtocolNode(plugin: GRPCPlugin(), children: []),
                    ]),
                ]),
                ProtocolNode(plugin: SOCKS5Plugin(), children: []),
            ]),

            // UDP root
            ProtocolNode(plugin: RootPlugin(id: "udp", displayName: "UDP"), children: [
                ProtocolNode(plugin: DNSPlugin(), children: []),
            ]),
        ]
    }
}

// MARK: - RootPlugin

/// Placeholder plugin for the transport-layer root nodes (TCP / UDP).
/// It is never asked to match or build a pipeline in production; it merely
/// anchors child plugins in the detection tree.
final class RootPlugin: ProtocolPlugin {

    let id: String
    let displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        return .no
    }

    func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        return nil
    }
}
