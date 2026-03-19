import Foundation
import SQLite

public enum CatalogSchema {
    public static func create(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS capture_task (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                started_at REAL,
                stopped_at REAL,
                status INTEGER NOT NULL DEFAULT 0,
                rule_id INTEGER,
                ssl_enabled INTEGER NOT NULL DEFAULT 0,
                local_ip TEXT NOT NULL DEFAULT '127.0.0.1',
                local_port INTEGER NOT NULL DEFAULT 8080,
                local_enabled INTEGER NOT NULL DEFAULT 0,
                wifi_ip TEXT NOT NULL DEFAULT '',
                wifi_port INTEGER NOT NULL DEFAULT 0,
                wifi_enabled INTEGER NOT NULL DEFAULT 0,
                flow_count INTEGER NOT NULL DEFAULT 0,
                upload_bytes INTEGER NOT NULL DEFAULT 0,
                download_bytes INTEGER NOT NULL DEFAULT 0,
                note TEXT NOT NULL DEFAULT '',
                extra TEXT NOT NULL DEFAULT ''
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS rule (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL DEFAULT 'Default',
                default_strategy TEXT NOT NULL DEFAULT 'DIRECT',
                blacklist_enabled INTEGER NOT NULL DEFAULT 0,
                config TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                author TEXT NOT NULL DEFAULT '',
                note TEXT NOT NULL DEFAULT ''
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS breakpoint (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                enabled INTEGER NOT NULL DEFAULT 1,
                match_phase TEXT NOT NULL DEFAULT 'request',
                match_protocol TEXT NOT NULL DEFAULT '*',
                match_pattern TEXT NOT NULL DEFAULT '',
                action TEXT NOT NULL DEFAULT 'pause',
                script_ref TEXT NOT NULL DEFAULT '',
                priority INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                note TEXT NOT NULL DEFAULT ''
            )
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_breakpoint_enabled ON breakpoint(enabled)
            """)
    }
}
