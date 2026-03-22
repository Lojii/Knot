import XCTest
@testable import KnotStorage

final class StorageWriterTests: XCTestCase {

    private var tempDir: String!
    private var manager: DatabaseManager!
    private var group: TaskDatabaseGroup!

    override func setUpWithError() throws {
        tempDir = NSTemporaryDirectory() + "KnotStorageTests_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        manager = DatabaseManager(rootPath: tempDir)
        let taskId = try CatalogDAO.insertTask(db: manager.catalogDB, name: "Test", createdAt: Date().timeIntervalSince1970)
        group = try manager.openTask(taskId)
    }

    override func tearDownWithError() throws {
        if let taskId = group?.taskId {
            manager.closeTask(taskId)
        }
        if let dir = tempDir, FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    // MARK: - Tests

    func testFlowIdIsGenerated() {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)
        XCTAssertFalse(writer.flowId.isEmpty, "flowId should be non-empty")
        XCTAssertTrue(writer.flowId.contains("_"), "flowId should contain underscore separator")
    }

    func testWriteRequestBodyCreatesFile() throws {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)
        let testData = Data("Hello, request!".utf8)

        writer.writeRequestBody(testData)
        writer.close()

        let ref = writer.reqPayloadRef
        XCTAssertFalse(ref.isEmpty, "reqPayloadRef should be set after writing data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ref), "Payload file should exist on disk")

        let contents = try Data(contentsOf: URL(fileURLWithPath: ref))
        XCTAssertEqual(contents, testData)
    }

    func testWriteResponseBodyCreatesFile() throws {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)
        let testData = Data("Hello, response!".utf8)

        writer.writeResponseBody(testData)
        writer.close()

        let ref = writer.rspPayloadRef
        XCTAssertFalse(ref.isEmpty, "rspPayloadRef should be set after writing data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ref), "Payload file should exist on disk")

        let contents = try Data(contentsOf: URL(fileURLWithPath: ref))
        XCTAssertEqual(contents, testData)
    }

    func testEmptyDataIsIgnored() {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)
        writer.writeRequestBody(Data())
        writer.close()
        XCTAssertEqual(writer.reqPayloadRef, "", "Empty data should not create a file")
    }

    func testInsertAndQueryFlowRecord() throws {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)

        var record = FlowRecord(
            flowId: writer.flowId,
            protocolName: "HTTP",
            host: "example.com",
            port: 443,
            startedAt: Date().timeIntervalSince1970
        )
        record.status = .completed
        record.summary = "GET /index.html"
        record.searchKey1 = "GET"
        record.searchKey2 = "/index.html"

        writer.insertFlow(record)

        // Wait for the async write to complete
        let expectation = XCTestExpectation(description: "Flow inserted")
        group.protoWriteQueue.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        // Query back
        let found = try FlowDAO.find(db: group.proto, flowId: writer.flowId)
        XCTAssertNotNil(found, "Should find the inserted flow record")
        XCTAssertEqual(found?.host, "example.com")
        XCTAssertEqual(found?.protocolName, "HTTP")
        XCTAssertEqual(found?.summary, "GET /index.html")
        XCTAssertEqual(found?.status, .completed)
    }

    func testUpdateFlowRecord() throws {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)

        var record = FlowRecord(
            flowId: writer.flowId,
            protocolName: "HTTP",
            host: "example.com",
            port: 80,
            startedAt: Date().timeIntervalSince1970
        )
        record.status = .inProgress

        writer.insertFlow(record)

        // Wait for insert
        let insertDone = XCTestExpectation(description: "Insert done")
        group.protoWriteQueue.async { insertDone.fulfill() }
        wait(for: [insertDone], timeout: 5.0)

        // Update
        let endTime = Date().timeIntervalSince1970
        writer.updateFlow(writer.flowId, status: .completed, endedAt: endTime)

        let updateDone = XCTestExpectation(description: "Update done")
        group.protoWriteQueue.async { updateDone.fulfill() }
        wait(for: [updateDone], timeout: 5.0)

        let found = try FlowDAO.find(db: group.proto, flowId: writer.flowId)
        XCTAssertEqual(found?.status, .completed)
        XCTAssertNotNil(found?.endedAt)
    }

    func testCloseIsIdempotent() {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)
        writer.writeRequestBody(Data("test".utf8))
        writer.close()
        // Second close should not crash
        writer.close()
    }

    func testMultipleWritesAccumulate() throws {
        let writer = StorageWriter(dbGroup: group, rootPath: tempDir)
        let chunk1 = Data("chunk1".utf8)
        let chunk2 = Data("chunk2".utf8)

        writer.writeRequestBody(chunk1)
        writer.writeRequestBody(chunk2)
        writer.close()

        let ref = writer.reqPayloadRef
        XCTAssertFalse(ref.isEmpty)
        let contents = try Data(contentsOf: URL(fileURLWithPath: ref))
        XCTAssertEqual(contents, chunk1 + chunk2)
    }
}
