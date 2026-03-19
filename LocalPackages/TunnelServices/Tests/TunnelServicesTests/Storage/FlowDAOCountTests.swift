import XCTest
import SQLite
@testable import TunnelServices

final class FlowDAOCountTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "protocol.db")
        try! ProtocolSchema.create(db)
        // Seed: 5 HTTP, 3 DNS, 2 WS
        for i in 0..<5 {
            var r = FlowRecord(flowId: "http_\(i)", protocolName: "HTTP", host: "h", port: 80, startedAt: Double(i))
            try! FlowDAO.insert(db: db, record: r)
        }
        for i in 0..<3 {
            var r = FlowRecord(flowId: "dns_\(i)", protocolName: "DNS", host: "h", port: 53, startedAt: Double(10+i))
            try! FlowDAO.insert(db: db, record: r)
        }
        for i in 0..<2 {
            var r = FlowRecord(flowId: "ws_\(i)", protocolName: "WS", host: "h", port: 443, startedAt: Double(20+i))
            try! FlowDAO.insert(db: db, record: r)
        }
    }
    override func tearDown() { helper = nil }

    func testCountByProtocol() throws {
        let counts = try FlowDAO.countByProtocol(db: db)
        XCTAssertEqual(counts["HTTP"], 5)
        XCTAssertEqual(counts["DNS"], 3)
        XCTAssertEqual(counts["WS"], 2)
    }

    func testTotalCount() throws {
        let counts = try FlowDAO.countByProtocol(db: db)
        let total = counts.values.reduce(0, +)
        XCTAssertEqual(total, 10)
    }
}
