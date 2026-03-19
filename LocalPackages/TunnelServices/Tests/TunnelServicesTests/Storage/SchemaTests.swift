import XCTest
import SQLite
@testable import TunnelServices

final class SchemaTests: XCTestCase {
    var helper: StorageTestHelper!
    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testCatalogSchema() throws {
        let db = try helper.createTempDB(name: "catalog.db")
        try CatalogSchema.create(db)
        let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { $0[0] as! String }
        XCTAssertTrue(tables.contains("capture_task"))
        XCTAssertTrue(tables.contains("rule"))
        XCTAssertTrue(tables.contains("breakpoint"))
    }

    func testTransportSchema() throws {
        let db = try helper.createTempDB(name: "transport.db")
        try TransportSchema.create(db)
        let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { $0[0] as! String }
        XCTAssertTrue(tables.contains("packet"))
    }

    func testProtocolSchema() throws {
        let db = try helper.createTempDB(name: "protocol.db")
        try ProtocolSchema.create(db)
        let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { $0[0] as! String }
        XCTAssertTrue(tables.contains("flow"))
    }

    func testDecodedSchema() throws {
        let db = try helper.createTempDB(name: "decoded.db")
        try DecodedSchema.create(db)
        let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { $0[0] as! String }
        XCTAssertTrue(tables.contains("decoded_entry"))
        // Verify FTS virtual table
        let vtables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='decoded_fts'").map { $0[0] as! String }
        XCTAssertTrue(vtables.contains("decoded_fts"))
    }

    func testStateSchema() throws {
        let db = try helper.createTempDB(name: "state.db")
        try StateSchema.create(db)
        let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { $0[0] as! String }
        XCTAssertTrue(tables.contains("connection"))
        XCTAssertTrue(tables.contains("modify_log"))
        XCTAssertTrue(tables.contains("task_stats"))
        // Verify task_stats singleton row
        let count = try db.scalar("SELECT COUNT(*) FROM task_stats") as! Int64
        XCTAssertEqual(count, 1)
    }

    func testIdempotent() throws {
        let db = try helper.createTempDB()
        try CatalogSchema.create(db)
        try CatalogSchema.create(db)  // should not throw
        try TransportSchema.create(db)
        try TransportSchema.create(db)
    }
}
