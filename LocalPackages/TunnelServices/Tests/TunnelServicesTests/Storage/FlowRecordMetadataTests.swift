import XCTest
import SQLite
@testable import TunnelServices

final class FlowRecordMetadataTests: XCTestCase {
    private var db: Connection!

    override func setUp() {
        super.setUp()
        db = try! Connection(.inMemory)
        try! ProtocolSchema.create(db)
        try! ProtocolSchema.migrateIfNeeded(db)
    }

    func testInsertAndReadNewColumns() throws {
        var record = FlowRecord(
            flowId: "test-1", protocolName: "HTTP",
            host: "example.com", port: 443,
            startedAt: Date().timeIntervalSince1970
        )
        record.connReuse = 2
        record.protoFlags = 0x0001 | 0x0040 | 0x0100
        record.pushStatus = nil
        record.certChainRef = "certs/test-1.pem"
        record.status = .completed

        try FlowDAO.insert(db: db, record: record)

        let found = try FlowDAO.find(db: db, flowId: "test-1")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.connReuse, 2)
        XCTAssertEqual(found?.protoFlags, 0x0001 | 0x0040 | 0x0100)
        XCTAssertNil(found?.pushStatus)
        XCTAssertEqual(found?.certChainRef, "certs/test-1.pem")
    }

    func testPushStatusRoundTrip() throws {
        var record = FlowRecord(
            flowId: "push-1", protocolName: "HTTP",
            host: "example.com", port: 443,
            startedAt: Date().timeIntervalSince1970
        )
        record.pushStatus = 1
        record.status = .completed

        try FlowDAO.insert(db: db, record: record)
        let found = try FlowDAO.find(db: db, flowId: "push-1")
        XCTAssertEqual(found?.pushStatus, 1)
    }

    func testAggregateQuery() throws {
        for (i, reuse) in [0, 1, 2].enumerated() {
            var r = FlowRecord(
                flowId: "agg-\(i)", protocolName: "HTTP",
                host: "example.com", port: 443,
                startedAt: Date().timeIntervalSince1970
            )
            r.connReuse = reuse
            r.status = .completed
            try FlowDAO.insert(db: db, record: r)
        }

        let rows = try db.prepare("SELECT conn_reuse, COUNT(*) as cnt FROM flow GROUP BY conn_reuse ORDER BY conn_reuse")
        var results = [(Int, Int)]()
        for row in rows {
            results.append((Int(row[0] as! Int64), Int(row[1] as! Int64)))
        }
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].0, 0); XCTAssertEqual(results[0].1, 1)
        XCTAssertEqual(results[1].0, 1); XCTAssertEqual(results[1].1, 1)
        XCTAssertEqual(results[2].0, 2); XCTAssertEqual(results[2].1, 1)
    }
}
