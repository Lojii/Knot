import XCTest
import SQLite
@testable import TunnelServices

final class FlowDAOTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "protocol.db")
        try! ProtocolSchema.create(db)
    }
    override func tearDown() { helper = nil }

    func testInsertAndFind() throws {
        var record = FlowRecord(flowId: "test_0001", protocolName: "HTTP", host: "example.com", port: 443, startedAt: 1000.0)
        record.searchKey1 = "GET"
        record.searchKey2 = "/api/users"
        record.searchKey3 = "200"
        record.summary = "GET /api/users → 200"
        record.metadata = ["httpVersion": "1.1"]
        try FlowDAO.insert(db: db, record: record)

        let found = try FlowDAO.find(db: db, flowId: "test_0001")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.host, "example.com")
        XCTAssertEqual(found?.searchKey1, "GET")
        XCTAssertEqual(found?.summary, "GET /api/users → 200")
    }

    func testUpdateFields() throws {
        var record = FlowRecord(flowId: "test_0001", protocolName: "HTTP", host: "example.com", port: 80, startedAt: 1000)
        try FlowDAO.insert(db: db, record: record)

        try FlowDAO.update(db: db, flowId: "test_0001", endedAt: 2000.0, status: .completed, summary: "GET / → 200", downloadBytes: 4096)

        let found = try FlowDAO.find(db: db, flowId: "test_0001")
        XCTAssertEqual(found?.status, .completed)
        XCTAssertEqual(found?.downloadBytes, 4096)
        XCTAssertEqual(found?.summary, "GET / → 200")
    }

    func testQueryAll() throws {
        for i in 0..<10 {
            var r = FlowRecord(flowId: "f_\(String(format: "%04d", i))", protocolName: i < 5 ? "HTTP" : "DNS",
                               host: "host\(i).com", port: 80, startedAt: Double(i))
            r.searchKey1 = i < 5 ? "GET" : "A"
            try FlowDAO.insert(db: db, record: r)
        }
        let all = try FlowDAO.query(db: db, limit: 100)
        XCTAssertEqual(all.count, 10)
    }

    func testQueryWithProtocolFilter() throws {
        for i in 0..<10 {
            var r = FlowRecord(flowId: "f_\(i)", protocolName: i < 5 ? "HTTP" : "DNS",
                               host: "host\(i).com", port: 80, startedAt: Double(i))
            try FlowDAO.insert(db: db, record: r)
        }
        let httpOnly = try FlowDAO.query(db: db, protocolFilter: "HTTP")
        XCTAssertEqual(httpOnly.count, 5)
    }

    func testQueryWithHostFilter() throws {
        for i in 0..<5 {
            var r = FlowRecord(flowId: "f_\(i)", protocolName: "HTTP",
                               host: i < 3 ? "api.example.com" : "cdn.other.com", port: 80, startedAt: Double(i))
            try FlowDAO.insert(db: db, record: r)
        }
        let filtered = try FlowDAO.query(db: db, hostContains: "example")
        XCTAssertEqual(filtered.count, 3)
    }

    func testQueryPagination() throws {
        for i in 0..<20 {
            var r = FlowRecord(flowId: "f_\(String(format: "%04d", i))", protocolName: "HTTP",
                               host: "host.com", port: 80, startedAt: Double(i))
            try FlowDAO.insert(db: db, record: r)
        }
        let page1 = try FlowDAO.query(db: db, offset: 0, limit: 5)
        XCTAssertEqual(page1.count, 5)
        let page2 = try FlowDAO.query(db: db, offset: 5, limit: 5)
        XCTAssertEqual(page2.count, 5)
        // Results ordered by started_at DESC
        XCTAssertTrue(page1[0].startedAt > page1[4].startedAt)
    }

    func testFindNonExistent() throws {
        let found = try FlowDAO.find(db: db, flowId: "nonexistent")
        XCTAssertNil(found)
    }
}
