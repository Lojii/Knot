import XCTest
import KnotStorage
import NIOCore
@testable import TunnelServices

final class PayloadWriterTests: XCTestCase {
    var helper: StorageTestHelper!
    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testWriteAndReadBack() throws {
        let writer = try PayloadWriter(directory: helper.tempDir, fileName: "test.bin")
        let testData = Data(repeating: 0xAB, count: 1024)
        try writer.append(testData)
        try writer.close()

        let readBack = try Data(contentsOf: URL(fileURLWithPath: "\(helper.tempDir)/test.bin"))
        XCTAssertEqual(readBack, testData)
        XCTAssertEqual(writer.totalBytesWritten, 1024)
    }

    func testBufferingFlushesAtThreshold() throws {
        // Use small threshold to test buffering behavior
        let writer = try PayloadWriter(directory: helper.tempDir, fileName: "test.bin", flushThreshold: 100)

        // Write 50 bytes — should be buffered only
        try writer.append(Data(repeating: 0x01, count: 50))
        let fileURL = URL(fileURLWithPath: "\(helper.tempDir)/test.bin")
        let size1 = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as! UInt64
        XCTAssertEqual(size1, 0, "Data should still be in buffer")

        // Write 60 more — total 110 exceeds threshold, should auto-flush
        try writer.append(Data(repeating: 0x02, count: 60))
        let size2 = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as! UInt64
        XCTAssertEqual(size2, 110, "Buffer should have flushed to disk")

        try writer.close()
    }

    func testCloseFlushesRemainingBuffer() throws {
        let writer = try PayloadWriter(directory: helper.tempDir, fileName: "test.bin", flushThreshold: 1024)
        try writer.append(Data(repeating: 0xFF, count: 10))
        try writer.close()
        let size = try FileManager.default.attributesOfItem(atPath: "\(helper.tempDir)/test.bin")[.size] as! UInt64
        XCTAssertEqual(size, 10)
    }

    func testLargeWriteMultipleChunks() throws {
        let writer = try PayloadWriter(directory: helper.tempDir, fileName: "large.bin")
        let chunk = Data(repeating: 0xCD, count: 8192)
        for _ in 0..<100 { try writer.append(chunk) } // 800KB total
        try writer.close()
        XCTAssertEqual(writer.totalBytesWritten, 819200)
        let fileSize = try FileManager.default.attributesOfItem(atPath: "\(helper.tempDir)/large.bin")[.size] as! UInt64
        XCTAssertEqual(fileSize, 819200)
    }

    func testAppendByteBuffer() throws {
        let writer = try PayloadWriter(directory: helper.tempDir, fileName: "nio.bin")
        var buf = ByteBufferAllocator().buffer(capacity: 256)
        buf.writeBytes([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        try writer.append(Data(buf.readableBytesView))
        try writer.close()
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(helper.tempDir)/nio.bin"))
        XCTAssertEqual(String(data: data, encoding: .utf8), "Hello")
    }
}
