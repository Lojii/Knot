import Foundation
import SQLite

public struct CaptureTaskRecord {
    public var id: Int64 = 0
    public var name: String = ""
    public var createdAt: TimeInterval = 0
    public var status: Int = 0
    // ... add other fields as needed for queries
    public init() {}
}

public struct RuleRecord {
    public var id: Int64 = 0
    public var name: String = ""
    public var config: String = ""
    public var defaultStrategy: String = "DIRECT"
    public var blacklistEnabled: Bool = false
    public var createdAt: TimeInterval = 0
    public var author: String = ""
    public var note: String = ""
    public init() {}

    /// Parsed rule items from config via RuleEngine.
    public var ruleItems: [RuleItem] {
        let engine = RuleEngine(config: config)
        return engine.validRuleItems
    }

    /// Parsed host items from config via RuleEngine.
    public var hosts: [HostItem] {
        let engine = RuleEngine(config: config)
        return engine.lines.compactMap { $0 as? HostItem }
    }

    /// All parsed lines from config via RuleEngine.
    public var lines: [RuleLine] {
        let engine = RuleEngine(config: config)
        return engine.lines
    }
}

public struct BreakpointRecord {
    public var id: Int64 = 0
    public var enabled: Bool = true
    public var matchPhase: String = "request"
    public var matchProtocol: String = "*"
    public var matchPattern: String = ""
    public var action: String = "pause"
    public var scriptRef: String = ""
    public var priority: Int = 0
    public var createdAt: TimeInterval = 0
    public var note: String = ""
    public init() {}
}

public enum CatalogDAO {
    // MARK: - CaptureTask

    @discardableResult
    public static func insertTask(db: Connection, name: String, createdAt: TimeInterval) throws -> Int64 {
        try db.run("INSERT INTO capture_task (name, created_at) VALUES (?, ?)", name, createdAt)
        return db.lastInsertRowid
    }

    public static func updateTask(db: Connection, taskId: Int64, flowCount: Int64? = nil,
                                  uploadBytes: Int64? = nil, downloadBytes: Int64? = nil,
                                  status: Int? = nil) throws {
        var sets: [String] = []
        var bindings: [Binding?] = []
        if let v = flowCount { sets.append("flow_count = ?"); bindings.append(v) }
        if let v = uploadBytes { sets.append("upload_bytes = ?"); bindings.append(v) }
        if let v = downloadBytes { sets.append("download_bytes = ?"); bindings.append(v) }
        if let v = status { sets.append("status = ?"); bindings.append(Int64(v)) }
        guard !sets.isEmpty else { return }
        bindings.append(taskId)
        try db.run("UPDATE capture_task SET \(sets.joined(separator: ", ")) WHERE id = ?", bindings)
    }

    public static func findAllTasks(db: Connection) throws -> [CaptureTaskRecord] {
        let stmt = try db.prepare("SELECT id, name, created_at, status FROM capture_task ORDER BY created_at DESC")
        return stmt.map { row in
            var r = CaptureTaskRecord()
            r.id = row[0] as? Int64 ?? 0
            r.name = row[1] as? String ?? ""
            r.createdAt = row[2] as? Double ?? 0
            r.status = Int(row[3] as? Int64 ?? 0)
            return r
        }
    }

    public static func deleteTask(db: Connection, taskId: Int64) throws {
        try db.run("DELETE FROM capture_task WHERE id = ?", taskId)
    }

    /// Insert a full CaptureTask with all columns. Returns the new row id.
    @discardableResult
    public static func insertFullTask(db: Connection, task: CaptureTask) throws -> Int64 {
        try db.run("""
            INSERT INTO capture_task
                (name, created_at, started_at, stopped_at, status, rule_id,
                 local_ip, local_port, local_enabled, wifi_ip, wifi_port, wifi_enabled,
                 flow_count, upload_bytes, download_bytes, note, extra)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            task.ruleName,
            task.creatTime ?? Date().timeIntervalSince1970,
            task.startTime,
            task.stopTime,
            Int64(task.numberOfUse),
            task.ruleId.map { Int64($0) },
            task.localIP,
            Int64(task.localPort),
            Int64(task.localEnable),
            task.wifiIP,
            Int64(task.wifiPort),
            Int64(task.wifiEnable),
            task.interceptCount,
            task.uploadTraffic,
            task.downloadFlow,
            task.note,
            task.extra
        )
        return db.lastInsertRowid
    }

    /// Update all mutable columns of a CaptureTask by id.
    public static func updateFullTask(db: Connection, task: CaptureTask) throws {
        try db.run("""
            UPDATE capture_task SET
                name = ?, started_at = ?, stopped_at = ?, status = ?, rule_id = ?,
                local_ip = ?, local_port = ?, local_enabled = ?,
                wifi_ip = ?, wifi_port = ?, wifi_enabled = ?,
                flow_count = ?, upload_bytes = ?, download_bytes = ?,
                note = ?, extra = ?
            WHERE id = ?
            """,
            task.ruleName,
            task.startTime,
            task.stopTime,
            Int64(task.numberOfUse),
            task.ruleId.map { Int64($0) },
            task.localIP,
            Int64(task.localPort),
            Int64(task.localEnable),
            task.wifiIP,
            Int64(task.wifiPort),
            Int64(task.wifiEnable),
            task.interceptCount,
            task.uploadTraffic,
            task.downloadFlow,
            task.note,
            task.extra,
            task.id
        )
    }

    /// Find the most recent task from catalog.db, populating all CaptureTask fields.
    public static func findLastTask(db: Connection) -> CaptureTask? {
        do {
            let stmt = try db.prepare("""
                SELECT id, name, created_at, started_at, stopped_at, status, rule_id,
                       local_ip, local_port, local_enabled,
                       wifi_ip, wifi_port, wifi_enabled,
                       flow_count, upload_bytes, download_bytes, note, extra
                FROM capture_task ORDER BY id DESC LIMIT 1
                """)
            for row in stmt {
                let task = CaptureTask()
                task.id = row[0] as? Int64 ?? 0
                task.ruleName = row[1] as? String ?? ""
                task.creatTime = row[2] as? Double
                task.startTime = row[3] as? Double
                task.stopTime = row[4] as? Double
                task.numberOfUse = Int(row[5] as? Int64 ?? 0)
                task.ruleId = row[6] as? Int64
                task.localIP = row[7] as? String ?? ProxyConfig.LocalProxy.host
                task.localPort = Int(row[8] as? Int64 ?? Int64(ProxyConfig.LocalProxy.port))
                task.localEnable = Int(row[9] as? Int64 ?? 1)
                task.wifiIP = row[10] as? String ?? ""
                task.wifiPort = Int(row[11] as? Int64 ?? Int64(ProxyConfig.LocalProxy.port))
                task.wifiEnable = Int(row[12] as? Int64 ?? 1)
                task.interceptCount = row[13] as? Int64 ?? 0
                task.uploadTraffic = row[14] as? Int64 ?? 0
                task.downloadFlow = row[15] as? Int64 ?? 0
                task.note = row[16] as? String ?? ""
                task.extra = row[17] as? String ?? ""
                return task
            }
        } catch {
            print("findLastTask error: \(error)")
        }
        return nil
    }

    // MARK: - Rule

    @discardableResult
    public static func insertRule(db: Connection, name: String, config: String, createdAt: TimeInterval,
                                  defaultStrategy: String = "DIRECT", blacklistEnabled: Bool = false,
                                  author: String = "", note: String = "") throws -> Int64 {
        try db.run("""
            INSERT INTO rule (name, config, created_at, default_strategy, blacklist_enabled, author, note)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            name, config, createdAt, defaultStrategy, blacklistEnabled ? 1 : 0, author, note
        )
        return db.lastInsertRowid
    }

    public static func findAllRules(db: Connection) throws -> [RuleRecord] {
        let stmt = try db.prepare(
            "SELECT id, name, config, default_strategy, blacklist_enabled, created_at, author, note FROM rule ORDER BY created_at DESC"
        )
        return stmt.map { row in
            var r = RuleRecord()
            r.id = row[0] as? Int64 ?? 0
            r.name = row[1] as? String ?? ""
            r.config = row[2] as? String ?? ""
            r.defaultStrategy = row[3] as? String ?? "DIRECT"
            r.blacklistEnabled = (row[4] as? Int64 ?? 0) == 1
            r.createdAt = row[5] as? Double ?? 0
            r.author = row[6] as? String ?? ""
            r.note = row[7] as? String ?? ""
            return r
        }
    }

    public static func findRule(db: Connection, id: Int64) throws -> RuleRecord? {
        let stmt = try db.prepare(
            "SELECT id, name, config, default_strategy, blacklist_enabled, created_at, author, note FROM rule WHERE id = ?", id
        )
        for row in stmt {
            var r = RuleRecord()
            r.id = row[0] as? Int64 ?? 0
            r.name = row[1] as? String ?? ""
            r.config = row[2] as? String ?? ""
            r.defaultStrategy = row[3] as? String ?? "DIRECT"
            r.blacklistEnabled = (row[4] as? Int64 ?? 0) == 1
            r.createdAt = row[5] as? Double ?? 0
            r.author = row[6] as? String ?? ""
            r.note = row[7] as? String ?? ""
            return r
        }
        return nil
    }

    public static func updateRule(db: Connection, record: RuleRecord) throws {
        try db.run("""
            UPDATE rule SET name = ?, config = ?, default_strategy = ?, blacklist_enabled = ?, author = ?, note = ?
            WHERE id = ?
            """,
            record.name, record.config, record.defaultStrategy,
            record.blacklistEnabled ? 1 : 0, record.author, record.note,
            record.id
        )
    }

    public static func deleteRule(db: Connection, id: Int64) throws {
        try db.run("DELETE FROM rule WHERE id = ?", id)
    }

    // MARK: - Breakpoint

    public static func insertBreakpoint(db: Connection, matchPattern: String, action: String, createdAt: TimeInterval,
                                        matchPhase: String = "request", matchProtocol: String = "*",
                                        scriptRef: String = "", priority: Int = 0, note: String = "") throws {
        try db.run("""
            INSERT INTO breakpoint (match_pattern, action, created_at, match_phase,
                match_protocol, script_ref, priority, note)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            matchPattern, action, createdAt, matchPhase, matchProtocol, scriptRef, priority, note
        )
    }

    public static func findEnabledBreakpoints(db: Connection) throws -> [BreakpointRecord] {
        let stmt = try db.prepare("SELECT * FROM breakpoint WHERE enabled = 1 ORDER BY priority DESC")
        return stmt.map { row in
            var bp = BreakpointRecord()
            bp.id = row[0] as? Int64 ?? 0
            bp.enabled = (row[1] as? Int64 ?? 0) == 1
            bp.matchPhase = row[2] as? String ?? "request"
            bp.matchProtocol = row[3] as? String ?? "*"
            bp.matchPattern = row[4] as? String ?? ""
            bp.action = row[5] as? String ?? "pause"
            bp.scriptRef = row[6] as? String ?? ""
            bp.priority = Int(row[7] as? Int64 ?? 0)
            bp.createdAt = row[8] as? Double ?? 0
            bp.note = row[9] as? String ?? ""
            return bp
        }
    }
}
