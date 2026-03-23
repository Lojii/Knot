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
}
