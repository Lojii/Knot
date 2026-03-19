# Connection.db Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a connection.db database layer between transport.db and protocol.db, storing TCP connection and QUIC connection/stream state.

**Architecture:** New ConnectionSchema with 3 tables (tcp_connection, quic_connection, quic_stream). Existing state.db `connection` table migrated to connection.db `tcp_connection` with expanded fields. TaskDatabaseGroup expands from 4 to 5 databases. Existing ConnectionDAO replaced by TcpConnectionDAO.

**Tech Stack:** Swift 5.9, SQLite.swift 0.16+

**Spec:** `docs/superpowers/specs/2026-03-19-multi-protocol-ui-cleanup-design.md` (Sub-project A0 section)

---

## File Structure

```
LocalPackages/TunnelServices/Sources/TunnelServices/Storage/
├── Schema/
│   ├── ConnectionSchema.swift          # NEW: tcp_connection + quic_connection + quic_stream DDL
│   └── StateSchema.swift               # MODIFY: remove connection table
├── Model/
│   ├── ConnectionRecord.swift          # MODIFY: rename to TcpConnectionRecord, add fields
│   ├── QuicConnectionRecord.swift      # NEW
│   └── QuicStreamRecord.swift          # NEW
├── DAO/
│   ├── ConnectionDAO.swift             # DELETE: replaced by TcpConnectionDAO
│   ├── TcpConnectionDAO.swift          # NEW: TCP connection CRUD
│   ├── QuicConnectionDAO.swift         # NEW: QUIC connection CRUD
│   └── QuicStreamDAO.swift             # NEW: QUIC stream CRUD
├── PathManager.swift                   # MODIFY: add connectionDBPath
├── TaskDatabaseGroup.swift             # MODIFY: add 5th database
└── DatabaseManager.swift               # (no change needed, uses TaskDatabaseGroup)

Tests/TunnelServicesTests/Storage/
├── ConnectionSchemaTests.swift         # NEW
├── TcpConnectionDAOTests.swift         # NEW
└── QuicDAOTests.swift                  # NEW
```

---

## Phase 1: Schema and Models

### Task 1: Add connectionDBPath to PathManager

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/PathManager.swift`
- Modify: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/PathManagerTests.swift`

- [ ] **Step 1: Add test for connectionDBPath**

Add to `PathManagerTests.swift`:
```swift
func testConnectionDBPath() {
    let path = PathManager.connectionDBPath(42, root: helper.tempDir)
    XCTAssertTrue(path.hasSuffix("/tasks/42/connection.db"))
}
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Add connectionDBPath to PathManager**

Add after `stateDBPath` in PathManager.swift:
```swift
public static func connectionDBPath(_ taskId: Int64, root: String? = nil) -> String {
    "\(taskDirectory(taskId, root: root))/connection.db"
}
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/PathManager.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/PathManagerTests.swift
git commit -m "feat(storage): add connectionDBPath to PathManager"
```

---

### Task 2: ConnectionSchema

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Schema/ConnectionSchema.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/ConnectionSchemaTests.swift`

- [ ] **Step 1: Write schema tests**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class ConnectionSchemaTests: XCTestCase {
    var helper: StorageTestHelper!
    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testCreatesTables() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        let tables = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            .map { $0[0] as! String }
        XCTAssertTrue(tables.contains("tcp_connection"))
        XCTAssertTrue(tables.contains("quic_connection"))
        XCTAssertTrue(tables.contains("quic_stream"))
    }

    func testIdempotent() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        try ConnectionSchema.create(db) // should not throw
    }

    func testTcpConnectionInsert() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        try db.run("""
            INSERT INTO tcp_connection (flow_id, src_ip, src_port, dst_ip, dst_port, started_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, "tcp_001", "192.168.1.1", 12345, "10.0.0.1", 443, 1000.0)
        let count = try db.scalar("SELECT COUNT(*) FROM tcp_connection") as! Int64
        XCTAssertEqual(count, 1)
    }

    func testQuicConnectionInsert() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        try db.run("""
            INSERT INTO quic_connection (flow_id, src_ip, src_port, dst_ip, dst_port, started_at, version, dcid, scid)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, "quic_001", "192.168.1.1", 54321, "10.0.0.1", 443, 1000.0, "1", "abcd", "1234")
        let count = try db.scalar("SELECT COUNT(*) FROM quic_connection") as! Int64
        XCTAssertEqual(count, 1)
    }

    func testQuicStreamUniqueConstraint() throws {
        let db = try helper.createTempDB(name: "connection.db")
        try ConnectionSchema.create(db)
        try db.run("""
            INSERT INTO quic_stream (connection_id, stream_id, started_at)
            VALUES (?, ?, ?)
            """, "quic_001", 1, 1000.0)
        // Same connection_id + stream_id should fail
        XCTAssertThrowsError(try db.run("""
            INSERT INTO quic_stream (connection_id, stream_id, started_at)
            VALUES (?, ?, ?)
            """, "quic_001", 1, 1001.0))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement ConnectionSchema**

Create `Storage/Schema/ConnectionSchema.swift` with exact SQL from spec (lines 36-106). Use `db.execute()` per statement, all with `IF NOT EXISTS`.

```swift
import Foundation
import SQLite

public enum ConnectionSchema {
    public static func create(_ db: Connection) throws {
        // tcp_connection table
        try db.execute("""
            CREATE TABLE IF NOT EXISTS tcp_connection (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL UNIQUE,
                src_ip TEXT NOT NULL,
                src_port INTEGER NOT NULL,
                dst_ip TEXT NOT NULL,
                dst_port INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT 'open',
                started_at REAL NOT NULL,
                established_at REAL,
                closed_at REAL,
                close_reason TEXT NOT NULL DEFAULT '',
                tls_version TEXT NOT NULL DEFAULT '',
                tls_cipher TEXT NOT NULL DEFAULT '',
                tls_sni TEXT NOT NULL DEFAULT '',
                server_cert TEXT NOT NULL DEFAULT '',
                packets_in INTEGER NOT NULL DEFAULT 0,
                packets_out INTEGER NOT NULL DEFAULT 0,
                bytes_in INTEGER NOT NULL DEFAULT 0,
                bytes_out INTEGER NOT NULL DEFAULT 0
            )
            """)
        // quic_connection table
        try db.execute("""
            CREATE TABLE IF NOT EXISTS quic_connection (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_id TEXT NOT NULL UNIQUE,
                src_ip TEXT NOT NULL,
                src_port INTEGER NOT NULL,
                dst_ip TEXT NOT NULL,
                dst_port INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT 'handshaking',
                started_at REAL NOT NULL,
                established_at REAL,
                closed_at REAL,
                close_reason TEXT NOT NULL DEFAULT '',
                version TEXT NOT NULL DEFAULT '',
                dcid TEXT NOT NULL DEFAULT '',
                scid TEXT NOT NULL DEFAULT '',
                alpn TEXT NOT NULL DEFAULT '',
                tls_cipher TEXT NOT NULL DEFAULT '',
                tls_sni TEXT NOT NULL DEFAULT '',
                server_cert TEXT NOT NULL DEFAULT '',
                is_0rtt INTEGER NOT NULL DEFAULT 0,
                packets_in INTEGER NOT NULL DEFAULT 0,
                packets_out INTEGER NOT NULL DEFAULT 0,
                bytes_in INTEGER NOT NULL DEFAULT 0,
                bytes_out INTEGER NOT NULL DEFAULT 0,
                streams_count INTEGER NOT NULL DEFAULT 0
            )
            """)
        // quic_stream table
        try db.execute("""
            CREATE TABLE IF NOT EXISTS quic_stream (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                connection_id TEXT NOT NULL,
                stream_id INTEGER NOT NULL,
                stream_type TEXT NOT NULL DEFAULT '',
                state TEXT NOT NULL DEFAULT 'open',
                started_at REAL NOT NULL,
                closed_at REAL,
                protocol_flow_id TEXT NOT NULL DEFAULT '',
                bytes_in INTEGER NOT NULL DEFAULT 0,
                bytes_out INTEGER NOT NULL DEFAULT 0,
                UNIQUE(connection_id, stream_id)
            )
            """)
        // Indexes
        try db.execute("CREATE INDEX IF NOT EXISTS idx_tcp_conn_flow_id ON tcp_connection(flow_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_quic_conn_flow_id ON quic_connection(flow_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_quic_stream_conn ON quic_stream(connection_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_quic_stream_proto ON quic_stream(protocol_flow_id)")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Schema/ConnectionSchema.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/ConnectionSchemaTests.swift
git commit -m "feat(storage): add ConnectionSchema with tcp/quic/stream tables"
```

---

### Task 3: Model structs (TcpConnectionRecord, QuicConnectionRecord, QuicStreamRecord)

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Model/ConnectionRecord.swift` (rename to TcpConnectionRecord + add fields)
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Model/QuicConnectionRecord.swift`
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Model/QuicStreamRecord.swift`

- [ ] **Step 1: Rename ConnectionRecord to TcpConnectionRecord and add new fields**

Replace the entire content of `ConnectionRecord.swift`:

```swift
import Foundation

/// TCP connection record.
/// Maps to the `tcp_connection` table in connection.db.
public struct TcpConnectionRecord {
    public let flowId: String
    public var srcIp: String
    public var srcPort: Int
    public var dstIp: String
    public var dstPort: Int
    public var state: String
    public var startedAt: TimeInterval
    public var establishedAt: TimeInterval?
    public var closedAt: TimeInterval?
    public var closeReason: String
    public var tlsVersion: String
    public var tlsCipher: String
    public var tlsSni: String
    public var serverCert: String
    public var packetsIn: Int64
    public var packetsOut: Int64
    public var bytesIn: Int64
    public var bytesOut: Int64

    public init(flowId: String, srcIp: String, srcPort: Int, dstIp: String, dstPort: Int,
                startedAt: TimeInterval, state: String = "open",
                establishedAt: TimeInterval? = nil, closedAt: TimeInterval? = nil,
                closeReason: String = "", tlsVersion: String = "", tlsCipher: String = "",
                tlsSni: String = "", serverCert: String = "",
                packetsIn: Int64 = 0, packetsOut: Int64 = 0,
                bytesIn: Int64 = 0, bytesOut: Int64 = 0) {
        self.flowId = flowId
        self.srcIp = srcIp; self.srcPort = srcPort
        self.dstIp = dstIp; self.dstPort = dstPort
        self.state = state; self.startedAt = startedAt
        self.establishedAt = establishedAt; self.closedAt = closedAt
        self.closeReason = closeReason
        self.tlsVersion = tlsVersion; self.tlsCipher = tlsCipher
        self.tlsSni = tlsSni; self.serverCert = serverCert
        self.packetsIn = packetsIn; self.packetsOut = packetsOut
        self.bytesIn = bytesIn; self.bytesOut = bytesOut
    }
}
```

- [ ] **Step 2: Create QuicConnectionRecord.swift**

```swift
import Foundation

/// QUIC connection record.
/// Maps to the `quic_connection` table in connection.db.
public struct QuicConnectionRecord {
    public let flowId: String
    public var srcIp: String
    public var srcPort: Int
    public var dstIp: String
    public var dstPort: Int
    public var state: String
    public var startedAt: TimeInterval
    public var establishedAt: TimeInterval?
    public var closedAt: TimeInterval?
    public var closeReason: String
    public var version: String
    public var dcid: String
    public var scid: String
    public var alpn: String
    public var tlsCipher: String
    public var tlsSni: String
    public var serverCert: String
    public var is0rtt: Bool
    public var packetsIn: Int64
    public var packetsOut: Int64
    public var bytesIn: Int64
    public var bytesOut: Int64
    public var streamsCount: Int64

    public init(flowId: String, srcIp: String, srcPort: Int, dstIp: String, dstPort: Int,
                startedAt: TimeInterval, state: String = "handshaking",
                establishedAt: TimeInterval? = nil, closedAt: TimeInterval? = nil,
                closeReason: String = "", version: String = "",
                dcid: String = "", scid: String = "", alpn: String = "",
                tlsCipher: String = "", tlsSni: String = "", serverCert: String = "",
                is0rtt: Bool = false,
                packetsIn: Int64 = 0, packetsOut: Int64 = 0,
                bytesIn: Int64 = 0, bytesOut: Int64 = 0, streamsCount: Int64 = 0) {
        self.flowId = flowId
        self.srcIp = srcIp; self.srcPort = srcPort
        self.dstIp = dstIp; self.dstPort = dstPort
        self.state = state; self.startedAt = startedAt
        self.establishedAt = establishedAt; self.closedAt = closedAt
        self.closeReason = closeReason
        self.version = version; self.dcid = dcid; self.scid = scid; self.alpn = alpn
        self.tlsCipher = tlsCipher; self.tlsSni = tlsSni; self.serverCert = serverCert
        self.is0rtt = is0rtt
        self.packetsIn = packetsIn; self.packetsOut = packetsOut
        self.bytesIn = bytesIn; self.bytesOut = bytesOut
        self.streamsCount = streamsCount
    }
}
```

- [ ] **Step 3: Create QuicStreamRecord.swift**

```swift
import Foundation

/// QUIC stream record.
/// Maps to the `quic_stream` table in connection.db.
public struct QuicStreamRecord {
    public let connectionId: String
    public let streamId: Int
    public var streamType: String
    public var state: String
    public var startedAt: TimeInterval
    public var closedAt: TimeInterval?
    public var protocolFlowId: String
    public var bytesIn: Int64
    public var bytesOut: Int64

    public init(connectionId: String, streamId: Int, startedAt: TimeInterval,
                streamType: String = "", state: String = "open",
                closedAt: TimeInterval? = nil, protocolFlowId: String = "",
                bytesIn: Int64 = 0, bytesOut: Int64 = 0) {
        self.connectionId = connectionId; self.streamId = streamId
        self.streamType = streamType; self.state = state
        self.startedAt = startedAt; self.closedAt = closedAt
        self.protocolFlowId = protocolFlowId
        self.bytesIn = bytesIn; self.bytesOut = bytesOut
    }
}
```

- [ ] **Step 4: Fix any compilation errors from ConnectionRecord → TcpConnectionRecord rename**

Search for all references to `ConnectionRecord` in the codebase and update them. The main reference is in `ConnectionDAO.swift` which will be replaced in Task 5. Check if `SessionRecorder.swift` references it.

- [ ] **Step 5: Verify build passes**

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Model/
git commit -m "feat(storage): add TcpConnectionRecord, QuicConnectionRecord, QuicStreamRecord models"
```

---

## Phase 2: DAOs

### Task 4: TcpConnectionDAO (replaces ConnectionDAO)

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/TcpConnectionDAO.swift`
- Delete: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/ConnectionDAO.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/TcpConnectionDAOTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class TcpConnectionDAOTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "connection.db")
        try! ConnectionSchema.create(db)
    }
    override func tearDown() { helper = nil }

    func testInsertAndFind() throws {
        let record = TcpConnectionRecord(
            flowId: "tcp_001", srcIp: "192.168.1.1", srcPort: 12345,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0,
            tlsSni: "example.com"
        )
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)
        let found = try TcpConnectionDAO.find(db: db, flowId: "tcp_001")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.dstPort, 443)
        XCTAssertEqual(found?.tlsSni, "example.com")
    }

    func testUpsertUpdatesOnConflict() throws {
        var record = TcpConnectionRecord(
            flowId: "tcp_001", srcIp: "192.168.1.1", srcPort: 12345,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0
        )
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)

        record.state = "closed"
        record.closedAt = 2000.0
        record.closeReason = "normal"
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)

        let found = try TcpConnectionDAO.find(db: db, flowId: "tcp_001")
        XCTAssertEqual(found?.state, "closed")
        XCTAssertEqual(found?.closedAt, 2000.0)
    }

    func testUpdateStats() throws {
        let record = TcpConnectionRecord(
            flowId: "tcp_001", srcIp: "192.168.1.1", srcPort: 12345,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0
        )
        try TcpConnectionDAO.insertOrUpdate(db: db, record: record)
        try TcpConnectionDAO.updateStats(db: db, flowId: "tcp_001",
                                          packetsIn: 100, packetsOut: 50,
                                          bytesIn: 4096, bytesOut: 1024)
        let found = try TcpConnectionDAO.find(db: db, flowId: "tcp_001")
        XCTAssertEqual(found?.packetsIn, 100)
        XCTAssertEqual(found?.bytesIn, 4096)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement TcpConnectionDAO**

```swift
import Foundation
import SQLite

public enum TcpConnectionDAO {
    public static func insertOrUpdate(db: Connection, record: TcpConnectionRecord) throws {
        try db.run("""
            INSERT INTO tcp_connection (flow_id, src_ip, src_port, dst_ip, dst_port,
                state, started_at, established_at, closed_at, close_reason,
                tls_version, tls_cipher, tls_sni, server_cert,
                packets_in, packets_out, bytes_in, bytes_out)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(flow_id) DO UPDATE SET
                state = excluded.state, established_at = excluded.established_at,
                closed_at = excluded.closed_at, close_reason = excluded.close_reason,
                tls_version = excluded.tls_version, tls_cipher = excluded.tls_cipher,
                tls_sni = excluded.tls_sni, server_cert = excluded.server_cert
            """,
            record.flowId, record.srcIp, record.srcPort, record.dstIp, record.dstPort,
            record.state, record.startedAt, record.establishedAt, record.closedAt, record.closeReason,
            record.tlsVersion, record.tlsCipher, record.tlsSni, record.serverCert,
            record.packetsIn, record.packetsOut, record.bytesIn, record.bytesOut
        )
    }

    public static func find(db: Connection, flowId: String) throws -> TcpConnectionRecord? {
        let stmt = try db.prepare("SELECT * FROM tcp_connection WHERE flow_id = ?", flowId)
        for row in stmt {
            return TcpConnectionRecord(
                flowId: row[1] as? String ?? "", srcIp: row[2] as? String ?? "",
                srcPort: Int(row[3] as? Int64 ?? 0), dstIp: row[4] as? String ?? "",
                dstPort: Int(row[5] as? Int64 ?? 0), startedAt: row[7] as? Double ?? 0,
                state: row[6] as? String ?? "open",
                establishedAt: row[8] as? Double, closedAt: row[9] as? Double,
                closeReason: row[10] as? String ?? "",
                tlsVersion: row[11] as? String ?? "", tlsCipher: row[12] as? String ?? "",
                tlsSni: row[13] as? String ?? "", serverCert: row[14] as? String ?? "",
                packetsIn: row[15] as? Int64 ?? 0, packetsOut: row[16] as? Int64 ?? 0,
                bytesIn: row[17] as? Int64 ?? 0, bytesOut: row[18] as? Int64 ?? 0
            )
        }
        return nil
    }

    public static func updateStats(db: Connection, flowId: String,
                                    packetsIn: Int64, packetsOut: Int64,
                                    bytesIn: Int64, bytesOut: Int64) throws {
        try db.run("""
            UPDATE tcp_connection SET packets_in = ?, packets_out = ?, bytes_in = ?, bytes_out = ?
            WHERE flow_id = ?
            """, packetsIn, packetsOut, bytesIn, bytesOut, flowId)
    }
}
```

- [ ] **Step 4: Delete old ConnectionDAO.swift**

```bash
rm LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/ConnectionDAO.swift
```

- [ ] **Step 5: Run tests to verify they pass**

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/TcpConnectionDAO.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/TcpConnectionDAOTests.swift
git rm LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/ConnectionDAO.swift
git commit -m "feat(storage): add TcpConnectionDAO, remove old ConnectionDAO"
```

---

### Task 5: QuicConnectionDAO + QuicStreamDAO

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/QuicConnectionDAO.swift`
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/QuicStreamDAO.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/QuicDAOTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class QuicDAOTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "connection.db")
        try! ConnectionSchema.create(db)
    }
    override func tearDown() { helper = nil }

    // MARK: - QuicConnectionDAO

    func testInsertAndFindConnection() throws {
        let record = QuicConnectionRecord(
            flowId: "quic_001", srcIp: "192.168.1.1", srcPort: 54321,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0,
            version: "1", dcid: "abcd1234", scid: "5678efgh", alpn: "h3"
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)
        let found = try QuicConnectionDAO.find(db: db, flowId: "quic_001")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.version, "1")
        XCTAssertEqual(found?.alpn, "h3")
        XCTAssertEqual(found?.dcid, "abcd1234")
    }

    func testUpsertConnection() throws {
        var record = QuicConnectionRecord(
            flowId: "quic_001", srcIp: "192.168.1.1", srcPort: 54321,
            dstIp: "10.0.0.1", dstPort: 443, startedAt: 1000.0
        )
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)
        record.state = "established"
        record.establishedAt = 1005.0
        try QuicConnectionDAO.insertOrUpdate(db: db, record: record)
        let found = try QuicConnectionDAO.find(db: db, flowId: "quic_001")
        XCTAssertEqual(found?.state, "established")
    }

    // MARK: - QuicStreamDAO

    func testInsertAndFindStream() throws {
        let stream = QuicStreamRecord(
            connectionId: "quic_001", streamId: 0, startedAt: 1000.0,
            streamType: "bidi", protocolFlowId: "h3_001"
        )
        try QuicStreamDAO.insert(db: db, record: stream)
        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic_001")
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].protocolFlowId, "h3_001")
    }

    func testFindStreamByProtocolFlowId() throws {
        let stream = QuicStreamRecord(
            connectionId: "quic_001", streamId: 4, startedAt: 1000.0,
            protocolFlowId: "h3_042"
        )
        try QuicStreamDAO.insert(db: db, record: stream)
        let found = try QuicStreamDAO.findByProtocolFlowId(db: db, protocolFlowId: "h3_042")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.streamId, 4)
    }

    func testUpdateProtocolFlowId() throws {
        let stream = QuicStreamRecord(
            connectionId: "quic_001", streamId: 0, startedAt: 1000.0
        )
        try QuicStreamDAO.insert(db: db, record: stream)
        try QuicStreamDAO.updateProtocolFlowId(db: db, connectionId: "quic_001", streamId: 0, protocolFlowId: "h3_099")
        let streams = try QuicStreamDAO.findByConnection(db: db, connectionId: "quic_001")
        XCTAssertEqual(streams[0].protocolFlowId, "h3_099")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement QuicConnectionDAO**

Similar pattern to TcpConnectionDAO: `insertOrUpdate` with UPSERT, `find` by flowId.

- [ ] **Step 4: Implement QuicStreamDAO**

Methods: `insert(db:record:)`, `findByConnection(db:connectionId:)`, `findByProtocolFlowId(db:protocolFlowId:)`, `updateProtocolFlowId(db:connectionId:streamId:protocolFlowId:)`.

- [ ] **Step 5: Run tests to verify they pass**

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/QuicConnectionDAO.swift \
       LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/QuicStreamDAO.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/QuicDAOTests.swift
git commit -m "feat(storage): add QuicConnectionDAO and QuicStreamDAO"
```

---

## Phase 3: Integration

### Task 6: Update StateSchema (remove connection table)

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Schema/StateSchema.swift`
- Modify: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/SchemaTests.swift`

- [ ] **Step 1: Update StateSchema to remove connection table**

Remove the `CREATE TABLE IF NOT EXISTS connection` and `CREATE INDEX IF NOT EXISTS idx_connection_flow_id` statements from `StateSchema.create()`. Keep `modify_log`, `task_stats`, and their indexes.

- [ ] **Step 2: Update SchemaTests.testStateSchema to not check for connection table**

Remove `XCTAssertTrue(tables.contains("connection"))` from the state schema test.

- [ ] **Step 3: Run all schema tests to verify they pass**

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Schema/StateSchema.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/SchemaTests.swift
git commit -m "refactor(storage): remove connection table from StateSchema (moved to connection.db)"
```

---

### Task 7: Expand TaskDatabaseGroup to 5 databases

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/TaskDatabaseGroup.swift`
- Modify: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/DatabaseManagerTests.swift`

- [ ] **Step 1: Update DatabaseManagerTests to verify 5th database**

Add to `testOpenAndCloseTask`:
```swift
XCTAssertNoThrow(try group.connection.scalar("SELECT COUNT(*) FROM tcp_connection"))
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Add connection database to TaskDatabaseGroup**

Add to properties:
```swift
public let connection: Connection
public let connectionWriteQueue: DispatchQueue
```

In `init`, after opening `state`:
```swift
connection = try Connection(PathManager.connectionDBPath(taskId, root: rootPath))
```

Add `connection` to the PRAGMA configuration loop:
```swift
for db in [transport, proto, decoded, state, connection] {
```

Add schema creation:
```swift
try ConnectionSchema.create(connection)
```

Add write queue:
```swift
connectionWriteQueue = DispatchQueue(label: "db.connection.\(taskId)")
```

- [ ] **Step 4: Run all tests to verify they pass**

Verify: DatabaseManagerTests, SchemaTests, and any other tests that use TaskDatabaseGroup.

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/TaskDatabaseGroup.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/DatabaseManagerTests.swift
git commit -m "feat(storage): expand TaskDatabaseGroup to 5 databases (add connection.db)"
```

---

### Task 8: Update SessionRecorder dual-write to use connection.db

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/SessionRecorder.swift`

- [ ] **Step 1: Read current SessionRecorder to understand dual-write points**

The dual-write code from Phase 1 writes to `protocol.db` via `FlowDAO.insert()` in `recordClosed()`. It also records connection events (`recordConnected`, `recordHandshakeComplete`). These should now also write `TcpConnectionRecord` to `connection.db`.

- [ ] **Step 2: Add TCP connection recording**

In `recordConnected` (or the equivalent method that fires when TCP connection is established):
```swift
if let group = dbGroup, let flowId = self.flowId {
    let tcpRecord = TcpConnectionRecord(
        flowId: flowId,
        srcIp: localAddress ?? "",
        srcPort: 0,  // may not be available
        dstIp: remoteAddress ?? "",
        dstPort: port,
        startedAt: Date().timeIntervalSince1970
    )
    group.connectionWriteQueue.async {
        try? TcpConnectionDAO.insertOrUpdate(db: group.connection, record: tcpRecord)
    }
}
```

In `recordHandshakeComplete`:
```swift
// Update TLS info on existing TCP connection record
```

In `recordClosed`:
```swift
// Update TCP connection state to closed
```

All new writes wrapped in `try?` — fail-safe.

- [ ] **Step 3: Verify build passes**

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/SessionRecorder.swift
git commit -m "feat(storage): write TCP connection data to connection.db in dual-write"
```

---

## Post-Implementation Notes

This plan does NOT cover:
- QUIC handler integration (writing quic_connection/quic_stream from PacketCaptureEngine) — covered in Sub-project A plan
- UI for connection.db data — covered in Sub-project B2 plan
- Removing old state.db connection references from other code — covered in Sub-project C plan
