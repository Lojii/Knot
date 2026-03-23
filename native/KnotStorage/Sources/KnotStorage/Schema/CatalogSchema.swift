import Foundation
import os
import SQLite

private let logger = Logger(subsystem: "com.knot.storage", category: "Schema")

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

        // Rule tables (global, not per-task)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS map_local_rule (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                enabled INTEGER DEFAULT 1,
                url_pattern TEXT NOT NULL,
                method TEXT,
                status_code INTEGER DEFAULT 200,
                response_headers TEXT,
                response_file TEXT,
                comment TEXT,
                created_at REAL
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS breakpoint_rule (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                enabled INTEGER DEFAULT 1,
                url_pattern TEXT NOT NULL,
                method TEXT,
                break_on TEXT DEFAULT 'both',
                comment TEXT,
                created_at REAL
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS map_remote_rule (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                enabled INTEGER DEFAULT 1,
                url_pattern TEXT NOT NULL,
                method TEXT,
                replace_scheme TEXT,
                replace_host TEXT,
                replace_port INTEGER,
                replace_path TEXT,
                comment TEXT,
                created_at REAL
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS allow_list (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                pattern TEXT NOT NULL UNIQUE
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS block_list (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                pattern TEXT NOT NULL UNIQUE
            )
            """)

        // Migrate: drop capture_task if it still has the removed ssl_enabled column
        migrateDropSSLEnabled(db)
    }

    /// Drop and recreate capture_task if it has the legacy ssl_enabled column.
    private static func migrateDropSSLEnabled(_ db: Connection) {
        do {
            let columns = try db.prepare("PRAGMA table_info(capture_task)")
            let hasSSLEnabled = columns.contains { row in
                (row[1] as? String) == "ssl_enabled"
            }
            if hasSSLEnabled {
                logger.warning("[CatalogSchema] Migrating: dropping capture_task (ssl_enabled removed)")
                try db.execute("DROP TABLE IF EXISTS capture_task")
                try db.execute("""
                    CREATE TABLE IF NOT EXISTS capture_task (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL DEFAULT '',
                        created_at REAL NOT NULL,
                        started_at REAL,
                        stopped_at REAL,
                        status INTEGER NOT NULL DEFAULT 0,
                        rule_id INTEGER,
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
            }
        } catch {
            logger.error("[CatalogSchema] migration check failed: \(error)")
        }
    }
}
