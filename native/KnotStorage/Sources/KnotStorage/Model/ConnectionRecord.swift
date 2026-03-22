import Foundation

/// TCP connection record.
/// Maps to the `tcp_connection` table in connection.db.
public struct TcpConnectionRecord {
    public let flowId: String
    public var srcIp: String
    public var srcPort: Int
    public var dstIp: String
    public var dstPort: Int
    public var state: String
    public var startedAt: TimeInterval
    public var establishedAt: TimeInterval?
    public var closedAt: TimeInterval?
    public var closeReason: String
    public var tlsVersion: String
    public var tlsCipher: String
    public var tlsSni: String
    public var serverCert: String
    public var packetsIn: Int64
    public var packetsOut: Int64
    public var bytesIn: Int64
    public var bytesOut: Int64

    public init(flowId: String, srcIp: String, srcPort: Int, dstIp: String, dstPort: Int,
                startedAt: TimeInterval, state: String = "open",
                establishedAt: TimeInterval? = nil, closedAt: TimeInterval? = nil,
                closeReason: String = "", tlsVersion: String = "", tlsCipher: String = "",
                tlsSni: String = "", serverCert: String = "",
                packetsIn: Int64 = 0, packetsOut: Int64 = 0,
                bytesIn: Int64 = 0, bytesOut: Int64 = 0) {
        self.flowId = flowId
        self.srcIp = srcIp; self.srcPort = srcPort
        self.dstIp = dstIp; self.dstPort = dstPort
        self.state = state; self.startedAt = startedAt
        self.establishedAt = establishedAt; self.closedAt = closedAt
        self.closeReason = closeReason
        self.tlsVersion = tlsVersion; self.tlsCipher = tlsCipher
        self.tlsSni = tlsSni; self.serverCert = serverCert
        self.packetsIn = packetsIn; self.packetsOut = packetsOut
        self.bytesIn = bytesIn; self.bytesOut = bytesOut
    }
}
