import Foundation
import SQLite

public enum ConnectionSchema {
    public static func create(_ db: Connection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS tcp_connection (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL UNIQUE,
                src_ip TEXT NOT NULL,
                src_port INTEGER NOT NULL,
                dst_ip TEXT NOT NULL,
                dst_port INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT 'open',
                started_at REAL NOT NULL,
                established_at REAL,
                closed_at REAL,
                close_reason TEXT NOT NULL DEFAULT '',
                tls_version TEXT NOT NULL DEFAULT '',
                tls_cipher TEXT NOT NULL DEFAULT '',
                tls_sni TEXT NOT NULL DEFAULT '',
                server_cert TEXT NOT NULL DEFAULT '',
                packets_in INTEGER NOT NULL DEFAULT 0,
                packets_out INTEGER NOT NULL DEFAULT 0,
                bytes_in INTEGER NOT NULL DEFAULT 0,
                bytes_out INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS quic_connection (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL UNIQUE,
                src_ip TEXT NOT NULL,
                src_port INTEGER NOT NULL,
                dst_ip TEXT NOT NULL,
                dst_port INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT 'handshaking',
                started_at REAL NOT NULL,
                established_at REAL,
                closed_at REAL,
                close_reason TEXT NOT NULL DEFAULT '',
                version TEXT NOT NULL DEFAULT '',
                dcid TEXT NOT NULL DEFAULT '',
                scid TEXT NOT NULL DEFAULT '',
                alpn TEXT NOT NULL DEFAULT '',
                tls_cipher TEXT NOT NULL DEFAULT '',
                tls_sni TEXT NOT NULL DEFAULT '',
                server_cert TEXT NOT NULL DEFAULT '',
                is_0rtt INTEGER NOT NULL DEFAULT 0,
                packets_in INTEGER NOT NULL DEFAULT 0,
                packets_out INTEGER NOT NULL DEFAULT 0,
                bytes_in INTEGER NOT NULL DEFAULT 0,
                bytes_out INTEGER NOT NULL DEFAULT 0,
                streams_count INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS quic_stream (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                connection_id TEXT NOT NULL,
                stream_id INTEGER NOT NULL,
                stream_type TEXT NOT NULL DEFAULT '',
                state TEXT NOT NULL DEFAULT 'open',
                started_at REAL NOT NULL,
                closed_at REAL,
                protocol_flow_id TEXT NOT NULL DEFAULT '',
                bytes_in INTEGER NOT NULL DEFAULT 0,
                bytes_out INTEGER NOT NULL DEFAULT 0,
                UNIQUE(connection_id, stream_id)
            )
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_tcp_conn_flow_id ON tcp_connection(flow_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_quic_conn_flow_id ON quic_connection(flow_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_quic_stream_conn ON quic_stream(connection_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_quic_stream_proto ON quic_stream(protocol_flow_id)")
    }
}
