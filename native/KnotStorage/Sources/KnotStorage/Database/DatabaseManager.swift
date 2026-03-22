import Foundation
import SQLite
import os

/// Global manager for all database connections.
/// Manages catalog.db (always open) and per-task database groups (opened on demand).
public class DatabaseManager {

    private static let logger = Logger(subsystem: "KnotStorage", category: "DatabaseManager")

    /// Set by app on launch before first use.
    /// Defaults to PathManager.root if not set explicitly.
    public static var rootPath: String = ""

    /// Shared singleton for production use. Initialized lazily on first access.
    public static let shared = DatabaseManager()

    /// The catalog.db connection (always open while manager exists)
    public let catalogDB: Connection

    private let resolvedRootPath: String
    private var activePools: [Int64: TaskDatabaseGroup] = [:]
    private let poolLock = NSLock()
    private let profile: PragmaProfile

    public init(rootPath: String? = nil, profile: PragmaProfile = .mainApp) {
        let root = rootPath ?? (Self.rootPath.isEmpty ? PathManager.root : Self.rootPath)
        self.resolvedRootPath = root
        self.profile = profile

        do {
            // Ensure root directory exists
            try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)

            // Open catalog.db
            let db = try Connection(PathManager.catalogDBPath(root: root))
            try TaskDatabaseGroup.configurePragmas(db, profile: profile)
            try CatalogSchema.create(db)
            catalogDB = db
        } catch {
            // If we cannot open catalog.db, fall back to an in-memory database so the app
            // doesn't crash. This is a degraded state — data won't persist.
            Self.logger.error("Failed to initialize catalog.db at \(root): \(error.localizedDescription). Falling back to in-memory database.")
            do {
                let db = try Connection(.inMemory)
                try CatalogSchema.create(db)
                catalogDB = db
            } catch {
                // Absolute last resort — this should never happen with an in-memory DB.
                fatalError("[DatabaseManager] Cannot create even an in-memory database: \(error)")
            }
        }
    }

    /// Open or get existing TaskDatabaseGroup. Increments ref count if already open.
    public func openTask(_ taskId: Int64) throws -> TaskDatabaseGroup {
        poolLock.lock()
        defer { poolLock.unlock() }

        if let existing = activePools[taskId] {
            existing.refCount += 1
            return existing
        }

        let group = try TaskDatabaseGroup(taskId: taskId, rootPath: resolvedRootPath, profile: profile)
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

        let taskDir = PathManager.taskDirectory(taskId, root: resolvedRootPath)
        if FileManager.default.fileExists(atPath: taskDir) {
            try FileManager.default.removeItem(atPath: taskDir)
        }
    }
}
