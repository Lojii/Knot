import Foundation

/// QUIC stream record.
/// Maps to the `quic_stream` table in connection.db.
public struct QuicStreamRecord {
    public let connectionId: String
    public let streamId: Int
    public var streamType: String
    public var state: String
    public var startedAt: TimeInterval
    public var closedAt: TimeInterval?
    public var protocolFlowId: String
    public var bytesIn: Int64
    public var bytesOut: Int64

    public init(connectionId: String, streamId: Int, startedAt: TimeInterval,
                streamType: String = "", state: String = "open",
                closedAt: TimeInterval? = nil, protocolFlowId: String = "",
                bytesIn: Int64 = 0, bytesOut: Int64 = 0) {
        self.connectionId = connectionId; self.streamId = streamId
        self.streamType = streamType; self.state = state
        self.startedAt = startedAt; self.closedAt = closedAt
        self.protocolFlowId = protocolFlowId
        self.bytesIn = bytesIn; self.bytesOut = bytesOut
    }
}
