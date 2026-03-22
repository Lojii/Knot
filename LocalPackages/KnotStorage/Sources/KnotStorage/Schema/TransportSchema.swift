import Foundation
import SQLite

public enum TransportSchema {
    public static func create(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS packet (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL,
                direction INTEGER NOT NULL,
                timestamp REAL NOT NULL,
                ip_version INTEGER NOT NULL DEFAULT 4,
                src_ip TEXT NOT NULL,
                dst_ip TEXT NOT NULL,
                transport INTEGER NOT NULL,
                src_port INTEGER NOT NULL DEFAULT 0,
                dst_port INTEGER NOT NULL DEFAULT 0,
                seq_no INTEGER NOT NULL DEFAULT 0,
                ack_no INTEGER NOT NULL DEFAULT 0,
                tcp_flags INTEGER NOT NULL DEFAULT 0,
                window_size INTEGER NOT NULL DEFAULT 0,
                payload_length INTEGER NOT NULL DEFAULT 0,
                payload_ref TEXT NOT NULL DEFAULT ''
            )
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_packet_flow_id ON packet(flow_id)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_packet_timestamp ON packet(timestamp)
            """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_packet_transport ON packet(transport)
            """)
    }
}
