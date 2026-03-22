import Foundation

/// Status of a captured flow
public enum FlowStatus: Int {
    case inProgress = 0
    case completed = 1
    case failed = 2
}

/// Semantic meaning of search_key columns, per protocol
public struct SearchKeyMapping {
    public let key1: String  // e.g. "method"
    public let key2: String  // e.g. "uri"
    public let key3: String  // e.g. "statusCode"
    public let key4: String  // e.g. "contentType"

    public init(key1: String, key2: String, key3: String, key4: String) {
        self.key1 = key1
        self.key2 = key2
        self.key3 = key3
        self.key4 = key4
    }
}

/// Universal flow record used by all protocols.
/// Maps to the `flow` table in protocol.db.
public struct FlowRecord {
    public let flowId: String
    public let protocolName: String
    public let host: String
    public let port: Int
    public let startedAt: TimeInterval

    public var endedAt: TimeInterval?
    public var durationMs: Double?
    public var uploadBytes: Int64 = 0
    public var downloadBytes: Int64 = 0
    public var status: FlowStatus = .inProgress
    public var errorMessage: String = ""
    public var summary: String = ""

    // High-frequency query fields (meaning varies by protocol)
    public var searchKey1: String = ""
    public var searchKey2: String = ""
    public var searchKey3: String = ""
    public var searchKey4: String = ""

    // Detailed timeline (optional)
    public var connectAt: TimeInterval?
    public var connectedAt: TimeInterval?
    public var tlsDoneAt: TimeInterval?
    public var reqEndAt: TimeInterval?
    public var rspStartAt: TimeInterval?

    // Protocol-specific fields serialized as JSON
    public var metadata: [String: Any] = [:]

    // Payload file references
    public var reqPayloadRef: String = ""
    public var rspPayloadRef: String = ""

    // Flags
    public var isIntercepted: Bool = false
    public var isModified: Bool = false
    public var tags: String = ""

    // Protocol metadata (indexed columns for aggregate queries)
    public var connReuse: Int = 0       // 0=new, 1=keep-alive, 2=pool
    public var protoFlags: Int = 0      // ProtoFlag bitmask
    public var pushStatus: Int? = nil   // PushForwardStatus raw value
    public var certChainRef: String? = nil  // PEM file path

    public init(flowId: String, protocolName: String, host: String, port: Int, startedAt: TimeInterval) {
        self.flowId = flowId
        self.protocolName = protocolName
        self.host = host
        self.port = port
        self.startedAt = startedAt
    }
}
