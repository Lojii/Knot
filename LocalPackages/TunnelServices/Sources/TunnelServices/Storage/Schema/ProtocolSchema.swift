import Foundation
import SQLite

public enum ProtocolSchema {
    public static func create(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS flow (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL UNIQUE,
                protocol TEXT NOT NULL,
                host TEXT NOT NULL DEFAULT '',
                port INTEGER NOT NULL DEFAULT 0,
                started_at REAL NOT NULL,
                ended_at REAL,
                duration_ms REAL,
                connect_at REAL,
                connected_at REAL,
                tls_done_at REAL,
                req_end_at REAL,
                rsp_start_at REAL,
                upload_bytes INTEGER NOT NULL DEFAULT 0,
                download_bytes INTEGER NOT NULL DEFAULT 0,
                status INTEGER NOT NULL DEFAULT 0,
                error_message TEXT NOT NULL DEFAULT '',
                summary TEXT NOT NULL DEFAULT '',
                search_key1 TEXT NOT NULL DEFAULT '',
                search_key2 TEXT NOT NULL DEFAULT '',
                search_key3 TEXT NOT NULL DEFAULT '',
                search_key4 TEXT NOT NULL DEFAULT '',
                metadata TEXT NOT NULL DEFAULT '{}',
                req_payload_ref TEXT NOT NULL DEFAULT '',
                rsp_payload_ref TEXT NOT NULL DEFAULT '',
                is_intercepted INTEGER NOT NULL DEFAULT 0,
                is_modified INTEGER NOT NULL DEFAULT 0,
                tags TEXT NOT NULL DEFAULT ''
            )
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_protocol ON flow(protocol)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_host ON flow(host)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_started_at ON flow(started_at)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_status ON flow(status)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_search_key1 ON flow(search_key1)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_search_key2 ON flow(search_key2)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_search_key3 ON flow(search_key3)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_flow_search_key4 ON flow(search_key4)
            """)
    }

    static let schemaVersion: Int64 = 2

    /// Migrate from v1 (original) to v2 (protocol metadata columns).
    public static func migrateIfNeeded(_ db: Connection) throws {
        let version = try db.scalar("PRAGMA user_version") as! Int64
        if version < schemaVersion {
            // Use addColumnIfNotExists to be safe against partial migrations
            // (e.g., crash between ALTER and PRAGMA update) or future CREATE TABLE
            // that already includes these columns.
            let existingColumns = try columnNames(db: db, table: "flow")
            let newColumns: [(name: String, definition: String)] = [
                ("conn_reuse", "INTEGER DEFAULT 0"),
                ("proto_flags", "INTEGER DEFAULT 0"),
                ("push_status", "INTEGER"),
                ("cert_chain_ref", "TEXT"),
            ]
            for col in newColumns where !existingColumns.contains(col.name) {
                try db.run("ALTER TABLE flow ADD COLUMN \(col.name) \(col.definition)")
            }
            try db.run("CREATE INDEX IF NOT EXISTS idx_flow_conn_reuse ON flow(conn_reuse)")
            try db.run("PRAGMA user_version = \(schemaVersion)")
        }
    }

    /// Query existing column names for a table.
    private static func columnNames(db: Connection, table: String) throws -> Set<String> {
        var names = Set<String>()
        for row in try db.prepare("PRAGMA table_info(\(table))") {
            if let name = row[1] as? String {
                names.insert(name)
            }
        }
        return names
    }
}
