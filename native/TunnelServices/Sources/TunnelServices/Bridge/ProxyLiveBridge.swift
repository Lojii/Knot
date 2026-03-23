//
//  ProxyLiveBridge.swift
//  TunnelServices
//
//  Concrete LiveBridge used by ProxyServer to push real-time events
//  from the capture pipeline into KnotWebService's WebSocket clients.
//

import Foundation
import KnotWebService

public class ProxyLiveBridge: LiveBridge {
    public var onNewFlow: (([String: Any]) -> Void)?
    public var onFlowUpdate: (([String: Any]) -> Void)?
    public var onMetrics: (([String: Any]) -> Void)?
    public var onStats: (([String: Any]) -> Void)?
    public var onRetest: (([String: Any]) -> Void)?
    public var onSurfProgress: (([String: Any]) -> Void)?
    public var onBreakpointHit: (([String: Any]) -> Void)?
    public var onBreakpointResume: ((String, String, [String: Any]?) -> Void)?
    public init() {}
}
