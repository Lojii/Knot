# Integration Tests Design

**Goal:** Add end-to-end integration tests for TunnelServices that exercise the full proxy pipeline (client → proxy → echo server), verify database recording, protocol feature preservation, and system behavior under stress — with an easy-to-run script and HTML test report.

**Approach:** Internal NIO echo server + NIO client, both in-process. Tests organized by protocol. Three stress levels with memory profiling. Shell script runner with HTML report generation.

---

## Important Technical Constraints

### CaptureTask Construction

`CaptureTask.newTask()` depends on `DatabaseManager.shared` and `UserDefaults`. Tests MUST construct `CaptureTask()` manually (empty init) and set fields directly:

```swift
let task = CaptureTask()
task.id = 1
task.localIP = "127.0.0.1"
task.localPort = 0  // will be set after bind
task.sslEnable = 1
task.certManager = testCertManager
task.ruleEngine = RuleEngine(config: "")
task.fileFolder = tempDir
```

Do NOT use `newTask()`, `save()`, or `update()` — they touch the shared singleton.

### ProxyServer Blocking Start

`ProxyServer.startServer()` calls `closeFuture.wait()` which blocks. `TestProxyLauncher.start()` must dispatch the proxy start to a background thread and use a semaphore or promise to return the bound port:

```swift
func start() throws -> Int {
    let portPromise = eventLoopGroup.next().makePromise(of: Int.self)
    DispatchQueue.global().async {
        self.proxyServer.start(task: self.task) { port in
            portPromise.succeed(port)
        }
    }
    return try portPromise.futureResult.wait()
}
```

### CertGenerator Signing Key

`CertGenerator.generateCert` signs leaf certs with `rsaKey`. If this key differs from `caKey`, the chain won't validate normally. The test CA must use the same key for CA and leaf signing. If this causes TLS failures, the test NIO client can configure `certificateVerification: .none` as a fallback, but the preferred fix is ensuring the signing key matches.

### WebSocket Client Complexity

NIO does not provide a client-side WebSocket handshake implementation. `TestNIOClient.webSocketConnect()` must implement the full HTTP/1.1 Upgrade handshake (~200-300 lines):
- Send `GET / HTTP/1.1` with `Connection: Upgrade`, `Upgrade: websocket`, `Sec-WebSocket-Key`
- Handle `101 Switching Protocols`
- Install `WebSocketFrameEncoder` + `WebSocketFrameDecoder`
- All through the CONNECT tunnel for WSS

### Out of Scope

- SOCKS5 integration tests (protocol exists but not priority)
- DNS/QUIC integration tests (UDP-based, separate architecture)
- These can be added in future iterations.

---

## Test Infrastructure (3 Core Components)

### TestEchoServer

A configurable NIO server started within the test process. Binds `127.0.0.1:0` (OS-assigned port) to avoid conflicts.

**Modes:**
- `.http1` — Plain HTTP/1.1 echo (returns request body as response body)
- `.http1TLS(cert, key)` — HTTP/1.1 over TLS, ALPN `http/1.1`
- `.http2TLS(cert, key)` — HTTP/2 over TLS, ALPN `h2`
- `.webSocket` — WebSocket echo (returns received frames)
- `.webSocketTLS(cert, key)` — WSS echo

**Configurable behaviors** (via `EchoServerOptions`):
- `connectionHeader: String?` — override response `Connection` header (test keep-alive/close)
- `pushPromises: [(path: String, body: String)]` — H2 push promises to send
- `responseDelay: TimeAmount?` — delay before responding (timeout tests)
- `maxConcurrentStreams: Int?` — H2 SETTINGS limit
- `dropConnectionAfterHead: Bool` — simulate server crash mid-response

**Lifecycle:** `start() throws -> Int` (returns port) / `stop()`

### TestProxyLauncher

Encapsulates CaptureTask + ProxyServer + DB + CA lifecycle:

```swift
let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
let proxyPort = try launcher.start()

// After test:
let flows = try launcher.queryFlows()             // [FlowRecord]
let connections = try launcher.queryConnections()  // [TcpConnectionRecord]
let flow = try launcher.findFlow(host: "example.com")
launcher.stop()
```

**Internal setup:**
1. Temp directory via `StorageTestHelper`
2. `CertGenerator.generateCA()` → test CA (when `withCA: true`)
3. CaptureTask: `localIP=127.0.0.1`, dynamic port, configured sslEnable/certManager
4. `DatabaseManager(rootPath: tempDir)` + `TaskDatabaseGroup`
5. `ProxyServer.start(task:)`
6. Query APIs read directly from `protocol.db` / `connection.db`
7. Cleanup on `stop()`: proxy shutdown + temp directory removal

**Exposed for assertions:**
- `caCertificate: NIOSSLCertificate?` — for client trust configuration
- `taskFileFolder: String` — for payload/cert file assertions
- `connectionPool: OutboundConnectionPool` — for pool state assertions

### TestNIOClient

NIO-based client for sending requests through the proxy:

```swift
let client = TestNIOClient(proxyHost: "127.0.0.1", proxyPort: proxyPort)

// HTTP/1.1 plaintext
let rsp = try client.httpRequest(method: .GET, host: "echo.test", port: serverPort, uri: "/hello")

// HTTPS via CONNECT (trust test CA)
let rsp = try client.httpsRequest(method: .POST, host: "secure.test", port: serverPort,
                                   uri: "/api", body: "data", trustCA: launcher.caCertificate)

// HTTP/2 via CONNECT
let rsp = try client.h2Request(host: "h2.test", port: serverPort, uri: "/stream",
                                trustCA: launcher.caCertificate)

// WebSocket
let ws = try client.webSocketConnect(host: "ws.test", port: serverPort, path: "/ws")
ws.send("hello")
let reply = ws.receive()
ws.close()
```

All methods synchronous (`.wait()`) — acceptable in test context. Each method handles CONNECT tunnel setup, TLS handshake, ALPN negotiation internally.

---

## Test Files

```
Tests/TunnelServicesTests/Integration/
├── TestInfrastructure/
│   ├── TestEchoServer.swift
│   ├── TestProxyLauncher.swift
│   └── TestNIOClient.swift
├── HTTP1IntegrationTests.swift
├── HTTP2IntegrationTests.swift
├── WebSocketIntegrationTests.swift
├── TLSIntegrationTests.swift
├── EdgeCaseTests.swift
└── StressTests.swift
```

---

## HTTP/1.1 Integration Tests

### HTTPS + MITM (with CA)

| Test | Assertions |
|------|-----------|
| `testHTTP1_HTTPS_MITM_BasicRequest` | flow: `protocol=HTTPS`, `status=completed`, `proto_flags & tlsMITM`, `proto_flags & tlsHandshakeOK`, `cert_chain_ref != nil` |
| `testHTTP1_HTTPS_MITM_POST_WithBody` | `uploadBytes > 0`, `downloadBytes > 0`, `req_payload_ref` file exists with correct content, `rsp_payload_ref` file exists |
| `testHTTP1_HTTPS_MITM_KeepAlive` | 3 requests on same connection → 3 flow records, 2nd/3rd `conn_reuse=1`, `proto_flags & keepAlive`, `proto_flags & pipelining`, metadata `keepAliveRequestIndex` = 1, 2 |
| `testHTTP1_HTTPS_MITM_ConnectionClose` | Server returns `Connection: close` → `proto_flags & keepAlive` = 0, connection closed |
| `testHTTP1_HTTPS_MITM_CertChain` | `cert_chain_ref` → PEM file with 2 certs (leaf + CA), metadata `certChainSummary` has subject/issuer/sha256 |
| `testHTTP1_HTTPS_MITM_Timeline` | `connectAt < connectedAt < tlsDoneAt < reqEndAt < rspStartAt < endedAt`, all non-nil |

### HTTPS + Tunnel (no CA)

| Test | Assertions |
|------|-----------|
| `testHTTP1_HTTPS_Tunnel_NoCA` | `protocol=HTTPS(Tunnel)`, `proto_flags & tlsTunnel`, `cert_chain_ref = nil` |
| `testHTTP1_HTTPS_Tunnel_DataRelayed` | Data passes through, `uploadBytes > 0`, `downloadBytes > 0` |

### Plain HTTP

| Test | Assertions |
|------|-----------|
| `testHTTP1_Plaintext_BasicRequest` | `protocol=HTTP`, no TLS flags, `conn_reuse=0` |
| `testHTTP1_Plaintext_KeepAlive_PoolReuse` | First client → close → second client same host → `conn_reuse=2`, metadata `connReusePoolKey` set |

### Data Integrity

| Test | Assertions |
|------|-----------|
| `testData_LargeBody_1MB` | POST 1MB → echo → payload file size == 1MB, SHA256 match |
| `testData_ChunkedTransfer` | Chunked response → complete reception, `downloadBytes` correct |
| `testData_EmptyBody` | GET → `uploadBytes == 0`, no `req_payload_ref` |

### Hop-by-Hop Headers

| Test | Assertions |
|------|-----------|
| `testHopByHop_StandardHeadersStripped` | `Proxy-Authorization`, `Keep-Alive`, `TE` not seen by server |
| `testHopByHop_ConnectionNominated` | `Connection: X-Custom` → `X-Custom` also stripped |
| `testHopByHop_UpgradePreservedForWS` | WebSocket `Connection: upgrade` + `Upgrade: websocket` preserved |

---

## HTTP/2 Integration Tests

### MITM + ALPN h2 (with CA)

| Test | Assertions |
|------|-----------|
| `testH2_MITM_BasicRequest` | `schemes=H2`, `proto_flags & h2Multiplexing & tlsMITM & tlsHandshakeOK` |
| `testH2_MITM_ConcurrentStreams` | 3 concurrent requests → 3 flows, each with distinct metadata `h2StreamId` |
| `testH2_MITM_ServerPush` | PUSH_PROMISE → extra flow with `schemes=H2-Push`, `proto_flags & h2ServerPush`, `push_status` = 0 or 1 |
| `testH2_MITM_FlowControl` | >64KB body → `proto_flags & h2FlowControl` |
| `testH2_MITM_POST_WithBody` | `uploadBytes`/`downloadBytes` match, payload files correct |
| `testH2_MITM_Timeline` | Same timeline ordering as HTTP/1.1 |
| `testH2_MITM_CertChain` | Cert export success, chain length 2 |

### Tunnel (no CA)

| Test | Assertions |
|------|-----------|
| `testH2_Tunnel_NoCA` | `proto_flags & tlsTunnel`, no H2 flags (can't see inside encrypted tunnel) |

### H2 Edge Cases

| Test | Assertions |
|------|-----------|
| `testH2_MITM_StreamReset` | Client cancels one stream → that flow `status=failed`, others unaffected |
| `testH2_MITM_GRPCContentType` | `content-type: application/grpc` → `schemes=gRPC` |

---

## WebSocket Integration Tests

### WSS + MITM (with CA)

| Test | Assertions |
|------|-----------|
| `testWS_WSS_MITM_UpgradeAndEcho` | `schemes=WSS`, `proto_flags & wsFrameMasked & tlsMITM & tlsHandshakeOK` |
| `testWS_WSS_MITM_BinaryFrames` | Binary frame round-trip, `uploadBytes > 0`, `downloadBytes > 0` |
| `testWS_WSS_MITM_MultipleFrames` | 10 messages → 10 echoes, traffic counters accumulate |
| `testWS_WSS_MITM_CloseFrame` | Close handshake → `status=completed` |
| `testWS_WSS_MITM_CertChain` | Cert file exists, summary in metadata |
| `testWS_WSS_MITM_Timeline` | `connectAt < connectedAt < tlsDoneAt`, endedAt after close |

### Tunnel (no CA)

| Test | Assertions |
|------|-----------|
| `testWS_WSS_Tunnel_NoCA` | `proto_flags & tlsTunnel`, no `wsFrameMasked` (encrypted) |

### Plain WS

| Test | Assertions |
|------|-----------|
| `testWS_Plaintext_UpgradeAndEcho` | `schemes=WS`, `proto_flags & wsFrameMasked`, no TLS flags |
| `testWS_Plaintext_MaskingDirection` | Echo server verifies: received frames are masked; client verifies: received frames are not masked |

### WS Edge Cases

| Test | Assertions |
|------|-----------|
| `testWS_ServerDisconnect` | Server drops → client receives goingAway close |
| `testWS_LargeFrame` | >128KB frame → no truncation |

---

## TLS Integration Tests

### MITM Certificate Behavior

| Test | Assertions |
|------|-----------|
| `testTLS_MITM_DynamicCertPerHost` | Two hosts → different PEM files, leaf subjects differ |
| `testTLS_MITM_CertCacheReuse` | Same host twice → same cert sha256 (cache hit) |
| `testTLS_MITM_CertExportPEM` | `CertExportService.exportCertChain` → success, chain parseable, length 2 |

### Handshake Failures

| Test | Assertions |
|------|-----------|
| `testTLS_HandshakeFail_UntrustedCA` | Client rejects cert → `proto_flags & tlsHandshakeFail`, `status=failed` |
| `testTLS_HandshakeTimeout` | No ClientHello → `proto_flags & tlsHandshakeTimeout` |
| `testTLS_NonTLSData` | Plain text to MITM → `error_message` contains "not a TLS ClientHello" |

### Tunnel vs MITM Decision

| Test | Assertions |
|------|-----------|
| `testTLS_SSLEnabled_MITMPath` | sslEnable=1 → `proto_flags & tlsMITM`, decrypted HTTP visible |
| `testTLS_SSLDisabled_TunnelPath` | sslEnable=0 → `proto_flags & tlsTunnel`, only SNI metadata |

### ALPN Negotiation

| Test | Assertions |
|------|-----------|
| `testTLS_ALPN_NegotiateH2` | Server supports h2 → `schemes=H2`, metadata `alpnNegotiated=h2` |
| `testTLS_ALPN_FallbackHTTP11` | Server supports http/1.1 only → `schemes=Https`, metadata `alpnNegotiated=http/1.1` |

---

## Edge Case Tests

### ConnectHandler

| Test | Assertions |
|------|-----------|
| `testConnectHandler_CONNECTResponse200` | CONNECT → `200 Connection Established` → TLS succeeds |
| `testConnectHandler_NonCONNECT_PassThrough` | Plain GET → ConnectHandler passes through, HTTPCaptureHandler handles it |
| `testConnectHandler_InvalidHost` | CONNECT to unreachable host → `status=failed`, `error_message` non-empty |

### Connection Pool (direct eviction calls, no wall-clock waits)

| Test | Assertions |
|------|-----------|
| `testPool_IdleEviction` | Checkin → close the channel → call `evictExpired()` directly → pool count == 0 |
| `testPool_MaxPerKey` | Checkin 7 channels to same host → pool count == 6, 7th channel closed |
| `testPool_TotalCapacity` | Fill pool to 32 across different hosts → next checkin is rejected |

### Error Recovery

| Test | Assertions |
|------|-----------|
| `testError_ServerDropsConnection` | Server closes TCP mid-response → `status=failed`, recorder closed, no leaks |
| `testError_ClientDropsMidRequest` | Client disconnects after head → `status=failed`, outbound closed or pooled |
| `testError_ServerSlowResponse` | 5s delay → still completes, `rspStartAt - reqEndAt > 4s` |

---

## Stress Tests

### Three Levels

| Level | Concurrency | Timeout | Success Rate | Memory Delta |
|-------|-------------|---------|-------------|--------------|
| Light | 100 | 30s | == 100% | < 10MB |
| Medium | 1000 | 60s | >= 99% | < 50MB |
| Heavy | 5000 | 180s | >= 95% | < 200MB |

### Scenarios

| Test | Description |
|------|------------|
| `testStress_HTTP1_Plaintext_{Light,Medium,Heavy}` | Pure HTTP/1.1 max throughput |
| `testStress_HTTPS_MITM_{Light,Medium,Heavy}` | HTTPS + TLS handshake + cert gen pressure |
| `testStress_H2_MITM_Medium` | H2 concurrent streams multiplexer stress |
| `testStress_Mixed_Medium` | 25% HTTP + 25% HTTPS + 25% H2 + 25% WS |

### Per-Test Metrics Collected

```swift
struct StressResult {
    let totalRequests: Int
    let successCount: Int
    let failureCount: Int
    let totalDurationMs: Double
    let avgLatencyMs: Double
    let p99LatencyMs: Double
    let peakMemoryBytes: Int64
    let baselineMemoryBytes: Int64
    let memoryDeltaBytes: Int64
    let flowsInDB: Int
    let pooledConnectionsAfter: Int
}
```

### Per-Test Assertions

- `flowsInDB == successCount` (every success recorded)
- `pooledConnectionsAfter <= 32` (pool max)
- `memoryDeltaBytes` within threshold for level
- All SessionRecorders finalized (no dangling `recordClosed` calls)

### Memory Monitoring

Uses `mach_task_basic_info.resident_size` (RSS). Baseline sampled before test, peak tracked during test (sampled every 100 requests).

### Cleanup Strategy

All test classes use `addTeardownBlock` in `setUp` to ensure cleanup even on assertion failures or crashes:

```swift
override func setUp() {
    super.setUp()
    launcher = try! TestProxyLauncher(sslEnabled: true, withCA: true)
    proxyPort = try! launcher.start()
    addTeardownBlock { [weak self] in
        self?.launcher?.stop()  // Stops proxy, closes DBs, removes temp dir
    }
}
```

This prevents leaked ports, event loop groups, and temp directories.

### Memory Measurement Note

`mach_task_basic_info.resident_size` measures process-wide RSS (includes test framework overhead). Memory thresholds are empirical and may need tuning per machine. The baseline measurement before each stress test accounts for framework overhead. Thresholds should be treated as sanity checks (catching obvious leaks) rather than precise measurements.

### Heavy Test Opt-In

```swift
func testStress_Heavy_5000() throws {
    try XCTSkipIf(
        ProcessInfo.processInfo.environment["RUN_STRESS_HEAVY"] == nil,
        "Set RUN_STRESS_HEAVY=1 to run"
    )
}
```

---

## Test Runner Script and HTML Report

### Shell Script: `scripts/run-integration-tests.sh`

```bash
#!/bin/bash
# Usage:
#   ./scripts/run-integration-tests.sh              # Run all except heavy stress
#   ./scripts/run-integration-tests.sh --all         # Run everything including heavy
#   ./scripts/run-integration-tests.sh --filter H2   # Run only H2 tests
#   ./scripts/run-integration-tests.sh --stress-only # Run only stress tests
```

**What it does:**
1. Build the test target
2. Run `swift test` with appropriate filters and environment variables
3. Capture output (stdout+stderr) and exit code
4. Parse test results (pass/fail/skip counts, durations, stress metrics)
5. Generate HTML report
6. Open report in browser (macOS `open` command, optional `--no-open` flag)

**Environment variables:**
- `RUN_STRESS_HEAVY=1` — enable heavy stress tests
- `TEST_REPORT_DIR=path` — custom output directory (default: `build/test-reports/`)

### HTML Report: `build/test-reports/integration-test-report.html`

A single self-contained HTML file (inline CSS/JS, no external dependencies) that can be read by Claude for debugging.

**Report sections:**

1. **Summary Bar** — total pass/fail/skip, overall duration, timestamp
2. **Protocol Coverage Matrix** — table showing each protocol x scenario (with CA / no CA / plain), each cell green/red/yellow
3. **Per-Test Details** — collapsible sections:
   - Test name, duration, pass/fail
   - Assertion failures with expected vs actual values
   - Database field values (flow record dump for failed tests)
   - Error output / stack traces
4. **Stress Test Dashboard** — for each stress level:
   - Success rate, latency percentiles (avg, p50, p95, p99)
   - Memory: baseline, peak, delta (with bar chart)
   - Throughput (requests/sec)
   - Table of flow count vs expected
5. **Raw Output** — collapsible full test log

**Report generator:** The shell script uses `swift test --xunit-output build/test-reports/results.xml` to produce JUnit XML (machine-parseable, toolchain-independent). A companion Swift script (`generate-test-report.swift`) reads the JUnit XML + the stress metric lines from stdout to produce the HTML report. This avoids fragile stdout format parsing — JUnit XML is the standard and is stable across Swift toolchain versions.

### Stress Metric Output Convention

Stress tests print structured lines for the report generator to parse:

```
[STRESS_METRIC] test=testStress_HTTPS_MITM_Medium total=1000 success=998 failed=2 duration_ms=12345 avg_latency_ms=12.3 p99_latency_ms=45.6 baseline_mem=52428800 peak_mem=89128960 delta_mem=36700160 flows_in_db=998 pool_after=12
```

### Reading the Report for Debugging

The HTML report is designed to be machine-readable:
- All data is in a `<script>` tag as a JSON object (`window.testResults = {...}`)
- Claude can read the HTML file and parse the embedded JSON to identify failures
- Failed test sections include the full assertion context (field name, expected value, actual value)
- Stress sections include the full `StressResult` struct serialized as JSON

**Workflow for debugging a failure:**
1. Run `./scripts/run-integration-tests.sh`
2. If failures: `claude "Read build/test-reports/integration-test-report.html and diagnose the failures"`
3. The report contains enough context (DB values, error messages, timing) to pinpoint issues

---

## File Structure Summary

### New Files (Source)
None — all changes are test-only.

### New Files (Tests)
```
Tests/TunnelServicesTests/Integration/
├── TestInfrastructure/
│   ├── TestEchoServer.swift        — Configurable NIO echo server
│   ├── TestProxyLauncher.swift     — Proxy + DB + CA lifecycle manager
│   └── TestNIOClient.swift         — NIO client for proxy requests
├── HTTP1IntegrationTests.swift     — 12 tests
├── HTTP2IntegrationTests.swift     — 10 tests
├── WebSocketIntegrationTests.swift — 10 tests
├── TLSIntegrationTests.swift       — 10 tests
├── EdgeCaseTests.swift             — 9 tests
└── StressTests.swift               — 13 tests (4 heavy opt-in)
```

### New Files (Scripts)
```
scripts/
├── run-integration-tests.sh        — Test runner with HTML report generation
└── generate-test-report.swift      — Swift script to parse results → HTML
```

### Total: ~64 new test cases + 3 infrastructure files + 2 scripts
