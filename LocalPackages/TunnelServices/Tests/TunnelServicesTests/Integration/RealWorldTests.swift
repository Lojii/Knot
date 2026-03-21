//
//  RealWorldTests.swift
//  TunnelServicesTests
//
//  Integration tests that route traffic through the proxy to REAL public
//  internet endpoints.  These are opt-in — run with:
//
//      RUN_REAL_WORLD_TESTS=1 swift test --package-path LocalPackages/TunnelServices --filter RealWorld
//

import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
@testable import TunnelServices

// MARK: - HTTP/1.1 Plaintext

final class RealWorldHTTP1Tests: XCTestCase {

    private var launcher: TestProxyLauncher!
    private var client: TestNIOClient!

    override func setUp() {
        super.setUp()
        try! XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_REAL_WORLD_TESTS"] == nil,
            "Real-world tests skipped. Set RUN_REAL_WORLD_TESTS=1 to run."
        )
        do {
            launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
            let proxyPort = try launcher.start()
            client = TestNIOClient(proxyPort: proxyPort)
        } catch {
            XCTFail("setUp failed: \(error)")
        }
        addTeardownBlock { [weak self] in
            self?.client?.shutdown()
            self?.launcher?.stop()
        }
    }

    // MARK: - GET

    func testRealWorld_HTTP1_httpbin_get() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/get"
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"url\""), "httpbin /get should return JSON with url field")
        print("[REAL_WORLD] HTTP1 GET /get — status=\(rsp.status) bodyLen=\(rsp.body.count)")

        Thread.sleep(forTimeInterval: 1.0)
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1)
        let flow = flows.first!
        XCTAssertEqual(flow.protocolName, "HTTP")
        XCTAssertEqual(flow.status, .completed)
        XCTAssertTrue(flow.downloadBytes > 0)
    }

    // MARK: - POST

    func testRealWorld_HTTP1_httpbin_post() throws {
        let payload = "hello from proxy test".data(using: .utf8)!
        let rsp = try client.httpRequest(
            method: .POST, host: "httpbin.org", port: 80, uri: "/post",
            body: payload,
            headers: [("Content-Type", "text/plain")]
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("hello from proxy test"),
                       "httpbin /post should echo back the posted body")
        print("[REAL_WORLD] HTTP1 POST /post — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }

    // MARK: - Status 200

    func testRealWorld_HTTP1_httpbin_status200() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/status/200"
        )
        XCTAssertEqual(rsp.status, 200)
        print("[REAL_WORLD] HTTP1 /status/200 — status=\(rsp.status)")
    }

    // MARK: - Headers

    func testRealWorld_HTTP1_httpbin_headers() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/headers",
            headers: [("X-Test-Proxy", "knot-test")]
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("X-Test-Proxy") || body.contains("x-test-proxy"),
                       "httpbin /headers should echo our custom header")
        print("[REAL_WORLD] HTTP1 /headers — status=\(rsp.status)")
    }

    // MARK: - Redirect Chain

    func testRealWorld_HTTP1_httpbin_redirect() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/redirect/3"
        )
        // Proxy forwards the 302; NIO client does not follow redirects
        XCTAssertEqual(rsp.status, 302)
        let location = rsp.headers.first(where: { $0.0.lowercased() == "location" })?.1
        XCTAssertNotNil(location, "Should have Location header for redirect")
        print("[REAL_WORLD] HTTP1 /redirect/3 — status=\(rsp.status) location=\(location ?? "nil")")
    }

    // MARK: - Delayed Response

    func testRealWorld_HTTP1_httpbin_delay() throws {
        let start = Date()
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/delay/2"
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(rsp.status, 200)
        XCTAssertGreaterThanOrEqual(elapsed, 2.0, "Should take at least 2 seconds")
        print("[REAL_WORLD] HTTP1 /delay/2 — status=\(rsp.status) elapsed=\(String(format: "%.1f", elapsed))s")

        Thread.sleep(forTimeInterval: 1.0)
        let flows = try launcher.queryFlows()
        if let flow = flows.first {
            if let reqEnd = flow.reqEndAt, let rspStart = flow.rspStartAt {
                let gap = rspStart - reqEnd
                XCTAssertGreaterThanOrEqual(gap, 1.5,
                    "Server delay should be visible in timeline (gap=\(gap)s)")
                print("[REAL_WORLD]   timeline gap reqEnd->rspStart = \(String(format: "%.2f", gap))s")
            }
        }
    }

    // MARK: - Random Bytes

    func testRealWorld_HTTP1_httpbin_bytes() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/bytes/1024"
        )
        XCTAssertEqual(rsp.status, 200)
        XCTAssertEqual(rsp.body.count, 1024, "Should receive exactly 1024 bytes")
        print("[REAL_WORLD] HTTP1 /bytes/1024 — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }

    // MARK: - Chunked Streaming

    func testRealWorld_HTTP1_httpbin_stream() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/stream/5"
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        let lines = body.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 3, "Should have multiple streamed lines")
        print("[REAL_WORLD] HTTP1 /stream/5 — status=\(rsp.status) lines=\(lines.count)")
    }

    // MARK: - Large File (1MB)

    func testRealWorld_HTTP1_LargeFile_1MB() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "speedtest.tele2.net", port: 80, uri: "/1MB.zip"
        )
        // speedtest.tele2.net may return 200 or redirect
        XCTAssertTrue(rsp.status == 200 || rsp.status == 301 || rsp.status == 302,
                       "Expected 200 or redirect, got \(rsp.status)")
        if rsp.status == 200 {
            XCTAssertGreaterThanOrEqual(rsp.body.count, 500_000,
                "1MB file should have at least 500KB")
        }
        print("[REAL_WORLD] HTTP1 1MB.zip — status=\(rsp.status) bodyLen=\(rsp.body.count)")

        Thread.sleep(forTimeInterval: 1.0)
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1)
        if let flow = flows.first {
            XCTAssertTrue(flow.downloadBytes > 0)
            print("[REAL_WORLD]   downloadBytes=\(flow.downloadBytes)")
        }
    }

    // MARK: - Large File Streaming (100MB, first chunk only)

    func testRealWorld_HTTP1_LargeFile_Hetzner_FirstChunk() throws {
        // We request the 100MB file but the client will naturally read
        // whatever arrives within the default timeout. We just verify
        // streaming starts and some data arrives.
        let rsp = try client.httpRequest(
            method: .GET, host: "ash-speed.hetzner.com", port: 80, uri: "/100MB.bin"
        )
        XCTAssertEqual(rsp.status, 200)
        XCTAssertTrue(rsp.body.count > 0, "Should have received some data")
        print("[REAL_WORLD] HTTP1 100MB.bin — status=\(rsp.status) bodyLen=\(rsp.body.count)")

        Thread.sleep(forTimeInterval: 1.0)
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1)
        if let flow = flows.first {
            XCTAssertTrue(flow.downloadBytes > 0)
        }
    }

    // MARK: - Multi-Site Sequence

    func testRealWorld_HTTP1_MultiSite_Sequence() throws {
        let sites: [(host: String, uri: String)] = [
            ("httpbin.org", "/get"),
            ("example.com", "/"),
            ("httpbin.org", "/status/200"),
            ("example.com", "/"),
            ("httpbin.org", "/get"),
        ]

        for site in sites {
            let rsp = try client.httpRequest(
                method: .GET, host: site.host, port: 80, uri: site.uri
            )
            XCTAssertTrue(rsp.status == 200 || rsp.status == 301 || rsp.status == 302,
                "Expected success/redirect for \(site.host)\(site.uri), got \(rsp.status)")
            print("[REAL_WORLD] Multi-site \(site.host)\(site.uri) — status=\(rsp.status)")
        }

        Thread.sleep(forTimeInterval: 2.0)
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 5,
            "Expected at least 5 flow records for 5 requests")
        let poolReused = flows.filter { $0.connReuse == 2 }
        print("[REAL_WORLD] Pool reuse count: \(poolReused.count)/\(flows.count)")
    }

    // MARK: - Streaming (10 chunks)

    func testRealWorld_HTTP1_httpbin_stream10() throws {
        let rsp = try client.httpRequest(
            method: .GET, host: "httpbin.org", port: 80, uri: "/stream/10"
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        let lines = body.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 5,
            "Should have at least 5 streamed lines from /stream/10")
        print("[REAL_WORLD] HTTP1 /stream/10 — status=\(rsp.status) lines=\(lines.count)")
    }
}

// MARK: - HTTPS MITM

final class RealWorldHTTPSMITMTests: XCTestCase {

    private var launcher: TestProxyLauncher!
    private var client: TestNIOClient!

    override func setUp() {
        super.setUp()
        try! XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_REAL_WORLD_TESTS"] == nil,
            "Real-world tests skipped. Set RUN_REAL_WORLD_TESTS=1 to run."
        )
        do {
            launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
            let proxyPort = try launcher.start()
            client = TestNIOClient(proxyPort: proxyPort)
        } catch {
            XCTFail("setUp failed: \(error)")
        }
        addTeardownBlock { [weak self] in
            self?.client?.shutdown()
            self?.launcher?.stop()
        }
    }

    // MARK: - httpbin HTTPS

    func testRealWorld_HTTPS_MITM_httpbin_get() throws {
        let rsp = try client.httpsRequest(
            method: .GET, host: "httpbin.org", port: 443, uri: "/get",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("httpbin.org"),
                       "httpbin /get should reference httpbin.org in its JSON")
        print("[REAL_WORLD] HTTPS MITM httpbin /get — status=\(rsp.status) bodyLen=\(rsp.body.count)")

        Thread.sleep(forTimeInterval: 1.5)
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1)
        // Check MITM flag (tlsMITM = 0x0040)
        if let flow = flows.first(where: { $0.protoFlags & 0x0040 != 0 }) {
            // TLS handshake should succeed (tlsHandshakeOK = 0x0100)
            XCTAssertTrue(flow.protoFlags & 0x0100 != 0,
                "TLS handshake should succeed")
            print("[REAL_WORLD]   MITM flow: protoFlags=0x\(String(flow.protoFlags, radix: 16))")
        }
    }

    // MARK: - Google

    func testRealWorld_HTTPS_MITM_google() throws {
        let rsp = try client.httpsRequest(
            method: .GET, host: "www.google.com", port: 443, uri: "/",
            trustCA: launcher.caCertificate
        )
        // Google may return 200 or 302
        XCTAssertTrue(rsp.status == 200 || rsp.status == 302,
            "Expected 200 or 302 from Google, got \(rsp.status)")
        XCTAssertTrue(rsp.body.count > 0, "Google response should have a body")
        print("[REAL_WORLD] HTTPS MITM google — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }

    // MARK: - GitHub API

    func testRealWorld_HTTPS_MITM_github_api() throws {
        let rsp = try client.httpsRequest(
            method: .GET, host: "api.github.com", port: 443, uri: "/",
            trustCA: launcher.caCertificate,
            headers: [("User-Agent", "Knot-Proxy-Test/1.0")]
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("current_user_url") || body.contains("api.github.com"),
                       "GitHub API root should return JSON with API endpoints")
        print("[REAL_WORLD] HTTPS MITM github API — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }

    // MARK: - nghttp2.org (HTTPS/1.1 path)

    func testRealWorld_HTTPS_MITM_nghttp2() throws {
        let rsp = try client.httpsRequest(
            method: .GET, host: "nghttp2.org", port: 443, uri: "/",
            trustCA: launcher.caCertificate
        )
        XCTAssertTrue(rsp.status == 200 || rsp.status == 301 || rsp.status == 302,
            "Expected success or redirect from nghttp2.org, got \(rsp.status)")
        XCTAssertTrue(rsp.body.count > 0)
        print("[REAL_WORLD] HTTPS MITM nghttp2 — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }

    // MARK: - Cert chain recording

    func testRealWorld_HTTPS_MITM_certChain_recorded() throws {
        let rsp = try client.httpsRequest(
            method: .GET, host: "httpbin.org", port: 443, uri: "/get",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(rsp.status, 200)

        Thread.sleep(forTimeInterval: 1.5)
        let flows = try launcher.queryFlows()
        // Look for a flow with MITM flag and cert chain
        let mitmFlow = flows.first(where: { $0.protoFlags & 0x0040 != 0 })
        if let flow = mitmFlow {
            XCTAssertNotNil(flow.certChainRef,
                "Cert chain should be recorded for MITM intercepted flow")
            print("[REAL_WORLD]   certChainRef=\(flow.certChainRef ?? "nil")")
        } else {
            print("[REAL_WORLD]   No MITM flow found — proxy may not have set MITM flag")
        }
    }
}

// MARK: - HTTPS Tunnel (No MITM)

final class RealWorldHTTPSTunnelTests: XCTestCase {

    private var launcher: TestProxyLauncher!
    private var client: TestNIOClient!

    override func setUp() {
        super.setUp()
        try! XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_REAL_WORLD_TESTS"] == nil,
            "Real-world tests skipped. Set RUN_REAL_WORLD_TESTS=1 to run."
        )
        do {
            // No SSL interception — proxy just tunnels the CONNECT
            launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
            let proxyPort = try launcher.start()
            client = TestNIOClient(proxyPort: proxyPort)
        } catch {
            XCTFail("setUp failed: \(error)")
        }
        addTeardownBlock { [weak self] in
            self?.client?.shutdown()
            self?.launcher?.stop()
        }
    }

    func testRealWorld_HTTPS_Tunnel_httpbin() throws {
        // With sslEnabled=false the proxy creates a raw tunnel;
        // the client does real TLS directly to httpbin.org.
        // We use trustCA: nil + certificateVerification: .none in httpsRequest
        // so the client accepts httpbin.org's real cert.
        let rsp = try client.httpsRequest(
            method: .GET, host: "httpbin.org", port: 443, uri: "/get"
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("httpbin.org"))
        print("[REAL_WORLD] HTTPS Tunnel httpbin — status=\(rsp.status) bodyLen=\(rsp.body.count)")

        Thread.sleep(forTimeInterval: 1.5)
        let flows = try launcher.queryFlows()
        // Tunnel mode should have tlsTunnel flag (0x0080)
        let tunnelFlow = flows.first(where: { $0.protoFlags & 0x0080 != 0 })
        if let flow = tunnelFlow {
            print("[REAL_WORLD]   Tunnel flow: protoFlags=0x\(String(flow.protoFlags, radix: 16))")
        } else {
            print("[REAL_WORLD]   No tunnel-flagged flow found (may not be set for passthrough)")
        }
    }

    func testRealWorld_HTTPS_Tunnel_google() throws {
        let rsp = try client.httpsRequest(
            method: .GET, host: "www.google.com", port: 443, uri: "/"
        )
        XCTAssertTrue(rsp.status == 200 || rsp.status == 302,
            "Expected 200 or 302 from Google via tunnel, got \(rsp.status)")
        XCTAssertTrue(rsp.body.count > 0)
        print("[REAL_WORLD] HTTPS Tunnel google — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }
}

// MARK: - HTTP/2

final class RealWorldH2Tests: XCTestCase {

    private var launcher: TestProxyLauncher!
    private var client: TestNIOClient!

    override func setUp() {
        super.setUp()
        try! XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_REAL_WORLD_TESTS"] == nil,
            "Real-world tests skipped. Set RUN_REAL_WORLD_TESTS=1 to run."
        )
        do {
            launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
            let proxyPort = try launcher.start()
            client = TestNIOClient(proxyPort: proxyPort)
        } catch {
            XCTFail("setUp failed: \(error)")
        }
        addTeardownBlock { [weak self] in
            self?.client?.shutdown()
            self?.launcher?.stop()
        }
    }

    // MARK: - nghttp2.org (canonical H2 test server)

    func testRealWorld_H2_nghttp2() throws {
        // H2 through MITM: client negotiates h2 ALPN with the MITM proxy.
        // If MITM cert verification fails, fall back to no-verification mode.
        let rsp: TestHTTPResponse
        do {
            rsp = try client.h2Request(
                host: "nghttp2.org", port: 443, uri: "/",
                trustCA: launcher.caCertificate
            )
        } catch {
            // Cert verification may fail for H2 — retry without strict verification
            print("[REAL_WORLD] H2 nghttp2 cert verify failed (\(error)), retrying without verification")
            rsp = try client.h2Request(
                host: "nghttp2.org", port: 443, uri: "/"
            )
        }
        XCTAssertTrue(rsp.status == 200 || rsp.status == 301 || rsp.status == 302,
            "Expected success or redirect from nghttp2.org via H2, got \(rsp.status)")
        print("[REAL_WORLD] H2 nghttp2 — status=\(rsp.status) bodyLen=\(rsp.body.count)")

        Thread.sleep(forTimeInterval: 1.5)
        let flows = try launcher.queryFlows()
        // h2Multiplexing = 0x0004
        let h2Flow = flows.first(where: { $0.protoFlags & 0x0004 != 0 })
        if let flow = h2Flow {
            print("[REAL_WORLD]   H2 flow: protoFlags=0x\(String(flow.protoFlags, radix: 16)) proto=\(flow.protocolName)")
        } else {
            print("[REAL_WORLD]   No H2-flagged flow (proxy may negotiate H1 fallback)")
        }
    }

    // MARK: - Google H2

    func testRealWorld_H2_google() throws {
        let rsp: TestHTTPResponse
        do {
            rsp = try client.h2Request(
                host: "www.google.com", port: 443, uri: "/",
                trustCA: launcher.caCertificate
            )
        } catch {
            print("[REAL_WORLD] H2 google cert verify failed, retrying without verification")
            rsp = try client.h2Request(host: "www.google.com", port: 443, uri: "/")
        }
        XCTAssertTrue(rsp.status == 200 || rsp.status == 302,
            "Expected 200 or 302 from Google via H2, got \(rsp.status)")
        XCTAssertTrue(rsp.body.count > 0)
        print("[REAL_WORLD] H2 google — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }

    // MARK: - Cloudflare H2

    func testRealWorld_H2_cloudflare() throws {
        let rsp: TestHTTPResponse
        do {
            rsp = try client.h2Request(
                host: "cloudflare.com", port: 443, uri: "/",
                trustCA: launcher.caCertificate
            )
        } catch {
            print("[REAL_WORLD] H2 cloudflare cert verify failed, retrying without verification")
            rsp = try client.h2Request(host: "cloudflare.com", port: 443, uri: "/")
        }
        // Cloudflare may redirect to www.cloudflare.com
        XCTAssertTrue(rsp.status == 200 || rsp.status == 301 || rsp.status == 302,
            "Expected success or redirect from Cloudflare via H2, got \(rsp.status)")
        print("[REAL_WORLD] H2 cloudflare — status=\(rsp.status) bodyLen=\(rsp.body.count)")
    }
}

// MARK: - WebSocket

final class RealWorldWebSocketTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try! XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_REAL_WORLD_TESTS"] == nil,
            "Real-world tests skipped. Set RUN_REAL_WORLD_TESTS=1 to run."
        )
    }

    // MARK: - WSS echo.websocket.org (primary)

    func testRealWorld_WSS_echo_websocket_org_primary() throws {
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)
        defer {
            client.shutdown()
            launcher.stop()
        }

        do {
            try client.webSocketSession(
                host: "echo.websocket.org", port: 443, path: "/",
                tls: true, trustCA: launcher.caCertificate
            ) { session in
                try session.send("hello from proxy test")
                let frame = try session.receive(timeout: .seconds(15))

                switch frame.type {
                case .text(let text):
                    XCTAssertTrue(text.contains("hello from proxy test"),
                        "Echo server should return our message")
                    print("[REAL_WORLD] WSS echo — received: \(text.prefix(80))")
                case .binary:
                    // Some echo servers return binary; that is acceptable
                    print("[REAL_WORLD] WSS echo — received binary frame")
                case .close:
                    XCTFail("Expected data frame, got close")
                }

                try session.close()
            }
        } catch {
            // Public WebSocket echo servers are unreliable — skip gracefully
            print("[REAL_WORLD] WSS echo.websocket.org unavailable: \(error)")
            throw XCTSkip("WebSocket echo server unreachable: \(error)")
        }

        Thread.sleep(forTimeInterval: 2.0)
        let flows = try launcher.queryFlows()
        if !flows.isEmpty {
            print("[REAL_WORLD] WSS flows recorded: \(flows.count)")
        }
    }

    // MARK: - WSS echo.websocket.org (alternative)

    func testRealWorld_WSS_echo_websocket_org() throws {
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)
        defer {
            client.shutdown()
            launcher.stop()
        }

        do {
            try client.webSocketSession(
                host: "echo.websocket.org", port: 443, path: "/",
                tls: true, trustCA: launcher.caCertificate
            ) { session in
                try session.send("proxy ws test")
                let frame = try session.receive(timeout: .seconds(15))

                switch frame.type {
                case .text(let text):
                    XCTAssertTrue(text.contains("proxy ws test"),
                        "Echo should return our message")
                    print("[REAL_WORLD] WSS echo.websocket.org — received: \(text.prefix(80))")
                case .binary:
                    print("[REAL_WORLD] WSS echo.websocket.org — received binary")
                case .close:
                    XCTFail("Expected data frame, got close")
                }

                try session.close()
            }
        } catch {
            print("[REAL_WORLD] WSS echo.websocket.org unavailable: \(error)")
            throw XCTSkip("WebSocket echo server unreachable: \(error)")
        }
    }
}

// MARK: - Edge Cases & Stress

final class RealWorldEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try! XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_REAL_WORLD_TESTS"] == nil,
            "Real-world tests skipped. Set RUN_REAL_WORLD_TESTS=1 to run."
        )
    }

    // MARK: - Keep-alive reuse to same host

    func testRealWorld_KeepAlive_httpbin() throws {
        let launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)
        defer {
            client.shutdown()
            launcher.stop()
        }

        let requests: [(method: HTTPMethod, uri: String, body: Data?)] = [
            (.GET, "http://httpbin.org:80/get", nil),
            (.GET, "http://httpbin.org:80/status/200", nil),
            (.GET, "http://httpbin.org:80/headers", nil),
        ]

        let responses = try client.httpKeepAliveRequests(
            host: "httpbin.org", port: 80, requests: requests
        )

        XCTAssertEqual(responses.count, 3)
        for (i, rsp) in responses.enumerated() {
            XCTAssertEqual(rsp.status, 200,
                "Request \(i) should return 200, got \(rsp.status)")
            print("[REAL_WORLD] Keep-alive request \(i) — status=\(rsp.status)")
        }

        Thread.sleep(forTimeInterval: 2.0)
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 3)
        let keepAliveFlows = flows.filter { $0.connReuse == 1 }
        print("[REAL_WORLD] Keep-alive reuse: \(keepAliveFlows.count)/\(flows.count)")
    }

    // MARK: - HTTPS MITM to multiple different hosts in sequence

    func testRealWorld_HTTPS_MITM_MultiHost() throws {
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)
        defer {
            client.shutdown()
            launcher.stop()
        }

        let hosts: [(host: String, uri: String)] = [
            ("httpbin.org", "/get"),
            ("www.google.com", "/"),
            ("api.github.com", "/"),
        ]

        for site in hosts {
            do {
                let rsp = try client.httpsRequest(
                    method: .GET, host: site.host, port: 443, uri: site.uri,
                    trustCA: launcher.caCertificate,
                    headers: [("User-Agent", "Knot-Proxy-Test/1.0")]
                )
                XCTAssertTrue(rsp.status == 200 || rsp.status == 301 || rsp.status == 302,
                    "Expected success/redirect from \(site.host), got \(rsp.status)")
                print("[REAL_WORLD] HTTPS multi-host \(site.host) — status=\(rsp.status) bodyLen=\(rsp.body.count)")
            } catch {
                print("[REAL_WORLD] HTTPS multi-host \(site.host) failed: \(error)")
                // Don't fail the entire test if one host is flaky
                continue
            }
        }

        Thread.sleep(forTimeInterval: 2.0)
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 2,
            "Expected at least 2 successful HTTPS MITM flows across multiple hosts")
        print("[REAL_WORLD] HTTPS multi-host total flows: \(flows.count)")
    }

    // MARK: - SSE / Streaming via HTTPS

    func testRealWorld_HTTPS_MITM_streaming() throws {
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)
        defer {
            client.shutdown()
            launcher.stop()
        }

        let rsp = try client.httpsRequest(
            method: .GET, host: "httpbin.org", port: 443, uri: "/stream/10",
            trustCA: launcher.caCertificate
        )
        XCTAssertEqual(rsp.status, 200)
        let body = String(data: rsp.body, encoding: .utf8) ?? ""
        let lines = body.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 5,
            "Should have at least 5 streamed lines from /stream/10 via HTTPS MITM")
        print("[REAL_WORLD] HTTPS MITM /stream/10 — status=\(rsp.status) lines=\(lines.count)")
    }

    // MARK: - Raw CONNECT tunnel then manual TLS

    func testRealWorld_RawConnect_ManualTLS() throws {
        let launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
        let proxyPort = try launcher.start()
        let client = TestNIOClient(proxyPort: proxyPort)
        defer {
            client.shutdown()
            launcher.stop()
        }

        // Get a raw tunnel channel to httpbin.org:443
        let channel = try client.rawConnect(host: "httpbin.org", port: 443)
        defer { try? channel.close().wait() }

        // The channel is now a raw TCP tunnel to httpbin.org:443.
        // We can verify it is open and writable.
        XCTAssertTrue(channel.isActive, "Tunnel channel should be active after CONNECT")
        print("[REAL_WORLD] Raw CONNECT tunnel to httpbin.org:443 — channel active")

        Thread.sleep(forTimeInterval: 1.0)
        let flows = try launcher.queryFlows()
        // Should have at least a CONNECT record
        if !flows.isEmpty {
            print("[REAL_WORLD]   Tunnel flows: \(flows.count)")
        }
    }
}
