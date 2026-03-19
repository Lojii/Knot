import XCTest
import SQLite
@testable import TunnelServices

final class TcpConnectionDAOTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "connection.db")
        try! ConnectionSchema.create(db)
    }
    override func tearDown() { helper = nil }

    func testInsertAndFind() throws {
        let record = TcpConnectionRecord(
            flowId: "tcp_001", srcIp: "192.168.1.1", srcPort: 12345,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0,
            tlsSni: "example.com"
        )
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)
        let found = try TcpConnectionDAO.find(db: db, flowId: "tcp_001")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.dstPort, 443)
        XCTAssertEqual(found?.tlsSni, "example.com")
    }

    func testUpsertUpdatesOnConflict() throws {
        var record = TcpConnectionRecord(
            flowId: "tcp_001", srcIp: "192.168.1.1", srcPort: 12345,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0
        )
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)
        record.state = "closed"
        record.closedAt = 2000.0
        record.closeReason = "normal"
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)
        let found = try TcpConnectionDAO.find(db: db, flowId: "tcp_001")
        XCTAssertEqual(found?.state, "closed")
        XCTAssertEqual(found?.closedAt, 2000.0)
    }

    func testUpdateStats() throws {
        let record = TcpConnectionRecord(
            flowId: "tcp_001", srcIp: "192.168.1.1", srcPort: 12345,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0
        )
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)
        try TcpConnectionDAO.updateStats(db: db, flowId: "tcp_001",
                                          packetsIn: 100, packetsOut: 50,
                                          bytesIn: 4096, bytesOut: 1024)
        let found = try TcpConnectionDAO.find(db: db, flowId: "tcp_001")
        XCTAssertEqual(found?.packetsIn, 100)
        XCTAssertEqual(found?.bytesIn, 4096)
    }
}
