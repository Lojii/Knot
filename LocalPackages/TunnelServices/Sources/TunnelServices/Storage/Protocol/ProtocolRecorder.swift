import Foundation

/// Interface for protocol-specific recording.
/// Each protocol (HTTP, WebSocket, DNS, etc.) implements this to produce FlowRecords.
public protocol ProtocolRecorder: AnyObject {
    static var protocolName: String { get }
    static var searchKeyMapping: SearchKeyMapping { get }
    func buildFlowRecord() -> FlowRecord
}
