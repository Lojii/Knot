# Protocol Recorders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WebSocket, DNS, gRPC, and HTTP/2/HTTP/3 protocol recorders, plus extend existing DAOs for multi-entry queries.

**Architecture:** Each new protocol gets a Recorder class implementing `ProtocolRecorder`. WebSocket/gRPC write frame/message data to decoded.db in real-time. DNS stores everything in flow metadata. HTTP/2 and HTTP/3 reuse HTTPRecorder with `protocolOverride`. Handler integration via dual-write alongside existing code.

**Tech Stack:** Swift 5.9, SQLite.swift, SwiftNIO

**Spec:** `docs/superpowers/specs/2026-03-19-multi-protocol-ui-cleanup-design.md` (Sub-project A)

---

## File Structure

```
Sources/TunnelServices/Storage/
├── Protocol/
│   ├── HTTPRecorder.swift              # MODIFY: add protocolOverride + extraMetadata
│   ├── WebSocketRecorder.swift         # NEW
│   ├── DNSRecorder.swift               # NEW
│   └── GRPCRecorder.swift              # NEW
├── DAO/
│   ├── FlowDAO.swift                   # MODIFY: add keyword search
│   └── DecodedEntryDAO.swift           # MODIFY: add findAll with pagination

Tests/TunnelServicesTests/Storage/
├── WebSocketRecorderTests.swift        # NEW
├── DNSRecorderTests.swift              # NEW
├── GRPCRecorderTests.swift             # NEW
└── FlowDAOSearchTests.swift            # NEW
```

Note: Handler integration (WebSocketCaptureHandler, HTTP2CaptureHandler, etc.) is deferred — it requires careful testing with live captures. This plan focuses on the Recorder classes and DAO extensions that can be fully unit tested.

---

### Task 1: Extend HTTPRecorder with protocolOverride + extraMetadata

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/HTTPRecorder.swift`
- Modify: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/HTTPRecorderTests.swift`

- [ ] **Step 1: Add tests for protocolOverride**

Add to HTTPRecorderTests:
```swift
func testProtocolOverrideH2() {
    let recorder = HTTPRecorder(flowId: "h2_0001", host: "api.example.com", port: 443,
                                protocolOverride: "H2", extraMetadata: ["streamId": 5])
    recorder.recordRequestHead(method: "GET", uri: "/api", httpVersion: "HTTP/2", headers: [])
    recorder.recordResponseHead(statusCode: 200, headers: [])
    let record = recorder.buildFlowRecord()
    XCTAssertEqual(record.protocolName, "H2")
    XCTAssertEqual(record.metadata["streamId"] as? Int, 5)
}

func testProtocolOverrideH3() {
    let recorder = HTTPRecorder(flowId: "h3_0001", host: "api.example.com", port: 443,
                                protocolOverride: "H3", extraMetadata: ["quicVersion": "1", "streamId": 0])
    recorder.recordRequestHead(method: "POST", uri: "/data", httpVersion: "HTTP/3", headers: [])
    recorder.recordResponseHead(statusCode: 201, headers: [])
    let record = recorder.buildFlowRecord()
    XCTAssertEqual(record.protocolName, "H3")
    XCTAssertEqual(record.metadata["quicVersion"] as? String, "1")
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Add protocolOverride and extraMetadata to HTTPRecorder**

Read the current HTTPRecorder.swift. Add:
- `private var protocolOverride: String?` property
- `private var extraMetadata: [String: Any]` property
- Update `init` to accept `protocolOverride: String? = nil, extraMetadata: [String: Any] = [:]`
- In `buildFlowRecord()`: use `protocolOverride ?? Self.protocolName` for protocolName, and `record.metadata.merge(extraMetadata) { _, new in new }`

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/HTTPRecorder.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/HTTPRecorderTests.swift
git commit -m "feat(storage): add protocolOverride and extraMetadata to HTTPRecorder"
```

---

### Task 2: Extend DecodedEntryDAO with findAll pagination

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/DecodedEntryDAO.swift`
- Modify: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/DecodedEntryDAOTests.swift`

- [ ] **Step 1: Add test for findAll**

Add to DecodedEntryDAOTests:
```swift
func testFindAllPaginated() throws {
    // Insert 10 entries for same flow, different sequences
    for i in 0..<10 {
        let entry = DecodedEntry(flowId: "ws_001", direction: i % 2,
            decodedType: "text", decodedSize: 100,
            searchText: "frame \(i)", decodedAt: Double(1000 + i), sequence: i / 2)
        try DecodedEntryDAO.insert(db: db, entry: entry)
    }
    // Page 1
    let page1 = try DecodedEntryDAO.findAll(db: db, flowId: "ws_001", offset: 0, limit: 5)
    XCTAssertEqual(page1.count, 5)
    // Page 2
    let page2 = try DecodedEntryDAO.findAll(db: db, flowId: "ws_001", offset: 5, limit: 5)
    XCTAssertEqual(page2.count, 5)
    // Ordered by decoded_at ASC
    XCTAssertTrue(page1[0].decodedAt <= page1[4].decodedAt)
}
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement findAll**

Add to DecodedEntryDAO:
```swift
public static func findAll(db: Connection, flowId: String, offset: Int = 0, limit: Int = 50) throws -> [DecodedEntry] {
    let stmt = try db.prepare(
        "SELECT * FROM decoded_entry WHERE flow_id = ? ORDER BY decoded_at ASC LIMIT ? OFFSET ?",
        flowId, limit, offset
    )
    return stmt.map { mapRow($0) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/DecodedEntryDAO.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/DecodedEntryDAOTests.swift
git commit -m "feat(storage): add findAll with pagination to DecodedEntryDAO"
```

---

### Task 3: Extend FlowDAO with keyword search

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/FlowDAO.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/FlowDAOSearchTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class FlowDAOSearchTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "protocol.db")
        try! ProtocolSchema.create(db)
        // Seed data
        for i in 0..<5 {
            var r = FlowRecord(flowId: "f_\(i)", protocolName: "HTTP",
                               host: "api.example.com", port: 443, startedAt: Double(i))
            r.searchKey2 = "/api/users/\(i)"
            r.summary = "GET /api/users/\(i) → 200"
            try! FlowDAO.insert(db: db, record: r)
        }
        var dns = FlowRecord(flowId: "dns_1", protocolName: "DNS",
                             host: "example.com", port: 53, startedAt: 10)
        dns.summary = "A example.com → 1.2.3.4"
        try! FlowDAO.insert(db: db, record: dns)
    }
    override func tearDown() { helper = nil }

    func testKeywordSearchHost() throws {
        let results = try FlowDAO.query(db: db, keyword: "example")
        XCTAssertEqual(results.count, 6) // all 5 HTTP + 1 DNS
    }

    func testKeywordSearchUri() throws {
        let results = try FlowDAO.query(db: db, keyword: "users/3")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].flowId, "f_3")
    }

    func testKeywordSearchSummary() throws {
        let results = try FlowDAO.query(db: db, keyword: "1.2.3.4")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].protocolName, "DNS")
    }

    func testKeywordWithProtocolFilter() throws {
        let results = try FlowDAO.query(db: db, protocolFilter: "HTTP", keyword: "users")
        XCTAssertEqual(results.count, 5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Add keyword parameter to FlowDAO.query**

Read current FlowDAO.swift. Add an optional `keyword: String? = nil` parameter. When non-nil, add:
```sql
AND (host LIKE ? OR search_key2 LIKE ? OR summary LIKE ?)
```
with `%keyword%` bindings.

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/FlowDAO.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/FlowDAOSearchTests.swift
git commit -m "feat(storage): add keyword search to FlowDAO.query"
```

---

### Task 4: WebSocketRecorder

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/WebSocketRecorder.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/WebSocketRecorderTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class WebSocketRecorderTests: XCTestCase {
    var helper: StorageTestHelper!
    var dbGroup: TaskDatabaseGroup!

    override func setUp() {
        helper = StorageTestHelper()
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        dbGroup = try! mgr.openTask(1)
    }
    override func tearDown() { helper = nil }

    func testBuildFlowRecord() {
        let recorder = WebSocketRecorder(
            flowId: "ws_001", host: "ws.example.com", port: 443, uri: "/chat",
            isSecure: true, dbGroup: dbGroup
        )
        recorder.recordUpgradeHeaders(
            reqHeaders: [("Sec-WebSocket-Protocol", "graphql-ws")],
            rspHeaders: [("Sec-WebSocket-Accept", "xxx")]
        )
        recorder.recordFrame(direction: 0, opcode: "text", payload: Data("hello".utf8), timestamp: 1000)
        recorder.recordFrame(direction: 1, opcode: "text", payload: Data("world".utf8), timestamp: 1001)
        recorder.recordClosed(closeCode: 1000)

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "WSS")
        XCTAssertEqual(record.host, "ws.example.com")
        XCTAssertEqual(record.searchKey1, "graphql-ws")
        XCTAssertEqual(record.searchKey2, "/chat")
        XCTAssertEqual(record.searchKey3, "2")  // 2 total frames
        XCTAssertEqual(record.searchKey4, "1000") // close code
        XCTAssertTrue(record.summary.contains("↑1"))
        XCTAssertTrue(record.summary.contains("↓1"))
    }

    func testFramesWrittenToDecodedDB() throws {
        let recorder = WebSocketRecorder(
            flowId: "ws_002", host: "ws.example.com", port: 443, uri: "/chat",
            isSecure: false, dbGroup: dbGroup
        )
        recorder.recordFrame(direction: 0, opcode: "text", payload: Data("msg1".utf8), timestamp: 1000)
        recorder.recordFrame(direction: 1, opcode: "text", payload: Data("msg2".utf8), timestamp: 1001)

        // Wait for write queue
        dbGroup.decodedWriteQueue.sync {}

        let entries = try DecodedEntryDAO.findAll(db: dbGroup.decoded, flowId: "ws_002")
        XCTAssertEqual(entries.count, 2)
    }

    func testSearchKeyMapping() {
        XCTAssertEqual(WebSocketRecorder.searchKeyMapping.key1, "subprotocol")
        XCTAssertEqual(WebSocketRecorder.searchKeyMapping.key2, "uri")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement WebSocketRecorder**

Key design:
- `init` inserts a preliminary Flow (status=inProgress) to protocol.db immediately
- `recordFrame(direction:opcode:payload:timestamp:)` writes to decoded.db in real-time via `dbGroup.decodedWriteQueue`
  - TEXT ≤ 4KB → inline_data + search_text
  - TEXT > 4KB or BINARY → file storage (direct FileManager write)
  - PING/PONG/CLOSE → metadata only (no payload storage)
- `recordClosed(closeCode:)` updates the Flow record (endedAt, summary, status, searchKeys)
- `buildFlowRecord()` returns the accumulated FlowRecord
- Client/server frame sequences tracked independently

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/WebSocketRecorder.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/WebSocketRecorderTests.swift
git commit -m "feat(storage): add WebSocketRecorder with real-time frame recording"
```

---

### Task 5: DNSRecorder

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/DNSRecorder.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/DNSRecorderTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import TunnelServices

final class DNSRecorderTests: XCTestCase {
    func testUDPDNSRecord() {
        let recorder = DNSRecorder(flowId: "dns_001", transport: .udp, serverIp: "8.8.8.8", serverPort: 53)
        recorder.recordQuery(domain: "example.com", queryType: "A", dnsId: 1234)
        recorder.recordResponse(
            responseCode: "NOERROR",
            answers: [["name": "example.com", "type": "A", "ttl": 300, "data": "93.184.216.34"]],
            authorities: [], additionals: []
        )
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "DNS")
        XCTAssertEqual(record.host, "example.com")
        XCTAssertEqual(record.port, 53)
        XCTAssertEqual(record.searchKey1, "A")
        XCTAssertEqual(record.searchKey2, "example.com")
        XCTAssertEqual(record.searchKey3, "93.184.216.34")
        XCTAssertEqual(record.searchKey4, "NOERROR")
        XCTAssertEqual(record.metadata["transport"] as? String, "udp")
        XCTAssertEqual(record.summary, "A example.com → 93.184.216.34")
    }

    func testDoHDNSRecord() {
        let recorder = DNSRecorder(flowId: "dns_002", transport: .doh, serverIp: "1.1.1.1", serverPort: 443)
        recorder.httpFlowId = "http_042"
        recorder.recordQuery(domain: "api.example.com", queryType: "AAAA", dnsId: 5678)
        recorder.recordResponse(responseCode: "NXDOMAIN", answers: [], authorities: [], additionals: [])
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.metadata["transport"] as? String, "doh")
        XCTAssertEqual(record.metadata["httpFlowId"] as? String, "http_042")
        XCTAssertEqual(record.searchKey3, "")  // no answers
        XCTAssertEqual(record.searchKey4, "NXDOMAIN")
        XCTAssertTrue(record.summary.contains("NXDOMAIN"))
    }

    func testSearchKeyMapping() {
        XCTAssertEqual(DNSRecorder.searchKeyMapping.key1, "queryType")
        XCTAssertEqual(DNSRecorder.searchKeyMapping.key2, "domain")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement DNSRecorder**

```swift
public enum DNSTransport: String {
    case udp = "udp"
    case doh = "doh"
}

public class DNSRecorder: ProtocolRecorder {
    public static let protocolName = "DNS"
    public static let searchKeyMapping = SearchKeyMapping(
        key1: "queryType", key2: "domain", key3: "firstAnswer", key4: "responseCode"
    )
    // Properties: flowId, transport, serverIp, serverPort, httpFlowId (optional)
    // Query data: domain, queryType, dnsId, questions
    // Response data: responseCode, answers, authorities, additionals
    // buildFlowRecord(): assembles everything into FlowRecord with full metadata JSON
}
```

DNS stores ALL data in `flow.metadata` — no decoded.db, no payload files.

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/DNSRecorder.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/DNSRecorderTests.swift
git commit -m "feat(storage): add DNSRecorder for UDP and DoH DNS flows"
```

---

### Task 6: GRPCRecorder

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/GRPCRecorder.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/GRPCRecorderTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class GRPCRecorderTests: XCTestCase {
    var helper: StorageTestHelper!
    var dbGroup: TaskDatabaseGroup!

    override func setUp() {
        helper = StorageTestHelper()
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        dbGroup = try! mgr.openTask(1)
    }
    override func tearDown() { helper = nil }

    func testUnaryRPC() {
        let recorder = GRPCRecorder(
            flowId: "grpc_001", host: "api.example.com", port: 443,
            path: "/UserService/GetUser", dbGroup: dbGroup
        )
        recorder.recordRequestMessage(data: Data("{\"id\":1}".utf8), sequence: 0)
        recorder.recordResponseMessage(data: Data("{\"name\":\"Alice\"}".utf8), sequence: 0)
        recorder.recordClosed(grpcStatus: 0, grpcMessage: "OK",
                              trailers: [("grpc-status", "0")])
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "gRPC")
        XCTAssertEqual(record.searchKey1, "GetUser")
        XCTAssertEqual(record.searchKey2, "UserService")
        XCTAssertEqual(record.searchKey3, "0")
        XCTAssertEqual(record.searchKey4, "OK")
        XCTAssertEqual(record.summary, "UserService/GetUser → OK")
    }

    func testStreamingRPC() {
        let recorder = GRPCRecorder(
            flowId: "grpc_002", host: "api.example.com", port: 443,
            path: "/ChatService/StreamMessages", dbGroup: dbGroup
        )
        for i in 0..<3 {
            recorder.recordResponseMessage(data: Data("msg\(i)".utf8), sequence: i)
        }
        recorder.recordClosed(grpcStatus: 0, grpcMessage: "OK", trailers: [])

        // Verify messages written to decoded.db
        dbGroup.decodedWriteQueue.sync {}
        let entries = try! DecodedEntryDAO.findAll(db: dbGroup.decoded, flowId: "grpc_002")
        XCTAssertEqual(entries.count, 3)
    }

    func testSearchKeyMapping() {
        XCTAssertEqual(GRPCRecorder.searchKeyMapping.key1, "method")
        XCTAssertEqual(GRPCRecorder.searchKeyMapping.key2, "service")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement GRPCRecorder**

Parses `path` to extract service and method (e.g. `/UserService/GetUser` → service=`UserService`, method=`GetUser`).
Each message written to decoded.db via `DecodedEntryDAO.insert` (direction 0=req, 1=rsp, sequence incrementing).
On close, builds FlowRecord with gRPC-specific search keys and metadata (headers, trailers).

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/GRPCRecorder.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/GRPCRecorderTests.swift
git commit -m "feat(storage): add GRPCRecorder with streaming message support"
```

---

## Post-Implementation Notes

Handler integration (wiring recorders into WebSocketCaptureHandler, HTTP2CaptureHandler, HTTPCaptureHandler DoH detection, UDPForwarder DNS) is deferred to a separate integration plan. The recorders are fully unit-testable without live network capture.
