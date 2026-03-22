import Foundation
import SQLite

public enum QuicConnectionDAO {
    public static func insertOrUpdate(db: Connection, record: QuicConnectionRecord) throws {
        try db.run("""
            INSERT INTO quic_connection (flow_id, src_ip, src_port, dst_ip, dst_port,
                state, started_at, established_at, closed_at, close_reason,
                version, dcid, scid, alpn, tls_cipher, tls_sni, server_cert,
                is_0rtt, packets_in, packets_out, bytes_in, bytes_out, streams_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(flow_id) DO UPDATE SET
                state = excluded.state, established_at = excluded.established_at,
                closed_at = excluded.closed_at, close_reason = excluded.close_reason,
                streams_count = excluded.streams_count
            """,
            record.flowId, record.srcIp, record.srcPort, record.dstIp, record.dstPort,
            record.state, record.startedAt, record.establishedAt, record.closedAt, record.closeReason,
            record.version, record.dcid, record.scid, record.alpn,
            record.tlsCipher, record.tlsSni, record.serverCert,
            record.is0rtt ? 1 : 0,
            record.packetsIn, record.packetsOut, record.bytesIn, record.bytesOut, record.streamsCount
        )
    }

    public static func find(db: Connection, flowId: String) throws -> QuicConnectionRecord? {
        let stmt = try db.prepare("SELECT * FROM quic_connection WHERE flow_id = ?", flowId)
        for row in stmt {
            return QuicConnectionRecord(
                flowId: row[1] as? String ?? "",
                srcIp: row[2] as? String ?? "", srcPort: Int(row[3] as? Int64 ?? 0),
                dstIp: row[4] as? String ?? "", dstPort: Int(row[5] as? Int64 ?? 0),
                startedAt: row[7] as? Double ?? 0, state: row[6] as? String ?? "handshaking",
                establishedAt: row[8] as? Double, closedAt: row[9] as? Double,
                closeReason: row[10] as? String ?? "",
                version: row[11] as? String ?? "", dcid: row[12] as? String ?? "",
                scid: row[13] as? String ?? "", alpn: row[14] as? String ?? "",
                tlsCipher: row[15] as? String ?? "", tlsSni: row[16] as? String ?? "",
                serverCert: row[17] as? String ?? "",
                is0rtt: (row[18] as? Int64 ?? 0) == 1,
                packetsIn: row[19] as? Int64 ?? 0, packetsOut: row[20] as? Int64 ?? 0,
                bytesIn: row[21] as? Int64 ?? 0, bytesOut: row[22] as? Int64 ?? 0,
                streamsCount: row[23] as? Int64 ?? 0
            )
        }
        return nil
    }
}
