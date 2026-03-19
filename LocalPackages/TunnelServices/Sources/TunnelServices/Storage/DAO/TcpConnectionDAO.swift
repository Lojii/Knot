import Foundation
import SQLite

public enum TcpConnectionDAO {
    public static func insertOrUpdate(db: Connection, record: TcpConnectionRecord) throws {
        try db.run("""
            INSERT INTO tcp_connection (flow_id, src_ip, src_port, dst_ip, dst_port,
                state, started_at, established_at, closed_at, close_reason,
                tls_version, tls_cipher, tls_sni, server_cert,
                packets_in, packets_out, bytes_in, bytes_out)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(flow_id) DO UPDATE SET
                state = excluded.state, established_at = excluded.established_at,
                closed_at = excluded.closed_at, close_reason = excluded.close_reason,
                tls_version = excluded.tls_version, tls_cipher = excluded.tls_cipher,
                tls_sni = excluded.tls_sni, server_cert = excluded.server_cert
            """,
            record.flowId, record.srcIp, record.srcPort, record.dstIp, record.dstPort,
            record.state, record.startedAt, record.establishedAt, record.closedAt, record.closeReason,
            record.tlsVersion, record.tlsCipher, record.tlsSni, record.serverCert,
            record.packetsIn, record.packetsOut, record.bytesIn, record.bytesOut
        )
    }

    public static func find(db: Connection, flowId: String) throws -> TcpConnectionRecord? {
        let stmt = try db.prepare("SELECT * FROM tcp_connection WHERE flow_id = ?", flowId)
        for row in stmt {
            return TcpConnectionRecord(
                flowId: row[1] as? String ?? "",
                srcIp: row[2] as? String ?? "",
                srcPort: Int(row[3] as? Int64 ?? 0),
                dstIp: row[4] as? String ?? "",
                dstPort: Int(row[5] as? Int64 ?? 0),
                startedAt: row[7] as? Double ?? 0,
                state: row[6] as? String ?? "open",
                establishedAt: row[8] as? Double,
                closedAt: row[9] as? Double,
                closeReason: row[10] as? String ?? "",
                tlsVersion: row[11] as? String ?? "",
                tlsCipher: row[12] as? String ?? "",
                tlsSni: row[13] as? String ?? "",
                serverCert: row[14] as? String ?? "",
                packetsIn: row[15] as? Int64 ?? 0,
                packetsOut: row[16] as? Int64 ?? 0,
                bytesIn: row[17] as? Int64 ?? 0,
                bytesOut: row[18] as? Int64 ?? 0
            )
        }
        return nil
    }

    public static func updateStats(db: Connection, flowId: String,
                                    packetsIn: Int64, packetsOut: Int64,
                                    bytesIn: Int64, bytesOut: Int64) throws {
        try db.run("""
            UPDATE tcp_connection SET packets_in = ?, packets_out = ?, bytes_in = ?, bytes_out = ?
            WHERE flow_id = ?
            """, packetsIn, packetsOut, bytesIn, bytesOut, flowId)
    }
}
