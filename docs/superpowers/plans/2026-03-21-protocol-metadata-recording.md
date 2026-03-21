# Protocol Metadata Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record protocol feature usage (connection reuse, H2/WS/TLS characteristics, push status) and TLS certificate chains for every captured flow, with indexed columns for aggregate statistics.

**Architecture:** Add `ProtoFlag` OptionSet and `ConnectionReuseType` enum to SessionRecorder. Each handler calls simple setters during its lifecycle. On `recordClosed()`, flags flow into FlowRecord → FlowDAO → `flow` table (4 new columns). Certificate chains are written as PEM files using the existing payload-ref pattern.

**Tech Stack:** Swift, SQLite.swift, SwiftNIO, NIOSSL, swift-certificates (X509)

---

## File Structure

All source paths relative to `LocalPackages/TunnelServices/Sources/TunnelServices/`.
Test paths relative to `LocalPackages/TunnelServices/Tests/TunnelServicesTests/`.

### New Files
- `Storage/CertExportService.swift` — Certificate chain PEM save/export
- `Tests/.../ProtoFlagTests.swift` — ProtoFlag OptionSet + ConnectionReuseType tests
- `Tests/.../CertExportServiceTests.swift` — Cert save/export tests
- `Tests/.../FlowRecordMetadataTests.swift` — FlowDAO round-trip tests for new columns

### Modified Files
- `Storage/Schema/ProtocolSchema.swift` — Schema migration v2 (4 columns + 1 index)
- `Storage/Model/FlowRecord.swift` — 4 new fields
- `Storage/DAO/FlowDAO.swift` — insert/mapRow updated
- `Storage/TaskDatabaseGroup.swift` — Call migration after schema create
- `Framework/SessionRecorder.swift` — ProtoFlag, ConnectionReuseType, PushForwardStatus types + setter methods + cert buffering
- `Plugins/HTTP1/HTTPRecorder.swift` — buildFlowRecord() merges new fields
- `Plugins/HTTP1/HTTPCaptureHandler.swift` — Call markConnectionReuse, addProtoFlag
- `Plugins/HTTP2/HTTP2CaptureHandler.swift` — Call addProtoFlag, markPushStatus, setH2StreamId
- `Plugins/WebSocket/WebSocketCaptureHandler.swift` — Call addProtoFlag(.wsFrameMasked)
- `Plugins/TLS/MITMHandler.swift` — Call addProtoFlag (MITM/handshake), recordCertificateChain
- `Plugins/TLS/TLSPlugin.swift` — Call addProtoFlag(.tlsTunnel)

---

## Priority Order

| P | Task | Impact |
|---|------|--------|
| P0 | Task 1: Types + SessionRecorder interface | Foundation — everything depends on this |
| P0 | Task 2: FlowRecord + Schema migration | Database layer must exist before handlers write |
| P0 | Task 3: FlowDAO + HTTPRecorder wiring | Connects recorder to database |
| P1 | Task 4: HTTP/1.1 handler instrumentation | Most traffic goes through HTTP/1.1 |
| P1 | Task 5: HTTP/2 handler instrumentation | H2 + push status |
| P1 | Task 6: TLS handler instrumentation | MITM/tunnel/handshake flags |
| P1 | Task 7: WebSocket instrumentation | WS masking flag |
| P2 | Task 8: Certificate chain storage | PEM save + export service |

---

### Task 1: Protocol Metadata Types + SessionRecorder Interface

**Files:**
- Modify: `Framework/SessionRecorder.swift`
- Create: `Tests/.../ProtoFlagTests.swift`

**Problem:** No types or API exist yet for tracking protocol features.

**Design:** Add `ProtoFlag` OptionSet, `ConnectionReuseType` enum, `PushForwardStatus` enum to SessionRecorder.swift. Add private state fields and public setter methods. All setters are in-memory only.

- [ ] **Step 1: Write ProtoFlag and enum tests**

```swift
// Tests/TunnelServicesTests/ProtoFlagTests.swift
import XCTest
@testable import TunnelServices

final class ProtoFlagTests: XCTestCase {
    func testSingleFlag() {
        var flags = ProtoFlag()
        flags.insert(.keepAlive)
        XCTAssertEqual(flags.rawValue, 0x0001)
        XCTAssertTrue(flags.contains(.keepAlive))
        XCTAssertFalse(flags.contains(.h2Multiplexing))
    }

    func testMultipleFlags() {
        var flags: ProtoFlag = [.keepAlive, .tlsMITM, .tlsHandshakeOK]
        XCTAssertEqual(flags.rawValue, 0x0001 | 0x0040 | 0x0100)
        XCTAssertTrue(flags.contains(.keepAlive))
        XCTAssertTrue(flags.contains(.tlsMITM))
        XCTAssertTrue(flags.contains(.tlsHandshakeOK))
        XCTAssertFalse(flags.contains(.pipelining))
    }

    func testBitmaskRoundTrip() {
        let value = 0x0001 | 0x0004 | 0x0020
        let flags = ProtoFlag(rawValue: value)
        XCTAssertTrue(flags.contains(.keepAlive))
        XCTAssertTrue(flags.contains(.h2Multiplexing))
        XCTAssertTrue(flags.contains(.wsFrameMasked))
        XCTAssertEqual(flags.rawValue, value)
    }

    func testConnectionReuseType() {
        XCTAssertEqual(ConnectionReuseType.new.rawValue, 0)
        XCTAssertEqual(ConnectionReuseType.keepAlive.rawValue, 1)
        XCTAssertEqual(ConnectionReuseType.pooled.rawValue, 2)
    }

    func testPushForwardStatus() {
        XCTAssertEqual(PushForwardStatus.captureOnly.rawValue, 0)
        XCTAssertEqual(PushForwardStatus.forwarded.rawValue, 1)
        XCTAssertEqual(PushForwardStatus.failed.rawValue, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path LocalPackages/TunnelServices --filter ProtoFlag`
Expected: Compilation failure (types not defined yet)

- [ ] **Step 3: Add types and SessionRecorder interface**

In `Framework/SessionRecorder.swift`, add at top of file (before the class):

```swift
// MARK: - Protocol Metadata Types

public struct ProtoFlag: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let keepAlive           = ProtoFlag(rawValue: 0x0001)
    public static let pipelining          = ProtoFlag(rawValue: 0x0002)
    public static let h2Multiplexing      = ProtoFlag(rawValue: 0x0004)
    public static let h2ServerPush        = ProtoFlag(rawValue: 0x0008)
    public static let h2FlowControl       = ProtoFlag(rawValue: 0x0010)
    public static let wsFrameMasked       = ProtoFlag(rawValue: 0x0020)
    public static let tlsMITM             = ProtoFlag(rawValue: 0x0040)
    public static let tlsTunnel           = ProtoFlag(rawValue: 0x0080)
    public static let tlsHandshakeOK      = ProtoFlag(rawValue: 0x0100)
    public static let tlsHandshakeFail    = ProtoFlag(rawValue: 0x0200)
    public static let tlsHandshakeTimeout = ProtoFlag(rawValue: 0x0400)
}

public enum ConnectionReuseType: Int, Sendable {
    case new = 0
    case keepAlive = 1
    case pooled = 2
}

public enum PushForwardStatus: Int, Sendable {
    case captureOnly = 0
    case forwarded = 1
    case failed = 2
}
```

Inside `SessionRecorder` class, add private state and public API:

```swift
// MARK: - Protocol Metadata State

private var _connReuse: ConnectionReuseType = .new
private var _protoFlags: ProtoFlag = []
private var _pushStatus: PushForwardStatus? = nil
private var _certChainRef: String? = nil
private var _connReusePoolKey: String? = nil
private var _keepAliveRequestIndex: Int = 0
private var _h2StreamId: Int? = nil
private var _bufferedCerts: [Any]? = nil  // Buffered NIOSSLCertificate refs, written on recordClosed()

// MARK: - Protocol Metadata Public API

public var connReuse: Int { _connReuse.rawValue }
public var protoFlags: Int { _protoFlags.rawValue }
public var pushStatus: Int? { _pushStatus?.rawValue }
public var certChainRef: String? { _certChainRef }
public var connReusePoolKey: String? { _connReusePoolKey }
public var keepAliveRequestIndex: Int { _keepAliveRequestIndex }
public var h2StreamId: Int? { _h2StreamId }

public func markConnectionReuse(_ type: ConnectionReuseType, poolKey: String? = nil, requestIndex: Int = 0) {
    _connReuse = type
    _connReusePoolKey = poolKey
    _keepAliveRequestIndex = requestIndex
}

public func addProtoFlag(_ flag: ProtoFlag) {
    _protoFlags.insert(flag)
}

public func markPushStatus(_ status: PushForwardStatus) {
    _pushStatus = status
}

public func setH2StreamId(_ id: Int) {
    _h2StreamId = id
}

public func bufferCertificateChain(_ certs: [Any]) {
    _bufferedCerts = certs
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path LocalPackages/TunnelServices --filter ProtoFlag`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Framework/SessionRecorder.swift \
  LocalPackages/TunnelServices/Tests/TunnelServicesTests/ProtoFlagTests.swift
git commit -m "feat: add ProtoFlag, ConnectionReuseType, PushForwardStatus types and SessionRecorder API"
```

---

### Task 2: FlowRecord Fields + Schema Migration

**Files:**
- Modify: `Storage/Model/FlowRecord.swift`
- Modify: `Storage/Schema/ProtocolSchema.swift`
- Modify: `Storage/TaskDatabaseGroup.swift`

**Problem:** The `flow` table and `FlowRecord` model don't have columns for the new metadata.

**Design:** Add 4 fields to FlowRecord. Add migration using `PRAGMA user_version`. Run migration in TaskDatabaseGroup after schema create.

- [ ] **Step 1: Add fields to FlowRecord**

In `Storage/Model/FlowRecord.swift`, add after `tags`:

```swift
    // Protocol metadata (indexed columns for aggregate queries)
    public var connReuse: Int = 0       // 0=new, 1=keep-alive, 2=pool
    public var protoFlags: Int = 0      // ProtoFlag bitmask
    public var pushStatus: Int? = nil   // PushForwardStatus raw value
    public var certChainRef: String? = nil  // PEM file path
```

- [ ] **Step 2: Add schema migration to ProtocolSchema**

In `Storage/Schema/ProtocolSchema.swift`, add after the `create` method:

```swift
    static let schemaVersion: Int64 = 2

    /// Migrate from v1 (original) to v2 (protocol metadata columns).
    public static func migrateIfNeeded(_ db: Connection) throws {
        let version = try db.scalar("PRAGMA user_version") as! Int64
        if version < schemaVersion {
            // Add protocol metadata columns
            try db.run("ALTER TABLE flow ADD COLUMN conn_reuse INTEGER DEFAULT 0")
            try db.run("ALTER TABLE flow ADD COLUMN proto_flags INTEGER DEFAULT 0")
            try db.run("ALTER TABLE flow ADD COLUMN push_status INTEGER")
            try db.run("ALTER TABLE flow ADD COLUMN cert_chain_ref TEXT")
            // Index for conn_reuse aggregate queries (proto_flags uses bitmask, no B-tree index)
            try db.run("CREATE INDEX IF NOT EXISTS idx_flow_conn_reuse ON flow(conn_reuse)")
            // Update version
            try db.run("PRAGMA user_version = \(schemaVersion)")
        }
    }
```

- [ ] **Step 3: Call migration in TaskDatabaseGroup**

In `Storage/TaskDatabaseGroup.swift`, after `try ProtocolSchema.create(proto)` (around line 57), add:

```swift
    try ProtocolSchema.migrateIfNeeded(proto)
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build --package-path LocalPackages/TunnelServices`
Expected: Build complete

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Model/FlowRecord.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Schema/ProtocolSchema.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Storage/TaskDatabaseGroup.swift
git commit -m "feat: add protocol metadata columns to flow table with PRAGMA user_version migration"
```

---

### Task 3: FlowDAO + HTTPRecorder Wiring

**Files:**
- Modify: `Storage/DAO/FlowDAO.swift`
- Modify: `Plugins/HTTP1/HTTPRecorder.swift`
- Modify: `Framework/SessionRecorder.swift` (recordClosed)
- Create: `Tests/.../FlowRecordMetadataTests.swift`

**Problem:** FlowDAO.insert() and mapRow() don't know about the new columns. HTTPRecorder.buildFlowRecord() doesn't merge protocol metadata from SessionRecorder.

**Design:** Update FlowDAO to read/write 4 new columns. Update HTTPRecorder to accept a SessionRecorder reference and merge metadata into FlowRecord. Update SessionRecorder.recordClosed() to pass itself to buildFlowRecord().

- [ ] **Step 1: Write FlowDAO round-trip test**

```swift
// Tests/TunnelServicesTests/FlowRecordMetadataTests.swift
import XCTest
import SQLite
@testable import TunnelServices

final class FlowRecordMetadataTests: XCTestCase {
    private var db: Connection!

    override func setUp() {
        super.setUp()
        db = try! Connection(.inMemory)
        try! ProtocolSchema.create(db)
        try! ProtocolSchema.migrateIfNeeded(db)
    }

    func testInsertAndReadNewColumns() throws {
        var record = FlowRecord(
            flowId: "test-1", protocolName: "HTTP",
            host: "example.com", port: 443,
            startedAt: Date().timeIntervalSince1970
        )
        record.connReuse = 2
        record.protoFlags = 0x0001 | 0x0040 | 0x0100  // keepAlive + tlsMITM + tlsHandshakeOK
        record.pushStatus = nil
        record.certChainRef = "certs/test-1.pem"
        record.status = .completed

        try FlowDAO.insert(db: db, record: record)

        let found = try FlowDAO.find(db: db, flowId: "test-1")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.connReuse, 2)
        XCTAssertEqual(found?.protoFlags, 0x0001 | 0x0040 | 0x0100)
        XCTAssertNil(found?.pushStatus)
        XCTAssertEqual(found?.certChainRef, "certs/test-1.pem")
    }

    func testPushStatusRoundTrip() throws {
        var record = FlowRecord(
            flowId: "push-1", protocolName: "HTTP",
            host: "example.com", port: 443,
            startedAt: Date().timeIntervalSince1970
        )
        record.pushStatus = 1  // forwarded
        record.status = .completed

        try FlowDAO.insert(db: db, record: record)
        let found = try FlowDAO.find(db: db, flowId: "push-1")
        XCTAssertEqual(found?.pushStatus, 1)
    }

    func testAggregateQuery() throws {
        // Insert 3 records with different conn_reuse values
        for (i, reuse) in [0, 1, 2].enumerated() {
            var r = FlowRecord(
                flowId: "agg-\(i)", protocolName: "HTTP",
                host: "example.com", port: 443,
                startedAt: Date().timeIntervalSince1970
            )
            r.connReuse = reuse
            r.status = .completed
            try FlowDAO.insert(db: db, record: r)
        }

        let rows = try db.prepare("SELECT conn_reuse, COUNT(*) as cnt FROM flow GROUP BY conn_reuse ORDER BY conn_reuse")
        var results = [(Int, Int)]()
        for row in rows {
            results.append((Int(row[0] as! Int64), Int(row[1] as! Int64)))
        }
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0], (0, 1))
        XCTAssertEqual(results[1], (1, 1))
        XCTAssertEqual(results[2], (2, 1))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path LocalPackages/TunnelServices --filter FlowRecordMetadata`
Expected: Compilation or runtime failure (FlowDAO doesn't handle new columns yet)

- [ ] **Step 3: Update FlowDAO.insert() to include new columns**

In `Storage/DAO/FlowDAO.swift`, replace the INSERT statement (lines 20-68) with:

```swift
try db.run("""
    INSERT INTO flow (
        flow_id, protocol, host, port, started_at,
        ended_at, duration_ms,
        connect_at, connected_at, tls_done_at, req_end_at, rsp_start_at,
        upload_bytes, download_bytes,
        status, error_message, summary,
        search_key1, search_key2, search_key3, search_key4,
        metadata, req_payload_ref, rsp_payload_ref,
        is_intercepted, is_modified, tags,
        conn_reuse, proto_flags, push_status, cert_chain_ref
    ) VALUES (
        ?, ?, ?, ?, ?,
        ?, ?,
        ?, ?, ?, ?, ?,
        ?, ?,
        ?, ?, ?,
        ?, ?, ?, ?,
        ?, ?, ?,
        ?, ?, ?,
        ?, ?, ?, ?
    )
    """,
    record.flowId,
    record.protocolName,
    record.host,
    record.port,
    record.startedAt,
    record.endedAt,
    record.durationMs,
    record.connectAt,
    record.connectedAt,
    record.tlsDoneAt,
    record.reqEndAt,
    record.rspStartAt,
    record.uploadBytes,
    record.downloadBytes,
    record.status.rawValue,
    record.errorMessage,
    record.summary,
    record.searchKey1,
    record.searchKey2,
    record.searchKey3,
    record.searchKey4,
    metadataJSON,
    record.reqPayloadRef,
    record.rspPayloadRef,
    record.isIntercepted ? 1 : 0,
    record.isModified ? 1 : 0,
    record.tags,
    record.connReuse,
    record.protoFlags,
    record.pushStatus,
    record.certChainRef
)
```

- [ ] **Step 4: Update FlowDAO.mapRow() to read new columns**

In `Storage/DAO/FlowDAO.swift`, in `mapRow()` (line 182+), add a new helper after `int64()` (line 203):

```swift
func optInt64(_ name: String) -> Int64? {
    let i = idx(name)
    guard i >= 0 else { return nil }
    return row[i] as? Int64
}
func optStr(_ name: String) -> String? {
    let i = idx(name)
    guard i >= 0 else { return nil }
    return row[i] as? String
}
```

After `record.tags = str("tags")` (line 250), add:

```swift
record.connReuse = Int(int64("conn_reuse"))
record.protoFlags = Int(int64("proto_flags"))
record.pushStatus = optInt64("push_status").map { Int($0) }
record.certChainRef = optStr("cert_chain_ref")
```

- [ ] **Step 5: Update ProtocolRecorder protocol**

In `Storage/Protocol/ProtocolRecorder.swift`, update the protocol and add default:

```swift
public protocol ProtocolRecorder: AnyObject {
    static var protocolName: String { get }
    static var searchKeyMapping: SearchKeyMapping { get }
    func buildFlowRecord(sessionRecorder: SessionRecorder?) -> FlowRecord
}

extension ProtocolRecorder {
    // Backward-compatible overload so existing callsites still compile
    public func buildFlowRecord() -> FlowRecord {
        buildFlowRecord(sessionRecorder: nil)
    }
}
```

- [ ] **Step 6: Update HTTPRecorder.buildFlowRecord() to merge SessionRecorder metadata**

In `Plugins/HTTP1/HTTPRecorder.swift`, change the method signature (line 101) and add protocol metadata merging at the end of the method, before `return record`:

```swift
public func buildFlowRecord(sessionRecorder: SessionRecorder? = nil) -> FlowRecord {
    // ... all existing code stays the same ...

    // After the existing metadata merge (after record.metadata.merge(extraMetadata)),
    // add protocol metadata from SessionRecorder:
    if let sr = sessionRecorder {
        record.connReuse = sr.connReuse
        record.protoFlags = sr.protoFlags
        record.pushStatus = sr.pushStatus
        record.certChainRef = sr.certChainRef

        if let poolKey = sr.connReusePoolKey {
            record.metadata["connReusePoolKey"] = poolKey
        }
        if sr.keepAliveRequestIndex > 0 {
            record.metadata["keepAliveRequestIndex"] = sr.keepAliveRequestIndex
        }
        if let streamId = sr.h2StreamId {
            record.metadata["h2StreamId"] = streamId
        }
        if let summary = sr.certChainSummary {
            record.metadata["certChainSummary"] = summary
        }
    }

    return record
}
```

- [ ] **Step 7: Update SessionRecorder.recordClosed() to pass self**

In `Framework/SessionRecorder.swift`, in `recordClosed()`, change line 370:

```swift
// Before:
let flowRecord = recorder.buildFlowRecord()
// After:
let flowRecord = recorder.buildFlowRecord(sessionRecorder: self)
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --package-path LocalPackages/TunnelServices --filter FlowRecordMetadata`
Expected: PASS

- [ ] **Step 9: Run all tests**

Run: `swift test --package-path LocalPackages/TunnelServices`
Expected: All tests pass

- [ ] **Step 10: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/FlowDAO.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP1/HTTPRecorder.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Framework/SessionRecorder.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/ProtocolRecorder.swift \
  LocalPackages/TunnelServices/Tests/TunnelServicesTests/FlowRecordMetadataTests.swift
git commit -m "feat: wire protocol metadata through FlowDAO, HTTPRecorder, and SessionRecorder"
```

---

### Task 4: HTTP/1.1 Handler Instrumentation

**Files:**
- Modify: `Plugins/HTTP1/HTTPCaptureHandler.swift`

**Problem:** HTTPCaptureHandler doesn't report connection reuse or keep-alive status.

**Design:** Add a `_keepAliveRequestIndex` counter (persists across keep-alive cycles). Call `markConnectionReuse` and `addProtoFlag` at the right points.

- [ ] **Step 1: Add request index counter to HTTPCaptureHandler**

In `HTTPCaptureHandler`, add a property (persists across cycles, unlike SessionRecorder):

```swift
private var _keepAliveIndex: Int = 0
```

- [ ] **Step 2: Instrument connectToServer — pool checkout path**

After the successful pool checkout (around line 165, where `self.clientChannel = result.channel`), add:

```swift
recorder.markConnectionReuse(.pooled, poolKey: "\(req.host):\(req.port):\(req.ssl)")
```

- [ ] **Step 3: Instrument channelRead(.head) — keep-alive reuse path**

In the `else` branch at line 125 (where existing clientChannel is reused), add:

```swift
_keepAliveIndex += 1
recorder.markConnectionReuse(.keepAlive, requestIndex: _keepAliveIndex)
recorder.addProtoFlag(.pipelining)
```

- [ ] **Step 4: Instrument ResponseRelayHandler — keep-alive flag**

IMPORTANT: The `.keepAlive` flag must be set BEFORE `recorder.recordClosed()` is called (line 460 in ResponseRelayHandler), because `recordClosed()` builds the FlowRecord and writes to DB.

In `ResponseRelayHandler.channelRead`, in the `.end` case, BEFORE `recorder.recordClosed()` (line 460), add:

```swift
if shouldKeepAlive() {
    recorder.addProtoFlag(.keepAlive)
}
```

This ensures the flag is captured in the FlowRecord before it's persisted.

- [ ] **Step 5: Build and run tests**

Run: `swift test --package-path LocalPackages/TunnelServices`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP1/HTTPCaptureHandler.swift
git commit -m "feat: instrument HTTPCaptureHandler with connection reuse and keep-alive tracking"
```

---

### Task 5: HTTP/2 Handler Instrumentation

**Files:**
- Modify: `Plugins/HTTP2/HTTP2CaptureHandler.swift`

**Problem:** H2 handlers don't report multiplexing, push status, flow control, or stream IDs.

- [ ] **Step 1: Instrument H2StreamCaptureHandler**

In `channelRead(.head)` (around line 259), after `request = NetRequest(head)`, add:

```swift
recorder.addProtoFlag(.h2Multiplexing)
```

In `createServerStream` success callback (around line 549), after registering stream mapping, add:

```swift
if let serverStreamID = try? stream.syncOptions?.getOption(HTTP2StreamChannelOptions.streamID) {
    self.recorder.setH2StreamId(Int(Int32(serverStreamID)))
}
```

- [ ] **Step 2: Instrument H2StreamCaptureHandler flow control**

In `channelWritabilityChanged` (around line 350), add:

```swift
recorder.addProtoFlag(.h2FlowControl)
```

- [ ] **Step 3: Instrument H2PushRelayHandler**

At the start of `channelRead(.head)` (around line 315), add:

```swift
recorder.addProtoFlag(.h2ServerPush)
recorder.markPushStatus(.captureOnly)  // default, upgraded if forwarding succeeds
```

After `pushPromiseSent = true` (around line 384), add:

```swift
recorder.markPushStatus(.forwarded)
```

In `tryForwardPushPromise` early returns (where forwarding can't proceed), add:

```swift
recorder.markPushStatus(.failed)
```

- [ ] **Step 4: Build and run tests**

Run: `swift test --package-path LocalPackages/TunnelServices`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP2/HTTP2CaptureHandler.swift
git commit -m "feat: instrument H2 handlers with multiplexing, push status, and flow control flags"
```

---

### Task 6: TLS Handler Instrumentation

**Files:**
- Modify: `Plugins/TLS/MITMHandler.swift`
- Modify: `Plugins/TLS/TLSPlugin.swift`

**Problem:** TLS handlers don't report MITM/tunnel/handshake status.

- [ ] **Step 1: Instrument MITMHandler**

In `channelRead` (around line 40, after `AxLogger.log("[MITM] channelRead"`), add:

```swift
recorder.addProtoFlag(.tlsMITM)
```

In the ALPN handler success callback (around line 116, after `recorder.recordHandshakeComplete()`), add:

```swift
recorder.addProtoFlag(.tlsHandshakeOK)
```

In `errorCaught`, in the SSL error branch (around line 202), add:

```swift
recorder.addProtoFlag(.tlsHandshakeFail)
```

In the handshake timeout callback (around line 107), add:

```swift
recorder.addProtoFlag(.tlsHandshakeTimeout)
```

- [ ] **Step 2: Instrument TLSPlugin**

In `buildPipeline`, in the tunnel passthrough branch (around line 76, where `recorder.session.schemes = "HTTPS(Tunnel)"`), add:

```swift
recorder.addProtoFlag(.tlsTunnel)
```

- [ ] **Step 3: Build and run tests**

Run: `swift test --package-path LocalPackages/TunnelServices`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/TLS/MITMHandler.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/TLS/TLSPlugin.swift
git commit -m "feat: instrument TLS handlers with MITM/tunnel/handshake flags"
```

---

### Task 7: WebSocket Instrumentation

**Files:**
- Modify: `Plugins/WebSocket/WebSocketCaptureHandler.swift`

**Problem:** WebSocket frame masking status is not recorded.

- [ ] **Step 1: Instrument WebSocketUpgradeInterceptor**

The file is `Plugins/WebSocket/WebSocketCaptureHandler.swift` but the class is `WebSocketUpgradeInterceptor` (line 31). It has a `recorder: SessionRecorder` property (line 35).

In `WebSocketUpgradeInterceptor.performWebSocketUpgrade()` (line 64), after the guard statement (line 68), add:

```swift
recorder.addProtoFlag(.wsFrameMasked)
```

This is set once when WS pipeline is established, since `WebSocketForwarder` always applies correct direction-aware masking.

- [ ] **Step 2: Build and run tests**

Run: `swift test --package-path LocalPackages/TunnelServices`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/WebSocket/WebSocketCaptureHandler.swift
git commit -m "feat: instrument WebSocket with frame masking flag"
```

---

### Task 8: Certificate Chain Storage + Export Service

**Files:**
- Create: `Storage/CertExportService.swift`
- Create: `Tests/.../CertExportServiceTests.swift`
- Modify: `Framework/SessionRecorder.swift` (recordClosed — cert write)
- Modify: `Plugins/TLS/MITMHandler.swift` (buffer certs after handshake)

**Problem:** TLS certificate chains are not persisted. No export capability exists.

**Design:** `CertExportService` handles PEM file write and export. `SessionRecorder.recordClosed()` calls the service to write buffered certs. `MITMHandler` buffers certs after successful ALPN negotiation.

- [ ] **Step 1: Write CertExportService tests**

```swift
// Tests/TunnelServicesTests/CertExportServiceTests.swift
import XCTest
@testable import TunnelServices

final class CertExportServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSavePEMCreatesFile() throws {
        let service = CertExportService(fileFolder: tempDir.path)
        // Use a test PEM string (no real NIOSSLCertificate needed for file I/O test)
        let testPEM = "-----BEGIN CERTIFICATE-----\nTESTDATA\n-----END CERTIFICATE-----\n"
        let ref = try service.savePEMString(flowId: "test-1", pemContent: testPEM)

        XCTAssertEqual(ref, "certs/test-1.pem")
        let fullPath = tempDir.appendingPathComponent(ref).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullPath))

        let content = try String(contentsOfFile: fullPath)
        XCTAssertEqual(content, testPEM)
    }

    func testExportReturnsFileContent() throws {
        let service = CertExportService(fileFolder: tempDir.path)
        let testPEM = "-----BEGIN CERTIFICATE-----\nDATA\n-----END CERTIFICATE-----\n"
        let ref = try service.savePEMString(flowId: "exp-1", pemContent: testPEM)

        let result = service.exportCertChain(certChainRef: ref)
        switch result {
        case .success(let export):
            XCTAssertEqual(export.pemText, testPEM)
        case .failure(let error):
            XCTFail("Export failed: \(error)")
        }
    }

    func testExportMissingFileReturnsError() {
        let service = CertExportService(fileFolder: tempDir.path)
        let result = service.exportCertChain(certChainRef: "certs/nonexistent.pem")
        if case .failure(let error) = result {
            if case .fileNotFound = error { /* expected */ }
            else { XCTFail("Wrong error type: \(error)") }
        } else {
            XCTFail("Should have failed")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path LocalPackages/TunnelServices --filter CertExportService`
Expected: Compilation failure

- [ ] **Step 3: Implement CertExportService**

```swift
// Storage/CertExportService.swift
import Foundation
import NIOSSL
import X509
import SwiftASN1
import Crypto

public final class CertExportService {

    private let fileFolder: String

    public init(fileFolder: String) {
        self.fileFolder = fileFolder
    }

    // MARK: - Save

    /// Save raw PEM text to file. Returns relative path.
    public func savePEMString(flowId: String, pemContent: String) throws -> String {
        let relPath = "certs/\(flowId).pem"
        let dir = (fileFolder as NSString).appendingPathComponent("certs")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let fullPath = (fileFolder as NSString).appendingPathComponent(relPath)
        try pemContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
        return relPath
    }

    /// Convert NIOSSLCertificates to PEM, save, and return (ref, summaries).
    public func saveCertChain(
        flowId: String,
        certificates: [NIOSSLCertificate]
    ) throws -> (ref: String, summary: [[String: String]]) {
        var pemParts = [String]()
        var summaries = [[String: String]]()

        for cert in certificates {
            let derBytes = try cert.toDERBytes()
            let base64 = Data(derBytes).base64EncodedString(options: .lineLength64Characters)
            pemParts.append("-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n")

            // Parse for summary
            let x509 = try Certificate(derEncoded: derBytes)
            summaries.append([
                "subject": x509.subject.description,
                "issuer": x509.issuer.description,
                "serial": x509.serialNumber.description,
                "sha256": SHA256.hash(data: Data(derBytes)).map { String(format: "%02x", $0) }.joined(),
                "notBefore": "\(x509.notValidBefore)",
                "notAfter": "\(x509.notValidAfter)",
            ])
        }

        let pemContent = pemParts.joined()
        let ref = try savePEMString(flowId: flowId, pemContent: pemContent)
        return (ref, summaries)
    }

    // MARK: - Export

    public struct CertExportResult {
        public let pemText: String
        public let summary: [[String: String]]
    }

    public enum CertExportError: Error {
        case noCertChain
        case fileNotFound(String)
        case parseFailed(String)
    }

    public func exportCertChain(certChainRef: String) -> Result<CertExportResult, CertExportError> {
        let fullPath = (fileFolder as NSString).appendingPathComponent(certChainRef)
        guard FileManager.default.fileExists(atPath: fullPath) else {
            return .failure(.fileNotFound(fullPath))
        }
        do {
            let pem = try String(contentsOfFile: fullPath, encoding: .utf8)
            // Parse PEM blocks for summaries
            var summaries = [[String: String]]()
            let blocks = pem.components(separatedBy: "-----END CERTIFICATE-----")
            for block in blocks {
                guard let range = block.range(of: "-----BEGIN CERTIFICATE-----") else { continue }
                let base64 = block[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if let derData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                    if let x509 = try? Certificate(derEncoded: Array(derData)) {
                        summaries.append([
                            "subject": x509.subject.description,
                            "issuer": x509.issuer.description,
                        ])
                    }
                }
            }
            return .success(CertExportResult(pemText: pem, summary: summaries))
        } catch {
            return .failure(.parseFailed(error.localizedDescription))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path LocalPackages/TunnelServices --filter CertExportService`
Expected: PASS

- [ ] **Step 5: Add certChainSummary to SessionRecorder**

In `Framework/SessionRecorder.swift`, add to the metadata state section:

```swift
private var _certChainSummary: [[String: String]]? = nil
public var certChainSummary: [[String: String]]? { _certChainSummary }
```

Add `import NIOSSL` at the top of the file (needed for `NIOSSLCertificate` cast).

- [ ] **Step 6: Wire cert buffering in MITMHandler**

In `MITMHandler.swift`, in the ALPN success callback (line 113-133), after `self.recorder.recordHandshakeComplete()` (line 117), add:

```swift
// Buffer the MITM-generated cert chain for PEM storage in recordClosed()
// `cert` is the NIOSSLCertificate from line 79, captured in this closure's scope
if let leafCert = niosslCert {
    var chain: [NIOSSLCertificate] = [leafCert]
    // Add CA cert if available
    if let caCertNIOSSL = self.task.certManager?.caCertNIOSSL {
        chain.append(caCertNIOSSL)
    }
    self.recorder.bufferCertificateChain(chain)
}
```

Note: `niosslCert` is the local variable from line 61-77 of MITMHandler.channelRead. It is captured by the ALPN closure. If the certManager doesn't expose a `caCertNIOSSL` property, derive it from `x509CACert` using `CertGenerator.toNIOSSL()`.

- [ ] **Step 7: Wire cert writing in SessionRecorder.recordClosed() (off EventLoop)**

In `SessionRecorder.recordClosed()`, BEFORE the FlowDAO.insert() call (line 370), add cert writing dispatched to a background queue to avoid blocking the EventLoop:

```swift
// Write buffered certificate chain to PEM file (off EventLoop)
if let certs = _bufferedCerts as? [NIOSSLCertificate],
   let fid = flowId,
   let folder = task.fileFolder {
    // Synchronous write is OK here because recordClosed() flushes data.
    // Use the protoWriteQueue if available, or do it inline since
    // the file write is small (< 10KB for a typical cert chain).
    let certService = CertExportService(fileFolder: folder)
    do {
        let (ref, summary) = try certService.saveCertChain(flowId: fid, certificates: certs)
        _certChainRef = ref
        _certChainSummary = summary
    } catch {
        NSLog("[SessionRecorder] cert chain save failed: \(error)")
    }
}
// _certChainRef and _certChainSummary are now set and will be
// picked up by buildFlowRecord(sessionRecorder: self) below.
```
```

- [ ] **Step 7: Run all tests**

Run: `swift test --package-path LocalPackages/TunnelServices`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/CertExportService.swift \
  LocalPackages/TunnelServices/Tests/TunnelServicesTests/CertExportServiceTests.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Framework/SessionRecorder.swift \
  LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/TLS/MITMHandler.swift
git commit -m "feat: add CertExportService for PEM cert chain storage and export"
```

---

## Post-Implementation Verification

After all tasks:

1. **Build**: `swift build --package-path LocalPackages/TunnelServices` — must pass
2. **Tests**: `swift test --package-path LocalPackages/TunnelServices` — all pass
3. **Schema migration**: Open existing protocol.db, verify 4 new columns exist after migration
4. **HTTP/1.1 flow**: Proxy an HTTP request, query `flow` table:
   - `conn_reuse` should be 0 (first request) or 1/2 (subsequent)
   - `proto_flags & 0x0001` should be set if keep-alive
5. **H2 flow**: Proxy an H2 request:
   - `proto_flags & 0x0004` should be set
   - metadata should contain `h2StreamId`
6. **TLS MITM**: Proxy an HTTPS request with MITM enabled:
   - `proto_flags & 0x0040` and `proto_flags & 0x0100` should be set
   - `cert_chain_ref` should point to existing PEM file
7. **Aggregate query**: `SELECT conn_reuse, COUNT(*) FROM flow GROUP BY conn_reuse` returns correct distribution
