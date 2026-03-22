import Foundation
import SQLite

/// Data access for the `packet` table in transport.db.
public enum PacketDAO {

    /// Insert a single packet row.
    public static func insert(db: Connection, row: PacketRow) throws {
        try db.run("""
            INSERT INTO packet (flow_id, direction, timestamp, ip_version, src_ip, dst_ip,
                transport, src_port, dst_port, seq_no, ack_no, tcp_flags, window_size,
                payload_length, payload_ref)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            row.flowId, row.direction, row.timestamp, row.ipVersion,
            row.srcIp, row.dstIp, row.transport, row.srcPort, row.dstPort,
            row.seqNo, row.ackNo, row.tcpFlags, row.windowSize,
            row.payloadLength, row.payloadRef
        )
    }

    /// Batch insert in a single transaction.
    public static func insertBatch(db: Connection, rows: [PacketRow]) throws {
        try db.transaction {
            for row in rows {
                try insert(db: db, row: row)
            }
        }
    }
}
