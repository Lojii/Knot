import Foundation

public protocol LiveBridge: AnyObject {
    var onNewFlow: (([String: Any]) -> Void)? { get set }
    var onFlowUpdate: (([String: Any]) -> Void)? { get set }
    var onMetrics: (([String: Any]) -> Void)? { get set }
    var onStats: (([String: Any]) -> Void)? { get set }
    var onRetest: (([String: Any]) -> Void)? { get set }
    var onSurfProgress: (([String: Any]) -> Void)? { get set }
}
