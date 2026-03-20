import XCTest
import NIO
@testable import TunnelServices

final class TLSPluginTests: XCTestCase {

    private let plugin = TLSPlugin()
    private let allocator = ByteBufferAllocator()
    private var context: MatchContext { MatchContext(localPort: 8080) }

    // MARK: - Positive matches

    func testMatchesTLSClientHello() {
        // TLS 1.0 ClientHello: content-type=0x16, version 0x03 0x01
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x16, 0x03, 0x01, 0x00, 0xF0])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 100))
    }

    func testMatchesTLS12() {
        // TLS 1.2 ClientHello: content-type=0x16, version 0x03 0x03
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x16, 0x03, 0x03, 0x00, 0x50])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 100))
    }

    func testMatchesSSL30() {
        // SSL 3.0 record: content-type=0x16, version 0x03 0x00
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x16, 0x03, 0x00, 0x00, 0x10])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 100))
    }

    // MARK: - Negative matches

    func testDoesNotMatchHTTP() {
        // Plain HTTP GET request
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("GET /index.html HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    func testDoesNotMatchSOCKS5() {
        // SOCKS5 greeting: version=0x05
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x05, 0x01, 0x00, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    func testDoesNotMatchRandomBytes() {
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0xFF, 0xFE, 0x01, 0x02])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    func testDoesNotMatchHighVersionBytes() {
        // content-type=0x16, but version bytes exceed 0x03
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x16, 0x04, 0x00, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    // MARK: - Insufficient data

    func testNeedMoreDataWithTwoBytes() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x16, 0x03]) // only 2 bytes
        XCTAssertEqual(plugin.canMatch(buf, context: context), .needMoreData(minimum: 3))
    }

    func testNeedMoreDataWithOneByteClientHello() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x16]) // only 1 byte
        XCTAssertEqual(plugin.canMatch(buf, context: context), .needMoreData(minimum: 3))
    }

    func testNeedMoreDataWithEmptyBuffer() {
        let buf = allocator.buffer(capacity: 0)
        XCTAssertEqual(plugin.canMatch(buf, context: context), .needMoreData(minimum: 3))
    }

    // MARK: - Plugin identity

    func testPluginId() {
        XCTAssertEqual(plugin.id, "tls")
    }

    func testPluginDisplayName() {
        XCTAssertEqual(plugin.displayName, "TLS")
    }
}
