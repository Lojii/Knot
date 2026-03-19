import Foundation

/// Record of a payload modification (MITM or replay).
/// Maps to the `modify_log` table in state.db.
public struct ModifyLogEntry {
    public let flowId: String
    public let direction: Int          // 0=request, 1=response
    public let modifyType: String      // "header" / "body" / "both"
    public let originalRef: String
    public let modifiedRef: String
    public let diffSummary: String
    public let source: String          // "manual" / "script:{name}"
    public let modifiedAt: TimeInterval

    public init(flowId: String, direction: Int, modifyType: String,
                originalRef: String = "", modifiedRef: String = "",
                diffSummary: String = "", source: String = "",
                modifiedAt: TimeInterval) {
        self.flowId = flowId
        self.direction = direction
        self.modifyType = modifyType
        self.originalRef = originalRef
        self.modifiedRef = modifiedRef
        self.diffSummary = diffSummary
        self.source = source
        self.modifiedAt = modifiedAt
    }
}
