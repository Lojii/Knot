import Foundation
import SQLite

public enum ModifyLogDAO {
    public static func insert(db: Connection, entry: ModifyLogEntry) throws {
        try db.run("""
            INSERT INTO modify_log (flow_id, direction, modify_type, original_ref,
                modified_ref, diff_summary, source, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            entry.flowId, entry.direction, entry.modifyType, entry.originalRef,
            entry.modifiedRef, entry.diffSummary, entry.source, entry.modifiedAt
        )
    }

    public static func findAll(db: Connection, flowId: String) throws -> [ModifyLogEntry] {
        let stmt = try db.prepare("SELECT * FROM modify_log WHERE flow_id = ? ORDER BY modified_at ASC", flowId)
        return stmt.map { row in
            ModifyLogEntry(
                flowId: row[1] as? String ?? "",
                direction: Int(row[2] as? Int64 ?? 0),
                modifyType: row[3] as? String ?? "",
                originalRef: row[4] as? String ?? "",
                modifiedRef: row[5] as? String ?? "",
                diffSummary: row[6] as? String ?? "",
                source: row[7] as? String ?? "",
                modifiedAt: row[8] as? Double ?? 0
            )
        }
    }
}
