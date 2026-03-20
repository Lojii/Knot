import XCTest
import NIO
@testable import TunnelServices

final class ProtocolRegistryTests: XCTestCase {

    // MARK: - testSharedSingletonExists

    func testSharedSingletonExists() {
        let registry = ProtocolRegistry.shared
        XCTAssertNotNil(registry)
        // Verify same instance is returned each time
        XCTAssertTrue(registry === ProtocolRegistry.shared)
    }

    // MARK: - testHasTCPAndUDPRoots

    func testHasTCPAndUDPRoots() {
        let roots = ProtocolRegistry.shared.roots
        XCTAssertEqual(roots.count, 2)

        let ids = roots.map { $0.plugin.id }
        XCTAssertTrue(ids.contains("tcp"), "Expected a TCP root node")
        XCTAssertTrue(ids.contains("udp"), "Expected a UDP root node")

        let displayNames = roots.map { $0.plugin.displayName }
        XCTAssertTrue(displayNames.contains("TCP"))
        XCTAssertTrue(displayNames.contains("UDP"))
    }

    // MARK: - testTCPChildrenAccessor

    func testTCPChildrenAccessor() {
        // Verify accessor returns children without crashing.
        let children = ProtocolRegistry.shared.tcpChildren
        XCTAssertNotNil(children)
        XCTAssertFalse(children.isEmpty)
    }

    // MARK: - testTCPChildrenContainsHTTP1

    func testTCPChildrenContainsHTTP1() {
        let children = ProtocolRegistry.shared.tcpChildren
        let ids = children.map { $0.plugin.id }
        XCTAssertTrue(ids.contains("http1"), "TCP children should include http1")
        XCTAssertTrue(ids.contains("tls"),   "TCP children should include tls")
        XCTAssertTrue(ids.contains("socks5"), "TCP children should include socks5")
    }

    // MARK: - testTLSChildrenContainsHTTP1AndHTTP2

    func testTLSChildrenContainsHTTP1AndHTTP2() {
        let tcpChildren = ProtocolRegistry.shared.tcpChildren
        guard let tlsNode = tcpChildren.first(where: { $0.plugin.id == "tls" }) else {
            XCTFail("Expected a TLS node under TCP")
            return
        }
        let tlsChildIds = tlsNode.children.map { $0.plugin.id }
        XCTAssertTrue(tlsChildIds.contains("http1"), "TLS children should include http1")
        XCTAssertTrue(tlsChildIds.contains("http2"), "TLS children should include http2")
    }

    // MARK: - testRootPluginNeverMatches

    func testRootPluginNeverMatches() {
        let roots = ProtocolRegistry.shared.roots

        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(capacity: 16)
        buffer.writeString("GET / HTTP/1.1\r\n")

        let context = MatchContext(localPort: 80)

        for node in roots {
            let result = node.plugin.canMatch(buffer, context: context)
            XCTAssertEqual(result, .no, "\(node.plugin.id) root plugin should never match")
        }
    }
}
