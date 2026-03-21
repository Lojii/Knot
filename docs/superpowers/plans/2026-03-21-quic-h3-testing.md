# QUIC/HTTP3 Packet Capture Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test the existing QUIC MITM packet capture code that has never been tested — QUICDecoder, QuicDAO, QUICMITMHandler (quiche backend), plus error handling and stress scenarios.

**Architecture:** Unit tests for QUICDecoder/DAO (no QUIC libraries needed). Integration tests use SwiftQuiche to build in-memory QUIC client/server, route packets through QUICMITMManager without real UDP sockets. Lsquic backend is a stub — integration tests skipped for it.

**Tech Stack:** Swift, XCTest, SwiftQuiche (quiche FFI), SQLite.swift

**Spec:** `docs/superpowers/specs/2026-03-21-quic-h3-testing-design.md`

---

## File Structure

Test paths relative to `LocalPackages/TunnelServices/Tests/TunnelServicesTests/`.

### New Files
- `Integration/QUIC/QUICDecoderTests.swift` — Header parsing, SNI extraction, isQUIC
- `Integration/QUIC/QuicDAOTests.swift` — QuicConnectionDAO + QuicStreamDAO round-trip
- `Integration/QUIC/QUICConfigTests.swift` — ProxyConfig.HTTP3 defaults
- `Integration/QUIC/TestInfrastructure/TestQUICServer.swift` — In-memory H3 echo server via SwiftQuiche
- `Integration/QUIC/TestInfrastructure/TestQUICClient.swift` — In-memory H3 client via SwiftQuiche
- `Integration/QUIC/TestInfrastructure/QUICMITMTestHarness.swift` — Packet router: client ↔ MITM ↔ server
- `Integration/QUIC/QUICMITMTests.swift` — Core MITM handshake + H3 request tests
- `Integration/QUIC/QUICErrorTests.swift` — Invalid packets, fallback, session limits
- `Integration/QUIC/QUICStressTests.swift` — 10/50 concurrent sessions + memory

### Modified Files
- `LocalPackages/TunnelServices/Package.swift` — May need `SwiftQuiche` in test target deps

---

## Priority Order

| P | Task | Impact |
|---|------|--------|
| P0 | Task 1: QUICDecoderTests | Pure unit test, no QUIC deps, validates parsing |
| P0 | Task 2: QuicDAOTests | Pure DB test, validates storage layer |
| P0 | Task 3: QUICConfigTests | Trivial, validates defaults |
| P1 | Task 4: TestQUICServer + TestQUICClient | Infrastructure for MITM tests |
| P1 | Task 5: QUICMITMTestHarness | Routes packets between client ↔ MITM ↔ server |
| P1 | Task 6: QUICMITMTests | Core: handshake + H3 request through MITM |
| P2 | Task 7: QUICErrorTests | Invalid packets, fallback, limits |
| P2 | Task 8: QUICStressTests | Concurrent sessions + memory |

---

### Task 1: QUICDecoderTests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/QUICDecoderTests.swift`

**Problem:** `QUICDecoder.parseHeader()`, `extractSNI()`, `isQUIC()`, and `format()` are untested.

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import TunnelServices

final class QUICDecoderTests: XCTestCase {

    // MARK: - parseHeader

    func testParseLongHeader_Initial() {
        // RFC 9000: Long Header, Initial packet
        // Byte 0: 1_1_00_0000 = 0xC0 (long header, Initial type)
        // Version: 0x00000001 (QUIC v1)
        // DCID len: 8, DCID: 8 random bytes
        // SCID len: 8, SCID: 8 random bytes
        var data = Data()
        data.append(0xC0)                    // Long header + Initial (00)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // Version 1
        data.append(0x08)                    // DCID length = 8
        data.append(contentsOf: [1,2,3,4,5,6,7,8]) // DCID
        data.append(0x08)                    // SCID length = 8
        data.append(contentsOf: [9,10,11,12,13,14,15,16]) // SCID
        data.append(contentsOf: [0x00])      // Token length = 0
        data.append(contentsOf: [0x00, 0x10]) // Payload length (16)
        data.append(contentsOf: Data(repeating: 0, count: 16)) // dummy payload

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertTrue(header!.isLongHeader)
        XCTAssertEqual(header!.packetType, .initial)
        XCTAssertEqual(header!.version, 0x00000001)
        XCTAssertEqual(header!.dcidLength, 8)
        XCTAssertEqual(header!.dcid, Data([1,2,3,4,5,6,7,8]))
        XCTAssertEqual(header!.scidLength, 8)
        XCTAssertEqual(header!.scid, Data([9,10,11,12,13,14,15,16]))
    }

    func testParseLongHeader_Handshake() {
        var data = Data()
        data.append(0xE0)                    // Long header + Handshake (10)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        data.append(0x04)
        data.append(contentsOf: [1,2,3,4])
        data.append(0x04)
        data.append(contentsOf: [5,6,7,8])
        data.append(contentsOf: [0x00, 0x08])
        data.append(contentsOf: Data(repeating: 0, count: 8))

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header!.packetType, .handshake)
    }

    func testParseShortHeader() {
        // Short header: bit 7 = 0
        var data = Data()
        data.append(0x40) // Short header (0_1_xxxxxx)
        data.append(contentsOf: Data(repeating: 0xAB, count: 20)) // DCID + payload

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertFalse(header!.isLongHeader)
        XCTAssertEqual(header!.packetType, .shortHeader)
        XCTAssertTrue(header!.dcidLength >= 8)
    }

    func testParseVersionNegotiation() {
        var data = Data()
        data.append(0x80)                    // Long header
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Version = 0
        data.append(0x04)
        data.append(contentsOf: [1,2,3,4])
        data.append(0x04)
        data.append(contentsOf: [5,6,7,8])

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header!.version, 0)
        XCTAssertEqual(header!.packetType, .unknown) // version 0 → unknown
    }

    func testParseTooShort() {
        let data = Data([0xC0, 0x00]) // Too short for a valid QUIC header
        let header = QUICDecoder.parseHeader(data)
        XCTAssertNil(header)
    }

    // MARK: - isQUIC

    func testIsQUIC_ValidInitial() {
        var data = Data()
        data.append(0xC0)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        data.append(0x08)
        data.append(contentsOf: Data(repeating: 0, count: 20))
        XCTAssertTrue(QUICDecoder.isQUIC(data))
    }

    func testIsQUIC_HTTPRequest() {
        let data = "GET / HTTP/1.1\r\n".data(using: .utf8)!
        XCTAssertFalse(QUICDecoder.isQUIC(data))
    }

    func testIsQUIC_TLSClientHello() {
        let data = Data([0x16, 0x03, 0x01, 0x00, 0x05]) // TLS record
        XCTAssertFalse(QUICDecoder.isQUIC(data))
    }

    func testIsQUIC_Empty() {
        XCTAssertFalse(QUICDecoder.isQUIC(Data()))
    }

    // MARK: - extractSNI

    func testExtractSNI_NotInitial() {
        var data = Data()
        data.append(0xE0) // Handshake, not Initial
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        data.append(0x04)
        data.append(contentsOf: Data(repeating: 0, count: 20))
        XCTAssertNil(QUICDecoder.extractSNI(data))
    }

    // MARK: - format

    func testFormat_Initial() {
        var data = Data()
        data.append(0xC0)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        data.append(0x04)
        data.append(contentsOf: [1,2,3,4])
        data.append(0x04)
        data.append(contentsOf: [5,6,7,8])
        data.append(contentsOf: [0x00, 0x00, 0x04])
        data.append(contentsOf: Data(repeating: 0, count: 4))

        let header = QUICDecoder.parseHeader(data)!
        let desc = QUICDecoder.format(header)
        XCTAssertTrue(desc.contains("Initial"))
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter QUICDecoder`
Expected: PASS (these are pure parsing tests against existing code)

If any fail, the test data construction may not match `QUICDecoder`'s expectations — read the decoder source and adjust byte patterns.

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/QUICDecoderTests.swift
git commit -m "feat: add QUICDecoder unit tests (header parsing, SNI, isQUIC)"
```

---

### Task 2: QuicDAOTests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/QuicDAOTests.swift`

**Problem:** QuicConnectionDAO and QuicStreamDAO have never been tested.

- [ ] **Step 1: Write tests**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class QuicDAOTests: XCTestCase {
    private var db: Connection!

    override func setUp() {
        super.setUp()
        db = try! Connection(.inMemory)
        try! ConnectionSchema.create(db)
    }

    // MARK: - QuicConnectionDAO

    func testInsertAndFindConnection() throws {
        let record = QuicConnectionRecord(
            flowId: "quic-1",
            srcIp: "192.168.1.1", srcPort: 12345,
            dstIp: "1.1.1.1", dstPort: 443,
            startedAt: Date().timeIntervalSince1970,
            state: "handshaking",
            version: "1", dcid: "aabbccdd", scid: "eeff0011",
            alpn: "h3", tlsSni: "example.com"
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        let found = try QuicConnectionDAO.find(db: db, flowId: "quic-1")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.flowId, "quic-1")
        XCTAssertEqual(found?.dstIp, "1.1.1.1")
        XCTAssertEqual(found?.dstPort, 443)
        XCTAssertEqual(found?.alpn, "h3")
        XCTAssertEqual(found?.tlsSni, "example.com")
        XCTAssertEqual(found?.state, "handshaking")
    }

    func testUpdateConnectionState() throws {
        var record = QuicConnectionRecord(
            flowId: "quic-2",
            srcIp: "10.0.0.1", srcPort: 5000,
            dstIp: "8.8.8.8", dstPort: 443,
            startedAt: Date().timeIntervalSince1970
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        record.state = "established"
        record.establishedAt = Date().timeIntervalSince1970
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        let found = try QuicConnectionDAO.find(db: db, flowId: "quic-2")
        XCTAssertEqual(found?.state, "established")
        XCTAssertNotNil(found?.establishedAt)
    }

    func testIs0RTT() throws {
        let record = QuicConnectionRecord(
            flowId: "quic-0rtt",
            srcIp: "10.0.0.1", srcPort: 5000,
            dstIp: "8.8.8.8", dstPort: 443,
            startedAt: Date().timeIntervalSince1970,
            is0rtt: true
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)

        let found = try QuicConnectionDAO.find(db: db, flowId: "quic-0rtt")
        XCTAssertTrue(found?.is0rtt ?? false)
    }

    func testFindNotFound() throws {
        let found = try QuicConnectionDAO.find(db: db, flowId: "nonexistent")
        XCTAssertNil(found)
    }

    // MARK: - QuicStreamDAO

    func testInsertAndFindStream() throws {
        let record = QuicStreamRecord(
            connectionId: "quic-1", streamId: 0,
            startedAt: Date().timeIntervalSince1970,
            streamType: "bidi", state: "open"
        )
        try QuicStreamDAO.insert(db: db, record: record)

        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic-1")
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].streamId, 0)
        XCTAssertEqual(streams[0].streamType, "bidi")
    }

    func testConnectionWithMultipleStreams() throws {
        for i in 0..<3 {
            let record = QuicStreamRecord(
                connectionId: "quic-multi", streamId: i * 4, // H3 client bidi streams: 0, 4, 8
                startedAt: Date().timeIntervalSince1970
            )
            try QuicStreamDAO.insert(db: db, record: record)
        }

        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic-multi")
        XCTAssertEqual(streams.count, 3)
        XCTAssertEqual(streams[0].streamId, 0)
        XCTAssertEqual(streams[1].streamId, 4)
        XCTAssertEqual(streams[2].streamId, 8)
    }

    func testStreamUpdateProtocolFlowId() throws {
        let record = QuicStreamRecord(
            connectionId: "quic-proto", streamId: 0,
            startedAt: Date().timeIntervalSince1970
        )
        try QuicStreamDAO.insert(db: db, record: record)

        try QuicStreamDAO.updateProtocolFlowId(
            db: db, connectionId: "quic-proto", streamId: 0,
            protocolFlowId: "flow-123"
        )

        let found = try QuicStreamDAO.findByProtocolFlowId(db: db, protocolFlowId: "flow-123")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.connectionId, "quic-proto")
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter QuicDAO`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/QuicDAOTests.swift
git commit -m "feat: add QuicConnectionDAO and QuicStreamDAO unit tests"
```

---

### Task 3: QUICConfigTests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/QUICConfigTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import TunnelServices

final class QUICConfigTests: XCTestCase {
    func testDefaultConfig() {
        XCTAssertFalse(ProxyConfig.HTTP3.enabled)
        XCTAssertEqual(ProxyConfig.HTTP3.backend, .quiche)
        XCTAssertEqual(ProxyConfig.HTTP3.maxSessions, 20)
        XCTAssertEqual(ProxyConfig.HTTP3.idleTimeoutMs, 30_000)
    }

    func testBackendEnum() {
        XCTAssertEqual(ProxyConfig.HTTP3.Backend.quiche.rawValue, "quiche")
        XCTAssertEqual(ProxyConfig.HTTP3.Backend.lsquic.rawValue, "lsquic")
    }
}
```

- [ ] **Step 2: Run and commit**

Run: `swift test --package-path LocalPackages/TunnelServices --filter QUICConfig`

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/QUICConfigTests.swift
git commit -m "feat: add QUICConfig unit tests"
```

---

### Task 4: TestQUICServer + TestQUICClient

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/TestInfrastructure/TestQUICServer.swift`
- Create: `Tests/TunnelServicesTests/Integration/QUIC/TestInfrastructure/TestQUICClient.swift`
- Possibly modify: `LocalPackages/TunnelServices/Package.swift` (add SwiftQuiche to test target)

**Problem:** Need in-memory QUIC client/server to feed packets to the MITM handler.

**Design:** Both use SwiftQuiche's `QUICConnection` + `HTTP3Connection`. No UDP sockets — packets are `Data` objects passed directly.

- [ ] **Step 1: Check if SwiftQuiche is available in test target**

Read `Package.swift` test target deps. If `SwiftQuiche` is not listed, add it:
```swift
.testTarget(
    name: "TunnelServicesTests",
    dependencies: [
        "TunnelServices",
        .product(name: "NIOEmbedded", package: "swift-nio"),
        .product(name: "SwiftQuiche", package: "SwiftQuiche"),
    ],
)
```

Since TunnelServices already depends on SwiftQuiche, it may be transitively available. Try importing first.

- [ ] **Step 2: Implement TestQUICServer**

Core: wraps `QUICConnection` (server mode) + `HTTP3Connection`. Accepts raw QUIC packets, responds to H3 requests with echo.

Key implementation points:
- `QUICConfig`: `verifyPeer(false)`, `setApplicationProtocols(["h3"])`, load test cert/key via `loadCertChain`/`loadPrivateKey`
- `QUICConnection(scid:odcid:localAddr:peerAddr:config:)` — server-side init
- `conn.recv(data)` to feed incoming packets
- `conn.send()` in a loop to drain outgoing packets
- After `conn.isEstablished`: create `HTTP3Connection`, poll for events
- On `.headers` event: record request; on `.data`: read body via `recvBody`; on `.finished`: send echo response via `sendResponse` + `sendBody`

Address concern: `QUICConnection.recv()` passes nil addresses — if quiche rejects this, extend the wrapper's `recv` to accept address info.

- [ ] **Step 3: Implement TestQUICClient**

Core: wraps `QUICConnection` (client mode) + `HTTP3Connection`. Generates QUIC packets, parses responses.

Key implementation points:
- `QUICConnection(serverName:scid:localAddr:peerAddr:config:)` — client-side init
- `conn.send()` after init produces the Initial packet (ClientHello)
- Feed response packets via `conn.recv(data)`
- After `conn.isEstablished`: create `HTTP3Connection`, send requests via `sendRequest`
- Poll for response events

- [ ] **Step 4: Write a basic test to verify client ↔ server direct exchange works (no MITM)**

```swift
func testDirectClientServer() throws {
    let server = try TestQUICServer(certPath: testCertPath, keyPath: testKeyPath)
    let client = try TestQUICClient(serverName: "localhost")

    // Exchange packets until handshake completes
    var clientPackets = client.startConnection()
    for _ in 0..<20 { // max rounds
        let serverResponses = clientPackets.flatMap { server.receive($0) }
        let serverOut = server.pendingOutbound()
        let allToClient = serverResponses + serverOut
        if allToClient.isEmpty && client.isEstablished { break }
        clientPackets = allToClient.flatMap { client.receive([$0]) }
    }

    XCTAssertTrue(client.isEstablished, "QUIC handshake should complete")
}
```

- [ ] **Step 5: Build and run**

Run: `swift test --package-path LocalPackages/TunnelServices --filter testDirectClientServer`

If quiche rejects nil addresses in recv(), fix the wrapper first.

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/TestInfrastructure/ \
  LocalPackages/TunnelServices/Package.swift
git commit -m "feat: add TestQUICServer and TestQUICClient for in-memory QUIC testing"
```

---

### Task 5: QUICMITMTestHarness

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/TestInfrastructure/QUICMITMTestHarness.swift`

**Problem:** Need to route packets: client → MITM manager → server → MITM manager → client.

- [ ] **Step 1: Implement harness**

```swift
import Foundation
@testable import TunnelServices

final class QUICMITMTestHarness {
    let client: TestQUICClient
    let server: TestQUICServer
    private let manager: QUICMITMManager

    let serverIP = "1.2.3.4"
    let serverPort: UInt16 = 443

    init(client: TestQUICClient, server: TestQUICServer, task: CaptureTask, certPath: String, keyPath: String) {
        self.client = client
        self.server = server
        self.manager = QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)
    }

    var sessionCount: Int { manager.activeSessions }

    /// Run one round: client→MITM→server→MITM→client
    func runRoundTrip() -> Bool {
        var activity = false

        // 1. Client outbound packets
        let clientOut = client.drainOutbound()
        for packet in clientOut {
            let (toApp, toServer) = manager.processOutbound(packet, dstIP: serverIP, dstPort: serverPort)
            // Feed toApp back to client
            for p in toApp { _ = client.receive([p]); activity = true }
            // Feed toServer to server
            for (data, _, _) in toServer {
                let responses = server.receive(data)
                for r in responses { activity = true }
            }
        }

        // 2. Server outbound packets
        let serverOut = server.pendingOutbound()
        for packet in serverOut {
            let toApp = manager.processInbound(packet, srcIP: serverIP, srcPort: serverPort)
            for p in toApp { _ = client.receive([p]); activity = true }
        }

        return activity
    }

    func runUntilEstablished(timeout: TimeInterval = 5.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !client.isEstablished && Date() < deadline {
            _ = runRoundTrip()
            usleep(1000) // 1ms between rounds
        }
        guard client.isEstablished else {
            throw NSError(domain: "QUICTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Handshake timeout"])
        }
    }

    func runUntilResponse(timeout: TimeInterval = 5.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while client.pollResponses().isEmpty && Date() < deadline {
            _ = runRoundTrip()
            usleep(1000)
        }
    }

    func shutdown() {
        manager.shutdown()
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build --package-path LocalPackages/TunnelServices --build-tests`

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/TestInfrastructure/QUICMITMTestHarness.swift
git commit -m "feat: add QUICMITMTestHarness for in-memory MITM packet routing"
```

---

### Task 6: QUICMITMTests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/QUICMITMTests.swift`

**Problem:** QUICMITMManager has never been tested. Need to verify handshake, H3 request/response, and recording.

- [ ] **Step 1: Implement MITM tests**

Each test:
1. Generate test CA + certs
2. Create TestQUICServer + TestQUICClient
3. Create QUICMITMTestHarness with QUICMITMManager
4. Run handshake
5. Send H3 request
6. Verify response + database records

Tests:
- `testMITM_Handshake` — client.isEstablished after runUntilEstablished
- `testMITM_H3_GET` — send GET, receive 200 + body
- `testMITM_H3_POST_WithBody` — POST echo
- `testMITM_H3_MultipleRequests` — 3 GETs on one connection
- `testMITM_Recording` — check QuicConnectionDAO + QuicStreamDAO after request

CaptureTask setup: same manual pattern as TestProxyLauncher (construct manually, set certManager, ruleEngine, fileFolder to temp dir).

- [ ] **Step 2: Run tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter QUICMITMTests`

This is the critical task — if the MITM manager has bugs, they'll surface here. Debug carefully.

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/QUICMITMTests.swift
git commit -m "feat: add QUIC MITM integration tests (handshake, H3 GET/POST, recording)"
```

---

### Task 7: QUICErrorTests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/QUICErrorTests.swift`

- [ ] **Step 1: Implement error tests**

- `testMITM_InvalidPacket` — random 100 bytes → processOutbound → no crash, returns empty or fallback
- `testMITM_TruncatedInitial` — first 10 bytes of Initial → no crash
- `testMITM_VersionZero` — packet with version=0 → manager returns empty (harness detects fallback)
- `testMITM_ConcurrentSessions` — 5 different DCIDs interleaved → all independent

- [ ] **Step 2: Run and commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/QUICErrorTests.swift
git commit -m "feat: add QUIC error handling tests (invalid packets, concurrent sessions)"
```

---

### Task 8: QUICStressTests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/QUICStressTests.swift`

- [ ] **Step 1: Implement stress tests**

- `testQUICStress_Light` — 10 connections, each does 1 H3 GET → all succeed, memory < 5MB
- `testQUICStress_Medium` — 50 connections → >= 90% succeed, memory < 20MB

Uses same `currentRSS()` pattern as TCP stress tests. Prints `[STRESS_METRIC]` lines.

- [ ] **Step 2: Run and commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/QUICStressTests.swift
git commit -m "feat: add QUIC stress tests (10/50 concurrent sessions + memory monitoring)"
```

---

## Post-Implementation Verification

1. **Unit tests**: `swift test --package-path LocalPackages/TunnelServices --filter "QUICDecoder|QuicDAO|QUICConfig"` — all pass
2. **MITM tests**: `swift test --package-path LocalPackages/TunnelServices --filter QUICMITMTests` — handshake + H3 work
3. **Error tests**: `swift test --package-path LocalPackages/TunnelServices --filter QUICError` — no crashes
4. **All QUIC tests**: `swift test --package-path LocalPackages/TunnelServices --filter "QUIC"` — everything passes
5. **Existing tests not broken**: `swift test --package-path LocalPackages/TunnelServices` — all 200+ tests pass
