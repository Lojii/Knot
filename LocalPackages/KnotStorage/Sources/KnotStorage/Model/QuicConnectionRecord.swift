import Foundation

/// QUIC connection record.
/// Maps to the `quic_connection` table in connection.db.
public struct QuicConnectionRecord {
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
    public var version: String
    public var dcid: String
    public var scid: String
    public var alpn: String
    public var tlsCipher: String
    public var tlsSni: String
    public var serverCert: String
    public var is0rtt: Bool
    public var packetsIn: Int64
    public var packetsOut: Int64
    public var bytesIn: Int64
    public var bytesOut: Int64
    public var streamsCount: Int64

    public init(flowId: String, srcIp: String, srcPort: Int, dstIp: String, dstPort: Int,
                startedAt: TimeInterval, state: String = "handshaking",
                establishedAt: TimeInterval? = nil, closedAt: TimeInterval? = nil,
                closeReason: String = "", version: String = "",
                dcid: String = "", scid: String = "", alpn: String = "",
                tlsCipher: String = "", tlsSni: String = "", serverCert: String = "",
                is0rtt: Bool = false,
                packetsIn: Int64 = 0, packetsOut: Int64 = 0,
                bytesIn: Int64 = 0, bytesOut: Int64 = 0, streamsCount: Int64 = 0) {
        self.flowId = flowId
        self.srcIp = srcIp; self.srcPort = srcPort
        self.dstIp = dstIp; self.dstPort = dstPort
        self.state = state; self.startedAt = startedAt
        self.establishedAt = establishedAt; self.closedAt = closedAt
        self.closeReason = closeReason
        self.version = version; self.dcid = dcid; self.scid = scid; self.alpn = alpn
        self.tlsCipher = tlsCipher; self.tlsSni = tlsSni; self.serverCert = serverCert
        self.is0rtt = is0rtt
        self.packetsIn = packetsIn; self.packetsOut = packetsOut
        self.bytesIn = bytesIn; self.bytesOut = bytesOut
        self.streamsCount = streamsCount
    }
}
