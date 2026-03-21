//
//  CaptureTask.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/1.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import NIO
import Security
import NIOConcurrencyHelpers
import CocoaAsyncSocket
import SQLite

public let TaskDidChangedNotification = AppNotification.taskDidChanged
public let TaskValueDidChanged = AppNotification.taskValueDidChanged
public let TaskConfigDidChanged = AppNotification.taskConfigDidChanged

public class CaptureTask: NSObject {

    // MARK: - Persisted properties (mapped to catalog.db capture_task table)

    public var id: Int64 = 0
    //
    var numberOfUse: Int = 0
    //
    public var localIP: String = ProxyConfig.LocalProxy.host
    public var localPort: Int = ProxyConfig.LocalProxy.port
    public var localEnable: Int = 1
    public var localState: Int = 0

    public var wifiIP: String = ""
    public var wifiPort: Int = ProxyConfig.LocalProxy.port
    public var wifiEnable: Int = 1
    public var wifiState: Int = 0

    //
    public var interceptCount: Int64 = 0
    public var uploadTraffic: Int64 = 0
    public var downloadFlow: Int64 = 0
    // wifi
    public var wifiInterceptCount: Int64 = 0
    public var wifiUploadTraffic: Int64 = 0
    public var wifiDownloadFlow: Int64 = 0
    // Rule info
    public var ruleName: String = ""
    public var ruleId: Int64?
    //
    public var sslEnable: Int = 1
    public var creatTime: TimeInterval?
    public var startTime: TimeInterval?
    public var stopTime: TimeInterval?

    public var note: String = ""
    public var extra: String = ""

    public var saveCount: Int = 0

    public var fileFolder: String = ""

    public var ruleEngine: RuleEngine!
    // Certificate management (CA cert, private key, cert pool)
    public var certManager: CertManager!
    public var ipc: AppGroupIPC?
    var udpSocket: GCDAsyncUdpSocket?

    /// Outbound connection pool for reusing TCP connections across client sessions.
    public lazy var connectionPool = OutboundConnectionPool()

    /// Hosts where MITM TLS handshake failed (client rejected our CA cert).
    /// When a host is in this set, ConnectHandler skips MITM and uses tunnel passthrough.
    /// This allows automatic fallback: first connection to a host fails (handshake error),
    /// subsequent connections to the same host work via transparent tunnel.
    public let mitmFailedHosts = MITMFailedHostTracker()

    /// Cached result of CA certificate trust check.
    /// nil = not yet checked, true = trusted, false = not trusted.
    /// When false, all HTTPS connections use tunnel passthrough.
    private var _caTrustChecked = false
    private var _caTrusted = false

    /// Check whether the proxy's CA certificate is trusted by the system.
    /// Result is cached after first check. Returns true if trusted (MITM OK),
    /// false if not trusted (should tunnel).
    public var isCACertTrusted: Bool {
        if _caTrustChecked { return _caTrusted }
        _caTrustChecked = true
        _caTrusted = evaluateCATrust()
        if !_caTrusted {
            AxLogger.log("[CaptureTask] CA certificate NOT trusted by system — all HTTPS will use tunnel passthrough", level: .Warning)
        } else {
            AxLogger.log("[CaptureTask] CA certificate is trusted by system — MITM enabled", level: .Info)
        }
        return _caTrusted
    }

    /// Reset the cached trust check (e.g., after user installs CA cert).
    public func resetCATrustCheck() {
        _caTrustChecked = false
        _caTrusted = false
        mitmFailedHosts.clear()
    }

    private func evaluateCATrust() -> Bool {
        guard let cm = certManager, cm.isValid else {
            AxLogger.log("[CaptureTask] certManager is nil or invalid — CA not trusted", level: .Warning)
            return false
        }

        // Try to get the CA cert as SecCertificate via DER bytes
        guard let x509CA = cm.x509CACert else { return false }
        do {
            let derBytes = try CertGenerator.toDER(x509CA)
            guard let secCert = SecCertificateCreateWithData(nil, derBytes as CFData) else {
                return false
            }

            // Evaluate trust against system trust store
            var trust: SecTrust?
            let policy = SecPolicyCreateBasicX509()
            let status = SecTrustCreateWithCertificates(secCert, policy, &trust)
            guard status == errSecSuccess, let t = trust else { return false }

            var error: CFError?
            let result = SecTrustEvaluateWithError(t, &error)
            return result
        } catch {
            AxLogger.log("[CaptureTask] CA trust evaluation failed: \(error)", level: .Warning)
            return false
        }
    }
}

// MARK: - MITM Failed Host Tracker

/// Thread-safe tracker for hosts where MITM TLS handshake failed.
/// Entries expire after 5 minutes to allow retrying if the user installs the CA cert.
public final class MITMFailedHostTracker {
    private var hosts: [String: TimeInterval] = [:]  // host → expiry timestamp
    private let lock = NIOLock()
    private static let ttl: TimeInterval = 300  // 5 minutes

    public init() {}

    /// Mark a host as MITM-failed.
    public func add(_ host: String) {
        lock.withLock {
            hosts[host] = Date().timeIntervalSince1970 + MITMFailedHostTracker.ttl
        }
        AxLogger.log("[MITMFallback] added \(host) — will tunnel for next 5 min", level: .Warning)
    }

    /// Check if a host should skip MITM and use tunnel instead.
    public func shouldTunnel(_ host: String) -> Bool {
        lock.withLock {
            guard let expiry = hosts[host] else { return false }
            if Date().timeIntervalSince1970 > expiry {
                hosts.removeValue(forKey: host)
                return false  // expired, retry MITM
            }
            return true
        }
    }

    /// Clear all entries (e.g., when user installs CA cert).
    public func clear() {
        lock.withLock { hosts.removeAll() }
    }
}

// MARK: - CaptureTask Persistence & Lifecycle

extension CaptureTask {

    // MARK: - Persistence helpers

    /// Save a new task to catalog.db. Sets self.id from the inserted row.
    public func save() throws {
        let db = DatabaseManager.shared.catalogDB
        let rowId = try CatalogDAO.insertFullTask(db: db, task: self)
        self.id = rowId
    }

    /// Update this task in catalog.db.
    public func update() throws {
        let db = DatabaseManager.shared.catalogDB
        try CatalogDAO.updateFullTask(db: db, task: self)
    }

    // MARK: - Factory methods

    public static func newTask() -> CaptureTask {
        let task = CaptureTask()
        // Load rule from catalog.db via CatalogDAO
        let catalogDB = DatabaseManager.shared.catalogDB
        let ruleRecord: RuleRecord? = {
            if let currentRuleIdStr = UserDefaults.standard.string(forKey: CurrentRuleId),
               let currentRuleId = Int64(currentRuleIdStr),
               let record = try? CatalogDAO.findRule(db: catalogDB, id: currentRuleId) {
                return record
            }
            // Fall back to first available rule
            if let first = (try? CatalogDAO.findAllRules(db: catalogDB))?.first {
                UserDefaults.standard.set("\(first.id)", forKey: CurrentRuleId)
                UserDefaults.standard.synchronize()
                return first
            }
            // No rules exist -- create a default one
            if let newId = try? CatalogDAO.insertRule(
                db: catalogDB, name: "Knot(Default)", config: "",
                createdAt: Date().timeIntervalSince1970,
                defaultStrategy: "DIRECT", blacklistEnabled: true, author: "Knot") {
                UserDefaults.standard.set("\(newId)", forKey: CurrentRuleId)
                UserDefaults.standard.synchronize()
                return try? CatalogDAO.findRule(db: catalogDB, id: newId)
            }
            return nil
        }()
        task.ruleEngine = RuleEngine(config: ruleRecord?.config ?? "")
        task.ruleName = ruleRecord?.name ?? "Knot(Default)"
        task.ruleId = ruleRecord?.id
        //
        task.creatTime = Date().timeIntervalSince1970
        let creatTimeStr = "\(task.creatTime!)".components(separatedBy: ".")
        task.fileFolder = "\(creatTimeStr.first ?? "temp")\(creatTimeStr.last ?? "")"
        task.startTime = Date().timeIntervalSince1970
        AxLogger.log("Task FileFolder:\(task.fileFolder)", level: .Info)
        // Get wifi address
        let wifiIP = NetworkInfo.LocalWifiIPv4()
        if wifiIP != "" {
            task.wifiIP = wifiIP
        }
        return task
    }

    public static func getLast(_ parseConfig: Bool = true) -> CaptureTask? {
        let catalogDB = DatabaseManager.shared.catalogDB
        guard let record = (try? CatalogDAO.findAllTasks(db: catalogDB))?.first else {
            return nil
        }
        let task = CaptureTask()
        task.id = record.id
        task.creatTime = record.createdAt
        task.numberOfUse = record.status  // status encodes numberOfUse
        // Load stats
        task.setNumbers()

        if !parseConfig {
            return task
        }
        // Load rule from catalog.db via CatalogDAO
        let ruleRecord: RuleRecord? = {
            if let ruleid = task.ruleId,
               let record = try? CatalogDAO.findRule(db: catalogDB, id: ruleid) {
                return record
            }
            // Fall back to first available rule
            if let first = (try? CatalogDAO.findAllRules(db: catalogDB))?.first {
                UserDefaults.standard.set("\(first.id)", forKey: CurrentRuleId)
                UserDefaults.standard.synchronize()
                return first
            }
            // No rules exist -- create a default one
            if let newId = try? CatalogDAO.insertRule(
                db: catalogDB, name: "Knot(Default)", config: "",
                createdAt: Date().timeIntervalSince1970,
                defaultStrategy: "DIRECT", blacklistEnabled: true, author: "Knot") {
                UserDefaults.standard.set("\(newId)", forKey: CurrentRuleId)
                UserDefaults.standard.synchronize()
                return try? CatalogDAO.findRule(db: catalogDB, id: newId)
            }
            return nil
        }()
        task.ruleEngine = RuleEngine(config: ruleRecord?.config ?? "")
        if parseConfig {
            task.loadCACert()
            task.addSender()
        }
        return task
    }

    public static func getSQL(pageSize: Int = 999999, pageIndex: Int = 0, orderBy: String = "id") -> String {
        let sql = "select t.id,t.started_at as startTime,t.stopped_at as stopTime,t.name as ruleName,t.rule_id as ruleId,t.flow_count as sessionCount,t.download_bytes as downloadFlowSum,t.upload_bytes as uploadTrafficSum from capture_task t order by t.\(orderBy) desc limit \(pageSize) offset \(pageSize*pageIndex)"
        return sql
    }

    public static func deleteAll(taskIds: [Int]) -> Bool {
        if taskIds.count <= 0 { return true }
        let s = taskIds.map { "\($0)" }
        let sql = "delete from capture_task where id in ( \(s.joined(separator: ",")) )"
        print("sql:\(sql)")
        let db = DatabaseManager.shared.catalogDB
        do {
            try db.run(sql)
            return true
        } catch {
            print("delete tasks error:\(error.localizedDescription)")
            return false
        }
    }

    public static func getAllIds() -> [Int] {
        let sql = "select id from capture_task"
        let db = DatabaseManager.shared.catalogDB
        var results = [Int]()
        do {
            let result = try db.prepare(sql)
            for row in result {
                if let taskId = row[0] as? Int64 {
                    results.append(Int(taskId))
                }
            }
        } catch {
            print("getAll error:\(error)")
        }
        return results
    }

    public static func findAll(pageSize: Int = 999999, pageIndex: Int = 0, orderBy: String?) -> [CaptureTask] {
        let sql = getSQL(pageSize: pageSize, pageIndex: pageIndex, orderBy: orderBy ?? "id")
        let db = DatabaseManager.shared.catalogDB
        var tasks = [CaptureTask]()
        do {
            let result = try db.prepare(sql)
            let columnNames: [String] = result.columnNames
            for row in result {
                if let task = getWith(columnNames: columnNames, row: row) {
                    tasks.append(task)
                }
            }
        } catch {
            print("getAll error:\(error)")
        }
        return tasks
    }

    static func getWith(columnNames: [String], row: Statement.Element) -> CaptureTask? {
        let task = CaptureTask()
        for i in 0..<columnNames.count {
            let columnName = columnNames[i]
            guard let value = row[i] else {
                continue
            }
            switch columnName {
            case "id":
                task.id = value as? Int64 ?? 0
            case "ruleName":
                task.ruleName = value as? String ?? ""
            case "ruleId":
                task.ruleId = value as? Int64
            case "sessionCount":
                task.interceptCount = value as? Int64 ?? 0
            case "downloadFlowSum":
                task.downloadFlow = value as? Int64 ?? 0
            case "uploadTrafficSum":
                task.uploadTraffic = value as? Int64 ?? 0
            case "startTime":
                task.startTime = value as? Double
            case "stopTime":
                task.stopTime = value as? Double
            default:
                break
            }
        }
        return task
    }

    public func setNumbers() {
        let sql = "select flow_count, download_bytes, upload_bytes from capture_task where id = \(id)"
        let db = DatabaseManager.shared.catalogDB
        do {
            let result = try db.prepare(sql)
            for row in result {
                interceptCount = row[0] as? Int64 ?? 0
                downloadFlow = row[1] as? Int64 ?? 0
                uploadTraffic = row[2] as? Int64 ?? 0
                return
            }
        } catch {
            print("setNumbers error:\(error)")
        }
    }

    func loadCACert() {
        certManager = CertManager()
    }

    func addSender() {
        if udpSocket == nil {
            udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.global())
        }
        if ipc == nil {
            ipc = AppGroupIPC(groupIdentifier: GROUPNAME)
            ipc?.listenForMessage(identifier: TaskConfigDidChanged, listener: { [weak self] value in
                if let json = value as? String {
                    let dic = [String: String].fromJson(json)
                    if let wifi = dic["wifiEnable"], let v = Int(wifi) {
                        self?.wifiEnable = v
                    }
                    if let local = dic["localEnable"], let v = Int(local) {
                        self?.localEnable = v
                    }
                    try? self?.update()
                    AxLogger.log("TaskConfigDidChanged:\(json)", level: .Info)
                }
            })
        }
    }

    func sendInfo(data: Data) {
        udpSocket?.send(data, toHost: ProxyConfig.IPC.udpHost, port: ProxyConfig.IPC.udpPort, withTimeout: -1, tag: 1)
    }

    func sendInfo(url: String, uploadTraffic: Int64, downloadFlow: Int64) {
        var infoDic = [String: String]()
        infoDic["url"] = url
        infoDic["uploadTraffic"] = "\(uploadTraffic)"
        infoDic["downloadFlow"] = "\(downloadFlow)"
        let info = infoDic.toJson()
        if let data = info.data(using: .utf8) {
            sendInfo(data: data)
        }
    }

    func getFullPath() -> String {
        var filePath = MitmService.getStoreFolder()
        filePath.append("\(fileFolder)")
        return filePath
    }

    func createFileFolder() {
        let filePath = getFullPath()
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        let isExits = fileManager.fileExists(atPath: filePath, isDirectory: &isDir)
        if isExits, isDir.boolValue {
            let errorStr = "Delete \(fileFolder), Because it's not a folder!"
            NSLog(errorStr)
            try? fileManager.removeItem(atPath: filePath)
            try? fileManager.createDirectory(atPath: filePath, withIntermediateDirectories: true, attributes: nil)
        }
        if !isExits {
            try? fileManager.createDirectory(atPath: filePath, withIntermediateDirectories: true, attributes: nil)
        }
    }

}

extension CaptureTask: GCDAsyncUdpSocketDelegate {

}

// MARK: - TaskProviding conformance

extension CaptureTask: TaskProviding {
    public var taskId: Int64 { id }
    public var taskCertManager: CertManager { certManager }
    public var sslEnabled: Bool { sslEnable == 1 }
    public var localEnabled: Bool { localEnable == 1 }
    public var wifiEnabled: Bool { wifiEnable == 1 }
    public func matchesRule(host: String, uri: String, target: String) -> Bool {
        return ruleEngine?.matching(host: host, uri: uri, target: target) ?? false
    }
    public var defaultStrategy: Strategy { ruleEngine?.defaultStrategy ?? .DIRECT }
}
