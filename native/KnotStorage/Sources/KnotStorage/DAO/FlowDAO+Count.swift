import Foundation
import SQLite

extension FlowDAO {
    /// Returns a dictionary of protocol name → count
    public static func countByProtocol(db: Connection) throws -> [String: Int] {
        var result: [String: Int] = [:]
        let stmt = try db.prepare("SELECT protocol, COUNT(*) FROM flow GROUP BY protocol")
        for row in stmt {
            let proto = row[0] as? String ?? ""
            let count = Int(row[1] as? Int64 ?? 0)
            result[proto] = count
        }
        return result
    }

    /// Count flows matching the same filters as `query()`.
    public static func count(
        db: Connection,
        protocolFilter: String? = nil,
        hostContains: String? = nil,
        keyword: String? = nil
    ) throws -> Int {
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
        let sql = "SELECT COUNT(*) FROM flow \(whereClause)"
        let stmt = try db.prepare(sql, bindings)
        for row in stmt {
            return Int(row[0] as? Int64 ?? 0)
        }
        return 0
    }

    /// Returns a dictionary of status raw value → count
    public static func countByStatus(db: Connection) throws -> [Int: Int] {
        var result: [Int: Int] = [:]
        let stmt = try db.prepare("SELECT status, COUNT(*) FROM flow GROUP BY status")
        for row in stmt {
            let status = Int(row[0] as? Int64 ?? 0)
            let count = Int(row[1] as? Int64 ?? 0)
            result[status] = count
        }
        return result
    }

    /// Returns domain (host) → request count.
    public static func countByHost(db: Connection) throws -> [String: Int] {
        var result: [String: Int] = [:]
        let stmt = try db.prepare("SELECT host, COUNT(*) FROM flow GROUP BY host ORDER BY COUNT(*) DESC")
        for row in stmt {
            let host = row[0] as? String ?? ""
            let count = Int(row[1] as? Int64 ?? 0)
            if !host.isEmpty { result[host] = count }
        }
        return result
    }

    /// Returns distinct non-empty values from search_key4 (content type).
    public static func distinctContentTypes(db: Connection) throws -> [String] {
        var result: [String] = []
        let stmt = try db.prepare("SELECT DISTINCT search_key4 FROM flow WHERE search_key4 != '' AND search_key4 IS NOT NULL")
        for row in stmt {
            if let ct = row[0] as? String, !ct.isEmpty {
                result.append(ct)
            }
        }
        return result
    }

    /// Returns total upload and download bytes across all flows.
    public static func totalBytes(db: Connection) throws -> (upload: Int64, download: Int64) {
        let stmt = try db.prepare("SELECT COALESCE(SUM(upload_bytes),0), COALESCE(SUM(download_bytes),0) FROM flow")
        for row in stmt {
            let up = row[0] as? Int64 ?? 0
            let down = row[1] as? Int64 ?? 0
            return (up, down)
        }
        return (0, 0)
    }
}
