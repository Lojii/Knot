import Foundation
import SQLite

public enum DecodedEntryDAO {
    /// Insert a decoded entry. Handles inline (≤4KB) vs file-ref decision via is_inline field.
    public static func insert(db: Connection, entry: DecodedEntry) throws {
        // Convert Data to SQLite.Blob for BLOB column binding
        let inlineBlob: SQLite.Blob? = entry.isInline ? entry.inlineData.map { SQLite.Blob(bytes: [UInt8]($0)) } : nil

        try db.run("""
            INSERT INTO decoded_entry (flow_id, direction, original_encoding, decoded_type,
                decoded_size, charset, payload_ref, is_inline, inline_data, search_text,
                decoded_at, sequence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            entry.flowId, entry.direction, entry.originalEncoding, entry.decodedType,
            entry.decodedSize, entry.charset, entry.payloadRef,
            entry.isInline ? 1 : 0,
            inlineBlob,
            entry.searchText, entry.decodedAt, entry.sequence
        )
    }

    /// Find decoded entry by flowId and direction
    public static func find(db: Connection, flowId: String, direction: Int) throws -> DecodedEntry? {
        let stmt = try db.prepare(
            "SELECT * FROM decoded_entry WHERE flow_id = ? AND direction = ? ORDER BY sequence ASC LIMIT 1",
            flowId, direction
        )
        for row in stmt {
            return mapRow(row)
        }
        return nil
    }

    /// Fetch all decoded entries for a flow, ordered by decoded_at ASC, with pagination.
    public static func findAll(db: Connection, flowId: String, offset: Int = 0, limit: Int = 50) throws -> [DecodedEntry] {
        let stmt = try db.prepare(
            "SELECT * FROM decoded_entry WHERE flow_id = ? ORDER BY decoded_at ASC LIMIT ? OFFSET ?",
            flowId, limit, offset
        )
        return stmt.map { mapRow($0) }
    }

    /// Full-text search via FTS5
    public static func searchFullText(db: Connection, query: String, limit: Int = 50) throws -> [DecodedEntry] {
        let stmt = try db.prepare("""
            SELECT de.* FROM decoded_entry de
            JOIN decoded_fts fts ON de.id = fts.rowid
            WHERE decoded_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """, query, limit)
        return stmt.map { mapRow($0) }
    }

    private static func mapRow(_ row: Statement.Element) -> DecodedEntry {
        // Convert SQLite.Blob back to Data
        let blobData: Data? = (row[9] as? SQLite.Blob).map { Data($0.bytes) }

        return DecodedEntry(
            flowId: row[1] as? String ?? "",
            direction: Int(row[2] as? Int64 ?? 0),
            originalEncoding: row[3] as? String ?? "",
            decodedType: row[4] as? String ?? "",
            decodedSize: row[5] as? Int64 ?? 0,
            charset: row[6] as? String ?? "utf-8",
            payloadRef: row[7] as? String ?? "",
            isInline: (row[8] as? Int64 ?? 0) == 1,
            inlineData: blobData,
            searchText: row[10] as? String,
            decodedAt: row[11] as? Double ?? 0,
            sequence: Int(row[12] as? Int64 ?? 0)
        )
    }
}
