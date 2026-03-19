import Foundation
import SQLite

/// Migrates data from legacy nio.db to new multi-database architecture.
///
/// The legacy schema (ActiveSQLite/ASModel):
///   - Table "Rule"    : id, name, config, created_at, updated_at  (subName stored in config)
///   - Table "task"    : id, creatTime, startTime, stopTime, ruleName, ruleId, fileFolder, …
///   - Table "Session" : id, taskID, host, schemes, methods, uri, state, startTime, endTime,
///                       connectTime, connectedTime, handshakeEndTime, reqEndTime, rspStartTime,
///                       rspEndTime, uploadTraffic, downloadFlow, sstate, reqHeads, rspHeads,
///                       reqBody, rspBody, reqHttpVersion, fileFolder, …
///
/// The legacy store folder for body files is:
///   {AppGroup}/Task/{fileFolder}/{reqBody|rspBody}
/// i.e. MitmService.getStoreFolder() + fileFolder + "/" + bodyFilename
/// MitmService.getStoreFolder() itself returns {AppGroup}/Task/ (with trailing slash).
/// When we receive `rootPath` (the AppGroup container root), the store folder is:
///   rootPath + "/Task/"
public enum LegacyMigrator {

    // MARK: - Public entry point

    /// Check if migration is needed and perform it.
    /// Safe: backs up nio.db first, uses transactions, idempotent.
    ///
    /// - Parameters:
    ///   - legacyDBPath: Full path to the legacy `nio.db` file.
    ///   - rootPath:     App Group container root (e.g. `.../group.Lojii.NIO1901`).
    public static func migrateIfNeeded(legacyDBPath: String, rootPath: String) {
        guard FileManager.default.fileExists(atPath: legacyDBPath) else { return }

        let mgr = DatabaseManager(rootPath: rootPath)

        // Idempotency check: skip if catalog.db already has tasks.
        let existingTasks = (try? CatalogDAO.findAllTasks(db: mgr.catalogDB)) ?? []
        guard existingTasks.isEmpty else { return }

        do {
            // 1. Backup nio.db before any writes.
            let backupPath = legacyDBPath + ".bak"
            if !FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.copyItem(atPath: legacyDBPath, toPath: backupPath)
            }

            // 2. Open legacy DB (read-only intent; SQLite.swift opens as read-write by default).
            let legacyDB = try Connection(legacyDBPath)

            // 3. Migrate Rules → catalog.db rule table.
            try migrateRules(from: legacyDB, to: mgr.catalogDB)

            // 4. Migrate CaptureTask rows + their Sessions.
            try migrateTasks(from: legacyDB, manager: mgr, rootPath: rootPath)

        } catch {
            // Migration failure is non-fatal.
            // The legacy nio.db backup is still intact; the app can fall back to the old system.
            NSLog("[LegacyMigrator] Migration failed: \(error). Backup preserved at \(legacyDBPath).bak")
        }
    }

    // MARK: - Rules

    private static func migrateRules(from legacyDB: Connection, to catalogDB: Connection) throws {
        // Check that the Rule table exists before querying it.
        let tableExists = try legacyDB.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='Rule'"
        ) as! Int64
        guard tableExists > 0 else { return }

        // The legacy Rule table columns (ASModel + Rule model):
        //   id, subName(?), name, config, created_at, updated_at
        // We use explicit column names to be resilient to column ordering.
        let stmt = try legacyDB.prepare(
            "SELECT name, config, created_at FROM Rule"
        )
        for row in stmt {
            let name      = row[0] as? String ?? "Default"
            let config    = row[1] as? String ?? ""
            // created_at is stored as milliseconds (ASModel default) — convert to seconds.
            let createdAtMs = row[2] as? Double ?? (Date().timeIntervalSince1970 * 1000)
            let createdAt = createdAtMs > 1_000_000_000_000 ? createdAtMs / 1000.0 : createdAtMs
            try? CatalogDAO.insertRule(db: catalogDB, name: name, config: config, createdAt: createdAt)
        }
    }

    // MARK: - Tasks

    private static func migrateTasks(from legacyDB: Connection,
                                     manager: DatabaseManager,
                                     rootPath: String) throws {
        // Check that the task table exists.
        let tableExists = try legacyDB.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='task'"
        ) as! Int64
        guard tableExists > 0 else { return }

        // The legacy CaptureTask columns we care about (table name is "task"):
        //   id, creatTime, startTime, stopTime, ruleName, fileFolder
        // creatTime is a Double stored as seconds (see CaptureTask.newTask()).
        let tasks = try legacyDB.prepare(
            "SELECT id, creatTime, ruleName, fileFolder FROM task ORDER BY creatTime ASC"
        )

        for taskRow in tasks {
            let legacyId    = taskRow[0] as? Int64  ?? 0
            let creatTime   = taskRow[1] as? Double ?? Date().timeIntervalSince1970
            let ruleName    = taskRow[2] as? String ?? "Migrated"
            let fileFolder  = taskRow[3] as? String ?? ""

            // The task name shown in the UI: use ruleName or a generic label.
            let taskName = ruleName.isEmpty ? "Migrated" : ruleName

            // Insert into catalog.db and get the new task id.
            let newTaskId = try CatalogDAO.insertTask(
                db: manager.catalogDB,
                name: taskName,
                createdAt: creatTime
            )

            // Open the new per-task database group (creates directory structure too).
            let group = try manager.openTask(newTaskId)

            // Migrate all sessions belonging to this legacy task.
            try migrateSessionsForTask(
                from: legacyDB,
                legacyTaskId: legacyId,
                legacyFileFolder: fileFolder,
                group: group,
                rootPath: rootPath
            )

            manager.closeTask(newTaskId)
        }
    }

    // MARK: - Sessions

    private static func migrateSessionsForTask(from legacyDB: Connection,
                                                legacyTaskId: Int64,
                                                legacyFileFolder: String,
                                                group: TaskDatabaseGroup,
                                                rootPath: String) throws {
        // Check that the Session table exists.
        let tableExists = try legacyDB.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='Session'"
        ) as! Int64
        guard tableExists > 0 else { return }

        // Select all session columns we need by name so column order doesn't matter.
        // Legacy Session columns relevant to FlowRecord:
        //   taskID, host, schemes, methods, uri, state (HTTP status code),
        //   startTime, endTime, connectTime, connectedTime, handshakeEndTime,
        //   reqEndTime, rspStartTime, rspEndTime,
        //   uploadTraffic, downloadFlow, sstate,
        //   reqHeads, rspHeads, reqHttpVersion,
        //   reqBody, rspBody, fileFolder
        let sql = """
            SELECT
                host, schemes, methods, uri, state,
                startTime, endTime, connectTime, connectedTime, handshakeEndTime,
                reqEndTime, rspStartTime, rspEndTime,
                uploadTraffic, downloadFlow, sstate,
                reqHeads, rspHeads, reqHttpVersion,
                reqBody, rspBody, fileFolder
            FROM Session
            WHERE taskID = ?
            """
        let sessions = try legacyDB.prepare(sql, legacyTaskId)

        // Batch all inserts for this task inside a single transaction.
        try group.proto.transaction {
            for row in sessions {
                // Column indices correspond to the SELECT order above (0-based).
                let host            = row[0]  as? String ?? ""
                let schemes         = row[1]  as? String ?? "http"
                let methods         = row[2]  as? String ?? ""
                let uri             = row[3]  as? String ?? ""
                let statusCode      = row[4]  as? String ?? ""
                let startTime       = row[5]  as? Double ?? 0
                let endTime         = row[6]  as? Double
                let connectTime     = row[7]  as? Double
                let connectedTime   = row[8]  as? Double
                let handshakeEnd    = row[9]  as? Double
                let reqEndTime      = row[10] as? Double
                let rspStartTime    = row[11] as? Double
                // rspEndTime (index 12) is not mapped to a FlowRecord field; endTime is the final end.
                let uploadTraffic   = row[13] as? Double ?? 0
                let downloadFlow    = row[14] as? Double ?? 0
                let sstate          = row[15] as? String ?? ""
                let reqHeads        = row[16] as? String ?? "{}"
                let rspHeads        = row[17] as? String ?? "{}"
                let reqHttpVersion  = row[18] as? String ?? ""
                let reqBodyFile     = row[19] as? String ?? ""
                let rspBodyFile     = row[20] as? String ?? ""
                // Per-session fileFolder may differ from task fileFolder; use it if present.
                let sessionFolder   = (row[21] as? String ?? "").isEmpty
                                        ? legacyFileFolder
                                        : (row[21] as? String ?? legacyFileFolder)

                let flowId = group.flowIdGenerator.next()

                // Determine protocol name from schemes field.
                let protocolName: String
                let schemeLower = schemes.lowercased()
                if schemeLower.contains("https") {
                    protocolName = "HTTPS"
                } else {
                    protocolName = "HTTP"
                }

                var record = FlowRecord(
                    flowId: flowId,
                    protocolName: protocolName,
                    host: host,
                    port: 0,          // Legacy schema does not store port separately.
                    startedAt: startTime
                )

                record.endedAt        = endTime
                record.connectAt      = connectTime
                record.connectedAt    = connectedTime
                record.tlsDoneAt      = handshakeEnd
                record.reqEndAt       = reqEndTime
                record.rspStartAt     = rspStartTime

                // Compute duration when both timestamps are available.
                if let end = endTime, startTime > 0 {
                    record.durationMs = (end - startTime) * 1000
                }

                // searchKey mapping for HTTP: method, uri, statusCode, contentType
                record.searchKey1 = methods
                record.searchKey2 = uri
                record.searchKey3 = statusCode

                record.uploadBytes   = Int64(uploadTraffic)
                record.downloadBytes = Int64(downloadFlow)

                // Map sstate to FlowStatus.
                record.status = sstate.lowercased() == "failure" ? .failed : .completed

                // Store headers and HTTP version in metadata.
                record.metadata = [
                    "reqHeaders":   reqHeads,
                    "rspHeaders":   rspHeads,
                    "httpVersion":  reqHttpVersion,
                    "legacyScheme": schemes
                ]

                // Build human-readable summary.
                if statusCode.isEmpty {
                    record.summary = "\(methods) \(uri)"
                } else {
                    record.summary = "\(methods) \(uri) → \(statusCode)"
                }

                // Move body files from the legacy location to the new payloads/raw/ directory.
                // Legacy path: {rootPath}/Task/{sessionFolder}/{bodyFilename}
                if !reqBodyFile.isEmpty {
                    let oldPath = "\(rootPath)/Task/\(sessionFolder)/\(reqBodyFile)"
                    let newRef  = "\(flowId)_req.bin"
                    let newPath = PathManager.rawPayloadPath(taskId: group.taskId, ref: newRef, root: rootPath)
                    try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
                    record.reqPayloadRef = newRef
                }
                if !rspBodyFile.isEmpty {
                    let oldPath = "\(rootPath)/Task/\(sessionFolder)/\(rspBodyFile)"
                    let newRef  = "\(flowId)_rsp.bin"
                    let newPath = PathManager.rawPayloadPath(taskId: group.taskId, ref: newRef, root: rootPath)
                    try? FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
                    record.rspPayloadRef = newRef
                }

                try FlowDAO.insert(db: group.proto, record: record)
            }
        }
    }
}
