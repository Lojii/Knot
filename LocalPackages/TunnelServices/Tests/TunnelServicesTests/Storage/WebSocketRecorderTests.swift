import XCTest
import KnotStorage
import SQLite
@testable import TunnelServices

final class WebSocketRecorderTests: XCTestCase {
    var helper: StorageTestHelper!
    var dbGroup: TaskDatabaseGroup!

    override func setUp() {
        helper = StorageTestHelper()
        dbGroup = try! TaskDatabaseGroup(taskId: 1, rootPath: helper.tempDir)
    }

    override func tearDown() {
        dbGroup = nil
        helper = nil
    }

    // MARK: - Helpers

    private func makeRecorder(flowId: String = "ws_0001", host: String = "chat.example.com",
                               port: Int = 443, isSecure: Bool = true,
                               uri: String = "/chat") -> WebSocketRecorder {
        WebSocketRecorder(flowId: flowId, host: host, port: port, isSecure: isSecure,
                          uri: uri, dbGroup: dbGroup)
    }

    // MARK: - Tests

    func testBuildFlowRecord() {
        let recorder = makeRecorder(flowId: "ws_0001", host: "chat.example.com",
                                    port: 443, isSecure: true, uri: "/chat")
        recorder.recordUpgradeHeaders(
            reqHeaders: [("Sec-WebSocket-Protocol", "chat")],
            rspHeaders: [("Sec-WebSocket-Protocol", "chat")]
        )
        recorder.recordFrame(direction: 0, opcode: "text",
                             payload: Data("hello".utf8), timestamp: 1000.0)
        recorder.recordFrame(direction: 1, opcode: "text",
                             payload: Data("world".utf8), timestamp: 1001.0)
        recorder.recordClosed(closeCode: 1000)

        let record = recorder.buildFlowRecord()

        // Protocol name should be WSS for secure
        XCTAssertEqual(record.protocolName, "WSS")
        XCTAssertEqual(record.host, "chat.example.com")
        XCTAssertEqual(record.port, 443)

        // Search keys
        XCTAssertEqual(record.searchKey1, "chat")       // subprotocol
        XCTAssertEqual(record.searchKey2, "/chat")      // uri
        XCTAssertEqual(record.searchKey3, "2")          // totalFrames (1 out + 1 in)
        XCTAssertEqual(record.searchKey4, "1000")       // closeCode

        // Summary contains protocol name and URI
        XCTAssertTrue(record.summary.contains("WSS"))
        XCTAssertTrue(record.summary.contains("/chat"))
        XCTAssertTrue(record.summary.contains("2 frames"))

        XCTAssertEqual(record.status, .completed)
        XCTAssertNotNil(record.endedAt)
    }

    func testBuildFlowRecordInsecure() {
        let recorder = makeRecorder(flowId: "ws_0002", host: "ws.example.com",
                                    port: 80, isSecure: false, uri: "/stream")
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "WS")
    }

    func testSearchKeyMapping() {
        let mapping = WebSocketRecorder.searchKeyMapping
        XCTAssertEqual(mapping.key1, "subprotocol")
        XCTAssertEqual(mapping.key2, "uri")
        XCTAssertEqual(mapping.key3, "totalFrames")
        XCTAssertEqual(mapping.key4, "closeCode")
    }

    func testPreliminaryFlowInserted() throws {
        // After init, a preliminary flow with status=inProgress should be in protocol.db
        let recorder = makeRecorder(flowId: "ws_0003")

        // Drain the protoWriteQueue to ensure the async insert has completed
        dbGroup.protoWriteQueue.sync {}

        let found = try FlowDAO.find(db: dbGroup.proto, flowId: "ws_0003")
        XCTAssertNotNil(found, "Preliminary flow should be inserted on init")
        XCTAssertEqual(found?.status, .inProgress)
        XCTAssertEqual(found?.protocolName, "WSS")
        XCTAssertEqual(found?.host, "chat.example.com")

        // Silence unused-variable warning
        _ = recorder
    }

    func testClosedUpdatesFlow() throws {
        let recorder = makeRecorder(flowId: "ws_0004")

        // Drain preliminary insert
        dbGroup.protoWriteQueue.sync {}

        recorder.recordClosed(closeCode: 1001)

        // Drain update
        dbGroup.protoWriteQueue.sync {}

        let found = try FlowDAO.find(db: dbGroup.proto, flowId: "ws_0004")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.status, .completed)
        XCTAssertNotNil(found?.endedAt)
    }

    func testFramesWrittenToDecodedDB() throws {
        let recorder = makeRecorder(flowId: "ws_0005")

        let textData = Data("Hello WebSocket".utf8)
        recorder.recordFrame(direction: 0, opcode: "text", payload: textData, timestamp: 2000.0)
        recorder.recordFrame(direction: 1, opcode: "text",
                             payload: Data("Response frame".utf8), timestamp: 2001.0)
        recorder.recordFrame(direction: 0, opcode: "binary",
                             payload: Data([0x01, 0x02, 0x03]), timestamp: 2002.0)

        // Drain the decodedWriteQueue
        dbGroup.decodedWriteQueue.sync {}

        let entries = try DecodedEntryDAO.findAll(db: dbGroup.decoded, flowId: "ws_0005", limit: 10)
        XCTAssertEqual(entries.count, 3, "All 3 frames should be written to decoded.db")

        // Verify frame directions
        let clientFrames = entries.filter { $0.direction == 0 }
        let serverFrames = entries.filter { $0.direction == 1 }
        XCTAssertEqual(clientFrames.count, 2)
        XCTAssertEqual(serverFrames.count, 1)

        // Verify text frame has search_text
        let textFrame = entries.first { $0.decodedType == "text" && $0.direction == 0 }
        XCTAssertNotNil(textFrame)
        XCTAssertEqual(textFrame?.searchText, "Hello WebSocket")
        XCTAssertTrue(textFrame?.isInline == true)

        // Verify binary frame
        let binaryFrame = entries.first { $0.decodedType == "binary" }
        XCTAssertNotNil(binaryFrame)
        XCTAssertTrue(binaryFrame?.isInline == true)
    }

    func testControlFramesStoredWithoutPayload() throws {
        let recorder = makeRecorder(flowId: "ws_0006")

        recorder.recordFrame(direction: 0, opcode: "ping", payload: Data([0x00]), timestamp: 3000.0)
        recorder.recordFrame(direction: 1, opcode: "pong", payload: Data([0x00]), timestamp: 3001.0)
        recorder.recordFrame(direction: 0, opcode: "close", payload: nil, timestamp: 3002.0)

        dbGroup.decodedWriteQueue.sync {}

        let entries = try DecodedEntryDAO.findAll(db: dbGroup.decoded, flowId: "ws_0006", limit: 10)
        XCTAssertEqual(entries.count, 3)

        // All control frames should have no inline data and no search text
        for entry in entries {
            XCTAssertFalse(entry.isInline, "Control frames should not store inline payload")
            XCTAssertNil(entry.searchText, "Control frames should not have search text")
        }

        // Verify opcode names
        let types = entries.map { $0.decodedType }
        XCTAssertTrue(types.contains("ping"))
        XCTAssertTrue(types.contains("pong"))
        XCTAssertTrue(types.contains("close"))
    }

    func testTrafficCounters() {
        let recorder = makeRecorder(flowId: "ws_0007")

        recorder.recordFrame(direction: 0, opcode: "text",
                             payload: Data(repeating: 0x41, count: 100), timestamp: 4000.0)
        recorder.recordFrame(direction: 0, opcode: "binary",
                             payload: Data(repeating: 0x00, count: 200), timestamp: 4001.0)
        recorder.recordFrame(direction: 1, opcode: "text",
                             payload: Data(repeating: 0x42, count: 512), timestamp: 4002.0)

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.uploadBytes, 300)
        XCTAssertEqual(record.downloadBytes, 512)
        XCTAssertEqual(record.searchKey3, "3") // totalFrames
    }

    func testSequenceCountersPerDirection() throws {
        let recorder = makeRecorder(flowId: "ws_0008")

        recorder.recordFrame(direction: 0, opcode: "text", payload: Data("a".utf8), timestamp: 5000.0)
        recorder.recordFrame(direction: 0, opcode: "text", payload: Data("b".utf8), timestamp: 5001.0)
        recorder.recordFrame(direction: 1, opcode: "text", payload: Data("x".utf8), timestamp: 5002.0)
        recorder.recordFrame(direction: 0, opcode: "text", payload: Data("c".utf8), timestamp: 5003.0)

        dbGroup.decodedWriteQueue.sync {}

        let entries = try DecodedEntryDAO.findAll(db: dbGroup.decoded, flowId: "ws_0008", limit: 10)
        let clientEntries = entries.filter { $0.direction == 0 }.sorted { $0.sequence < $1.sequence }
        let serverEntries = entries.filter { $0.direction == 1 }

        // Client sequences: 0, 1, 2
        XCTAssertEqual(clientEntries.count, 3)
        XCTAssertEqual(clientEntries[0].sequence, 0)
        XCTAssertEqual(clientEntries[1].sequence, 1)
        XCTAssertEqual(clientEntries[2].sequence, 2)

        // Server sequence: 0
        XCTAssertEqual(serverEntries.count, 1)
        XCTAssertEqual(serverEntries[0].sequence, 0)
    }
}
