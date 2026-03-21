# Integration Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add end-to-end integration tests that exercise the full proxy pipeline (client → proxy → echo server), verify database recording with full-chain assertions, and cover HTTP/1.1, HTTP/2, WebSocket, and TLS protocols with/without CA certificates.

**Architecture:** Three test infrastructure components (TestEchoServer, TestProxyLauncher, TestNIOClient) provide reusable setup. Tests organized by protocol, each file self-contained. All servers bind `127.0.0.1:0` for OS-assigned ports. CaptureTask constructed manually to avoid singleton dependencies.

**Tech Stack:** Swift, SwiftNIO, NIOHTTP1, NIOHTTP2, NIOWebSocket, NIOSSL, XCTest

**Spec:** `docs/superpowers/specs/2026-03-21-integration-tests-design.md`

**Note:** This is Plan 1 of 2. Plan 2 (stress tests + script + HTML report) builds on top of this.

---

## File Structure

All test paths relative to `LocalPackages/TunnelServices/Tests/TunnelServicesTests/`.

### New Files
- `Integration/TestInfrastructure/TestEchoServer.swift` — Configurable NIO HTTP/H2/WS/TLS echo server
- `Integration/TestInfrastructure/TestProxyLauncher.swift` — Proxy + DB + CA lifecycle manager
- `Integration/TestInfrastructure/TestNIOClient.swift` — NIO client for sending requests through proxy
- `Integration/HTTP1IntegrationTests.swift` — HTTP/1.1 tests (MITM/tunnel/plain, keep-alive, body, timeline)
- `Integration/HTTP2IntegrationTests.swift` — HTTP/2 tests (multiplexing, push, flow control)
- `Integration/WebSocketIntegrationTests.swift` — WebSocket tests (WSS/WS, masking, frames)
- `Integration/TLSIntegrationTests.swift` — TLS-specific tests (certs, handshake failures, ALPN)
- `Integration/EdgeCaseTests.swift` — ConnectHandler, pool, error recovery

### Modified Files
- `LocalPackages/TunnelServices/Package.swift` — Add `NIOEmbedded` to test target dependencies

---

## Priority Order

| P | Task | Impact |
|---|------|--------|
| P0 | Task 1: Package.swift + TestEchoServer | Foundation — echo server needed by everything |
| P0 | Task 2: TestProxyLauncher | Proxy lifecycle needed by all integration tests |
| P0 | Task 3: TestNIOClient | Client needed to send requests |
| P0 | Task 4: Smoke test — HTTP/1.1 basic request | Validates the entire infrastructure works end-to-end |
| P1 | Task 5: HTTP/1.1 full test suite | Keep-alive, body, timeline, pool reuse, tunnel |
| P1 | Task 6: TLS test suite | Certs, handshake failures, MITM vs tunnel, ALPN |
| P1 | Task 7: HTTP/2 test suite | Multiplexing, push, flow control |
| P1 | Task 8: WebSocket test suite | WSS/WS, masking, frames |
| P2 | Task 9: Edge case tests | ConnectHandler, pool, error recovery |

---

### Task 1: Package.swift + TestEchoServer

**Files:**
- Modify: `LocalPackages/TunnelServices/Package.swift`
- Create: `Tests/TunnelServicesTests/Integration/TestInfrastructure/TestEchoServer.swift`

**Problem:** No test server exists. Need a configurable HTTP/H2/WS echo server that runs in-process.

**Design:** SwiftNIO `ServerBootstrap` binding `127.0.0.1:0`. Supports plain HTTP/1.1 and TLS modes. Echo behavior: returns request body as response body with `200 OK`. Configurable options for Connection header, response delay, and H2 push.

- [ ] **Step 1: Add NIOEmbedded to Package.swift test target**

In `LocalPackages/TunnelServices/Package.swift`, add to the test target dependencies:

```swift
.testTarget(
    name: "TunnelServicesTests",
    dependencies: [
        "TunnelServices",
        .product(name: "NIOEmbedded", package: "swift-nio"),
    ],
    path: "Tests/TunnelServicesTests"
),
```

- [ ] **Step 2: Implement TestEchoServer**

Create `Tests/TunnelServicesTests/Integration/TestInfrastructure/TestEchoServer.swift`:

The server must support these modes:
- `.http1` — plain HTTP/1.1 echo
- `.http1TLS(cert, key)` — HTTPS with ALPN http/1.1
- `.http2TLS(cert, key)` — HTTPS with ALPN h2
- `.webSocket` — plain WS echo
- `.webSocketTLS(cert, key)` — WSS echo

Core structure:
```swift
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL
import NIOWebSocket

final class TestEchoServer {
    enum Mode {
        case http1
        case http1TLS(cert: NIOSSLCertificate, key: NIOSSLPrivateKey)
        case http2TLS(cert: NIOSSLCertificate, key: NIOSSLPrivateKey)
        case webSocket
        case webSocketTLS(cert: NIOSSLCertificate, key: NIOSSLPrivateKey)
    }

    struct Options {
        var connectionHeader: String? = nil       // Override Connection response header
        var pushPromises: [(path: String, body: String)] = []  // H2 push promises to send
        var responseDelay: TimeAmount? = nil       // Delay before responding
        var dropAfterHead: Bool = false            // Simulate crash mid-response
    }

    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    let mode: Mode
    var options: Options

    init(mode: Mode, options: Options = Options()) { ... }
    func start() throws -> Int { ... }  // Returns bound port
    func stop() throws { ... }
}
```

**HTTP/1.1 echo handler:**
- Receives `HTTPServerRequestPart`
- Accumulates body
- On `.end`: responds with `200 OK`, echoes body, respects `options.connectionHeader`

**TLS setup:**
- Create `NIOSSLContext` with provided cert/key
- Add `NIOSSLServerHandler` to pipeline
- For H2: configure ALPN `["h2", "http/1.1"]`, use `ApplicationProtocolNegotiationHandler`

**WebSocket echo handler:**
- Add NIO's WebSocket upgrade handler
- On upgrade: echo received frames back

- [ ] **Step 3: Build to verify compilation**

Run: `swift build --package-path LocalPackages/TunnelServices`
Expected: Build complete

- [ ] **Step 4: Write a minimal test to verify echo server starts**

```swift
// In a temporary test or at the bottom of TestEchoServer.swift
func testEchoServerStarts() throws {
    let server = TestEchoServer(mode: .http1)
    let port = try server.start()
    XCTAssertTrue(port > 0)
    try server.stop()
}
```

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Package.swift \
  LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/
git commit -m "feat: add TestEchoServer with HTTP/1.1, H2, WebSocket, TLS modes"
```

---

### Task 2: TestProxyLauncher

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/TestInfrastructure/TestProxyLauncher.swift`

**Problem:** Integration tests need a fully configured proxy (CaptureTask + ProxyServer + DB + CA) with easy setup/teardown and database query capabilities.

**Design:** Encapsulates the full lifecycle. Constructs CaptureTask manually (not `newTask()`) to avoid singleton dependencies. Generates test CA via `CertGenerator.generateCA()`. Provides query APIs for flow/connection records.

- [ ] **Step 1: Implement TestProxyLauncher**

Core structure:
```swift
import Foundation
import NIO
import NIOSSL
@testable import TunnelServices

final class TestProxyLauncher {
    let sslEnabled: Bool
    let withCA: Bool
    private var proxyServer: ProxyServer?
    private var task: CaptureTask?
    private var dbManager: DatabaseManager?
    private var dbGroup: TaskDatabaseGroup?
    private var tempDir: String
    private var eventLoopGroup: MultiThreadedEventLoopGroup?

    /// The test CA certificate (available after start, nil if withCA=false)
    private(set) var caCertificate: NIOSSLCertificate?

    /// The task's file folder (for payload/cert file assertions)
    var taskFileFolder: String { task?.fileFolder ?? tempDir }

    /// The connection pool (for pool state assertions)
    var connectionPool: OutboundConnectionPool? { task?.connectionPool }

    init(sslEnabled: Bool = true, withCA: Bool = true) {
        self.sslEnabled = sslEnabled
        self.withCA = withCA
        self.tempDir = NSTemporaryDirectory() + "KnotIntegrationTest_\(UUID().uuidString)"
    }

    func start() throws -> Int { ... }
    func stop() { ... }

    // Query APIs
    func queryFlows() throws -> [FlowRecord] { ... }
    func findFlow(host: String) throws -> FlowRecord? { ... }
    func queryConnections() throws -> [TcpConnectionRecord] { ... }
}
```

**start() implementation key points:**
1. Create temp directory
2. If `withCA`: generate test CA via `CertGenerator.generateCA()`, save to temp cert dir, create `CertManager`
3. Construct CaptureTask manually:
   ```swift
   let task = CaptureTask()
   task.id = 1
   task.localIP = "127.0.0.1"
   task.localPort = 0  // OS assigns
   task.localEnable = 1
   task.sslEnable = sslEnabled ? 1 : 0
   task.certManager = certManager  // from step 2
   task.ruleEngine = RuleEngine(config: "")
   task.fileFolder = tempDir + "/task_1"
   ```
4. Initialize `DatabaseManager(rootPath: tempDir)` and `TaskDatabaseGroup`
5. Start ProxyServer on background thread, capture bound port via callback
6. Return port

**stop() implementation:**
- Stop proxy server
- Close database connections
- Remove temp directory

**queryFlows():**
```swift
func queryFlows() throws -> [FlowRecord] {
    guard let group = dbGroup else { return [] }
    return try FlowDAO.query(db: group.proto)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build --package-path LocalPackages/TunnelServices`

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/
git commit -m "feat: add TestProxyLauncher for integration test lifecycle management"
```

---

### Task 3: TestNIOClient

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/TestInfrastructure/TestNIOClient.swift`

**Problem:** Need a NIO-based client that sends HTTP/1.1, HTTPS (via CONNECT), H2, and WebSocket requests through the proxy.

**Design:** Each method creates a `ClientBootstrap`, connects to the proxy, sends the request, waits for response. Synchronous API (`.wait()`) is acceptable in tests. HTTPS uses CONNECT tunnel + TLS with configurable trust.

- [ ] **Step 1: Implement TestNIOClient**

Core structure:
```swift
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL
import NIOWebSocket

struct HTTPResponse {
    let status: UInt
    let headers: [(String, String)]
    let body: Data
}

final class TestNIOClient {
    let proxyHost: String
    let proxyPort: Int
    private let group: MultiThreadedEventLoopGroup

    init(proxyHost: String = "127.0.0.1", proxyPort: Int) {
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    /// Plain HTTP/1.1 request through proxy
    func httpRequest(method: HTTPMethod = .GET, host: String, port: Int,
                     uri: String = "/", body: String? = nil) throws -> HTTPResponse

    /// HTTPS request via CONNECT tunnel (trusts provided CA cert)
    func httpsRequest(method: HTTPMethod = .GET, host: String, port: Int,
                      uri: String = "/", body: String? = nil,
                      trustCA: NIOSSLCertificate?) throws -> HTTPResponse

    /// HTTP/2 request via CONNECT tunnel (ALPN h2)
    func h2Request(host: String, port: Int, uri: String = "/",
                   body: String? = nil, trustCA: NIOSSLCertificate?) throws -> HTTPResponse

    /// Multiple HTTP/1.1 requests on the same connection (keep-alive test)
    func httpKeepAliveRequests(host: String, port: Int,
                               requests: [(method: HTTPMethod, uri: String)]) throws -> [HTTPResponse]

    /// WebSocket connection through proxy
    func webSocketSession(host: String, port: Int, path: String = "/ws",
                          trustCA: NIOSSLCertificate? = nil,
                          handler: (WebSocketTestSession) throws -> Void) throws
}

class WebSocketTestSession {
    func send(_ text: String) throws
    func sendBinary(_ data: Data) throws
    func receive() throws -> WebSocketTestFrame
    func close() throws
}
```

**httpRequest() implementation:**
1. `ClientBootstrap(group:).connect(host: proxyHost, port: proxyPort)`
2. Add HTTP client handlers to pipeline
3. Send `GET http://host:port/uri HTTP/1.1` (absolute URI for proxy)
4. Collect response via handler, return `HTTPResponse`

**httpsRequest() implementation:**
1. Connect to proxy
2. Send `CONNECT host:port HTTP/1.1`
3. Wait for `200 Connection Established`
4. Remove HTTP handlers, add `NIOSSLClientHandler(trustRoots: .certificates([trustCA!]))` + HTTP handlers
5. Send request on the TLS connection
6. Return response

**h2Request() — same as httpsRequest but:**
- ALPN `["h2"]` in TLS config
- After TLS: add `NIOHTTP2Handler(mode: .client)` + `HTTP2StreamMultiplexer`
- Send request on a stream

**webSocketSession():**
- Connect to proxy (plain or via CONNECT for WSS)
- Send HTTP Upgrade request with `Sec-WebSocket-Key`
- Handle `101 Switching Protocols`
- Add WebSocket frame codec
- Call handler closure with `WebSocketTestSession`

- [ ] **Step 2: Build to verify compilation**

Run: `swift build --package-path LocalPackages/TunnelServices`

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/
git commit -m "feat: add TestNIOClient for HTTP/1.1, HTTPS, H2, WebSocket proxy requests"
```

---

### Task 4: Smoke Test — HTTP/1.1 Basic Request

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/HTTP1IntegrationTests.swift`

**Problem:** Need to validate the entire infrastructure works end-to-end before writing the full test suite.

**Design:** One test that starts echo server + proxy, sends a plain HTTP request, verifies the response, checks the database.

- [ ] **Step 1: Write the smoke test**

```swift
import XCTest
@testable import TunnelServices

final class HTTP1IntegrationTests: XCTestCase {

    private var echoServer: TestEchoServer!
    private var launcher: TestProxyLauncher!
    private var client: TestNIOClient!
    private var serverPort: Int!
    private var proxyPort: Int!

    override func setUp() {
        super.setUp()
        // Start echo server
        echoServer = TestEchoServer(mode: .http1)
        serverPort = try! echoServer.start()

        // Start proxy (no SSL for smoke test)
        launcher = try! TestProxyLauncher(sslEnabled: false, withCA: false)
        proxyPort = try! launcher.start()

        // Create client
        client = TestNIOClient(proxyPort: proxyPort)

        addTeardownBlock { [weak self] in
            self?.client = nil
            self?.launcher?.stop()
            try? self?.echoServer?.stop()
        }
    }

    func testHTTP1_Plaintext_BasicRequest() throws {
        let response = try client.httpRequest(
            method: .GET, host: "127.0.0.1", port: serverPort, uri: "/hello"
        )

        // Response assertions
        XCTAssertEqual(response.status, 200)

        // Wait briefly for async DB write
        Thread.sleep(forTimeInterval: 0.5)

        // Database assertions
        let flows = try launcher.queryFlows()
        XCTAssertEqual(flows.count, 1)

        let flow = flows[0]
        XCTAssertEqual(flow.host, "127.0.0.1")
        XCTAssertEqual(flow.protocolName, "HTTP")
        XCTAssertEqual(flow.status, .completed)
        XCTAssertEqual(flow.connReuse, 0)  // new connection
        XCTAssertTrue(flow.uploadBytes > 0)
        XCTAssertTrue(flow.downloadBytes > 0)

        // Timeline assertions
        XCTAssertNotNil(flow.connectAt)
        XCTAssertNotNil(flow.connectedAt)
        if let connectAt = flow.connectAt, let connectedAt = flow.connectedAt {
            XCTAssertTrue(connectedAt > connectAt)
        }
    }
}
```

- [ ] **Step 2: Run the smoke test**

Run: `swift test --package-path LocalPackages/TunnelServices --filter testHTTP1_Plaintext_BasicRequest`
Expected: PASS (this validates all three infrastructure components work together)

- [ ] **Step 3: If it fails, debug and fix infrastructure issues**

Common issues:
- Port not binding (check `127.0.0.1:0` is available)
- CaptureTask missing required fields (ruleEngine, certManager)
- ProxyServer callback not firing (check background thread dispatch)
- DB not initialized (check TaskDatabaseGroup creation)

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/
git commit -m "feat: add HTTP/1.1 smoke test validating full proxy pipeline"
```

---

### Task 5: HTTP/1.1 Full Test Suite

**Files:**
- Modify: `Tests/TunnelServicesTests/Integration/HTTP1IntegrationTests.swift`

**Problem:** Need comprehensive HTTP/1.1 tests covering MITM, tunnel, keep-alive, body, timeline, pool reuse, and hop-by-hop headers.

- [ ] **Step 1: Add HTTPS MITM test setup**

Add a second test class or modify setUp to support SSL mode:
```swift
// Add to HTTP1IntegrationTests or create a subclass
private func setUpWithMITM() throws {
    echoServer = TestEchoServer(mode: .http1TLS(cert: serverCert, key: serverKey))
    serverPort = try echoServer.start()
    launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
    proxyPort = try launcher.start()
    client = TestNIOClient(proxyPort: proxyPort)
}
```

- [ ] **Step 2: Implement MITM tests**

Add these test methods (each calls `setUpWithMITM`):
- `testHTTP1_HTTPS_MITM_BasicRequest` — proto_flags & tlsMITM & tlsHandshakeOK, cert_chain_ref != nil
- `testHTTP1_HTTPS_MITM_POST_WithBody` — uploadBytes > 0, payload files exist with correct content
- `testHTTP1_HTTPS_MITM_CertChain` — PEM file has 2 certs, metadata certChainSummary
- `testHTTP1_HTTPS_MITM_Timeline` — connectAt < connectedAt < tlsDoneAt < reqEndAt < rspStartAt

- [ ] **Step 3: Implement keep-alive tests**

- `testHTTP1_HTTPS_MITM_KeepAlive` — 3 requests via `httpKeepAliveRequests()`, verify conn_reuse=1 on 2nd/3rd, proto_flags & keepAlive & pipelining
- `testHTTP1_HTTPS_MITM_ConnectionClose` — echo server configured with `connectionHeader: "close"`, verify no keepAlive flag

- [ ] **Step 4: Implement tunnel test**

- `testHTTP1_HTTPS_Tunnel_NoCA` — launcher with sslEnabled=false, proto_flags & tlsTunnel, no tlsMITM
- `testHTTP1_HTTPS_Tunnel_DataRelayed` — data passes through, uploadBytes/downloadBytes > 0

- [ ] **Step 5: Implement pool reuse test**

- `testHTTP1_Plaintext_KeepAlive_PoolReuse` — first client → close → second client same host → conn_reuse=2, connReusePoolKey in metadata

- [ ] **Step 6: Implement data integrity tests**

- `testData_LargeBody_1MB` — POST 1MB, verify payload file SHA256
- `testData_EmptyBody` — GET, uploadBytes==0

- [ ] **Step 7: Implement hop-by-hop tests**

- `testHopByHop_StandardHeadersStripped` — add Proxy-Authorization etc to request, verify echo server didn't receive them
- `testHopByHop_UpgradePreservedForWS` — verify WebSocket Upgrade headers survive

- [ ] **Step 8: Run all HTTP/1.1 tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter HTTP1Integration`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/HTTP1IntegrationTests.swift
git commit -m "feat: complete HTTP/1.1 integration test suite (MITM, tunnel, keep-alive, body, timeline)"
```

---

### Task 6: TLS Test Suite

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/TLSIntegrationTests.swift`

- [ ] **Step 1: Implement TLS cert behavior tests**

- `testTLS_MITM_DynamicCertPerHost` — request a.com and b.com, different PEM files, different subjects
- `testTLS_MITM_CertCacheReuse` — same host twice, same cert sha256
- `testTLS_MITM_CertExportPEM` — CertExportService.exportCertChain success, chain length 2

- [ ] **Step 2: Implement handshake failure tests**

- `testTLS_HandshakeFail_UntrustedCA` — client without trustRoots, proto_flags & tlsHandshakeFail
- `testTLS_HandshakeTimeout` — connect but don't send ClientHello, proto_flags & tlsHandshakeTimeout
- `testTLS_NonTLSData` — send plain text to MITM path, error_message contains "not a TLS ClientHello"

- [ ] **Step 3: Implement MITM vs tunnel decision tests**

- `testTLS_SSLEnabled_MITMPath` — sslEnable=1 → tlsMITM, decrypted HTTP visible
- `testTLS_SSLDisabled_TunnelPath` — sslEnable=0 → tlsTunnel, only SNI metadata

- [ ] **Step 4: Implement ALPN tests**

- `testTLS_ALPN_NegotiateH2` — H2 echo server → schemes=H2, alpnNegotiated=h2
- `testTLS_ALPN_FallbackHTTP11` — HTTP/1.1-only server → schemes=Https

- [ ] **Step 5: Run TLS tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter TLSIntegration`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/TLSIntegrationTests.swift
git commit -m "feat: add TLS integration tests (certs, handshake failures, ALPN, MITM vs tunnel)"
```

---

### Task 7: HTTP/2 Test Suite

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/HTTP2IntegrationTests.swift`

- [ ] **Step 1: Implement H2 basic and multiplexing tests**

- `testH2_MITM_BasicRequest` — schemes=H2, proto_flags & h2Multiplexing & tlsMITM
- `testH2_MITM_ConcurrentStreams` — 3 concurrent requests, 3 flows, distinct h2StreamId
- `testH2_MITM_POST_WithBody` — upload/download bytes match, payload files correct
- `testH2_MITM_Timeline` — timeline ordering verified

- [ ] **Step 2: Implement H2 push test**

- `testH2_MITM_ServerPush` — echo server configured with pushPromises, extra flow with schemes=H2-Push, push_status

- [ ] **Step 3: Implement H2 flow control test**

- `testH2_MITM_FlowControl` — send >64KB body, proto_flags & h2FlowControl

- [ ] **Step 4: Implement H2 tunnel test**

- `testH2_Tunnel_NoCA` — sslEnable=0, proto_flags & tlsTunnel, no H2 flags

- [ ] **Step 5: Implement H2 edge cases**

- `testH2_MITM_GRPCContentType` — content-type: application/grpc → schemes=gRPC

- [ ] **Step 6: Run H2 tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter HTTP2Integration`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/HTTP2IntegrationTests.swift
git commit -m "feat: add HTTP/2 integration tests (multiplexing, push, flow control, gRPC)"
```

---

### Task 8: WebSocket Test Suite

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/WebSocketIntegrationTests.swift`

- [ ] **Step 1: Implement WSS MITM tests**

- `testWS_WSS_MITM_UpgradeAndEcho` — schemes=WSS, proto_flags & wsFrameMasked & tlsMITM
- `testWS_WSS_MITM_BinaryFrames` — binary frame round-trip
- `testWS_WSS_MITM_MultipleFrames` — 10 messages, traffic counters accumulate
- `testWS_WSS_MITM_CloseFrame` — close handshake, status=completed

- [ ] **Step 2: Implement WS plain tests**

- `testWS_Plaintext_UpgradeAndEcho` — schemes=WS, proto_flags & wsFrameMasked
- `testWS_Plaintext_MaskingDirection` — echo server checks received frames are masked

- [ ] **Step 3: Implement WS tunnel test**

- `testWS_WSS_Tunnel_NoCA` — proto_flags & tlsTunnel, no wsFrameMasked

- [ ] **Step 4: Implement WS edge cases**

- `testWS_LargeFrame` — >128KB frame, no truncation

- [ ] **Step 5: Run WebSocket tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter WebSocketIntegration`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/WebSocketIntegrationTests.swift
git commit -m "feat: add WebSocket integration tests (WSS, WS, masking, frames)"
```

---

### Task 9: Edge Case Tests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/EdgeCaseTests.swift`

- [ ] **Step 1: Implement ConnectHandler tests**

- `testConnectHandler_CONNECTResponse200` — CONNECT → 200 → TLS succeeds
- `testConnectHandler_NonCONNECT_PassThrough` — plain GET passes through to HTTPCaptureHandler
- `testConnectHandler_InvalidHost` — CONNECT to unreachable → status=failed

- [ ] **Step 2: Implement connection pool tests**

- `testPool_IdleEviction` — checkin → close channel → evictExpired() → count == 0
- `testPool_MaxPerKey` — 7 channels to same host → count <= 6
- `testPool_TotalCapacity` — fill to 32 → next checkin rejected

- [ ] **Step 3: Implement error recovery tests**

- `testError_ServerDropsConnection` — server closes mid-response → status=failed, recorder closed
- `testError_ClientDropsMidRequest` — client disconnects after head → status=failed
- `testError_ServerSlowResponse` — 5s delay → still completes, rspStartAt - reqEndAt > 4s

- [ ] **Step 4: Run edge case tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter EdgeCase`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/EdgeCaseTests.swift
git commit -m "feat: add edge case integration tests (ConnectHandler, pool, error recovery)"
```

---

## Post-Implementation Verification

After all tasks:

1. **Build**: `swift build --package-path LocalPackages/TunnelServices` — pass
2. **All tests**: `swift test --package-path LocalPackages/TunnelServices` — all pass (existing 215 + new ~55 integration tests)
3. **Integration only**: `swift test --package-path LocalPackages/TunnelServices --filter Integration` — all pass
4. **Per-protocol**: Each `--filter HTTP1Integration`, `HTTP2Integration`, `WebSocketIntegration`, `TLSIntegration`, `EdgeCase` runs independently
5. **No port leaks**: No test leaves bound ports after tearDown (verified by `addTeardownBlock`)
6. **No temp file leaks**: No test leaves temp directories (verified by `addTeardownBlock`)
