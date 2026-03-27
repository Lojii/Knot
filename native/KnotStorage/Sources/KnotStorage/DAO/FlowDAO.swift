import Foundation
import SQLite

/// Data Access Object for the `flow` table in protocol.db.
/// All methods are static — use `FlowDAO` as a namespace, not an instance.
public enum FlowDAO {

    // MARK: - Insert

    /// Insert a new FlowRecord into the flow table.
    public static func insert(db: Connection, record: FlowRecord) throws {
        let metadataJSON: String
        if record.metadata.isEmpty {
            metadataJSON = "{}"
        } else {
            let data = try JSONSerialization.data(withJSONObject: record.metadata, options: [])
            metadataJSON = String(data: data, encoding: .utf8) ?? "{}"
        }

        try db.run("""
            INSERT INTO flow (
                flow_id, protocol, host, port, started_at,
                ended_at, duration_ms,
                connect_at, connected_at, tls_done_at, req_end_at, rsp_start_at,
                upload_bytes, download_bytes,
                status, error_message, summary,
                search_key1, search_key2, search_key3, search_key4,
                metadata, req_payload_ref, rsp_payload_ref,
                is_intercepted, is_modified, tags,
                conn_reuse, proto_flags, push_status, cert_chain_ref
            ) VALUES (
                ?, ?, ?, ?, ?,
                ?, ?,
                ?, ?, ?, ?, ?,
                ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?,
                ?, ?, ?, ?
            )
            """,
            record.flowId,
            record.protocolName,
            record.host,
            record.port,
            record.startedAt,
            record.endedAt,
            record.durationMs,
            record.connectAt,
            record.connectedAt,
            record.tlsDoneAt,
            record.reqEndAt,
            record.rspStartAt,
            record.uploadBytes,
            record.downloadBytes,
            record.status.rawValue,
            record.errorMessage,
            record.summary,
            record.searchKey1,
            record.searchKey2,
            record.searchKey3,
            record.searchKey4,
            metadataJSON,
            record.reqPayloadRef,
            record.rspPayloadRef,
            record.isIntercepted ? 1 : 0,
            record.isModified ? 1 : 0,
            record.tags,
            record.connReuse,
            record.protoFlags,
            record.pushStatus,
            record.certChainRef
        )
    }

    // MARK: - Update

    /// Update specific fields of an existing flow record.
    /// Only non-nil parameters are included in the SET clause.
    public static func update(
        db: Connection,
        flowId: String,
        endedAt: TimeInterval? = nil,
        status: FlowStatus? = nil,
        summary: String? = nil,
        downloadBytes: Int64? = nil,
        uploadBytes: Int64? = nil,
        errorMessage: String? = nil,
        durationMs: Double? = nil
    ) throws {
        var setClauses: [String] = []
        var bindings: [Binding?] = []

        if let v = endedAt {
            setClauses.append("ended_at = ?")
            bindings.append(v)
        }
        if let v = status {
            setClauses.append("status = ?")
            bindings.append(Int64(v.rawValue))
        }
        if let v = summary {
            setClauses.append("summary = ?")
            bindings.append(v)
        }
        if let v = downloadBytes {
            setClauses.append("download_bytes = ?")
            bindings.append(v)
        }
        if let v = uploadBytes {
            setClauses.append("upload_bytes = ?")
            bindings.append(v)
        }
        if let v = errorMessage {
            setClauses.append("error_message = ?")
            bindings.append(v)
        }
        if let v = durationMs {
            setClauses.append("duration_ms = ?")
            bindings.append(v)
        }

        guard !setClauses.isEmpty else { return }

        bindings.append(flowId)
        let sql = "UPDATE flow SET \(setClauses.joined(separator: ", ")) WHERE flow_id = ?"
        try db.run(sql, bindings)
    }

    // MARK: - Find

    /// Find a single FlowRecord by flowId. Returns nil if not found.
    public static func find(db: Connection, flowId: String) throws -> FlowRecord? {
        let stmt = try db.prepare("SELECT * FROM flow WHERE flow_id = ?", flowId)
        for row in stmt {
            return try mapRow(row, stmt: stmt)
        }
        return nil
    }

    // MARK: - Query

    /// Query flows with optional filters, ordered by started_at DESC.
    public static func query(
        db: Connection,
        protocolFilter: String? = nil,
        hostContains: String? = nil,
        keyword: String? = nil,
        offset: Int = 0,
        limit: Int = 100
    ) throws -> [FlowRecord] {
        var conditions: [String] = []
        var bindings: [Binding?] = []

        if let proto = protocolFilter {
            let parts = proto.split(separator: ",").map(String.init)
            if parts.count == 1 {
                conditions.append("protocol = ?")
                bindings.append(parts[0])
            } else {
                let placeholders = parts.map { _ in "?" }.joined(separator: ",")
                conditions.append("protocol IN (\(placeholders))")
                for p in parts { bindings.append(p) }
            }
        }
        if let host = hostContains {
            conditions.append("host LIKE ?")
            bindings.append("%\(host)%")
        }
        if let kw = keyword {
            conditions.append("(host LIKE ? OR search_key2 LIKE ? OR summary LIKE ?)")
            let pattern = "%\(kw)%"
            bindings.append(pattern)
            bindings.append(pattern)
            bindings.append(pattern)
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let sql = "SELECT * FROM flow \(whereClause) ORDER BY started_at DESC LIMIT ? OFFSET ?"
        bindings.append(Int64(limit))
        bindings.append(Int64(offset))

        let stmt = try db.prepare(sql, bindings)
        var results: [FlowRecord] = []
        for row in stmt {
            let record = try mapRow(row, stmt: stmt)
            results.append(record)
        }
        return results
    }

    /// Lightweight query: returns all flows with minimal fields for tree building.
    public static func querySummary(db: Connection) throws -> [[String: Any]] {
        let sql = """
            SELECT flow_id, host, protocol, search_key1, search_key2, search_key3, search_key4, status
            FROM flow ORDER BY started_at DESC
            """
        let stmt = try db.prepare(sql)
        var results: [[String: Any]] = []
        for row in stmt {
            let dict: [String: Any] = [
                "flowId": row[0] as? String ?? "",
                "host": row[1] as? String ?? "",
                "protocol": row[2] as? String ?? "",
                "method": row[3] as? String ?? "",
                "path": row[4] as? String ?? "",
                "statusCode": row[5] as? String ?? "",
                "contentType": row[6] as? String ?? "",
                "status": Int(row[7] as? Int64 ?? 0),
            ]
            results.append(dict)
        }
        return results
    }

    // MARK: - Row Mapping

    private static func mapRow(_ row: Statement.Element, stmt: Statement) throws -> FlowRecord {
        // Build column-name → index map from the statement
        let columnNames = stmt.columnNames
        func idx(_ name: String) -> Int {
            return columnNames.firstIndex(of: name) ?? -1
        }

        func str(_ name: String) -> String {
            let i = idx(name)
            guard i >= 0 else { return "" }
            return row[i] as? String ?? ""
        }
        func optDouble(_ name: String) -> Double? {
            let i = idx(name)
            guard i >= 0 else { return nil }
            return row[i] as? Double
        }
        func int64(_ name: String) -> Int64 {
            let i = idx(name)
            guard i >= 0 else { return 0 }
            return row[i] as? Int64 ?? 0
        }
        func optInt64(_ name: String) -> Int64? {
            let i = idx(name)
            guard i >= 0 else { return nil }
            return row[i] as? Int64
        }
        func optStr(_ name: String) -> String? {
            let i = idx(name)
            guard i >= 0 else { return nil }
            return row[i] as? String
        }

        let flowId = str("flow_id")
        let protocolName = str("protocol")
        let host = str("host")
        let port = Int(int64("port"))
        let startedAt = optDouble("started_at") ?? 0.0

        var record = FlowRecord(
            flowId: flowId,
            protocolName: protocolName,
            host: host,
            port: port,
            startedAt: startedAt
        )

        record.endedAt = optDouble("ended_at")
        record.durationMs = optDouble("duration_ms")
        record.uploadBytes = int64("upload_bytes")
        record.downloadBytes = int64("download_bytes")
        record.status = FlowStatus(rawValue: Int(int64("status"))) ?? .inProgress
        record.errorMessage = str("error_message")
        record.summary = str("summary")

        record.searchKey1 = str("search_key1")
        record.searchKey2 = str("search_key2")
        record.searchKey3 = str("search_key3")
        record.searchKey4 = str("search_key4")

        record.connectAt = optDouble("connect_at")
        record.connectedAt = optDouble("connected_at")
        record.tlsDoneAt = optDouble("tls_done_at")
        record.reqEndAt = optDouble("req_end_at")
        record.rspStartAt = optDouble("rsp_start_at")

        // Deserialize metadata JSON
        let metadataStr = str("metadata")
        if let data = metadataStr.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = obj as? [String: Any] {
            record.metadata = dict
        }

        record.reqPayloadRef = str("req_payload_ref")
        record.rspPayloadRef = str("rsp_payload_ref")
        record.isIntercepted = int64("is_intercepted") != 0
        record.isModified = int64("is_modified") != 0
        record.tags = str("tags")

        record.connReuse = Int(int64("conn_reuse"))
        record.protoFlags = Int(int64("proto_flags"))
        record.pushStatus = optInt64("push_status").map { Int($0) }
        record.certChainRef = optStr("cert_chain_ref")

        return record
    }
}
