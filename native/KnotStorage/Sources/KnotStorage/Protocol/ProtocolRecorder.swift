import Foundation

/// Context passed to ProtocolRecorder.buildFlowRecord() — replaces SessionRecorder dependency
public struct FlowBuildContext {
    public let flowId: String
    public let reqPayloadRef: String
    public let rspPayloadRef: String
    public let uploadBytes: Int64
    public let downloadBytes: Int64
    public let protoFlags: Int
    public let connReuse: Int
    public let certChainRef: String?

    public init(flowId: String, reqPayloadRef: String = "", rspPayloadRef: String = "",
                uploadBytes: Int64 = 0, downloadBytes: Int64 = 0,
                protoFlags: Int = 0, connReuse: Int = 0, certChainRef: String? = nil) {
        self.flowId = flowId
        self.reqPayloadRef = reqPayloadRef
        self.rspPayloadRef = rspPayloadRef
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.protoFlags = protoFlags
        self.connReuse = connReuse
        self.certChainRef = certChainRef
    }
}

/// Interface for protocol-specific recording.
/// Each protocol (HTTP, WebSocket, DNS, etc.) implements this to produce FlowRecords.
public protocol ProtocolRecorder: AnyObject {
    static var protocolName: String { get }
    static var searchKeyMapping: SearchKeyMapping { get }
    func buildFlowRecord(context: FlowBuildContext) -> FlowRecord
}

extension ProtocolRecorder {
    public func buildFlowRecord() -> FlowRecord {
        buildFlowRecord(context: FlowBuildContext(flowId: ""))
    }
}
