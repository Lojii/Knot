import XCTest
import SQLite
@testable import TunnelServices

final class CatalogDAOTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "catalog.db")
        try! CatalogSchema.create(db)
    }
    override func tearDown() { helper = nil }

    func testInsertAndFindTask() throws {
        let taskId = try CatalogDAO.insertTask(db: db, name: "Test", createdAt: 1000)
        XCTAssertGreaterThan(taskId, 0)
        let tasks = try CatalogDAO.findAllTasks(db: db)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].name, "Test")
    }

    func testUpdateTask() throws {
        let taskId = try CatalogDAO.insertTask(db: db, name: "Test", createdAt: 1000)
        try CatalogDAO.updateTask(db: db, taskId: taskId, flowCount: 42, status: 2)
        // Verify via raw query
        let row = try db.prepare("SELECT flow_count, status FROM capture_task WHERE id = ?", taskId).makeIterator().next()!
        XCTAssertEqual(row[0] as? Int64, 42)
        XCTAssertEqual(row[1] as? Int64, 2)
    }

    func testDeleteTask() throws {
        let taskId = try CatalogDAO.insertTask(db: db, name: "ToDelete", createdAt: 1000)
        try CatalogDAO.deleteTask(db: db, taskId: taskId)
        let tasks = try CatalogDAO.findAllTasks(db: db)
        XCTAssertEqual(tasks.count, 0)
    }

    func testInsertAndFindBreakpoint() throws {
        try CatalogDAO.insertBreakpoint(db: db, matchPattern: "*.example.com", action: "pause", createdAt: 1000)
        let bps = try CatalogDAO.findEnabledBreakpoints(db: db)
        XCTAssertEqual(bps.count, 1)
        XCTAssertEqual(bps[0].matchPattern, "*.example.com")
    }
}
