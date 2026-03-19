import Foundation
import SQLite

public enum ConnectionDAO {
    public static func insertOrUpdate(db: Connection, record: ConnectionRecord) throws {
        try db.run("""
            INSERT INTO connection (flow_id, client_state, server_state, started_at, closed_at,
                close_reason, tls_version, tls_cipher, server_cert)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(flow_id) DO UPDATE SET
                client_state = excluded.client_state,
                server_state = excluded.server_state,
                closed_at = excluded.closed_at,
                close_reason = excluded.close_reason
            """,
            record.flowId, record.clientState, record.serverState, record.startedAt,
            record.closedAt, record.closeReason, record.tlsVersion, record.tlsCipher, record.serverCert
        )
    }

    public static func find(db: Connection, flowId: String) throws -> ConnectionRecord? {
        let stmt = try db.prepare("SELECT * FROM connection WHERE flow_id = ?", flowId)
        for row in stmt {
            return ConnectionRecord(
                flowId: row[1] as? String ?? "",
                startedAt: row[4] as? Double ?? 0,
                clientState: row[2] as? String ?? "open",
                serverState: row[3] as? String ?? "open",
                closedAt: row[5] as? Double,
                closeReason: row[6] as? String ?? "",
                tlsVersion: row[7] as? String ?? "",
                tlsCipher: row[8] as? String ?? "",
                serverCert: row[9] as? String ?? ""
            )
        }
        return nil
    }
}
