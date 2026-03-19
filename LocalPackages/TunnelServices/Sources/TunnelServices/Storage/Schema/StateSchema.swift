import Foundation
import SQLite

public enum StateSchema {
    public static func create(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS connection (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL,
                client_state TEXT NOT NULL DEFAULT 'open',
                server_state TEXT NOT NULL DEFAULT 'open',
                started_at REAL NOT NULL,
                closed_at REAL,
                close_reason TEXT NOT NULL DEFAULT '',
                tls_version TEXT NOT NULL DEFAULT '',
                tls_cipher TEXT NOT NULL DEFAULT '',
                server_cert TEXT NOT NULL DEFAULT '',
                UNIQUE(flow_id)
            )
            """)
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
            CREATE INDEX IF NOT EXISTS idx_connection_flow_id ON connection(flow_id)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_modify_log_flow_id ON modify_log(flow_id)
            """)
        try db.execute("""
            INSERT OR IGNORE INTO task_stats (id, updated_at) VALUES (1, 0)
            """)
    }
}
