import Foundation
import SQLite

public enum QuicStreamDAO {
    public static func insert(db: Connection, record: QuicStreamRecord) throws {
        try db.run("""
            INSERT INTO quic_stream (connection_id, stream_id, stream_type, state,
                started_at, closed_at, protocol_flow_id, bytes_in, bytes_out)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            record.connectionId, record.streamId, record.streamType, record.state,
            record.startedAt, record.closedAt, record.protocolFlowId,
            record.bytesIn, record.bytesOut
        )
    }

    public static func findByConnection(db: Connection, connectionId: String) throws -> [QuicStreamRecord] {
        let stmt = try db.prepare("SELECT * FROM quic_stream WHERE connection_id = ? ORDER BY stream_id ASC", connectionId)
        return stmt.map { row in
            QuicStreamRecord(
                connectionId: row[1] as? String ?? "", streamId: Int(row[2] as? Int64 ?? 0),
                startedAt: row[5] as? Double ?? 0, streamType: row[3] as? String ?? "",
                state: row[4] as? String ?? "open", closedAt: row[6] as? Double,
                protocolFlowId: row[7] as? String ?? "",
                bytesIn: row[8] as? Int64 ?? 0, bytesOut: row[9] as? Int64 ?? 0
            )
        }
    }

    public static func findByProtocolFlowId(db: Connection, protocolFlowId: String) throws -> QuicStreamRecord? {
        let stmt = try db.prepare("SELECT * FROM quic_stream WHERE protocol_flow_id = ? LIMIT 1", protocolFlowId)
        for row in stmt {
            return QuicStreamRecord(
                connectionId: row[1] as? String ?? "", streamId: Int(row[2] as? Int64 ?? 0),
                startedAt: row[5] as? Double ?? 0, streamType: row[3] as? String ?? "",
                state: row[4] as? String ?? "open", closedAt: row[6] as? Double,
                protocolFlowId: row[7] as? String ?? "",
                bytesIn: row[8] as? Int64 ?? 0, bytesOut: row[9] as? Int64 ?? 0
            )
        }
        return nil
    }

    public static func updateProtocolFlowId(db: Connection, connectionId: String, streamId: Int, protocolFlowId: String) throws {
        try db.run("UPDATE quic_stream SET protocol_flow_id = ? WHERE connection_id = ? AND stream_id = ?",
                   protocolFlowId, connectionId, streamId)
    }
}
