import Foundation
import SQLite

public struct TaskStats {
    public var totalFlows: Int64 = 0
    public var activeConnections: Int64 = 0
    public var totalPackets: Int64 = 0
    public var uploadBytes: Int64 = 0
    public var downloadBytes: Int64 = 0
    public var interceptedCount: Int64 = 0
    public var errorCount: Int64 = 0
    public var updatedAt: TimeInterval = 0
    public init() {}
}

public enum TaskStatsDAO {
    public static func update(db: Connection, stats: TaskStats) throws {
        try db.run("""
            UPDATE task_stats SET
                total_flows = ?, active_connections = ?, total_packets = ?,
                upload_bytes = ?, download_bytes = ?,
                intercepted_count = ?, error_count = ?, updated_at = ?
            WHERE id = 1
            """,
            stats.totalFlows, stats.activeConnections, stats.totalPackets,
            stats.uploadBytes, stats.downloadBytes,
            stats.interceptedCount, stats.errorCount, stats.updatedAt
        )
    }

    public static func read(db: Connection) throws -> TaskStats {
        let stmt = try db.prepare("SELECT * FROM task_stats WHERE id = 1")
        for row in stmt {
            var s = TaskStats()
            s.totalFlows = row[1] as? Int64 ?? 0
            s.activeConnections = row[2] as? Int64 ?? 0
            s.totalPackets = row[3] as? Int64 ?? 0
            s.uploadBytes = row[4] as? Int64 ?? 0
            s.downloadBytes = row[5] as? Int64 ?? 0
            s.interceptedCount = row[6] as? Int64 ?? 0
            s.errorCount = row[7] as? Int64 ?? 0
            s.updatedAt = row[8] as? Double ?? 0
            return s
        }
        return TaskStats()
    }
}
