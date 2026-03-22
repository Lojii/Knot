import XCTest
import KnotStorage
import SQLite
@testable import TunnelServices

final class FlowDAOSearchTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "protocol.db")
        try! ProtocolSchema.create(db)
        try! ProtocolSchema.migrateIfNeeded(db)
        for i in 0..<5 {
            var r = FlowRecord(flowId: "f_\(i)", protocolName: "HTTP",
                               host: "api.example.com", port: 443, startedAt: Double(i))
            r.searchKey2 = "/api/users/\(i)"
            r.summary = "GET /api/users/\(i) → 200"
            try! FlowDAO.insert(db: db, record: r)
        }
        var dns = FlowRecord(flowId: "dns_1", protocolName: "DNS",
                             host: "example.com", port: 53, startedAt: 10)
        dns.summary = "A example.com → 1.2.3.4"
        try! FlowDAO.insert(db: db, record: dns)
    }
    override func tearDown() { helper = nil }

    func testKeywordSearchHost() throws {
        let results = try FlowDAO.query(db: db, keyword: "example")
        XCTAssertEqual(results.count, 6)
    }

    func testKeywordSearchUri() throws {
        let results = try FlowDAO.query(db: db, keyword: "users/3")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].flowId, "f_3")
    }

    func testKeywordSearchSummary() throws {
        let results = try FlowDAO.query(db: db, keyword: "1.2.3.4")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].protocolName, "DNS")
    }

    func testKeywordWithProtocolFilter() throws {
        let results = try FlowDAO.query(db: db, protocolFilter: "HTTP", keyword: "users")
        XCTAssertEqual(results.count, 5)
    }
}
