import Foundation
import SQLite

public enum StateSchema {
    public static func create(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS modify_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL,
                direction INTEGER NOT NULL,
                modify_type TEXT NOT NULL,
                original_ref TEXT NOT NULL DEFAULT '',
                modified_ref TEXT NOT NULL DEFAULT '',
                diff_summary TEXT NOT NULL DEFAULT '',
                source TEXT NOT NULL DEFAULT '',
                modified_at REAL NOT NULL
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS task_stats (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                total_flows INTEGER NOT NULL DEFAULT 0,
                active_connections INTEGER NOT NULL DEFAULT 0,
                total_packets INTEGER NOT NULL DEFAULT 0,
                upload_bytes INTEGER NOT NULL DEFAULT 0,
                download_bytes INTEGER NOT NULL DEFAULT 0,
                intercepted_count INTEGER NOT NULL DEFAULT 0,
                error_count INTEGER NOT NULL DEFAULT 0,
                updated_at REAL NOT NULL
            )
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_modify_log_flow_id ON modify_log(flow_id)
            """)
        try db.execute("""
            INSERT OR IGNORE INTO task_stats (id, updated_at) VALUES (1, 0)
            """)
        // Note: Rule tables (map_local_rule, breakpoint_rule, map_remote_rule,
        // allow_list, block_list) are in CatalogSchema (catalog.db) because
        // rules are global, not per-task.
    }
}
