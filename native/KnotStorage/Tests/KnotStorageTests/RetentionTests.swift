import XCTest
@testable import KnotStorage

final class RetentionTests: XCTestCase {

    private var tempDir: String!
    private var manager: DatabaseManager!

    override func setUpWithError() throws {
        tempDir = NSTemporaryDirectory() + "KnotRetentionTests_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        manager = DatabaseManager(rootPath: tempDir)
    }

    override func tearDownWithError() throws {
        if let dir = tempDir, FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    /// Insert a task with an explicit created_at and materialize its directory.
    @discardableResult
    private func makeTask(name: String, createdAt: TimeInterval) throws -> Int64 {
        let id = try CatalogDAO.insertTask(db: manager.catalogDB, name: name, createdAt: createdAt)
        let group = try manager.openTask(id)   // creates the task directory
        manager.closeTask(id)
        _ = group
        return id
    }

    func testFindRetiredByCount() throws {
        let now: TimeInterval = 1_000_000
        // 5 tasks, newest first by created_at
        for i in 0..<5 {
            try makeTask(name: "t\(i)", createdAt: now - TimeInterval(i))
        }
        let retired = try CatalogDAO.findRetiredTaskIds(
            db: manager.catalogDB, now: now, maxTasks: 3, maxAgeSeconds: 0)
        XCTAssertEqual(retired.count, 2, "2 oldest of 5 should be retired when cap is 3")
    }

    func testFindRetiredByAge() throws {
        let now: TimeInterval = 1_000_000
        try makeTask(name: "fresh", createdAt: now - 10)
        try makeTask(name: "old", createdAt: now - 100_000)
        let retired = try CatalogDAO.findRetiredTaskIds(
            db: manager.catalogDB, now: now, maxTasks: 0, maxAgeSeconds: 50_000)
        XCTAssertEqual(retired.count, 1, "only the task older than the age cutoff is retired")
    }

    func testEnforceRetentionDeletesRowsAndDirs() throws {
        let now: TimeInterval = 1_000_000
        var ids: [Int64] = []
        for i in 0..<4 {
            ids.append(try makeTask(name: "t\(i)", createdAt: now - TimeInterval(i)))
        }
        let deleted = manager.enforceRetention(maxTasks: 2, maxAgeDays: 0, now: now)
        XCTAssertEqual(deleted, 2)

        let remaining = try CatalogDAO.findAllTasks(db: manager.catalogDB)
        XCTAssertEqual(remaining.count, 2, "only the 2 newest tasks remain")

        // The two oldest task directories should be gone.
        for id in ids.suffix(2) {
            let dir = PathManager.taskDirectory(id, root: tempDir)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir),
                           "retired task \(id) directory should be removed")
        }
    }

    func testEnforceRetentionSkipsActiveTask() throws {
        let now: TimeInterval = 1_000_000
        let oldId = try makeTask(name: "old-but-active", createdAt: now - 100_000)
        try makeTask(name: "fresh", createdAt: now - 10)

        // Hold the old task open — it must not be deleted while active.
        let held = try manager.openTask(oldId)
        defer { manager.closeTask(oldId) }
        _ = held

        let deleted = manager.enforceRetention(maxTasks: 1, maxAgeDays: 0, now: now)
        XCTAssertEqual(deleted, 0, "the over-cap task is active and must be skipped")
    }
}
