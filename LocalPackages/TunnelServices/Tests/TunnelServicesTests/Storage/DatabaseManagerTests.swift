import XCTest
import SQLite
@testable import TunnelServices

final class DatabaseManagerTests: XCTestCase {
    var helper: StorageTestHelper!

    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testCatalogDBCreated() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        // catalog.db should be created and have tables
        let tables = try mgr.catalogDB.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { $0[0] as! String }
        XCTAssertTrue(tables.contains("capture_task"))
        XCTAssertTrue(tables.contains("rule"))
        XCTAssertTrue(tables.contains("breakpoint"))
    }

    func testOpenAndCloseTask() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        let group = try mgr.openTask(1)
        // Verify all 4 DBs are accessible
        XCTAssertNoThrow(try group.proto.scalar("SELECT COUNT(*) FROM flow"))
        XCTAssertNoThrow(try group.transport.scalar("SELECT COUNT(*) FROM packet"))
        XCTAssertNoThrow(try group.decoded.scalar("SELECT COUNT(*) FROM decoded_entry"))
        XCTAssertNoThrow(try group.state.scalar("SELECT COUNT(*) FROM task_stats"))
        // Verify FlowIdGenerator is available
        let flowId = group.flowIdGenerator.next()
        XCTAssertFalse(flowId.isEmpty)
        mgr.closeTask(1)
    }

    func testDeleteTask() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        _ = try mgr.openTask(1)
        mgr.closeTask(1)
        try mgr.deleteTask(1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: PathManager.taskDirectory(1, root: helper.tempDir)))
    }

    func testRefCounting() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        let g1 = try mgr.openTask(1)
        let g2 = try mgr.openTask(1) // same task, increments refCount
        XCTAssertTrue(g1 === g2)      // same instance
        mgr.closeTask(1)              // refCount 2 → 1
        // Should still be accessible
        XCTAssertNoThrow(try g1.proto.scalar("SELECT COUNT(*) FROM flow"))
        mgr.closeTask(1)              // refCount 1 → 0
    }

    func testTaskDirectoriesCreated() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        _ = try mgr.openTask(42)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/42/transport.db"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/42/protocol.db"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/42/decoded.db"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/42/state.db"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/42/payloads/raw"))
        mgr.closeTask(42)
    }
}
