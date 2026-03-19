import XCTest
import NIOCore
import NIOPosix
import SQLite
@testable import TunnelServices

final class DecodeSchedulerTests: XCTestCase {
    var helper: StorageTestHelper!

    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testAsyncDecodeProcessesQueue() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        let group = try mgr.openTask(1)
        let scheduler = DecodeScheduler(dbGroup: group, rootPath: helper.tempDir)

        // Insert a flow with a raw payload
        var record = FlowRecord(flowId: "test_0001", protocolName: "HTTP", host: "test.com", port: 80, startedAt: 1000)
        record.rspPayloadRef = "test_0001_rsp.bin"
        record.metadata = ["rspEncoding": "identity"]
        try FlowDAO.insert(db: group.proto, record: record)

        // Write raw payload file
        let rawDir = "\(helper.tempDir)/tasks/1/payloads/raw"
        try Data("decoded content".utf8).write(to: URL(fileURLWithPath: "\(rawDir)/test_0001_rsp.bin"))

        // Enqueue and wait
        scheduler.enqueueAsync(flowId: "test_0001")

        let expectation = expectation(description: "decode")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { expectation.fulfill() }
        wait(for: [expectation], timeout: 3.0)

        // Allow decodedWriteQueue to flush before querying
        let flushExpectation = self.expectation(description: "flush")
        group.decodedWriteQueue.async { flushExpectation.fulfill() }
        wait(for: [flushExpectation], timeout: 3.0)

        // Verify decoded entry was created
        let entry = try DecodedEntryDAO.find(db: group.decoded, flowId: "test_0001", direction: 1)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.searchText, "decoded content")

        mgr.closeTask(1)
    }

    func testSyncDecode() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        let group = try mgr.openTask(2)
        let scheduler = DecodeScheduler(dbGroup: group, rootPath: helper.tempDir)
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? elg.syncShutdownGracefully() }

        // Setup flow and raw payload
        var record = FlowRecord(flowId: "sync_0001", protocolName: "HTTP", host: "test.com", port: 80, startedAt: 1000)
        record.rspPayloadRef = "sync_0001_rsp.bin"
        try FlowDAO.insert(db: group.proto, record: record)
        let rawDir = "\(helper.tempDir)/tasks/2/payloads/raw"
        try Data("sync payload".utf8).write(to: URL(fileURLWithPath: "\(rawDir)/sync_0001_rsp.bin"))

        // Sync decode via EventLoopFuture
        let future = scheduler.decodeSynchronously(flowId: "sync_0001", eventLoop: elg.next())
        let result = try future.wait()
        XCTAssertNotNil(result.response)
        XCTAssertEqual(result.response?.searchText, "sync payload")

        mgr.closeTask(2)
    }

    func testAsyncDecodeMultipleFlowsFIFO() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        let group = try mgr.openTask(3)
        let scheduler = DecodeScheduler(dbGroup: group, rootPath: helper.tempDir)
        let rawDir = "\(helper.tempDir)/tasks/3/payloads/raw"

        // Insert 3 flows
        for i in 1...3 {
            var record = FlowRecord(flowId: "fifo_000\(i)", protocolName: "HTTP", host: "test.com", port: 80, startedAt: Double(i))
            record.rspPayloadRef = "fifo_000\(i)_rsp.bin"
            record.metadata = ["rspEncoding": "identity"]
            try FlowDAO.insert(db: group.proto, record: record)
            try Data("content \(i)".utf8).write(to: URL(fileURLWithPath: "\(rawDir)/fifo_000\(i)_rsp.bin"))
            scheduler.enqueueAsync(flowId: "fifo_000\(i)")
        }

        // Wait for all to process
        let expectation = expectation(description: "fifo_decode")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)

        // Flush decodedWriteQueue
        let flushExpectation = self.expectation(description: "flush")
        group.decodedWriteQueue.async { flushExpectation.fulfill() }
        wait(for: [flushExpectation], timeout: 3.0)

        // All 3 entries should be decoded
        for i in 1...3 {
            let entry = try DecodedEntryDAO.find(db: group.decoded, flowId: "fifo_000\(i)", direction: 1)
            XCTAssertNotNil(entry, "Expected entry for fifo_000\(i)")
            XCTAssertEqual(entry?.searchText, "content \(i)")
        }

        mgr.closeTask(3)
    }

    func testSyncDecodeFlowNotFound() throws {
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        let group = try mgr.openTask(4)
        let scheduler = DecodeScheduler(dbGroup: group, rootPath: helper.tempDir)
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? elg.syncShutdownGracefully() }

        // Decode a non-existent flowId — should succeed with empty DecodedPayload
        let future = scheduler.decodeSynchronously(flowId: "nonexistent_flow", eventLoop: elg.next())
        let result = try future.wait()
        XCTAssertNil(result.request)
        XCTAssertNil(result.response)

        mgr.closeTask(4)
    }
}
