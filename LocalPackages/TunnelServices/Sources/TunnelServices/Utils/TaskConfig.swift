//
//  TaskConfig.swift
//  TunnelServices
//
//  Runtime configuration for a capture task.
//  Replaces CaptureTask's runtime state without ASModel dependency.
//  Database persistence is handled by DatabaseManager + CatalogDAO.
//

import Foundation

/// Lightweight runtime configuration holder for a capture task.
/// Holds certificate management, rule engine, proxy config, and IPC —
/// everything handlers need at runtime — without any database (ASModel) coupling.
public class TaskConfig {

    public let taskId: Int64

    // MARK: - Certificate management

    public let certManager: CertManager

    // MARK: - Rule engine

    public let ruleEngine: RuleEngine

    // MARK: - Proxy configuration

    public var localIP: String = ProxyConfig.LocalProxy.host
    public var localPort: Int = ProxyConfig.LocalProxy.port
    public var localEnabled: Bool = true
    public var wifiIP: String = ""
    public var wifiPort: Int = ProxyConfig.LocalProxy.port
    public var wifiEnabled: Bool = true
    public var sslEnabled: Bool = true

    // MARK: - Lifecycle

    public var startTime: TimeInterval = 0
    public var stopTime: TimeInterval = 0
    public var fileFolder: String = ""

    // MARK: - IPC (real-time traffic reporting)

    public var ipc: AppGroupIPC?

    // MARK: - Init

    public init(taskId: Int64, certManager: CertManager, ruleEngine: RuleEngine) {
        self.taskId = taskId
        self.certManager = certManager
        self.ruleEngine = ruleEngine
    }

    /// Convenience factory: build a TaskConfig from catalog data and perform
    /// runtime initialization (cert loading, rule parsing).
    public static func fromCatalog(taskId: Int64, ruleConfig: String) -> TaskConfig {
        let certMgr = CertManager()
        let engine = RuleEngine(config: ruleConfig)
        return TaskConfig(taskId: taskId, certManager: certMgr, ruleEngine: engine)
    }

    /// Build the full path for storing payload files for this task.
    public func getFullPath(storeFolder: String) -> String {
        return storeFolder + fileFolder
    }

    /// Create the file folder on disk if it doesn't already exist.
    public func createFileFolder(storeFolder: String) {
        let filePath = getFullPath(storeFolder: storeFolder)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: filePath, isDirectory: &isDir)
        if exists && !isDir.boolValue {
            try? fm.removeItem(atPath: filePath)
            try? fm.createDirectory(atPath: filePath, withIntermediateDirectories: true, attributes: nil)
        }
        if !exists {
            try? fm.createDirectory(atPath: filePath, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
