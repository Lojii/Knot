import XCTest
import SQLite
@testable import TunnelServices

final class QuicDAOIntegrationTests: XCTestCase {
    var db: Connection!

    override func setUp() {
        db = try! Connection(.inMemory)
        try! ConnectionSchema.create(db)
    }

    override func tearDown() {
        db = nil
    }

    // MARK: - QuicConnectionDAO

    func testInsertAndFindConnection() throws {
        let record = QuicConnectionRecord(
            flowId: "quic_101", srcIp: "10.0.0.5", srcPort: 54321,
            dstIp: "93.184.216.34", dstPort: 443, startedAt: 2000.0,
            state: "handshaking", version: "1", dcid: "aabb1122",
            scid: "ccdd3344", alpn: "h3", tlsCipher: "AES_128_GCM",
            tlsSni: "example.com", serverCert: "CERT_PEM",
            is0rtt: false, packetsIn: 10, packetsOut: 5,
            bytesIn: 4096, bytesOut: 2048, streamsCount: 2
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        let found = try QuicConnectionDAO.find(db: db, flowId: "quic_101")
        XCTAssertNotNil(found)
        XCTAssertEqual(found!.flowId, "quic_101")
        XCTAssertEqual(found!.srcIp, "10.0.0.5")
        XCTAssertEqual(found!.srcPort, 54321)
        XCTAssertEqual(found!.dstIp, "93.184.216.34")
        XCTAssertEqual(found!.dstPort, 443)
        XCTAssertEqual(found!.state, "handshaking")
        XCTAssertEqual(found!.version, "1")
        XCTAssertEqual(found!.dcid, "aabb1122")
        XCTAssertEqual(found!.scid, "ccdd3344")
        XCTAssertEqual(found!.alpn, "h3")
        XCTAssertEqual(found!.tlsCipher, "AES_128_GCM")
        XCTAssertEqual(found!.tlsSni, "example.com")
        XCTAssertEqual(found!.serverCert, "CERT_PEM")
        XCTAssertEqual(found!.is0rtt, false)
        XCTAssertEqual(found!.packetsIn, 10)
        XCTAssertEqual(found!.packetsOut, 5)
        XCTAssertEqual(found!.bytesIn, 4096)
        XCTAssertEqual(found!.bytesOut, 2048)
        XCTAssertEqual(found!.streamsCount, 2)
    }

    func testUpdateConnectionState() throws {
        var record = QuicConnectionRecord(
            flowId: "quic_102", srcIp: "10.0.0.1", srcPort: 12345,
            dstIp: "10.0.0.2", dstPort: 443, startedAt: 1000.0
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        record.state = "established"
        record.establishedAt = 1005.0
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        let found = try QuicConnectionDAO.find(db: db, flowId: "quic_102")
        XCTAssertNotNil(found)
        XCTAssertEqual(found!.state, "established")
    }

    func testIs0RTT() throws {
        let record = QuicConnectionRecord(
            flowId: "quic_103", srcIp: "10.0.0.1", srcPort: 12345,
            dstIp: "10.0.0.2", dstPort: 443, startedAt: 1000.0, is0rtt: true
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        let found = try QuicConnectionDAO.find(db: db, flowId: "quic_103")
        XCTAssertNotNil(found)
        XCTAssertTrue(found!.is0rtt)
    }

    func testFindNotFound() throws {
        let found = try QuicConnectionDAO.find(db: db, flowId: "nonexistent")
        XCTAssertNil(found)
    }

    // MARK: - QuicStreamDAO

    func testInsertAndFindStream() throws {
        let stream = QuicStreamRecord(
            connectionId: "quic_201", streamId: 0, startedAt: 1000.0,
            streamType: "bidi", state: "open", protocolFlowId: "h3_001",
            bytesIn: 512, bytesOut: 256
        )
        try QuicStreamDAO.insert(db: db, record: stream)

        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic_201")
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].connectionId, "quic_201")
        XCTAssertEqual(streams[0].streamId, 0)
        XCTAssertEqual(streams[0].streamType, "bidi")
        XCTAssertEqual(streams[0].protocolFlowId, "h3_001")
        XCTAssertEqual(streams[0].bytesIn, 512)
        XCTAssertEqual(streams[0].bytesOut, 256)
    }

    func testConnectionWithMultipleStreams() throws {
        for i in 0..<3 {
            let stream = QuicStreamRecord(
                connectionId: "quic_301", streamId: i * 4, startedAt: 1000.0 + Double(i),
                streamType: "bidi"
            )
            try QuicStreamDAO.insert(db: db, record: stream)
        }

        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic_301")
        XCTAssertEqual(streams.count, 3)
    }

    func testStreamUpdateProtocolFlowId() throws {
        let stream = QuicStreamRecord(
            connectionId: "quic_401", streamId: 0, startedAt: 1000.0
        )
        try QuicStreamDAO.insert(db: db, record: stream)

        try QuicStreamDAO.updateProtocolFlowId(
            db: db, connectionId: "quic_401", streamId: 0, protocolFlowId: "h3_updated"
        )

        let found = try QuicStreamDAO.findByProtocolFlowId(db: db, protocolFlowId: "h3_updated")
        XCTAssertNotNil(found)
        XCTAssertEqual(found!.connectionId, "quic_401")
        XCTAssertEqual(found!.streamId, 0)
        XCTAssertEqual(found!.protocolFlowId, "h3_updated")
    }

    func testStreamFindByProtocolFlowId() throws {
        let stream = QuicStreamRecord(
            connectionId: "quic_501", streamId: 4, startedAt: 1000.0,
            protocolFlowId: "h3_findme"
        )
        try QuicStreamDAO.insert(db: db, record: stream)

        let found = try QuicStreamDAO.findByProtocolFlowId(db: db, protocolFlowId: "h3_findme")
        XCTAssertNotNil(found)
        XCTAssertEqual(found!.connectionId, "quic_501")
        XCTAssertEqual(found!.streamId, 4)
    }
}
