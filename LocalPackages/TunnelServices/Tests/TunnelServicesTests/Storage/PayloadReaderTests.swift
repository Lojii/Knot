import XCTest
@testable import TunnelServices

final class PayloadReaderTests: XCTestCase {
    var helper: StorageTestHelper!
    var testFilePath: String!

    override func setUp() {
        helper = StorageTestHelper()
        testFilePath = "\(helper.tempDir)/test_read.bin"
        // Write a known 256-byte file: 0x00, 0x01, ..., 0xFF
        var data = Data()
        for i: UInt8 in 0...255 { data.append(i) }
        FileManager.default.createFile(atPath: testFilePath, contents: data)
    }
    override func tearDown() { helper = nil }

    func testSize() throws {
        let reader = try PayloadReader(filePath: testFilePath)
        XCTAssertEqual(reader.size, 256)
        reader.close()
    }

    func testRangeRead() throws {
        let reader = try PayloadReader(filePath: testFilePath)
        let chunk = reader.read(offset: 10, length: 5)
        XCTAssertEqual(chunk, Data([10, 11, 12, 13, 14]))
        reader.close()
    }

    func testRangeReadBeyondEnd() throws {
        let reader = try PayloadReader(filePath: testFilePath)
        let chunk = reader.read(offset: 250, length: 100)
        XCTAssertEqual(chunk.count, 6) // only 6 bytes left (250...255)
        reader.close()
    }

    func testChunksIteration() throws {
        let reader = try PayloadReader(filePath: testFilePath, chunkSize: 100)
        var totalBytes = 0
        var chunkCount = 0
        for chunk in reader.chunks() {
            totalBytes += chunk.count
            chunkCount += 1
        }
        XCTAssertEqual(totalBytes, 256)
        XCTAssertEqual(chunkCount, 3) // 100 + 100 + 56
        reader.close()
    }

    func testChunksExactMultiple() throws {
        // Create a 200-byte file
        let path = "\(helper.tempDir)/exact.bin"
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0xAA, count: 200))
        let reader = try PayloadReader(filePath: path, chunkSize: 100)
        var chunkCount = 0
        for _ in reader.chunks() { chunkCount += 1 }
        XCTAssertEqual(chunkCount, 2)
        reader.close()
    }

    func testEmptyFile() throws {
        let path = "\(helper.tempDir)/empty.bin"
        FileManager.default.createFile(atPath: path, contents: Data())
        let reader = try PayloadReader(filePath: path)
        XCTAssertEqual(reader.size, 0)
        var count = 0
        for _ in reader.chunks() { count += 1 }
        XCTAssertEqual(count, 0)
        reader.close()
    }
}
