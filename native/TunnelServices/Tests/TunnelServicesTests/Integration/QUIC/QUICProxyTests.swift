//
//  QUICProxyTests.swift
//  TunnelServicesTests
//
//  Integration tests for the QUIC UDP proxy (QUICProxyHandler + QUICServerForwarder).
//  Validates DatagramChannel plumbing, QUIC handshake forwarding via real UDP,
//  and end-to-end HTTP/3 request/response through the proxy.
//

import XCTest
import NIO
@testable import TunnelServices

#if canImport(SwiftQuiche)
import SwiftQuiche

// MARK: - UDP Wrappers for In-Memory QUIC Objects

/// Wraps a TestQUICServer with a real DatagramChannel so it can receive/send UDP packets.
private final class UDPQUICServerHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    let server: TestQUICServer

    init(server: TestQUICServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buf = envelope.data
        guard let bytes = buf.readBytes(length: buf.readableBytes) else { return }
        let packetData = Data(bytes)
        let clientAddr = envelope.remoteAddress

        // Feed to in-memory server
        let responses = server.receive(packetData)
        let serverOut = server.pendingOutbound()

        // Send all response packets back to the sender
        for pkt in (responses + serverOut) {
            var outBuf = context.channel.allocator.buffer(capacity: pkt.count)
            outBuf.writeBytes(pkt)
            context.writeAndFlush(wrapOutboundOut(
                AddressedEnvelope(remoteAddress: clientAddr, data: outBuf)
            ), promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Ignore errors in test server
    }
}

/// Wraps a TestQUICClient with a real DatagramChannel so it can exchange
/// QUIC packets via UDP. Provides a blocking `waitUntilEstablished` helper.
private final class UDPQUICTestClient {
    let client: TestQUICClient
    let group: MultiThreadedEventLoopGroup
    let channel: Channel
    private let handler: UDPQUICClientHandler

    init(client: TestQUICClient, proxyAddress: SocketAddress) throws {
        self.client = client
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientHandler = UDPQUICClientHandler(client: client, proxyAddress: proxyAddress)
        self.handler = clientHandler

        self.channel = try DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(clientHandler)
            }
            .bind(host: "127.0.0.1", port: 0)
            .wait()
    }

    /// Send the QUIC Initial packets to start the handshake.
    func startConnection() {
        let packets = client.startConnection()
        handler.sendPackets(packets, on: channel)
    }

    var isEstablished: Bool {
        client.isEstablished
    }

    /// Block until the QUIC handshake completes, or timeout.
    func waitUntilEstablished(timeout: TimeInterval = 15.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !client.isEstablished && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            // Drain any outbound packets the client may have queued
            let outgoing = client.drainOutbound()
            if !outgoing.isEmpty {
                handler.sendPackets(outgoing, on: channel)
            }
        }
        return client.isEstablished
    }

    /// Send an H3 request and wait for the response.
    func sendRequestAndWait(
        method: String = "GET",
        path: String = "/",
        authority: String = "localhost",
        timeout: TimeInterval = 15.0
    ) -> [(headers: [(String, String)], body: Data)] {
        // Let H3 control streams settle with aggressive pumping.
        // The MITM creates two QUIC connections (client-facing and server-facing),
        // so there are many round trips needed for H3 control streams to stabilize.
        for _ in 0..<40 {
            let outgoing = client.drainOutbound()
            if !outgoing.isEmpty {
                handler.sendPackets(outgoing, on: channel)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let requestPackets = client.sendRequest(method: method, path: path, authority: authority)
        handler.sendPackets(requestPackets, on: channel)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            // Drain any outbound
            let outgoing = client.drainOutbound()
            if !outgoing.isEmpty {
                handler.sendPackets(outgoing, on: channel)
            }
            let responses = client.pollResponses()
            if !responses.isEmpty {
                return responses
            }
        }
        return []
    }

    func shutdown() {
        try? channel.close().wait()
        try? group.syncShutdownGracefully()
    }
}

/// NIO handler that sits on the client's DatagramChannel.
/// Receives server responses via UDP and feeds them to the in-memory TestQUICClient,
/// then sends any resulting outbound packets back.
private final class UDPQUICClientHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    let client: TestQUICClient
    let proxyAddress: SocketAddress

    init(client: TestQUICClient, proxyAddress: SocketAddress) {
        self.client = client
        self.proxyAddress = proxyAddress
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buf = envelope.data
        guard let bytes = buf.readBytes(length: buf.readableBytes) else { return }
        let packetData = Data(bytes)

        // Feed to in-memory client and send resulting outbound packets
        let outgoing = client.receive([packetData])
        sendPackets(outgoing, context: context)
    }

    func sendPackets(_ packets: [Data], on channel: Channel) {
        for pkt in packets {
            var buf = channel.allocator.buffer(capacity: pkt.count)
            buf.writeBytes(pkt)
            let envelope = AddressedEnvelope(remoteAddress: proxyAddress, data: buf)
            channel.writeAndFlush(envelope, promise: nil)
        }
    }

    private func sendPackets(_ packets: [Data], context: ChannelHandlerContext) {
        for pkt in packets {
            var buf = context.channel.allocator.buffer(capacity: pkt.count)
            buf.writeBytes(pkt)
            context.writeAndFlush(wrapOutboundOut(
                AddressedEnvelope(remoteAddress: proxyAddress, data: buf)
            ), promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Ignore errors in test client
    }
}

/// Simple handler that records whether channelRead was called.
/// Used by the smoke test to verify DatagramChannel plumbing.
private final class ChannelReadRecorder: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    var readCount = 0
    let readExpectation: XCTestExpectation

    init(expectation: XCTestExpectation) {
        self.readExpectation = expectation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        readCount += 1
        readExpectation.fulfill()
        // Forward to next handler
        context.fireChannelRead(data)
    }
}

// MARK: - Tests

final class QUICProxyTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quic-proxy-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeMITMManager(certPath: String, keyPath: String) -> QUICMITMManager {
        let task = CaptureTask()
        task.id = 0
        task.localIP = "127.0.0.1"
        task.localPort = 0
        task.localEnable = 1
        task.isCACertTrusted = true
        task.ruleEngine = RuleEngine(config: "")
        task.fileFolder = tempDir.path

        return QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)
    }

    /// Start a TestQUICServer on a real UDP DatagramChannel.
    /// Returns the channel and the bound port.
    private func startUDPServer(
        server: TestQUICServer,
        group: EventLoopGroup
    ) throws -> (Channel, Int) {
        let channel = try DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(UDPQUICServerHandler(server: server))
            }
            .bind(host: "127.0.0.1", port: 0)
            .wait()

        guard let port = channel.localAddress?.port else {
            throw NSError(domain: "QUICProxyTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not determine UDP server port"
            ])
        }
        return (channel, port)
    }

    /// Start a QUICProxyHandler on a real UDP DatagramChannel.
    /// Returns the channel and the bound port.
    private func startProxy(
        mitmManager: QUICMITMManager,
        defaultTarget: (host: String, port: Int),
        group: EventLoopGroup
    ) throws -> (Channel, Int) {
        let handler = QUICProxyHandler(mitmManager: mitmManager, defaultTarget: defaultTarget)

        let channel = try DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(handler)
            }
            .bind(host: "127.0.0.1", port: 0)
            .wait()

        guard let port = channel.localAddress?.port else {
            throw NSError(domain: "QUICProxyTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not determine proxy port"
            ])
        }
        return (channel, port)
    }

    // MARK: - Test 1: UDP Bind and Receive (Smoke Test)

    /// Verifies that a DatagramChannel with QUICProxyHandler can bind, receive a
    /// UDP packet, and process it without crashing. This is a smoke test for the
    /// NIO DatagramChannel plumbing.
    func testUDPProxy_BindAndReceive() throws {
        let (certPath, keyPath) = try TestQUICServer.generateTestCerts()
        let mitmManager = makeMITMManager(certPath: certPath, keyPath: keyPath)
        defer { mitmManager.shutdown() }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // Set up a read recorder to verify the handler pipeline works
        let readExpectation = expectation(description: "channelRead called on proxy handler")
        let recorder = ChannelReadRecorder(expectation: readExpectation)

        let proxyHandler = QUICProxyHandler(
            mitmManager: mitmManager,
            defaultTarget: (host: "127.0.0.1", port: 9999)
        )

        let proxyChannel = try DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                // Recorder first, so it fires before QUICProxyHandler
                channel.pipeline.addHandler(recorder).flatMap {
                    channel.pipeline.addHandler(proxyHandler)
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .wait()
        defer { try? proxyChannel.close().wait() }

        guard let proxyPort = proxyChannel.localAddress?.port else {
            XCTFail("Could not determine proxy port")
            return
        }

        // Create a simple UDP client and send a random packet
        let clientChannel = try DatagramBootstrap(group: group)
            .bind(host: "127.0.0.1", port: 0)
            .wait()
        defer { try? clientChannel.close().wait() }

        let proxyAddr = try SocketAddress(ipAddress: "127.0.0.1", port: proxyPort)
        var buf = clientChannel.allocator.buffer(capacity: 64)
        // Write random bytes (not a valid QUIC packet, but handler should not crash)
        let randomBytes = (0..<64).map { _ in UInt8.random(in: 0...255) }
        buf.writeBytes(randomBytes)
        let envelope = AddressedEnvelope(remoteAddress: proxyAddr, data: buf)
        try clientChannel.writeAndFlush(envelope).wait()

        // Wait for the handler to receive the packet
        wait(for: [readExpectation], timeout: 5.0)

        XCTAssertGreaterThanOrEqual(recorder.readCount, 1, "Proxy handler should have received at least one packet")
    }

    // MARK: - Test 2: QUIC Handshake via UDP Proxy

    /// Starts a real UDP QUIC server, a QUICProxyHandler on another port, and
    /// a UDP test client. Exchanges packets until the QUIC handshake completes
    /// through the MITM proxy.
    ///
    /// Note: This test may be timing-sensitive since it relies on real UDP I/O
    /// and multiple round trips through the MITM proxy.
    func testUDPProxy_QUICHandshakeViaUDP() throws {
        let (certPath, keyPath) = try TestQUICServer.generateTestCerts()
        let server = try TestQUICServer(certPath: certPath, keyPath: keyPath)
        let mitmManager = makeMITMManager(certPath: certPath, keyPath: keyPath)
        defer { mitmManager.shutdown() }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { try? group.syncShutdownGracefully() }

        // Start the real QUIC server on a UDP port
        let (serverChannel, serverPort) = try startUDPServer(server: server, group: group)
        defer { try? serverChannel.close().wait() }

        // Start the proxy pointing at the server
        let (proxyChannel, proxyPort) = try startProxy(
            mitmManager: mitmManager,
            defaultTarget: (host: "127.0.0.1", port: serverPort),
            group: group
        )
        defer { try? proxyChannel.close().wait() }

        // Create a UDP test client that talks to the proxy
        let client = try TestQUICClient(serverName: "localhost")
        let proxyAddr = try SocketAddress(ipAddress: "127.0.0.1", port: proxyPort)
        let udpClient = try UDPQUICTestClient(client: client, proxyAddress: proxyAddr)
        defer { udpClient.shutdown() }

        // Start the QUIC handshake
        udpClient.startConnection()

        // Wait for handshake to complete
        let established = udpClient.waitUntilEstablished(timeout: 15.0)

        XCTAssertTrue(established, "QUIC handshake should complete through the UDP proxy")
    }

    // MARK: - Test 3: H3 Request via UDP Proxy

    /// Full end-to-end test: QUIC handshake + HTTP/3 GET request through the
    /// UDP proxy. Verifies the response is received correctly.
    ///
    /// Note: This test may be timing-sensitive due to real UDP I/O and the
    /// number of round trips required (handshake + H3 control streams + request).
    func testUDPProxy_H3RequestViaUDP() throws {
        let (certPath, keyPath) = try TestQUICServer.generateTestCerts()
        let server = try TestQUICServer(certPath: certPath, keyPath: keyPath)
        let mitmManager = makeMITMManager(certPath: certPath, keyPath: keyPath)
        defer { mitmManager.shutdown() }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { try? group.syncShutdownGracefully() }

        // Start the real QUIC server on a UDP port
        let (serverChannel, serverPort) = try startUDPServer(server: server, group: group)
        defer { try? serverChannel.close().wait() }

        // Start the proxy pointing at the server
        let (proxyChannel, proxyPort) = try startProxy(
            mitmManager: mitmManager,
            defaultTarget: (host: "127.0.0.1", port: serverPort),
            group: group
        )
        defer { try? proxyChannel.close().wait() }

        // Create a UDP test client that talks to the proxy
        let client = try TestQUICClient(serverName: "localhost")
        let proxyAddr = try SocketAddress(ipAddress: "127.0.0.1", port: proxyPort)
        let udpClient = try UDPQUICTestClient(client: client, proxyAddress: proxyAddr)
        defer { udpClient.shutdown() }

        // Start the QUIC handshake
        udpClient.startConnection()

        let established = udpClient.waitUntilEstablished(timeout: 15.0)
        guard established else {
            XCTFail("QUIC handshake did not complete through the UDP proxy")
            return
        }

        // Send an H3 GET request and wait for the response.
        // The MITM creates two separate QUIC+H3 connections (client-facing and
        // server-facing), so we need generous settle time and polling.
        let responses = udpClient.sendRequestAndWait(
            method: "GET",
            path: "/test",
            authority: "localhost",
            timeout: 15.0
        )

        // Note: This test may be flaky due to timing sensitivity with real UDP I/O
        // through the MITM proxy. The MITM's bidirectional H3 forwarding requires
        // many round trips and correct DCID-based client address resolution.
        XCTAssertGreaterThanOrEqual(responses.count, 1, "Should receive at least one H3 response")
        if let response = responses.first {
            let status = response.headers.first(where: { $0.0 == ":status" })?.1
            XCTAssertEqual(status, "200", "Response status should be 200")

            let bodyStr = String(data: response.body, encoding: .utf8)
            XCTAssertEqual(bodyStr, "echo: /test", "Response body should echo the path")
        }
    }
}

#endif
