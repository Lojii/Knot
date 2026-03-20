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
        // Initially no children have been registered — verify accessor doesn't crash
        // and returns an empty array.
        let children = ProtocolRegistry.shared.tcpChildren
        XCTAssertNotNil(children)
        XCTAssertTrue(children.isEmpty)
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
