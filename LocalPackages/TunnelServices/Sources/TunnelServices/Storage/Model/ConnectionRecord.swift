import Foundation

/// Connection state record.
/// Maps to the `connection` table in state.db.
public struct ConnectionRecord {
    public let flowId: String
    public var clientState: String
    public var serverState: String
    public var startedAt: TimeInterval
    public var closedAt: TimeInterval?
    public var closeReason: String
    public var tlsVersion: String
    public var tlsCipher: String
    public var serverCert: String

    public init(flowId: String, startedAt: TimeInterval, clientState: String = "open",
                serverState: String = "open", closedAt: TimeInterval? = nil,
                closeReason: String = "", tlsVersion: String = "",
                tlsCipher: String = "", serverCert: String = "") {
        self.flowId = flowId
        self.startedAt = startedAt
        self.clientState = clientState
        self.serverState = serverState
        self.closedAt = closedAt
        self.closeReason = closeReason
        self.tlsVersion = tlsVersion
        self.tlsCipher = tlsCipher
        self.serverCert = serverCert
    }
}
