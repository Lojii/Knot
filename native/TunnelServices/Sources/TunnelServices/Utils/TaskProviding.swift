//
//  TaskProviding.swift
//  TunnelServices
//
//  Protocol for providing task configuration to handlers.
//  Both legacy CaptureTask and new TaskConfig conform to this.
//

import Foundation

/// Protocol for providing task configuration to handlers.
/// Both legacy CaptureTask and new TaskConfig conform to this.
public protocol TaskProviding: AnyObject {
    var taskId: Int64 { get }
    var taskCertManager: CertManager { get }
    var fileFolder: String { get }
    var sslEnabled: Bool { get }
    var localEnabled: Bool { get }
    var wifiEnabled: Bool { get }
    func matchesRule(host: String, uri: String, target: String) -> Bool
    var defaultStrategy: Strategy { get }
}
