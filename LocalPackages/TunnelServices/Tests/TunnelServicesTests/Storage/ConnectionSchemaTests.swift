import XCTest
import SQLite
@testable import TunnelServices

final class ConnectionSchemaTests: XCTestCase {
    var helper: StorageTestHelper!
    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testCreatesTables() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            .map { $0[0] as! String }
        XCTAssertTrue(tables.contains("tcp_connection"))
        XCTAssertTrue(tables.contains("quic_connection"))
        XCTAssertTrue(tables.contains("quic_stream"))
    }

    func testIdempotent() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        try ConnectionSchema.create(db)
    }

    func testTcpConnectionInsert() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        try db.run("""
            INSERT INTO tcp_connection (flow_id, src_ip, src_port, dst_ip, dst_port, started_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, "tcp_001", "192.168.1.1", 12345, "10.0.0.1", 443, 1000.0)
        let count = try db.scalar("SELECT COUNT(*) FROM tcp_connection") as! Int64
        XCTAssertEqual(count, 1)
    }

    func testQuicStreamUniqueConstraint() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        try db.run("INSERT INTO quic_stream (connection_id, stream_id, started_at) VALUES (?, ?, ?)",
                   "quic_001", 1, 1000.0)
        XCTAssertThrowsError(try db.run(
            "INSERT INTO quic_stream (connection_id, stream_id, started_at) VALUES (?, ?, ?)",
            "quic_001", 1, 1001.0))
    }
}
