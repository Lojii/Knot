import Foundation

/// A single transport-layer packet record.
/// Maps to the `packet` table in transport.db.
public struct PacketRow {
    public let flowId: String
    public let direction: Int        // 0=inbound, 1=outbound
    public let timestamp: TimeInterval
    public let ipVersion: Int        // 4 or 6
    public let srcIp: String
    public let dstIp: String
    public let transport: Int        // 6=TCP, 17=UDP, 1=ICMP
    public let srcPort: Int
    public let dstPort: Int
    public let seqNo: Int64
    public let ackNo: Int64
    public let tcpFlags: Int
    public let windowSize: Int
    public let payloadLength: Int
    public let payloadRef: String

    public init(flowId: String, direction: Int, timestamp: TimeInterval,
                ipVersion: Int = 4, srcIp: String, dstIp: String,
                transport: Int, srcPort: Int = 0, dstPort: Int = 0,
                seqNo: Int64 = 0, ackNo: Int64 = 0, tcpFlags: Int = 0,
                windowSize: Int = 0, payloadLength: Int = 0, payloadRef: String = "") {
        self.flowId = flowId
        self.direction = direction
        self.timestamp = timestamp
        self.ipVersion = ipVersion
        self.srcIp = srcIp
        self.dstIp = dstIp
        self.transport = transport
        self.srcPort = srcPort
        self.dstPort = dstPort
        self.seqNo = seqNo
        self.ackNo = ackNo
        self.tcpFlags = tcpFlags
        self.windowSize = windowSize
        self.payloadLength = payloadLength
        self.payloadRef = payloadRef
    }

    /// Convenience factory for tests
    public static func stub(flowId: String) -> PacketRow {
        PacketRow(flowId: flowId, direction: 1, timestamp: Date().timeIntervalSince1970,
                  srcIp: "192.168.1.1", dstIp: "10.0.0.1", transport: 6,
                  srcPort: 12345, dstPort: 443)
    }
}
