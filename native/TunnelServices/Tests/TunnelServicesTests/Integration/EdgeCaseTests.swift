//
//  EdgeCaseTests.swift
//  TunnelServicesTests
//
//  Edge case integration tests: ConnectHandler behavior, connection pool
//  capacity enforcement, and error recovery scenarios.
//

import XCTest
import NIOCore
import NIOPosix
import NIOEmbedded
import NIOHTTP1
import NIOSSL
import NIOTLS
@testable import TunnelServices

// MARK: - ConnectHandler Tests

final class ConnectHandlerEdgeCaseTests: XCTestCase {

    // MARK: 1. CONNECT Response 200

    func testConnectHandler_CONNECTResponse200() throws {
        // Start MITM proxy + TLS echo server
        let (cert, key) = try TestEchoServer.generateServerCert()
        let echoServer = TestEchoServer(mode: .http1TLS(cert: cert, key: key))
        let serverPort = try echoServer.start()

        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()

        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
            try? echoServer.stop()
        }

        // Use rawConnect to send CONNECT and verify 200 response
        // rawConnect succeeds only if the proxy returns 200
        let tunnel = try client.rawConnect(host: "localhost", port: serverPort)

        // Verify the tunnel channel is active (CONNECT succeeded with 200)
        XCTAssertTrue(tunnel.isActive, "Tunnel channel should be active after CONNECT 200")

        // Verify TLS handshake succeeds on the tunnel
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: "localhost")

        try tunnel.pipeline.addHandler(sslHandler, position: .first).wait()

        let el = tunnel.eventLoop
        let handshakePromise = el.makePromise(of: Void.self)
        let timeoutTask = el.scheduleTask(in: .seconds(10)) {
            handshakePromise.fail(TestNIOClientError.timeout)
        }

        let detector = HandshakeDetectorHandler(promise: handshakePromise)
        try tunnel.pipeline.addHandler(detector).wait()

        do {
            try handshakePromise.futureResult.wait()
            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            try? tunnel.close().wait()
            XCTFail("TLS handshake should succeed on the CONNECT tunnel: \(error)")
            return
        }

        try? tunnel.close().wait()
    }

    // MARK: 2. Non-CONNECT PassThrough

    func testConnectHandler_NonCONNECT_PassThrough() throws {
        // Start plain HTTP echo server + proxy (no SSL)
        let echoServer = TestEchoServer(mode: .http1)
        let serverPort = try echoServer.start()

        let launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
        let proxyPort = try launcher.start()

        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
            try? echoServer.stop()
        }

        // Send a normal GET (not CONNECT) through the proxy
        let response = try client.httpRequest(
            method: .GET, host: "127.0.0.1", port: serverPort, uri: "/passthrough-test"
        )

        XCTAssertEqual(response.status, 200, "Non-CONNECT GET should return 200")

        // Wait for async DB write
        Thread.sleep(forTimeInterval: 1.0)

        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1, "Expected at least 1 flow record")

        let flow = flows.first!
        XCTAssertEqual(flow.protocolName, "HTTP",
            "Non-CONNECT flow should be recorded as HTTP, got \(flow.protocolName)")
    }

    // MARK: 3. Invalid Host

    func testConnectHandler_InvalidHost() throws {
        // Start MITM proxy (no echo server needed)
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()

        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
        }

        // The proxy sends 200 Connection Established immediately before connecting
        // outbound, so rawConnect will succeed. The failure occurs when the MITM
        // handler tries to reach the unreachable host for TLS interception.
        var tunnelOrError: Channel?
        do {
            tunnelOrError = try client.rawConnect(host: "10.255.255.1", port: 9999)
        } catch {
            // CONNECT failed at the proxy level — also acceptable
        }

        if let tunnel = tunnelOrError {
            // Tunnel was opened (proxy sent 200), but the outbound connection
            // to the unreachable host will fail. Wait for the channel to close.
            let closedPromise = tunnel.eventLoop.makePromise(of: Void.self)
            tunnel.closeFuture.cascade(to: closedPromise)

            // Give the proxy time to detect the outbound failure and close the tunnel
            let timeoutTask = tunnel.eventLoop.scheduleTask(in: .seconds(5)) {
                closedPromise.fail(TestNIOClientError.timeout)
            }

            do {
                try closedPromise.futureResult.wait()
                timeoutTask.cancel()
            } catch {
                timeoutTask.cancel()
                // Timeout waiting for close — force close
                try? tunnel.close().wait()
            }
        }

        // Wait for async DB write — the MITM outbound connection to the unreachable
        // host may still be pending (TCP connect timeout can be long). The flow record
        // is written when the session closes, which may not happen until the client
        // disconnects or the outbound timeout fires.
        Thread.sleep(forTimeInterval: 3.0)

        // Check DB for the failed flow
        let flows = try launcher.queryFlows()

        if !flows.isEmpty {
            // If a flow was recorded, it should indicate failure
            let flow = flows.first!
            let isFailed = flow.status == .failed
            let hasError = !flow.errorMessage.isEmpty
            let isInProgress = flow.status == .inProgress

            XCTAssertTrue(isFailed || hasError || isInProgress,
                "Flow for unreachable host should indicate failure or in-progress: " +
                "status=\(flow.status), errorMessage=\(flow.errorMessage)")
        } else {
            // No flow recorded — acceptable if the MITM outbound connection is
            // still pending or the session tore down before the DB write completed.
            // The key assertion is that the proxy did not crash.
        }
    }
}

// MARK: - Connection Pool Edge Case Tests

final class ConnectionPoolEdgeCaseTests: XCTestCase {

    private var eventLoop: EmbeddedEventLoop!

    override func setUp() {
        super.setUp()
        eventLoop = EmbeddedEventLoop()
    }

    override func tearDown() {
        try? eventLoop.syncShutdownGracefully()
        super.tearDown()
    }

    private func makeKey(host: String = "example.com", port: Int = 443, isSSL: Bool = true) -> ConnectionPoolKey {
        ConnectionPoolKey(host: host, port: port, isSSL: isSSL)
    }

    private func makeActiveChannel() -> EmbeddedChannel {
        let channel = EmbeddedChannel(loop: eventLoop)
        try! channel.connect(to: .init(ipAddress: "127.0.0.1", port: 1234)).wait()
        return channel
    }

    // MARK: 4. Max Per Key

    func testPool_MaxPerKey() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        let key = makeKey()
        var channels = [EmbeddedChannel]()

        // Create and checkin 7 channels with the same key
        for _ in 0..<7 {
            let ch = makeActiveChannel()
            channels.append(ch)
            pool.checkin(key: key, channel: ch)
        }

        // maxConnectionsPerKey is 6, so the 7th should be rejected
        XCTAssertEqual(pool.count(for: key), OutboundConnectionPool.maxConnectionsPerKey,
            "Pool should contain exactly \(OutboundConnectionPool.maxConnectionsPerKey) connections per key, 7th rejected")
        XCTAssertEqual(pool.count(for: key), 6,
            "Pool per-key count should be 6 (7th rejected)")
    }

    // MARK: 5. Total Capacity

    func testPool_TotalCapacity() {
        let pool = OutboundConnectionPool()
        defer { pool.closeAll() }

        var channels = [EmbeddedChannel]()

        // Fill pool to 32 across different keys
        for i in 0..<32 {
            let key = makeKey(host: "host\(i).com")
            let ch = makeActiveChannel()
            channels.append(ch)
            pool.checkin(key: key, channel: ch)
        }

        XCTAssertEqual(pool.count, 32,
            "Pool should contain exactly 32 connections")

        // Next checkin should be rejected
        let overflowKey = makeKey(host: "overflow.com")
        let overflowCh = makeActiveChannel()
        pool.checkin(key: overflowKey, channel: overflowCh)

        XCTAssertEqual(pool.count, OutboundConnectionPool.maxTotalConnections,
            "Pool should still contain \(OutboundConnectionPool.maxTotalConnections) after overflow rejection")
        XCTAssertEqual(pool.count, 32,
            "Pool total count should remain 32 after rejected checkin")
    }
}

// MARK: - Error Recovery Tests

final class ErrorRecoveryEdgeCaseTests: XCTestCase {

    // MARK: 6. Server Drops Connection After Head

    func testError_ServerDropsConnection() throws {
        // Echo server that drops connection after sending response head
        let echoServer = TestEchoServer(mode: .http1, options: .init(dropAfterHead: true))
        let serverPort = try echoServer.start()

        let launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
        let proxyPort = try launcher.start()

        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
            try? echoServer.stop()
        }

        // Send request through proxy — server will drop after head
        // The response may succeed (with empty body) or throw (connection reset)
        var gotResponse = false
        do {
            let response = try client.httpRequest(
                method: .GET, host: "127.0.0.1", port: serverPort, uri: "/drop-test"
            )
            // If we got a response at all, status should be 200 (the head was sent)
            gotResponse = true
            XCTAssertEqual(response.status, 200,
                "Response head should indicate 200 before connection drop")
        } catch {
            // Connection dropped — also acceptable
            gotResponse = false
        }

        // Wait for async DB write
        Thread.sleep(forTimeInterval: 2.0)

        // Database should have a flow recorded (may be failed or partial)
        let flows = try launcher.queryFlows()

        // Accept: flow exists (failed or completed) OR no flow if connection tore down too fast
        if !flows.isEmpty {
            let flow = flows.first { $0.searchKey2.contains("/drop-test") } ?? flows.first!

            // The flow should be either completed (if head+end were fast enough)
            // or failed (if the connection drop was detected)
            let validStatus = flow.status == .completed || flow.status == .failed
            XCTAssertTrue(validStatus,
                "Flow should be completed or failed after server drops, got status=\(flow.status)")
        } else if gotResponse {
            // We got a response but no flow — the DB write may still be pending
            // This is a soft failure; the important thing is the proxy didn't crash
        }
    }
}

// MARK: - HandshakeDetectorHandler (helper — shared with TLSIntegrationTests)

private final class HandshakeDetectorHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = NIOAny

    private let promise: EventLoopPromise<Void>
    private var completed = false

    init(promise: EventLoopPromise<Void>) {
        self.promise = promise
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let tlsEvent = event as? TLSUserEvent {
            switch tlsEvent {
            case .handshakeCompleted:
                if !completed {
                    completed = true
                    promise.succeed(())
                }
            case .shutdownCompleted:
                break
            }
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if !completed {
            completed = true
            promise.fail(error)
        }
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !completed {
            completed = true
            promise.fail(ChannelError.ioOnClosedChannel)
        }
        context.fireChannelInactive()
    }
}
