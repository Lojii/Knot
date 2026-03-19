import XCTest
import NIOCore
@testable import TunnelServices

final class PayloadDecoderTests: XCTestCase {
    var helper: StorageTestHelper!
    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testDecodeIdentity() throws {
        let rawPath = "\(helper.tempDir)/raw.bin"
        let decodedPath = "\(helper.tempDir)/decoded.bin"
        let original = "Hello, World! This is a test payload."
        try Data(original.utf8).write(to: URL(fileURLWithPath: rawPath))

        let result = try PayloadDecoder.decode(rawPath: rawPath, decodedPath: decodedPath, encoding: "identity")
        XCTAssertEqual(result.decodedSize, Int64(original.utf8.count))
        XCTAssertEqual(result.searchText, original)

        let decoded = try Data(contentsOf: URL(fileURLWithPath: decodedPath))
        XCTAssertEqual(String(data: decoded, encoding: .utf8), original)
    }

    func testDecodeDeflate() throws {
        let rawPath = "\(helper.tempDir)/raw.deflate"
        let decodedPath = "\(helper.tempDir)/decoded.txt"
        let original = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 20)

        // Compress using zlib (deflate)
        let sourceData = Data(original.utf8)
        let compressed = try sourceData.compressed()
        try compressed.write(to: URL(fileURLWithPath: rawPath))

        let result = try PayloadDecoder.decode(rawPath: rawPath, decodedPath: decodedPath, encoding: "deflate")
        XCTAssertEqual(result.searchText, original)
        XCTAssertEqual(result.decodedSize, Int64(original.utf8.count))
    }

    func testDecodeLargeFile() throws {
        let rawPath = "\(helper.tempDir)/large_raw.bin"
        let decodedPath = "\(helper.tempDir)/large_decoded.bin"
        // Write a 500KB uncompressed file
        let chunk = Data(repeating: 0x41, count: 1024) // 'A'
        let writer = try PayloadWriter(directory: helper.tempDir, fileName: "large_raw.bin")
        for _ in 0..<500 { try writer.append(chunk) }
        try writer.close()

        let result = try PayloadDecoder.decode(rawPath: rawPath, decodedPath: decodedPath, encoding: "identity", chunkSize: 8192)
        XCTAssertEqual(result.decodedSize, 512000)
    }

    func testDecodeSynchronously() throws {
        let original = "Sync decode test data"
        let data = Data(original.utf8)
        let decoded = try PayloadDecoder.decodeSynchronously(data: data, encoding: "identity")
        XCTAssertEqual(String(data: decoded, encoding: .utf8), original)
    }

    func testTextAccumulatorMaxSizeRespected() throws {
        let rawPath = "\(helper.tempDir)/big_text.bin"
        let decodedPath = "\(helper.tempDir)/big_decoded.bin"
        // Write 200KB of text
        let text = String(repeating: "A", count: 200 * 1024)
        try Data(text.utf8).write(to: URL(fileURLWithPath: rawPath))

        let result = try PayloadDecoder.decode(rawPath: rawPath, decodedPath: decodedPath, encoding: "identity")
        // searchText should be truncated to ~100KB (TextAccumulator default maxSize)
        XCTAssertNotNil(result.searchText)
        XCTAssertLessThanOrEqual(result.searchText!.count, 100 * 1024)
        // But decoded file should have full content
        XCTAssertEqual(result.decodedSize, Int64(200 * 1024))
    }
}
