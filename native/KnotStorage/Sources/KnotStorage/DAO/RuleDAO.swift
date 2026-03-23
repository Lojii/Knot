import Foundation
import SQLite

public enum RuleDAO {
    // MARK: - Map Local

    public static func insertMapLocal(db: Connection, rule: MapLocalRule) throws -> Int64 {
        try db.run("""
            INSERT INTO map_local_rule (enabled, url_pattern, method, status_code, response_headers, response_file, comment, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, rule.enabled ? 1 : 0, rule.urlPattern, rule.method, Int64(rule.statusCode),
           rule.responseHeaders, rule.responseFile, rule.comment, rule.createdAt)
        return db.lastInsertRowid
    }

    public static func findAllMapLocal(db: Connection) throws -> [MapLocalRule] {
        let stmt = try db.prepare("""
            SELECT id, enabled, url_pattern, method, status_code, response_headers, response_file, comment, created_at
            FROM map_local_rule ORDER BY created_at DESC
        """)
        return stmt.map { row in
            MapLocalRule(
                id: row[0] as? Int64 ?? 0,
                enabled: (row[1] as? Int64 ?? 1) != 0,
                urlPattern: row[2] as? String ?? "",
                method: row[3] as? String,
                statusCode: Int(row[4] as? Int64 ?? 200),
                responseHeaders: row[5] as? String ?? "",
                responseFile: row[6] as? String ?? "",
                comment: row[7] as? String ?? "",
                createdAt: row[8] as? Double ?? 0
            )
        }
    }

    public static func updateMapLocal(db: Connection, rule: MapLocalRule) throws {
        try db.run("""
            UPDATE map_local_rule SET enabled=?, url_pattern=?, method=?, status_code=?,
            response_headers=?, response_file=?, comment=? WHERE id=?
        """, rule.enabled ? 1 : 0, rule.urlPattern, rule.method, Int64(rule.statusCode),
           rule.responseHeaders, rule.responseFile, rule.comment, rule.id)
    }

    public static func deleteMapLocal(db: Connection, id: Int64) throws {
        try db.run("DELETE FROM map_local_rule WHERE id = ?", id)
    }

    public static func toggleMapLocal(db: Connection, id: Int64) throws {
        try db.run("UPDATE map_local_rule SET enabled = 1 - enabled WHERE id = ?", id)
    }

    // MARK: - Breakpoint

    public static func insertBreakpoint(db: Connection, rule: BreakpointRule) throws -> Int64 {
        try db.run("""
            INSERT INTO breakpoint_rule (enabled, url_pattern, method, break_on, comment, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, rule.enabled ? 1 : 0, rule.urlPattern, rule.method, rule.breakOn,
           rule.comment, rule.createdAt)
        return db.lastInsertRowid
    }

    public static func findAllBreakpoint(db: Connection) throws -> [BreakpointRule] {
        let stmt = try db.prepare("""
            SELECT id, enabled, url_pattern, method, break_on, comment, created_at
            FROM breakpoint_rule ORDER BY created_at DESC
        """)
        return stmt.map { row in
            BreakpointRule(
                id: row[0] as? Int64 ?? 0,
                enabled: (row[1] as? Int64 ?? 1) != 0,
                urlPattern: row[2] as? String ?? "",
                method: row[3] as? String,
                breakOn: row[4] as? String ?? "both",
                comment: row[5] as? String ?? "",
                createdAt: row[6] as? Double ?? 0
            )
        }
    }

    public static func updateBreakpoint(db: Connection, rule: BreakpointRule) throws {
        try db.run("""
            UPDATE breakpoint_rule SET enabled=?, url_pattern=?, method=?, break_on=?, comment=? WHERE id=?
        """, rule.enabled ? 1 : 0, rule.urlPattern, rule.method, rule.breakOn, rule.comment, rule.id)
    }

    public static func deleteBreakpoint(db: Connection, id: Int64) throws {
        try db.run("DELETE FROM breakpoint_rule WHERE id = ?", id)
    }

    public static func toggleBreakpoint(db: Connection, id: Int64) throws {
        try db.run("UPDATE breakpoint_rule SET enabled = 1 - enabled WHERE id = ?", id)
    }

    // MARK: - Map Remote

    public static func insertMapRemote(db: Connection, rule: MapRemoteRule) throws -> Int64 {
        try db.run("""
            INSERT INTO map_remote_rule (enabled, url_pattern, method, replace_scheme, replace_host, replace_port, replace_path, comment, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, rule.enabled ? 1 : 0, rule.urlPattern, rule.method,
           rule.replaceScheme, rule.replaceHost,
           rule.replacePort.map { Int64($0) },
           rule.replacePath, rule.comment, rule.createdAt)
        return db.lastInsertRowid
    }

    public static func findAllMapRemote(db: Connection) throws -> [MapRemoteRule] {
        let stmt = try db.prepare("""
            SELECT id, enabled, url_pattern, method, replace_scheme, replace_host, replace_port, replace_path, comment, created_at
            FROM map_remote_rule ORDER BY created_at DESC
        """)
        return stmt.map { row in
            MapRemoteRule(
                id: row[0] as? Int64 ?? 0,
                enabled: (row[1] as? Int64 ?? 1) != 0,
                urlPattern: row[2] as? String ?? "",
                method: row[3] as? String,
                replaceScheme: row[4] as? String,
                replaceHost: row[5] as? String,
                replacePort: (row[6] as? Int64).map { Int($0) },
                replacePath: row[7] as? String,
                comment: row[8] as? String ?? "",
                createdAt: row[9] as? Double ?? 0
            )
        }
    }

    public static func updateMapRemote(db: Connection, rule: MapRemoteRule) throws {
        try db.run("""
            UPDATE map_remote_rule SET enabled=?, url_pattern=?, method=?, replace_scheme=?,
            replace_host=?, replace_port=?, replace_path=?, comment=? WHERE id=?
        """, rule.enabled ? 1 : 0, rule.urlPattern, rule.method,
           rule.replaceScheme, rule.replaceHost,
           rule.replacePort.map { Int64($0) },
           rule.replacePath, rule.comment, rule.id)
    }

    public static func deleteMapRemote(db: Connection, id: Int64) throws {
        try db.run("DELETE FROM map_remote_rule WHERE id = ?", id)
    }

    public static func toggleMapRemote(db: Connection, id: Int64) throws {
        try db.run("UPDATE map_remote_rule SET enabled = 1 - enabled WHERE id = ?", id)
    }

    // MARK: - Allow List

    public static func findAllAllowList(db: Connection) throws -> [String] {
        let stmt = try db.prepare("SELECT pattern FROM allow_list ORDER BY id")
        return stmt.compactMap { $0[0] as? String }
    }

    public static func addToAllowList(db: Connection, pattern: String) throws {
        try db.run("INSERT OR IGNORE INTO allow_list (pattern) VALUES (?)", pattern)
    }

    public static func removeFromAllowList(db: Connection, pattern: String) throws {
        try db.run("DELETE FROM allow_list WHERE pattern = ?", pattern)
    }

    // MARK: - Block List

    public static func findAllBlockList(db: Connection) throws -> [String] {
        let stmt = try db.prepare("SELECT pattern FROM block_list ORDER BY id")
        return stmt.compactMap { $0[0] as? String }
    }

    public static func addToBlockList(db: Connection, pattern: String) throws {
        try db.run("INSERT OR IGNORE INTO block_list (pattern) VALUES (?)", pattern)
    }

    public static func removeFromBlockList(db: Connection, pattern: String) throws {
        try db.run("DELETE FROM block_list WHERE pattern = ?", pattern)
    }
}
