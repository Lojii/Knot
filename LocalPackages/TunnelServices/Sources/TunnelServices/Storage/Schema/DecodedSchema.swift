import Foundation
import SQLite

public enum DecodedSchema {
    public static func create(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS decoded_entry (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL,
                direction INTEGER NOT NULL,
                original_encoding TEXT NOT NULL DEFAULT '',
                decoded_type TEXT NOT NULL DEFAULT '',
                decoded_size INTEGER NOT NULL DEFAULT 0,
                charset TEXT NOT NULL DEFAULT 'utf-8',
                payload_ref TEXT NOT NULL DEFAULT '',
                is_inline INTEGER NOT NULL DEFAULT 0,
                inline_data BLOB,
                search_text TEXT,
                decoded_at REAL NOT NULL,
                sequence INTEGER NOT NULL DEFAULT 0,
                UNIQUE(flow_id, direction, sequence)
            )
            """)
        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS decoded_fts USING fts5(
                search_text,
                content='decoded_entry',
                content_rowid='id'
            )
            """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS decoded_fts_insert AFTER INSERT ON decoded_entry
            WHEN NEW.search_text IS NOT NULL BEGIN
                INSERT INTO decoded_fts(rowid, search_text) VALUES (NEW.id, NEW.search_text);
            END
            """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS decoded_fts_delete BEFORE DELETE ON decoded_entry
            WHEN OLD.search_text IS NOT NULL BEGIN
                INSERT INTO decoded_fts(decoded_fts, rowid, search_text)
                VALUES('delete', OLD.id, OLD.search_text);
            END
            """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS decoded_fts_update AFTER UPDATE OF search_text ON decoded_entry BEGIN
                INSERT INTO decoded_fts(decoded_fts, rowid, search_text)
                SELECT 'delete', OLD.id, OLD.search_text WHERE OLD.search_text IS NOT NULL;
                INSERT INTO decoded_fts(rowid, search_text)
                SELECT NEW.id, NEW.search_text WHERE NEW.search_text IS NOT NULL;
            END
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_decoded_flow_id ON decoded_entry(flow_id)
            """)
    }
}
