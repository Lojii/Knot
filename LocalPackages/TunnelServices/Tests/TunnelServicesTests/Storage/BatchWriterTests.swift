import XCTest
import KnotStorage
import SQLite
@testable import TunnelServices

final class BatchWriterTests: XCTestCase {
    var helper: StorageTestHelper!
    var db: Connection!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "transport.db")
        try! TransportSchema.create(db)
    }
    override func tearDown() { helper = nil }

    func testBatchFlushOnSize() {
        let queue = DispatchQueue(label: "test.batch")
        let writer = BatchWriter(db: db, queue: queue, batchSize: 5, flushInterval: 10.0)

        for i in 0..<5 {
            writer.enqueue(PacketRow.stub(flowId: "flow_\(i)"))
        }

        // Wait for the serial queue to finish processing
        queue.sync {}

        let count = try! db.scalar("SELECT COUNT(*) FROM packet") as! Int64
        XCTAssertEqual(count, 5)

        writer.finalize()
    }

    func testFinalizeFlushesRemaining() {
        let queue = DispatchQueue(label: "test.batch")
        let writer = BatchWriter(db: db, queue: queue, batchSize: 100, flushInterval: 10.0)

        writer.enqueue(PacketRow.stub(flowId: "flow_1"))
        writer.enqueue(PacketRow.stub(flowId: "flow_2"))

        // Not enough for batch threshold, but finalize should flush
        writer.finalize()

        let count = try! db.scalar("SELECT COUNT(*) FROM packet") as! Int64
        XCTAssertEqual(count, 2)
    }

    func testTimerFlush() {
        let queue = DispatchQueue(label: "test.batch")
        // Large batch size, short timer
        let writer = BatchWriter(db: db, queue: queue, batchSize: 1000, flushInterval: 0.2)

        writer.enqueue(PacketRow.stub(flowId: "flow_1"))

        // Wait for timer to fire
        let expectation = expectation(description: "timer flush")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let count = try! db.scalar("SELECT COUNT(*) FROM packet") as! Int64
        XCTAssertEqual(count, 1)

        writer.finalize()
    }

    func testPacketDAODirectInsert() throws {
        try PacketDAO.insert(db: db, row: PacketRow.stub(flowId: "direct_1"))
        let count = try db.scalar("SELECT COUNT(*) FROM packet") as! Int64
        XCTAssertEqual(count, 1)
    }
}
