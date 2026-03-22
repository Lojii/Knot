import XCTest
import NIO
@testable import TunnelServices

final class SOCKS5PluginTests: XCTestCase {

    private let plugin = SOCKS5Plugin()
    private let allocator = ByteBufferAllocator()
    private var context: MatchContext { MatchContext(localPort: 1080) }

    // MARK: - Positive matches

    func testMatchesSOCKS5Greeting() {
        // Standard SOCKS5 greeting: version=0x05, 1 method (no-auth=0x00)
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x05, 0x01, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 95))
    }

    func testMatchesSOCKS5WithMultipleMethods() {
        // SOCKS5 greeting: version=0x05, 2 methods (no-auth=0x00, username/password=0x02)
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x05, 0x02, 0x00, 0x02])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .yes(confidence: 95))
    }

    // MARK: - Negative matches

    func testDoesNotMatchHTTP() {
        // Plain HTTP GET request
        var buf = allocator.buffer(capacity: 16)
        buf.writeString("GET ")
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    func testDoesNotMatchTLS() {
        // TLS ClientHello: content-type=0x16, version 0x03 0x01
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x16, 0x03, 0x01, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .no)
    }

    // MARK: - Insufficient data

    func testNeedMoreData() {
        // Only 1 byte — need at least 2 (version + method count)
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x05])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .needMoreData(minimum: 2))
    }

    func testIncompleteGreetingNeedsMoreData() {
        // Claims 2 methods but only 1 method byte present → need 4 bytes total
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x05, 0x02, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: context), .needMoreData(minimum: 4))
    }
}
