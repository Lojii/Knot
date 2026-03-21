import Foundation
import NIO
import NIOHTTP1

// MARK: - MatchResult

/// Result of a plugin's attempt to identify a protocol from a byte buffer.
public enum MatchResult: Equatable {
    /// The buffer matches this protocol with the given confidence score (0–100).
    case yes(confidence: Int)
    /// The buffer does not match this protocol.
    case no
    /// More data is required before a decision can be made.
    case needMoreData(minimum: Int)
}

// MARK: - ProtocolMetadata

/// Arbitrary metadata collected during protocol identification and parsing.
public struct ProtocolMetadata {
    public var parentId: String?
    public var alpnResult: String?
    public var sni: String?
    public var innerHost: String?
    public var innerPort: Int?
    public var isEncrypted: Bool = false
    public var extra: [String: Any] = [:]

    public static let empty = ProtocolMetadata()

    public init() {}

    public init(innerHost: String?, innerPort: Int?) {
        self.innerHost = innerHost
        self.innerPort = innerPort
    }
}

// MARK: - MatchContext

/// Contextual information available when a plugin is deciding whether it matches.
public struct MatchContext {
    public let localPort: Int
    public let remoteAddress: SocketAddress?
    public let parentProtocol: String?
    public let metadata: ProtocolMetadata

    public init(
        localPort: Int,
        remoteAddress: SocketAddress? = nil,
        parentProtocol: String? = nil,
        metadata: ProtocolMetadata = .empty
    ) {
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.parentProtocol = parentProtocol
        self.metadata = metadata
    }
}

// MARK: - ProtocolContext

/// Full context passed to a plugin when it is asked to build its NIO pipeline.
public struct ProtocolContext {
    public let channel: Channel
    public let task: CaptureTask
    public let recorder: SessionRecorder
    public let parentProtocol: String?
    public let childNodes: [ProtocolNode]
    public let metadata: ProtocolMetadata
    public let initialBuffer: ByteBuffer?

    public init(
        channel: Channel,
        task: CaptureTask,
        recorder: SessionRecorder,
        parentProtocol: String? = nil,
        childNodes: [ProtocolNode] = [],
        metadata: ProtocolMetadata = .empty,
        initialBuffer: ByteBuffer? = nil
    ) {
        self.channel = channel
        self.task = task
        self.recorder = recorder
        self.parentProtocol = parentProtocol
        self.childNodes = childNodes
        self.metadata = metadata
        self.initialBuffer = initialBuffer
    }
}

// MARK: - ProtocolPlugin

/// Core interface that every protocol plugin must conform to.
public protocol ProtocolPlugin: AnyObject {
    /// Stable, unique identifier for this plugin (e.g. `"http1"`, `"tls"`).
    var id: String { get }

    /// Human-readable name shown in the UI (e.g. `"HTTP/1.1"`, `"TLS"`).
    var displayName: String { get }

    /// Inspect `buffer` and decide whether this plugin handles the protocol.
    func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult

    /// Add the necessary NIO channel handlers for this protocol.
    func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void>

    /// Optionally create a protocol-specific recorder for the given flow.
    func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder?
}
