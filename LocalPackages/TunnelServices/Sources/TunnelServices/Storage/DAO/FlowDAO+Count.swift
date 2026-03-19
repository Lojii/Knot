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
}
