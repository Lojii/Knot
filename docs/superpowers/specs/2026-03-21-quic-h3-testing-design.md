# QUIC/HTTP3 Packet Capture Testing Design (Phase 1)

**Goal:** Test the existing QUIC MITM packet capture code (QUICMITMHandler, LsquicMITMHandler, QUICDecoder, QuicDAO) that has never been tested. Both quiche and lsquic backends are tested via parameterized test cases.

**Approach:** Build in-memory test infrastructure (TestQUICServer, TestQUICClient, QUICMITMTestHarness) using SwiftQuiche to route QUIC packets through the MITM handlers without real UDP sockets or NetworkExtension. Unit tests cover QUICDecoder, DAO, and config. Real-network tests (opt-in) validate against live H3 servers.

**Phase 2 (future):** Integrate H3 support into ProxyServer (UDP listener + QUIC protocol detection + MITM pipeline).

---

## Test File Structure

```
Tests/TunnelServicesTests/Integration/QUIC/
├── TestInfrastructure/
│   ├── TestQUICServer.swift         — In-memory H3 echo server via SwiftQuiche
│   ├── TestQUICClient.swift         — In-memory H3 client via SwiftQuiche
│   └── QUICMITMTestHarness.swift    — Routes packets: client ↔ MITM ↔ server
├── QUICDecoderTests.swift           — Header parsing, SNI extraction
├── QuicDAOTests.swift               — QuicConnectionDAO + QuicStreamDAO
├── QUICConfigTests.swift            — ProxyConfig.HTTP3 defaults
├── QUICMITMTests.swift              — Core: handshake + H3 request through MITM (x2 backends)
├── QUICErrorTests.swift             — Invalid packets, fallback, session limits
├── QUICStressTests.swift            — 10/50 concurrent QUIC sessions + memory
└── QUICRealWorldTests.swift         — Direct + MITM against real H3 servers (opt-in)
```

---

## Test Infrastructure

### TestQUICServer

In-memory H3 echo server using SwiftQuiche's `QUICConnection` + `HTTP3Connection`. No UDP socket — receives and returns raw `Data` packets.

```swift
class TestQUICServer {
    /// Feed a client packet. Returns response packets.
    func receive(_ packet: Data, from: SockAddr) -> [Data]

    /// Drain any pending outbound packets (handshake, response).
    func pendingOutbound() -> [Data]

    /// Whether any H3 requests have been received.
    var receivedRequests: [(method: String, path: String, body: Data)]
}
```

Server behavior:
- Accepts QUIC Initial → completes handshake via quiche
- After handshake: polls H3 streams for requests
- Returns echo response: status 200, body = request body (or "OK" for GET)
- Configured with a real TLS certificate (from `CertGenerator.generateCA()`)

### TestQUICClient

In-memory H3 client using SwiftQuiche. No UDP socket.

```swift
class TestQUICClient {
    /// Generate Initial packet (ClientHello) to start connection.
    func startConnection() -> [Data]

    /// Feed received packets. Returns next packets to send.
    func receive(_ packets: [Data]) -> [Data]

    /// Whether QUIC handshake is complete.
    var isEstablished: Bool

    /// Send an H3 request. Returns packets to send.
    func sendRequest(method: String, path: String, authority: String, body: Data?) -> [Data]

    /// Poll for received H3 responses.
    func pollResponses() -> [(headers: [(String, String)], body: Data)]
}
```

### QUICMITMTestHarness

Routes packets between client, MITM handler, and server in memory:

```swift
class QUICMITMTestHarness {
    let client: TestQUICClient
    let server: TestQUICServer
    let backend: QUICBackend  // .quiche or .lsquic

    // MITM manager (one of the two, based on backend)
    private var quicheManager: QUICMITMManager?
    private var lsquicManager: LsquicMITMManager?

    /// Run one round of packet exchange:
    /// client → MITM → server → MITM → client
    /// Returns true if there are still pending packets.
    func runRoundTrip() -> Bool

    /// Loop runRoundTrip until client.isEstablished or timeout.
    func runUntilEstablished(timeout: TimeInterval = 5.0) throws

    /// Loop until client receives at least one H3 response or timeout.
    func runUntilResponse(timeout: TimeInterval = 5.0) throws

    /// Access MITM session count.
    var sessionCount: Int

    /// Access fallback connections.
    var fallbackCount: Int
}
```

Round-trip loop:
1. `client.pendingOutbound()` → client packets
2. For each: `mitmManager.processOutbound(packet, clientAddr, serverAddr)` → `(toClient, toServer)`
3. Feed `toClient` back to client, `toServer` to server
4. `server.pendingOutbound()` → server packets
5. For each: `mitmManager.processInbound(packet, serverAddr, clientAddr)` → `toClient`
6. Feed `toClient` to client

### Backend Parameterization

```swift
enum QUICBackend: String, CaseIterable {
    case quiche, lsquic
}

// Shared test logic, called with each backend
private func runHandshakeTest(backend: QUICBackend) throws { ... }

// XCTest methods
func testMITMHandshake_quiche() throws { try runHandshakeTest(backend: .quiche) }
func testMITMHandshake_lsquic() throws { try runHandshakeTest(backend: .lsquic) }
```

---

## Unit Tests

### QUICDecoderTests

| Test | Input | Assertions |
|------|-------|-----------|
| `testParseLongHeader_Initial` | Hand-crafted Initial packet bytes per RFC 9000 | `isLongHeader=true`, `packetType=initial`, `version` matches, `dcid`/`scid` lengths correct |
| `testParseLongHeader_Handshake` | Handshake packet bytes | `packetType=handshake` |
| `testParseShortHeader_1RTT` | Short header bytes | `isLongHeader=false`, `dcid` >= 8 bytes |
| `testExtractSNI_Valid` | Initial packet with ClientHello + SNI extension | Returns correct domain string |
| `testExtractSNI_NoSNI` | Initial without SNI | Returns nil |
| `testExtractSNI_NotInitial` | Handshake packet | Returns nil |
| `testParseVersionNegotiation` | Version Negotiation packet | `packetType=versionNegotiation`, `version=0` |
| `testFormat_HumanReadable` | Parsed header | `format()` contains "Initial" or "Handshake" |

Test data: manually constructed `Data([...])` following RFC 9000 header format. Only headers needed, not encrypted payloads.

### QuicDAOTests

Uses `StorageTestHelper` + in-memory SQLite, following existing DAO test patterns.

| Test | Assertions |
|------|-----------|
| `testInsertAndFindConnection` | Insert QuicConnectionRecord → find by flowId → fields match |
| `testUpdateConnectionState` | Insert → update state to "closed" → verify |
| `testInsertAndFindStream` | Insert QuicStreamRecord → find → fields match |
| `testConnectionWithStreams` | 1 connection + 3 streams → query association correct |
| `testIs0RTT` | Insert with `is0rtt=true` → read back, verify true |
| `testQueryByState` | Insert 3 records with different states → filter works |

### QUICConfigTests

| Test | Assertions |
|------|-----------|
| `testDefaultConfig` | `HTTP3.enabled == false`, `backend == .quiche`, `maxSessions == 20` |
| `testBackendSwitch` | Set `.lsquic` → verify config value |

---

## QUIC MITM Integration Tests (x2 backends)

### Core Flow Tests

Each test is run twice (once per backend).

| Test | Scenario | Assertions |
|------|----------|-----------|
| `testMITM_Handshake` | Client → MITM → Server completes QUIC handshake | `client.isEstablished == true`, `harness.sessionCount == 1` |
| `testMITM_H3_GET` | After handshake, send GET /hello | Client receives 200 response, body correct |
| `testMITM_H3_POST_WithBody` | POST with body "test data" | Echo response body matches |
| `testMITM_H3_MultipleRequests` | 3 GETs on same connection | 3 responses received, all correct |
| `testMITM_Recording` | After request, check QuicConnectionDAO + QuicStreamDAO | Connection record: `alpn="h3"`, `state="established"`; Stream record exists with bytes > 0 |
| `testMITM_SessionRecorder` | After request, check FlowRecord via FlowDAO | Flow exists with `uploadBytes > 0`, `downloadBytes > 0` |

### Fallback Tests

| Test | Scenario | Assertions |
|------|----------|-----------|
| `testMITM_Fallback_NoCert` | Initialize MITM without valid cert | Packets transparently forwarded, `fallbackCount > 0` |
| `testMITM_SessionLimit` | Create 21 connections (limit=20) | First 20 succeed, 21st enters fallback |
| `testMITM_VersionZero` | Send packet with QUIC version=0 | Enters fallback immediately |

---

## Error Handling Tests

| Test | Scenario | Assertions |
|------|----------|-----------|
| `testMITM_InvalidPacket` | Feed random garbage bytes | No crash, returns empty or fallback |
| `testMITM_TruncatedInitial` | Truncated Initial packet (only first 10 bytes) | No crash, graceful error |
| `testMITM_ServerUnreachable` | Server never responds to any packet | Client times out, MITM cleans up session |
| `testMITM_ConcurrentSessions` | 5 different DCIDs, interleaved packets | All 5 sessions independent, correct responses |

---

## Stress Tests

| Test | Concurrent | Assertions |
|------|-----------|-----------|
| `testQUICStress_Light` | 10 connections, 1 request each | 100% success, memory delta < 5MB |
| `testQUICStress_Medium` | 50 connections, 1 request each | >= 90% success, memory delta < 20MB |

Uses same `currentRSS()` memory monitoring as TCP stress tests. Opt-in heavy test skipped by default.

---

## Real-World H3 Tests (opt-in: `RUN_REAL_WORLD_TESTS=1`)

### Direct QUIC Connection (no MITM)

Validates SwiftQuiche can connect to real H3 servers.

| Test | Target | Assertions |
|------|--------|-----------|
| `testRealH3_Direct_Google` | `quic.googleapis.com:443` | Handshake completes, H3 response received |
| `testRealH3_Direct_Cloudflare` | `cloudflare-quic.com:443` | Same |

These use **real UDP sockets** (NWConnection) — requires network access.

### MITM Against Real Servers

Routes real QUIC traffic through the MITM harness + real UDP.

| Test | Target | Assertions |
|------|--------|-----------|
| `testRealH3_MITM_Google` | `quic.googleapis.com:443` via MITM | MITM decrypts H3 response, client receives data |

Requires `RUN_REAL_WORLD_TESTS=1` + network access.

---

## Dependencies

No new source code dependencies. Tests use:
- `SwiftQuiche` (already in Package.swift) — for TestQUICServer/Client
- `@testable import TunnelServices` — for MITM handlers, DAO, decoder
- `StorageTestHelper` — for in-memory DB tests
- `CertGenerator` — for test TLS certificates

Test target may need `SwiftQuiche` added explicitly if not transitively available:
```swift
.testTarget(
    name: "TunnelServicesTests",
    dependencies: [
        "TunnelServices",
        .product(name: "NIOEmbedded", package: "swift-nio"),
        .product(name: "SwiftQuiche", package: "SwiftQuiche"),  // if needed
    ],
)
```

---

## Out of Scope (Phase 2)

- ProxyServer UDP listener for QUIC
- QUIC protocol detection plugin in ProtocolRegistry
- QUIC connection pool
- 0-RTT session resumption testing (depends on quiche support)
- QPACK header compression testing (handled internally by quiche)
