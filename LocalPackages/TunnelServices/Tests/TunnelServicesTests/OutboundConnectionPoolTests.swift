import XCTest
import NIOCore
import NIOEmbedded
@testable import TunnelServices

final class OutboundConnectionPoolTests: XCTestCase {

    private var eventLoop: EmbeddedEventLoop!

    override func setUp() {
        super.setUp()
        eventLoop = EmbeddedEventLoop()
    }

    override func tearDown() {
        try? eventLoop.syncShutdownGracefully()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeKey(host: String = "example.com", port: Int = 443, isSSL: Bool = true) -> ConnectionPoolKey {
        ConnectionPoolKey(host: host, port: port, isSSL: isSSL)
    }

    private func makeActiveChannel() -> EmbeddedChannel {
        let channel = EmbeddedChannel(loop: eventLoop)
        // EmbeddedChannel must be connected to be isActive
        try! channel.connect(to: .init(ipAddress: "127.0.0.1", port: 1234)).wait()
        return channel
    }

    // MARK: - ConnectionPoolKey equality

    func testKeyEquality() {
        let a = makeKey(host: "a.com", port: 443, isSSL: true)
        let b = makeKey(host: "a.com", port: 443, isSSL: true)
        let c = makeKey(host: "a.com", port: 80, isSSL: false)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testKeyHashable() {
        let a = makeKey(host: "a.com", port: 443, isSSL: true)
        let b = makeKey(host: "a.com", port: 443, isSSL: true)
        var set = Set<ConnectionPoolKey>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Basic checkout / checkin

    func testCheckinAndCheckout() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key = makeKey()
        let channel = makeActiveChannel()

        pool.checkin(key: key, channel: channel)
        XCTAssertEqual(pool.count, 1)

        let retrieved = pool.checkout(key: key)
        XCTAssertNotNil(retrieved)
        XCTAssertTrue(retrieved === channel)
        XCTAssertEqual(pool.count, 0)
    }

    func testCheckoutEmptyPoolReturnsNil() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key = makeKey()
        XCTAssertNil(pool.checkout(key: key))
    }

    func testCheckoutWrongKeyReturnsNil() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key1 = makeKey(host: "a.com")
        let key2 = makeKey(host: "b.com")
        let channel = makeActiveChannel()

        pool.checkin(key: key1, channel: channel)
        XCTAssertNil(pool.checkout(key: key2))

        pool.closeAll()
    }

    func testLIFOOrder() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key = makeKey()
        let ch1 = makeActiveChannel()
        let ch2 = makeActiveChannel()

        pool.checkin(key: key, channel: ch1)
        pool.checkin(key: key, channel: ch2)

        // LIFO: ch2 should come out first
        let out1 = pool.checkout(key: key)
        XCTAssertTrue(out1 === ch2)

        let out2 = pool.checkout(key: key)
        XCTAssertTrue(out2 === ch1)
    }

    // MARK: - Capacity enforcement

    func testPerKeyCapEnforced() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key = makeKey()
        var channels = [EmbeddedChannel]()

        for _ in 0..<OutboundConnectionPool.maxConnectionsPerKey {
            let ch = makeActiveChannel()
            channels.append(ch)
            pool.checkin(key: key, channel: ch)
        }

        XCTAssertEqual(pool.count(for: key), OutboundConnectionPool.maxConnectionsPerKey)

        // One more should be rejected (channel closed)
        let overflow = makeActiveChannel()
        pool.checkin(key: key, channel: overflow)
        XCTAssertEqual(pool.count(for: key), OutboundConnectionPool.maxConnectionsPerKey)
    }

    func testTotalCapEnforced() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        var channels = [EmbeddedChannel]()
        // Fill pool to max total using different keys
        for i in 0..<OutboundConnectionPool.maxTotalConnections {
            let key = makeKey(host: "host\(i).com")
            let ch = makeActiveChannel()
            channels.append(ch)
            pool.checkin(key: key, channel: ch)
        }

        XCTAssertEqual(pool.count, OutboundConnectionPool.maxTotalConnections)

        // One more should be rejected
        let overflow = makeActiveChannel()
        pool.checkin(key: makeKey(host: "overflow.com"), channel: overflow)
        XCTAssertEqual(pool.count, OutboundConnectionPool.maxTotalConnections)
    }

    // MARK: - Closed channels are skipped

    func testSkipsClosedChannelsOnCheckout() throws {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key = makeKey()
        let ch1 = makeActiveChannel()
        let ch2 = makeActiveChannel()

        pool.checkin(key: key, channel: ch1)
        pool.checkin(key: key, channel: ch2)

        // Close ch2 (LIFO top)
        try ch2.close().wait()

        // Should skip ch2 and return ch1
        let out = pool.checkout(key: key)
        XCTAssertTrue(out === ch1)
        XCTAssertEqual(pool.count, 0)
    }

    // MARK: - closeAll

    func testCloseAllEmptiesPool() {
        let pool = OutboundConnectionPool()

        let key = makeKey()
        let ch = makeActiveChannel()
        pool.checkin(key: key, channel: ch)
        XCTAssertEqual(pool.count, 1)

        pool.closeAll()
        XCTAssertEqual(pool.count, 0)
        XCTAssertNil(pool.checkout(key: key))
    }

    func testCheckinAfterCloseAllRejects() {
        let pool = OutboundConnectionPool()
        pool.closeAll()

        let key = makeKey()
        let ch = makeActiveChannel()
        pool.checkin(key: key, channel: ch)
        XCTAssertEqual(pool.count, 0)
    }

    func testCheckoutAfterCloseAllReturnsNil() {
        let pool = OutboundConnectionPool()
        let key = makeKey()
        let ch = makeActiveChannel()
        pool.checkin(key: key, channel: ch)

        pool.closeAll()
        XCTAssertNil(pool.checkout(key: key))
    }

    // MARK: - Eviction

    func testEvictExpiredRemovesInactiveChannels() throws {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key = makeKey()
        let ch = makeActiveChannel()
        pool.checkin(key: key, channel: ch)

        // Close the channel then evict
        try ch.close().wait()
        pool.evictExpired()

        XCTAssertEqual(pool.count, 0)
    }
}
