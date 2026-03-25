import Foundation
import SQLite

public struct CaptureTaskRecord {
    public var id: Int64 = 0
    public var name: String = ""
    public var createdAt: TimeInterval = 0
    public var startedAt: TimeInterval?
    public var stoppedAt: TimeInterval?
    public var status: Int = 0
    public var ruleId: Int64?
    public var localIp: String = ""
    public var localPort: Int = 0
    public var localEnabled: Int = 1
    public var wifiIp: String = ""
    public var wifiPort: Int = 0
    public var wifiEnabled: Int = 1
    public var flowCount: Int64 = 0
    public var uploadBytes: Int64 = 0
    public var downloadBytes: Int64 = 0
    public var note: String = ""
    public var extra: String = ""
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
        let stmt = try db.prepare("""
            SELECT id, name, created_at, started_at, stopped_at, status,
                   flow_count, upload_bytes, download_bytes
            FROM capture_task ORDER BY created_at DESC
        """)
        return stmt.map { row in
            var r = CaptureTaskRecord()
            r.id = row[0] as? Int64 ?? 0
            r.name = row[1] as? String ?? ""
            r.createdAt = row[2] as? Double ?? 0
            r.startedAt = row[3] as? Double
            r.stoppedAt = row[4] as? Double
            r.status = Int(row[5] as? Int64 ?? 0)
            r.flowCount = row[6] as? Int64 ?? 0
            r.uploadBytes = row[7] as? Int64 ?? 0
            r.downloadBytes = row[8] as? Int64 ?? 0
            return r
        }
    }

    /// Repair stats for all tasks with flow_count=0 by reading each task's protocol.db.
    /// This backfills historical tasks that never had their stats synced to catalog.db.
    /// Uses multiple root paths to find task directories (test temp dir + app group container).
    public static func repairAllStats(catalogDB: Connection, rootPath: String) {
        // Try both the provided rootPath and the default app group container
        var roots = [rootPath]
        let appGroupRoot = PathManager.root
        if appGroupRoot != rootPath { roots.append(appGroupRoot) }
        repairAllStatsWithRoots(catalogDB: catalogDB, roots: roots)
    }

    private static func repairAllStatsWithRoots(catalogDB: Connection, roots: [String]) {
        let tasks: [(Int64, Int64)]
        do {
            let stmt = try catalogDB.prepare("SELECT id, flow_count FROM capture_task")
            tasks = stmt.map { (($0[0] as? Int64 ?? 0), ($0[1] as? Int64 ?? 0)) }
        } catch { return }

        for (taskId, flowCount) in tasks {
            guard flowCount == 0 else { continue }

            // Try each root to find the protocol.db
            for root in roots {
                let protoPath = PathManager.protocolDBPath(taskId, root: root)
                guard FileManager.default.fileExists(atPath: protoPath) else { continue }

                do {
                    let protoDB = try Connection(protoPath, readonly: true)
                    let countStmt = try protoDB.prepare("SELECT COUNT(*), IFNULL(SUM(upload_bytes),0), IFNULL(SUM(download_bytes),0) FROM flow")
                    for row in countStmt {
                        let count = row[0] as? Int64 ?? 0
                        let upload = row[1] as? Int64 ?? 0
                        let download = row[2] as? Int64 ?? 0
                        if count > 0 {
                            try catalogDB.run(
                                "UPDATE capture_task SET flow_count = ?, upload_bytes = ?, download_bytes = ? WHERE id = ?",
                                count, upload, download, taskId
                            )
                        }
                    }
                    break
                } catch {
                    continue
                }
            }
        }
    }

    public static func renameTask(db: Connection, taskId: Int64, name: String) throws {
        try db.run("UPDATE capture_task SET name = ? WHERE id = ?", name, taskId)
    }

    public static func deleteTask(db: Connection, taskId: Int64) throws {
        try db.run("DELETE FROM capture_task WHERE id = ?", taskId)
    }

    /// Insert a full CaptureTaskRecord with all columns. Returns the new row id.
    @discardableResult
    public static func insertFullTask(db: Connection, task: CaptureTaskRecord) throws -> Int64 {
        try db.run("""
            INSERT INTO capture_task
                (name, created_at, started_at, stopped_at, status, rule_id,
                 local_ip, local_port, local_enabled, wifi_ip, wifi_port, wifi_enabled,
                 flow_count, upload_bytes, download_bytes, note, extra)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            task.name,
            task.createdAt,
            task.startedAt,
            task.stoppedAt,
            Int64(task.status),
            task.ruleId,
            task.localIp,
            Int64(task.localPort),
            Int64(task.localEnabled),
            task.wifiIp,
            Int64(task.wifiPort),
            Int64(task.wifiEnabled),
            task.flowCount,
            task.uploadBytes,
            task.downloadBytes,
            task.note,
            task.extra
        )
        return db.lastInsertRowid
    }

    /// Update all mutable columns of a CaptureTaskRecord by id.
    public static func updateFullTask(db: Connection, task: CaptureTaskRecord) throws {
        try db.run("""
            UPDATE capture_task SET
                name = ?, started_at = ?, stopped_at = ?, status = ?, rule_id = ?,
                local_ip = ?, local_port = ?, local_enabled = ?,
                wifi_ip = ?, wifi_port = ?, wifi_enabled = ?,
                flow_count = ?, upload_bytes = ?, download_bytes = ?,
                note = ?, extra = ?
            WHERE id = ?
            """,
            task.name,
            task.startedAt,
            task.stoppedAt,
            Int64(task.status),
            task.ruleId,
            task.localIp,
            Int64(task.localPort),
            Int64(task.localEnabled),
            task.wifiIp,
            Int64(task.wifiPort),
            Int64(task.wifiEnabled),
            task.flowCount,
            task.uploadBytes,
            task.downloadBytes,
            task.note,
            task.extra,
            task.id
        )
    }

    /// Find the most recent task from catalog.db, returning a CaptureTaskRecord.
    public static func findLastTask(db: Connection) -> CaptureTaskRecord? {
        do {
            let stmt = try db.prepare("""
                SELECT id, name, created_at, started_at, stopped_at, status, rule_id,
                       local_ip, local_port, local_enabled,
                       wifi_ip, wifi_port, wifi_enabled,
                       flow_count, upload_bytes, download_bytes, note, extra
                FROM capture_task ORDER BY id DESC LIMIT 1
                """)
            for row in stmt {
                var r = CaptureTaskRecord()
                r.id = row[0] as? Int64 ?? 0
                r.name = row[1] as? String ?? ""
                r.createdAt = row[2] as? Double ?? 0
                r.startedAt = row[3] as? Double
                r.stoppedAt = row[4] as? Double
                r.status = Int(row[5] as? Int64 ?? 0)
                r.ruleId = row[6] as? Int64
                r.localIp = row[7] as? String ?? ""
                r.localPort = Int(row[8] as? Int64 ?? 0)
                r.localEnabled = Int(row[9] as? Int64 ?? 1)
                r.wifiIp = row[10] as? String ?? ""
                r.wifiPort = Int(row[11] as? Int64 ?? 0)
                r.wifiEnabled = Int(row[12] as? Int64 ?? 1)
                r.flowCount = row[13] as? Int64 ?? 0
                r.uploadBytes = row[14] as? Int64 ?? 0
                r.downloadBytes = row[15] as? Int64 ?? 0
                r.note = row[16] as? String ?? ""
                r.extra = row[17] as? String ?? ""
                return r
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
