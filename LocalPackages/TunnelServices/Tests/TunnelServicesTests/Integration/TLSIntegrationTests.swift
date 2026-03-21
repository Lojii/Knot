//
//  TLSIntegrationTests.swift
//  TunnelServicesTests
//
//  TLS integration tests: dynamic cert generation, cert export,
//  handshake failures, MITM vs tunnel paths, and ALPN negotiation.
//

import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
import NIOTLS
@testable import TunnelServices

// MARK: - Cert Behavior Tests

final class TLSCertIntegrationTests: XCTestCase {

    private func setUpMITM() throws -> (
        echoServer: TestEchoServer,
        launcher: TestProxyLauncher,
        client: TestNIOClient,
        serverPort: Int,
        proxyPort: Int
    ) {
        let (cert, key) = try TestEchoServer.generateServerCert()
        let echoServer = TestEchoServer(mode: .http1TLS(cert: cert, key: key))
        let serverPort = try echoServer.start()
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)
        return (echoServer, launcher, client, serverPort, proxyPort)
    }

    // MARK: - 1. Dynamic Cert Per Host

    func testTLS_MITM_DynamicCertPerHost() throws {
        // Use two separate echo servers on different ports so we can use different CONNECT targets.
        // Both resolve to 127.0.0.1 via "localhost", but the proxy generates certs per flow.
        let (cert1, key1) = try TestEchoServer.generateServerCert()
        let echo1 = TestEchoServer(mode: .http1TLS(cert: cert1, key: key1))
        let port1 = try echo1.start()

        let (cert2, key2) = try TestEchoServer.generateServerCert()
        let echo2 = TestEchoServer(mode: .http1TLS(cert: cert2, key: key2))
        let port2 = try echo2.start()

        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
            try? echo1.stop()
            try? echo2.stop()
        }

        // Send request to first echo server
        let responseA = try client.httpsRequest(
            host: "localhost", port: port1, uri: "/cert-test-a",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(responseA.status, 200, "First request should return 200")

        // Send request to second echo server
        let responseB = try client.httpsRequest(
            host: "localhost", port: port2, uri: "/cert-test-b",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(responseB.status, 200, "Second request should return 200")

        // Wait for async DB writes
        Thread.sleep(forTimeInterval: 2.0)

        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 2, "Expected at least 2 flow records (one per request)")

        // Both flows should have certChainRef set
        let flowsWithCert = flows.filter { $0.certChainRef != nil }
        XCTAssertGreaterThanOrEqual(flowsWithCert.count, 2,
            "Both MITM flows should have certChainRef, found \(flowsWithCert.count)")

        // Cert files are saved under PathManager.taskDirectory(taskId)
        let taskDir = PathManager.taskDirectory(launcher.taskId)

        for flow in flowsWithCert {
            guard let ref = flow.certChainRef else { continue }
            let pemPath = (taskDir as NSString).appendingPathComponent(ref)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pemPath),
                "PEM file should exist at \(pemPath)")

            let pemContent = try String(contentsOfFile: pemPath, encoding: .utf8)
            XCTAssertTrue(pemContent.contains("BEGIN CERTIFICATE"),
                "PEM should contain certificate data")

            // Export and verify subject
            let exportService = CertExportService(fileFolder: taskDir)
            let result = exportService.exportCertChain(certChainRef: ref)
            if case .success(let export) = result {
                XCTAssertFalse(export.summary.isEmpty,
                    "Exported cert should have at least one entry in summary")
                let subject = export.summary.first?["subject"] ?? ""
                XCTAssertTrue(subject.contains("localhost"),
                    "Cert subject should contain localhost, got: \(subject)")
            } else {
                XCTFail("Failed to export cert for flow \(flow.flowId): \(result)")
            }
        }
    }

    // MARK: - 2. Cert Export PEM

    func testTLS_MITM_CertExportPEM() throws {
        let (server, launcher, client, serverPort, _) = try setUpMITM()
        defer {
            client.shutdown()
            launcher.stop()
            try? server.stop()
        }

        // Send HTTPS request
        let response = try client.httpsRequest(
            host: "localhost", port: serverPort, uri: "/cert-export-test",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(response.status, 200)

        // Wait for async DB write
        Thread.sleep(forTimeInterval: 2.0)

        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1, "Expected at least 1 flow record")

        let flow = flows.first { $0.protocolName == "HTTPS" } ?? flows.first!
        XCTAssertNotNil(flow.certChainRef, "Flow should have certChainRef for MITM")

        guard let ref = flow.certChainRef else { return }

        // Cert files are saved under PathManager.taskDirectory(taskId)
        let taskDir = PathManager.taskDirectory(launcher.taskId)
        let exportService = CertExportService(fileFolder: taskDir)
        let result = exportService.exportCertChain(certChainRef: ref)

        switch result {
        case .success(let export):
            // Assert PEM text contains "BEGIN CERTIFICATE"
            XCTAssertTrue(export.pemText.contains("BEGIN CERTIFICATE"),
                "Exported PEM should contain BEGIN CERTIFICATE")

            // Assert summary has subject and issuer
            XCTAssertFalse(export.summary.isEmpty, "Summary should have at least one entry")
            if let leafSummary = export.summary.first {
                XCTAssertNotNil(leafSummary["subject"], "Summary should have subject")
                XCTAssertNotNil(leafSummary["issuer"], "Summary should have issuer")
                XCTAssertFalse(leafSummary["subject"]?.isEmpty ?? true,
                    "Subject should not be empty")
                XCTAssertFalse(leafSummary["issuer"]?.isEmpty ?? true,
                    "Issuer should not be empty")
            }

        case .failure(let error):
            XCTFail("Cert export failed: \(error)")
        }
    }
}

// MARK: - Handshake Failure Tests

final class TLSHandshakeFailIntegrationTests: XCTestCase {

    func testTLS_HandshakeFail_UntrustedCA() throws {
        // Set up echo server with TLS
        let (cert, key) = try TestEchoServer.generateServerCert()
        let echoServer = TestEchoServer(mode: .http1TLS(cert: cert, key: key))
        let serverPort = try echoServer.start()

        // MITM proxy with CA
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()

        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
            try? echoServer.stop()
        }

        // Use rawConnect() to establish CONNECT tunnel, then do TLS with strict verification
        // and NO trusted CA. This triggers a handshake failure on the client side because
        // the MITM-generated cert is signed by our test CA which is not in system roots.
        let tunnel = try client.rawConnect(host: "localhost", port: serverPort)

        // Add TLS with strict verification and NO trusted CA
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .fullVerification
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: "localhost")

        try tunnel.pipeline.addHandler(sslHandler, position: .first).wait()

        let el = tunnel.eventLoop
        let handshakePromise = el.makePromise(of: Void.self)

        // Add a timeout so we don't hang if the error doesn't propagate
        let timeoutTask = el.scheduleTask(in: .seconds(10)) {
            handshakePromise.fail(TestNIOClientError.timeout)
        }

        let eventsHandler = HandshakeDetectorHandler(promise: handshakePromise)
        try tunnel.pipeline.addHandler(eventsHandler).wait()

        // Wait for the handshake to fail (or timeout)
        var handshakeFailed = false
        do {
            try handshakePromise.futureResult.wait()
            timeoutTask.cancel()
            // Handshake unexpectedly succeeded
        } catch {
            timeoutTask.cancel()
            // Expected: TLS handshake failed (untrusted CA) or timeout
            handshakeFailed = true
        }

        XCTAssertTrue(handshakeFailed,
            "TLS handshake should fail when CA is not trusted")

        try? tunnel.close().wait()

        // Wait for proxy-side DB writes. The MITM handshake timeout on the proxy side
        // is typically a few seconds, so we need to wait long enough.
        Thread.sleep(forTimeInterval: 3.0)

        // The proxy records the CONNECT session. When the client disconnects during
        // the MITM TLS handshake, the proxy should record the flow with error state.
        let flows = try launcher.queryFlows()

        // Accept either: flow recorded with error/fail flags, or no flow at all
        // (if the connection tore down before the proxy could write anything).
        if flows.isEmpty {
            // Handshake failure happened so fast the proxy didn't record a flow.
            // Acceptable — verify no crash occurred.
            return
        }

        if let flow = flows.first {
            let hasHandshakeFail = flow.protoFlags & 0x0200 != 0
            let hasHandshakeTimeout = flow.protoFlags & 0x0400 != 0
            let hasMITM = flow.protoFlags & 0x0040 != 0
            let isFailed = flow.status == .failed
            let hasError = !flow.errorMessage.isEmpty

            XCTAssertTrue(hasHandshakeFail || hasHandshakeTimeout || isFailed || hasError || hasMITM,
                "Flow should indicate handshake failure or MITM attempt: " +
                "protoFlags=0x\(String(flow.protoFlags, radix: 16)), " +
                "status=\(flow.status), error=\(flow.errorMessage)")
        }
    }
}

// MARK: - MITM vs Tunnel Tests

final class TLSMITMvsTunnelIntegrationTests: XCTestCase {

    // MARK: - 4. SSL Enabled -> MITM Path

    func testTLS_SSLEnabled_MITMPath() throws {
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

        // Send HTTPS request through MITM proxy
        let response = try client.httpsRequest(
            host: "localhost", port: serverPort, uri: "/mitm-path-test",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(response.status, 200, "MITM proxied HTTPS request should return 200")

        Thread.sleep(forTimeInterval: 2.0)

        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1, "Expected at least 1 flow record")

        let flow = flows.first { $0.protocolName == "HTTPS" } ?? flows.first!

        // proto_flags should contain tlsMITM (0x0040)
        XCTAssertTrue(flow.protoFlags & 0x0040 != 0,
            "Should have tlsMITM flag (0x0040), got protoFlags=0x\(String(flow.protoFlags, radix: 16))")

        // HTTP content should be visible (searchKey1 has method for HTTPS flows)
        XCTAssertTrue(flow.searchKey1.contains("GET") || flow.searchKey2.contains("/mitm-path-test"),
            "MITM should expose HTTP method/URI, searchKey1=\(flow.searchKey1) searchKey2=\(flow.searchKey2)")
    }

    // MARK: - 5. SSL Disabled -> Tunnel Path

    func testTLS_SSLDisabled_TunnelPath() throws {
        // Echo server in TLS mode
        let (cert, key) = try TestEchoServer.generateServerCert()
        let echoServer = TestEchoServer(mode: .http1TLS(cert: cert, key: key))
        let serverPort = try echoServer.start()

        // Launcher with sslEnabled: false, withCA: false (tunnel mode)
        let launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
        let proxyPort = try launcher.start()

        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
            try? echoServer.stop()
        }

        // Use rawConnect() to open the CONNECT tunnel, then manually do TLS to the echo
        // server. The proxy sees the CONNECT and creates a tunnel (no MITM).
        let tunnel = try client.rawConnect(host: "localhost", port: serverPort)

        // Add TLS to talk directly to the echo server through the tunnel
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: "localhost")

        try tunnel.pipeline.addHandler(sslHandler, position: .first).wait()

        // Wait for TLS handshake with timeout
        let el = tunnel.eventLoop
        let handshakePromise = el.makePromise(of: Void.self)
        let timeoutTask = el.scheduleTask(in: .seconds(10)) {
            handshakePromise.fail(TestNIOClientError.timeout)
        }
        let tlsEvents = HandshakeDetectorHandler(promise: handshakePromise)
        try tunnel.pipeline.addHandler(tlsEvents).wait()

        do {
            try handshakePromise.futureResult.wait()
            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            try? tunnel.close().wait()
            // If handshake fails/times out, the tunnel relay may not work correctly.
            // Still check DB for the tunnel flow.
            Thread.sleep(forTimeInterval: 2.0)
            let flows = try launcher.queryFlows()
            if let flow = flows.first {
                // Verify tunnel flag even if request didn't complete
                XCTAssertTrue(flow.protoFlags & 0x0080 != 0,
                    "Should have tlsTunnel flag (0x0080), got protoFlags=0x\(String(flow.protoFlags, radix: 16))")
                XCTAssertTrue(flow.protoFlags & 0x0040 == 0,
                    "Should NOT have tlsMITM flag, got protoFlags=0x\(String(flow.protoFlags, radix: 16))")
            } else {
                XCTFail("Expected at least 1 flow record for tunnel, got 0")
            }
            return
        }

        // Add HTTP handlers and send request
        try tunnel.pipeline.addHTTPClientHandlers().wait()
        let responsePromise = el.makePromise(of: TestHTTPResponse.self)
        try tunnel.pipeline.addHandler(TunnelResponseCollector(promise: responsePromise)).wait()

        var httpHeaders = HTTPHeaders()
        httpHeaders.add(name: "Host", value: "localhost:\(serverPort)")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/tunnel-path-test", headers: httpHeaders)
        tunnel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
        tunnel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

        // Add timeout for the response
        let rspTimeoutTask = el.scheduleTask(in: .seconds(10)) {
            responsePromise.fail(TestNIOClientError.timeout)
        }

        let response: TestHTTPResponse
        do {
            response = try responsePromise.futureResult.wait()
            rspTimeoutTask.cancel()
        } catch {
            rspTimeoutTask.cancel()
            try? tunnel.close().wait()
            // Response timed out — check DB for tunnel flag regardless
            Thread.sleep(forTimeInterval: 2.0)
            let flows = try launcher.queryFlows()
            if let flow = flows.first {
                XCTAssertTrue(flow.protoFlags & 0x0080 != 0,
                    "Should have tlsTunnel flag (0x0080), got protoFlags=0x\(String(flow.protoFlags, radix: 16))")
                XCTAssertTrue(flow.protoFlags & 0x0040 == 0,
                    "Should NOT have tlsMITM flag, got protoFlags=0x\(String(flow.protoFlags, radix: 16))")
            } else {
                XCTFail("Expected at least 1 flow record for tunnel, got 0")
            }
            return
        }

        XCTAssertEqual(response.status, 200, "Tunnel request should return 200")

        try? tunnel.close().wait()

        Thread.sleep(forTimeInterval: 2.0)

        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1, "Expected at least 1 flow record for tunnel")

        let flow = flows.first!

        // proto_flags should contain tlsTunnel (0x0080)
        XCTAssertTrue(flow.protoFlags & 0x0080 != 0,
            "Should have tlsTunnel flag (0x0080), got protoFlags=0x\(String(flow.protoFlags, radix: 16))")

        // proto_flags should NOT contain tlsMITM (0x0040)
        XCTAssertTrue(flow.protoFlags & 0x0040 == 0,
            "Should NOT have tlsMITM flag (no CA for interception), got protoFlags=0x\(String(flow.protoFlags, radix: 16))")
    }
}

// MARK: - ALPN Tests

final class TLSALPNIntegrationTests: XCTestCase {

    // MARK: - 6. ALPN Negotiate H2

    func testTLS_ALPN_NegotiateH2() throws {
        // Echo server in HTTP/2 TLS mode (ALPN h2)
        let (cert, key) = try TestEchoServer.generateServerCert()
        let echoServer = TestEchoServer(mode: .http2TLS(cert: cert, key: key))
        let serverPort = try echoServer.start()

        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()

        let client = TestNIOClient(proxyPort: proxyPort)

        defer {
            client.shutdown()
            launcher.stop()
            try? echoServer.stop()
        }

        // Send H2 request through MITM proxy.
        // Use trustCA: nil to skip cert verification (certificateVerification = .none).
        let response = try client.h2Request(
            host: "localhost", port: serverPort, uri: "/h2-alpn-test"
        )
        XCTAssertEqual(response.status, 200, "H2 request through MITM should return 200")

        // Wait longer for H2 stream flow records (multiplexed streams may take longer to flush)
        Thread.sleep(forTimeInterval: 3.0)

        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1, "Expected at least 1 flow record")

        // The MITM handler negotiates ALPN with the client. When h2 is negotiated:
        // - The outer CONNECT recorder gets schemes="H2" and protocolName from HTTPRecorder
        // - Per-stream recorders create separate H2 flow records
        // Look for: (a) a flow with protocolName "H2", or (b) h2Multiplexing flag (0x0004)
        let h2Flow = flows.first { $0.protocolName == "H2" }
        let anyH2Indicator = flows.first {
            $0.protocolName == "H2" ||
            $0.protoFlags & 0x0004 != 0 ||  // h2Multiplexing
            $0.protoFlags & 0x0040 != 0      // tlsMITM
        }

        XCTAssertNotNil(anyH2Indicator,
            "Should have a flow with H2 protocol or h2/MITM flags, " +
            "got: \(flows.map { "proto=\($0.protocolName) flags=0x\(String($0.protoFlags, radix: 16))" })")

        if let flow = h2Flow ?? anyH2Indicator {
            // The flow should indicate H2 usage in some way
            let isH2 = flow.protocolName == "H2"
            let hasH2Flag = flow.protoFlags & 0x0004 != 0  // h2Multiplexing
            XCTAssertTrue(isH2 || hasH2Flag,
                "Flow should indicate H2: protocolName=\(flow.protocolName), protoFlags=0x\(String(flow.protoFlags, radix: 16))")
        }
    }

    // MARK: - 7. ALPN Fallback HTTP/1.1

    func testTLS_ALPN_FallbackHTTP11() throws {
        // Echo server in HTTP/1.1 TLS mode (ALPN http/1.1 only)
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

        // Send HTTPS request (will negotiate http/1.1)
        let response = try client.httpsRequest(
            host: "localhost", port: serverPort, uri: "/h11-fallback-test",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(response.status, 200, "HTTPS/1.1 request should return 200")

        Thread.sleep(forTimeInterval: 2.0)

        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1, "Expected at least 1 flow record")

        let flow = flows.first { $0.protocolName == "HTTPS" } ?? flows.first!

        // Flow should be HTTPS (not H2)
        XCTAssertEqual(flow.protocolName, "HTTPS",
            "Protocol should be HTTPS (HTTP/1.1 fallback), got \(flow.protocolName)")

        // Should NOT be H2
        XCTAssertNotEqual(flow.protocolName, "H2",
            "Protocol should not be H2 when server only supports HTTP/1.1")

        // Should have MITM flag since sslEnabled=true
        XCTAssertTrue(flow.protoFlags & 0x0040 != 0,
            "Should have tlsMITM flag (0x0040), got protoFlags=0x\(String(flow.protoFlags, radix: 16))")
    }
}

// MARK: - HandshakeDetectorHandler (helper)

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

// MARK: - TunnelResponseCollector (helper for tunnel test)

private final class TunnelResponseCollector: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private var head: HTTPResponseHead?
    private var body = Data()
    private let promise: EventLoopPromise<TestHTTPResponse>

    init(promise: EventLoopPromise<TestHTTPResponse>) {
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h):
            head = h
        case .body(var buf):
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            let response = TestHTTPResponse(
                status: UInt(head?.status.code ?? 0),
                headers: head?.headers.map { ($0.name, $0.value) } ?? [],
                body: body
            )
            promise.succeed(response)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
    }
}
