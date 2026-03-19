import Foundation
import SQLite

/// Global manager for all database connections.
/// Manages catalog.db (always open) and per-task database groups (opened on demand).
public class DatabaseManager {

    /// Shared singleton for production use. Initialized lazily on first access.
    public static let shared = DatabaseManager()

    /// The catalog.db connection (always open while manager exists)
    public let catalogDB: Connection

    private let rootPath: String
    private var activePools: [Int64: TaskDatabaseGroup] = [:]
    private let poolLock = NSLock()
    private let profile: PragmaProfile

    public init(rootPath: String? = nil, profile: PragmaProfile = .mainApp) {
        let root = rootPath ?? PathManager.root
        self.rootPath = root
        self.profile = profile

        // Ensure root directory exists
        try! FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)

        // Open catalog.db
        catalogDB = try! Connection(PathManager.catalogDBPath(root: root))
        try! TaskDatabaseGroup.configurePragmas(catalogDB, profile: profile)
        try! CatalogSchema.create(catalogDB)
    }

    /// Open or get existing TaskDatabaseGroup. Increments ref count if already open.
    public func openTask(_ taskId: Int64) throws -> TaskDatabaseGroup {
        poolLock.lock()
        defer { poolLock.unlock() }

        if let existing = activePools[taskId] {
            existing.refCount += 1
            return existing
        }

        let group = try TaskDatabaseGroup(taskId: taskId, rootPath: rootPath, profile: profile)
        activePools[taskId] = group
        return group
    }

    /// Decrement ref count. Removes from pool when count reaches 0.
    public func closeTask(_ taskId: Int64) {
        poolLock.lock()
        defer { poolLock.unlock() }

        guard let group = activePools[taskId] else { return }
        group.refCount -= 1
        if group.refCount <= 0 {
            activePools.removeValue(forKey: taskId)
        }
    }

    /// Close connections and delete entire task directory.
    public func deleteTask(_ taskId: Int64) throws {
        poolLock.lock()
        activePools.removeValue(forKey: taskId)
        poolLock.unlock()

        let taskDir = PathManager.taskDirectory(taskId, root: rootPath)
        if FileManager.default.fileExists(atPath: taskDir) {
            try FileManager.default.removeItem(atPath: taskDir)
        }
    }
}
