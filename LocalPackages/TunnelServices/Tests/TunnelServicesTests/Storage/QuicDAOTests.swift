import XCTest
import SQLite
@testable import TunnelServices

final class QuicDAOTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "connection.db")
        try! ConnectionSchema.create(db)
    }
    override func tearDown() { helper = nil }

    func testInsertAndFindConnection() throws {
        let record = QuicConnectionRecord(
            flowId: "quic_001", srcIp: "192.168.1.1", srcPort: 54321,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0,
            version: "1", dcid: "abcd1234", scid: "5678efgh", alpn: "h3"
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)
        let found = try QuicConnectionDAO.find(db: db, flowId: "quic_001")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.version, "1")
        XCTAssertEqual(found?.alpn, "h3")
    }

    func testUpsertConnection() throws {
        var record = QuicConnectionRecord(
            flowId: "quic_001", srcIp: "192.168.1.1", srcPort: 54321,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)
        record.state = "established"
        record.establishedAt = 1005.0
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)
        let found = try QuicConnectionDAO.find(db: db, flowId: "quic_001")
        XCTAssertEqual(found?.state, "established")
    }

    func testInsertAndFindStream() throws {
        let stream = QuicStreamRecord(
            connectionId: "quic_001", streamId: 0, startedAt: 1000.0,
            streamType: "bidi", protocolFlowId: "h3_001"
        )
        try QuicStreamDAO.insert(db: db, record: stream)
        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic_001")
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].protocolFlowId, "h3_001")
    }

    func testFindStreamByProtocolFlowId() throws {
        let stream = QuicStreamRecord(connectionId: "quic_001", streamId: 4, startedAt: 1000.0, protocolFlowId: "h3_042")
        try QuicStreamDAO.insert(db: db, record: stream)
        let found = try QuicStreamDAO.findByProtocolFlowId(db: db, protocolFlowId: "h3_042")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.streamId, 4)
    }

    func testUpdateProtocolFlowId() throws {
        let stream = QuicStreamRecord(connectionId: "quic_001", streamId: 0, startedAt: 1000.0)
        try QuicStreamDAO.insert(db: db, record: stream)
        try QuicStreamDAO.updateProtocolFlowId(db: db, connectionId: "quic_001", streamId: 0, protocolFlowId: "h3_099")
        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic_001")
        XCTAssertEqual(streams[0].protocolFlowId, "h3_099")
    }
}
