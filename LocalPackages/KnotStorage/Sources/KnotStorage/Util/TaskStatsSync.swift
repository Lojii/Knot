import Foundation
import SQLite
import os

/// Periodically syncs task_stats from state.db to catalog.db capture_task.
/// Runs on a low-priority queue, does not block capture.
public class TaskStatsSync {
    private static let logger = Logger(subsystem: "KnotStorage", category: "TaskStatsSync")

    private let taskId: Int64
    private let catalogDB: Connection
    private let stateDB: Connection
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "stats.sync", qos: .utility)

    public init(taskId: Int64, catalogDB: Connection, stateDB: Connection) {
        self.taskId = taskId
        self.catalogDB = catalogDB
        self.stateDB = stateDB
    }

    /// Start periodic sync (default every 5 seconds)
    public func start(interval: TimeInterval = 5.0) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.syncNow()
        }
        timer.resume()
        self.timer = timer
    }

    /// Immediate sync (call on capture stop)
    public func syncNow() {
        do {
            let stats = try TaskStatsDAO.read(db: stateDB)
            try CatalogDAO.updateTask(
                db: catalogDB,
                taskId: taskId,
                flowCount: stats.totalFlows,
                uploadBytes: stats.uploadBytes,
                downloadBytes: stats.downloadBytes
            )
        } catch {
            Self.logger.error("Stats sync failed: \(error.localizedDescription)")
        }
    }

    /// Stop timer and do final sync
    public func stop() {
        timer?.cancel()
        timer = nil
        syncNow()
    }

    /// Recover crashed tasks on app launch.
    /// Finds tasks with status=running and syncs their stats.
    public static func recoverCrashedTasks(catalogDB: Connection, rootPath: String) {
        do {
            let tasks = try CatalogDAO.findAllTasks(db: catalogDB)
            for task in tasks where task.status == 1 { // 1 = running
                let stateDBPath = PathManager.stateDBPath(task.id, root: rootPath)
                guard FileManager.default.fileExists(atPath: stateDBPath) else { continue }
                let stateDB = try Connection(stateDBPath)
                let stats = try TaskStatsDAO.read(db: stateDB)
                try CatalogDAO.updateTask(
                    db: catalogDB, taskId: task.id,
                    flowCount: stats.totalFlows,
                    uploadBytes: stats.uploadBytes,
                    downloadBytes: stats.downloadBytes,
                    status: 2 // mark as stopped
                )
            }
        } catch {
            Self.logger.error("Crash recovery failed: \(error.localizedDescription)")
        }
    }

    deinit {
        timer?.cancel()
    }
}
