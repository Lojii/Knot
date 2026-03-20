import XCTest
import NIO
@testable import TunnelServices

final class HTTP1PluginTests: XCTestCase {

    private let plugin = HTTP1Plugin()
    private let allocator = ByteBufferAllocator()
    private var context: MatchContext { MatchContext(localPort: 8080) }

    // MARK: - Positive matches

    func testMatchesGET() {
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("GET /index.html HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 90))
    }

    func testMatchesPOST() {
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("POST /api/data HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 90))
    }

    func testMatchesPUT() {
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("PUT /resource HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 90))
    }

    func testMatchesHEAD() {
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("HEAD / HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 90))
    }

    func testMatchesCONNECT() {
        var buf = allocator.buffer(capacity: 32)
        buf.writeString("CONNECT example.com:443 HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 90))
    }

    func testMatchesOPTIONS() {
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("OPTIONS * HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 90))
    }

    func testMatchesDELETE() {
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("DELE /res HTTP/1.1\r\n")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 90))
    }

    // MARK: - Negative matches

    func testDoesNotMatchTLS() {
        // TLS ClientHello starts with content type 0x16
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x16, 0x03, 0x01, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    func testDoesNotMatchSOCKS5() {
        // SOCKS5 handshake starts with version byte 0x05
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x05, 0x01, 0x00, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    func testDoesNotMatchRandomBytes() {
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0xFF, 0xFE, 0xFD, 0xFC])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    // MARK: - Insufficient data

    func testNeedMoreDataWithFewerThan4Bytes() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x47, 0x45, 0x54]) // "GET" — only 3 bytes
        XCTAssertEqual(plugin.canMatch(buf, context: context), .needMoreData(minimum: 4))
    }

    func testNeedMoreDataWithEmptyBuffer() {
        let buf = allocator.buffer(capacity: 0)
        XCTAssertEqual(plugin.canMatch(buf, context: context), .needMoreData(minimum: 4))
    }

    // MARK: - Plugin identity

    func testPluginId() {
        XCTAssertEqual(plugin.id, "http1")
    }

    func testPluginDisplayName() {
        XCTAssertEqual(plugin.displayName, "HTTP/1.x")
    }
}
