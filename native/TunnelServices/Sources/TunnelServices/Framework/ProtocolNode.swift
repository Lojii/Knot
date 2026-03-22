import Foundation

// MARK: - ProtocolNode

/// A node in the protocol-detection tree.
/// Each node holds a plugin (the protocol handler) and zero or more child nodes
/// representing protocols that can be detected inside this one.
public struct ProtocolNode {
    public let plugin: any ProtocolPlugin
    public var children: [ProtocolNode]

    public init(plugin: any ProtocolPlugin, children: [ProtocolNode] = []) {
        self.plugin = plugin
        self.children = children
    }
}
