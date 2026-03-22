# KnotStorage Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the storage layer from TunnelServices into an independent `KnotStorage` Swift package with zero NIO dependency.

**Architecture:** Move all Storage/ files into a new LocalPackages/KnotStorage package. Strip NIO imports from 4 files (PayloadWriter, PayloadDecoder, DecodeScheduler, CertExportService). Create StorageWriter as the write facade. Decouple ProtocolRecorder from SessionRecorder. Update TunnelServices to `import KnotStorage`.

**Tech Stack:** Swift, SQLite.swift, Foundation, Apple Compression framework

**Spec:** `docs/superpowers/specs/2026-03-22-knot-web-service-design.md`

---

## File Structure

### New Files (KnotStorage package)

```
LocalPackages/KnotStorage/
├── Package.swift                                    # New: deps SQLite.swift only
├── Sources/KnotStorage/
│   ├── KnotStorage.swift                            # New: re-export convenience
│   ├── Database/
│   │   ├── DatabaseManager.swift                    # Moved from TunnelServices/Storage/
│   │   └── TaskDatabaseGroup.swift                  # Moved
│   ├── Schema/
│   │   ├── CatalogSchema.swift                      # Moved
│   │   ├── ProtocolSchema.swift                     # Moved
│   │   ├── TransportSchema.swift                    # Moved
│   │   ├── DecodedSchema.swift                      # Moved
│   │   ├── StateSchema.swift                        # Moved
│   │   └── ConnectionSchema.swift                   # Moved
│   ├── DAO/
│   │   ├── CatalogDAO.swift                         # Moved + refactored (decouple RuleEngine)
│   │   ├── FlowDAO.swift                            # Moved
│   │   ├── FlowDAO+Count.swift                      # Moved
│   │   ├── PacketDAO.swift                          # Moved
│   │   ├── DecodedEntryDAO.swift                    # Moved
│   │   ├── TcpConnectionDAO.swift                   # Moved
│   │   ├── QuicConnectionDAO.swift                  # Moved
│   │   ├── QuicStreamDAO.swift                      # Moved
│   │   ├── ModifyLogDAO.swift                       # Moved
│   │   └── TaskStatsDAO.swift                       # Moved
│   ├── Model/
│   │   ├── FlowRecord.swift                         # Moved
│   │   ├── PacketRow.swift                          # Moved
│   │   ├── DecodedEntry.swift                       # Moved
│   │   ├── ConnectionRecord.swift                   # Moved
│   │   ├── QuicConnectionRecord.swift               # Moved
│   │   ├── QuicStreamRecord.swift                   # Moved
│   │   └── ModifyLogEntry.swift                     # Moved
│   ├── Payload/
│   │   ├── PayloadWriter.swift                      # Moved + strip NIO ByteBuffer overload
│   │   ├── PayloadReader.swift                      # Moved (already pure Foundation)
│   │   ├── PayloadDecoder.swift                     # Moved + strip NIOCore import
│   │   ├── DecompressStream.swift                   # Moved (already pure Foundation)
│   │   └── TextAccumulator.swift                    # Moved (already pure Foundation)
│   ├── Protocol/
│   │   └── ProtocolRecorder.swift                   # Moved + decouple from SessionRecorder
│   ├── Migration/
│   │   └── LegacyMigrator.swift                     # Moved + decouple from CaptureTask
│   ├── Writer/
│   │   └── StorageWriter.swift                      # New: write facade
│   └── Util/
│       ├── PathManager.swift                        # Moved
│       ├── FlowIdGenerator.swift                    # Moved
│       ├── BatchWriter.swift                        # Moved
│       ├── TaskStatsSync.swift                      # Moved
│       ├── DecodeScheduler.swift                    # Moved + strip EventLoop, use DispatchQueue
│       └── CertExportService.swift                  # Moved + strip NIOSSL (PEM-from-Data only)
└── Tests/KnotStorageTests/
    └── StorageWriterTests.swift                     # New: test StorageWriter
```

### Modified Files (TunnelServices)

```
LocalPackages/TunnelServices/
├── Package.swift                                    # Add KnotStorage dependency
├── Sources/TunnelServices/
│   ├── Framework/SessionRecorder.swift              # Refactor: use StorageWriter, ByteBuffer→Data
│   ├── CaptureTask.swift                            # Remove direct DB imports, add liveBridge
│   ├── Plugins/HTTP1/HTTPRecorder.swift             # Add `import KnotStorage`
│   ├── Plugins/WebSocket/WebSocketRecorder.swift    # Add `import KnotStorage`
│   ├── Plugins/GRPC/GRPCRecorder.swift              # Add `import KnotStorage`
│   ├── Plugins/DNS/DNSRecorder.swift                # Add `import KnotStorage`
│   ├── Proxy/ProxyServer.swift                      # Add `import KnotStorage`
│   ├── MitmService.swift                            # Add `import KnotStorage`
│   └── Utils/CertExportNIO.swift                    # New: NIOSSL cert→DER conversion (split from CertExportService)
```

---

### Task 1: Create KnotStorage Package.swift and scaffold

**Files:**
- Create: `LocalPackages/KnotStorage/Package.swift`
- Create: `LocalPackages/KnotStorage/Sources/KnotStorage/KnotStorage.swift`

- [ ] **Step 1: Create package directory structure**

```bash
mkdir -p LocalPackages/KnotStorage/Sources/KnotStorage/{Database,Schema,DAO,Model,Payload,Protocol,Migration,Writer,Util}
mkdir -p LocalPackages/KnotStorage/Tests/KnotStorageTests
```

- [ ] **Step 2: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnotStorage",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "KnotStorage", targets: ["KnotStorage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nicklama/SQLite.swift", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "KnotStorage",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .testTarget(
            name: "KnotStorageTests",
            dependencies: ["KnotStorage"]
        ),
    ]
)
```

- [ ] **Step 3: Create placeholder KnotStorage.swift**

```swift
// KnotStorage.swift — public re-exports for convenience
// All public types from sub-modules are accessible via `import KnotStorage`
```

- [ ] **Step 4: Verify package resolves**

Run: `swift package --package-path LocalPackages/KnotStorage resolve`
Expected: SUCCESS (downloads SQLite.swift)

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/KnotStorage/
git commit -m "feat(KnotStorage): scaffold empty package with SQLite dependency"
```

---

### Task 2: Move Model files (zero dependencies, no changes needed)

**Files:**
- Move: all 7 files from `TunnelServices/Storage/Model/` → `KnotStorage/Model/`

- [ ] **Step 1: Copy model files**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Model/*.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Model/
```

- [ ] **Step 2: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS (models are pure Foundation structs)

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Model/
git commit -m "feat(KnotStorage): move Model files (FlowRecord, PacketRow, etc.)"
```

---

### Task 3: Move Schema files

**Files:**
- Move: all 6 files from `TunnelServices/Storage/Schema/` → `KnotStorage/Schema/`

- [ ] **Step 1: Copy schema files**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Schema/*.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Schema/
```

- [ ] **Step 2: Handle CatalogSchema AxLogger dependency**

CatalogSchema imports `AxLogger` which is in TunnelServices. Replace with `os.Logger`:

In `KnotStorage/Schema/CatalogSchema.swift`, find any `AxLogger.log(...)` calls and replace with:
```swift
import os
private let logger = Logger(subsystem: "com.knot.storage", category: "CatalogSchema")
// Replace: AxLogger.log("msg", level: .Warning)
// With:    logger.warning("msg")
```

- [ ] **Step 3: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Schema/
git commit -m "feat(KnotStorage): move Schema files, replace AxLogger with os.Logger"
```

---

### Task 4: Move DAO files (except CatalogDAO)

**Files:**
- Move: FlowDAO.swift, FlowDAO+Count.swift, PacketDAO.swift, DecodedEntryDAO.swift, TcpConnectionDAO.swift, QuicConnectionDAO.swift, QuicStreamDAO.swift, ModifyLogDAO.swift, TaskStatsDAO.swift

These 9 files depend only on SQLite + Model types (already in KnotStorage).

- [ ] **Step 1: Copy DAO files**

```bash
for f in FlowDAO.swift FlowDAO+Count.swift PacketDAO.swift DecodedEntryDAO.swift \
         TcpConnectionDAO.swift QuicConnectionDAO.swift QuicStreamDAO.swift \
         ModifyLogDAO.swift TaskStatsDAO.swift; do
  cp "LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/$f" \
     "LocalPackages/KnotStorage/Sources/KnotStorage/DAO/"
done
```

- [ ] **Step 2: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/DAO/
git commit -m "feat(KnotStorage): move 9 DAO files (FlowDAO, PacketDAO, etc.)"
```

---

### Task 5: Move CatalogDAO — decouple from RuleEngine/CaptureTask

**Files:**
- Move: `TunnelServices/Storage/DAO/CatalogDAO.swift` → `KnotStorage/DAO/CatalogDAO.swift`

CatalogDAO has methods that take `CaptureTask` and `RuleEngine` parameters. These need to be refactored to accept primitive types instead.

- [ ] **Step 1: Copy CatalogDAO.swift**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/CatalogDAO.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/DAO/
```

- [ ] **Step 2: Refactor external dependencies**

In `KnotStorage/DAO/CatalogDAO.swift`:

1. Remove any `import` of TunnelServices types
2. Methods like `insertFullTask(db:, task: CaptureTask)` → change parameter to `CaptureTaskRecord` (already defined in CatalogDAO itself)
3. Methods referencing `RuleEngine` → extract the fields needed as primitive parameters
4. Replace `AxLogger` calls with `os.Logger`
5. Replace `ProxyConfig` references with literal values or parameters

The goal: CatalogDAO should depend ONLY on Foundation + SQLite + its own CaptureTaskRecord/RuleRecord structs.

- [ ] **Step 3: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/DAO/CatalogDAO.swift
git commit -m "feat(KnotStorage): move CatalogDAO, decouple from CaptureTask/RuleEngine"
```

---

### Task 6: Move Payload files — strip NIO from PayloadWriter and PayloadDecoder

**Files:**
- Move: PayloadWriter.swift, PayloadReader.swift, PayloadDecoder.swift, DecompressStream.swift, TextAccumulator.swift

- [ ] **Step 1: Copy all Payload files**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Payload/*.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Payload/
```

- [ ] **Step 2: Strip NIO from PayloadWriter.swift**

In `KnotStorage/Payload/PayloadWriter.swift`:
1. Remove `import NIOCore`
2. Remove or replace `func append(_ byteBuffer: ByteBuffer)` — this overload converts ByteBuffer to Data internally. Remove it entirely; callers (SessionRecorder) will do `ByteBuffer → Data` conversion themselves.
3. Keep `func append(_ data: Data)` as the primary interface.

- [ ] **Step 3: Strip NIO from PayloadDecoder.swift**

In `KnotStorage/Payload/PayloadDecoder.swift`:
1. Remove `import NIOCore`
2. If any NIO types are used (ByteBuffer), replace with Data equivalents.

- [ ] **Step 4: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS (no NIO imports remain in Payload/)

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Payload/
git commit -m "feat(KnotStorage): move Payload files, strip NIO ByteBuffer dependency"
```

---

### Task 7: Move Util files — strip NIO from DecodeScheduler, split CertExportService

**Files:**
- Move: PathManager.swift, FlowIdGenerator.swift, BatchWriter.swift, TaskStatsSync.swift, DecodeScheduler.swift
- Split: CertExportService.swift → KnotStorage (Data-only) + TunnelServices (NIOSSL conversion)

- [ ] **Step 1: Copy pure util files**

```bash
for f in PathManager.swift FlowIdGenerator.swift BatchWriter.swift TaskStatsSync.swift; do
  cp "LocalPackages/TunnelServices/Sources/TunnelServices/Storage/$f" \
     "LocalPackages/KnotStorage/Sources/KnotStorage/Util/"
done
```

- [ ] **Step 2: Move and strip DecodeScheduler.swift**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DecodeScheduler.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Util/
```

In `KnotStorage/Util/DecodeScheduler.swift`:
1. Remove `import NIOCore`
2. Replace `EventLoop`/`EventLoopFuture` usage with `DispatchQueue` + completion callbacks
3. The scheduler runs decode operations off the main thread — `DispatchQueue.global()` replaces EventLoop scheduling

- [ ] **Step 3: Split CertExportService**

Copy to KnotStorage and strip NIOSSL:
```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/CertExportService.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Util/
```

In `KnotStorage/Util/CertExportService.swift`:
1. Remove `import NIOSSL`, `import X509`, `import SwiftASN1`, `import Crypto`
2. Keep only the PEM file writing/reading methods that work with `Data` or `String`
3. Remove methods that take `NIOSSLCertificate` parameters

Create a new file in TunnelServices for the NIOSSL-specific conversion:
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Utils/CertExportNIO.swift`
- This file imports NIOSSL and provides `NIOSSLCertificate → Data` conversion, then calls KnotStorage's CertExportService for PEM writing

- [ ] **Step 4: Replace AxLogger in all util files**

Search all moved util files for `AxLogger` references and replace with `os.Logger`.

- [ ] **Step 5: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Util/
git commit -m "feat(KnotStorage): move Util files, strip NIO from DecodeScheduler, split CertExportService"
```

---

### Task 8: Move Database files (DatabaseManager, TaskDatabaseGroup)

**Files:**
- Move: DatabaseManager.swift, TaskDatabaseGroup.swift

- [ ] **Step 1: Copy database files**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DatabaseManager.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Database/
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/TaskDatabaseGroup.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Database/
```

- [ ] **Step 2: Replace AxLogger and remove external deps**

In both files:
1. Replace `AxLogger` with `os.Logger`
2. `DatabaseManager` may reference `MitmService.storeFolder` for the root path — change to accept root path as an init parameter or a configurable static property:

```swift
public class DatabaseManager {
    public static var rootPath: String = ""  // Set by app on launch
    public static let shared = DatabaseManager()
}
```

- [ ] **Step 3: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Database/
git commit -m "feat(KnotStorage): move DatabaseManager and TaskDatabaseGroup"
```

---

### Task 9: Move ProtocolRecorder — decouple from SessionRecorder

**Files:**
- Move: `TunnelServices/Storage/Protocol/ProtocolRecorder.swift` → `KnotStorage/Protocol/`

- [ ] **Step 1: Copy and refactor**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/ProtocolRecorder.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Protocol/
```

In `KnotStorage/Protocol/ProtocolRecorder.swift`:
1. Remove dependency on `SessionRecorder`
2. Change `buildFlowRecord(sessionRecorder: SessionRecorder?)` to `buildFlowRecord(context: FlowBuildContext)`

Define a simple context struct in the same file:
```swift
public struct FlowBuildContext {
    public let flowId: String
    public let reqPayloadRef: String
    public let rspPayloadRef: String
    public let uploadBytes: Int64
    public let downloadBytes: Int64
    public let protoFlags: Int
    public let connReuse: Int
    public let certChainRef: String?

    public init(flowId: String, reqPayloadRef: String, rspPayloadRef: String,
                uploadBytes: Int64, downloadBytes: Int64,
                protoFlags: Int, connReuse: Int, certChainRef: String?) { ... }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Protocol/
git commit -m "feat(KnotStorage): move ProtocolRecorder, decouple from SessionRecorder"
```

---

### Task 10: Move LegacyMigrator — decouple from CaptureTask

**Files:**
- Move: `TunnelServices/Storage/Migration/LegacyMigrator.swift` → `KnotStorage/Migration/`

- [ ] **Step 1: Copy and refactor**

```bash
mkdir -p LocalPackages/KnotStorage/Sources/KnotStorage/Migration
cp LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Migration/LegacyMigrator.swift \
   LocalPackages/KnotStorage/Sources/KnotStorage/Migration/
```

Replace `CaptureTask` references with `CaptureTaskRecord` (which is in CatalogDAO, already in KnotStorage).

- [ ] **Step 2: Verify build**

Run: `swift build --package-path LocalPackages/KnotStorage`
Expected: BUILD SUCCESS — all files are now in KnotStorage

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Migration/
git commit -m "feat(KnotStorage): move LegacyMigrator, decouple from CaptureTask"
```

---

### Task 11: Create StorageWriter

**Files:**
- Create: `LocalPackages/KnotStorage/Sources/KnotStorage/Writer/StorageWriter.swift`
- Create: `LocalPackages/KnotStorage/Tests/KnotStorageTests/StorageWriterTests.swift`

- [ ] **Step 1: Write StorageWriter test**

```swift
import XCTest
@testable import KnotStorage

final class StorageWriterTests: XCTestCase {
    func testWriteRequestBody() throws {
        let tempDir = NSTemporaryDirectory() + "StorageWriterTest_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        DatabaseManager.rootPath = tempDir
        let dbGroup = try TaskDatabaseGroup(taskId: 1, rootPath: tempDir)
        let writer = StorageWriter(dbGroup: dbGroup)

        let testData = "Hello, KnotStorage!".data(using: .utf8)!
        writer.writeRequestBody(testData)
        writer.close()

        // Verify payload file was written
        let payloadPath = PathManager.rawPayloadPath(
            rootPath: tempDir, taskId: 1, flowId: writer.flowId, direction: .request)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadPath))
    }

    func testInsertFlow() throws {
        let tempDir = NSTemporaryDirectory() + "StorageWriterTest_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        DatabaseManager.rootPath = tempDir
        let dbGroup = try TaskDatabaseGroup(taskId: 1, rootPath: tempDir)
        let writer = StorageWriter(dbGroup: dbGroup)

        var record = FlowRecord(flowId: writer.flowId, protocolName: "HTTP",
                                host: "example.com", port: 80,
                                startedAt: Date().timeIntervalSince1970)
        record.status = .completed
        writer.insertFlow(record)
        writer.close()

        // Verify flow was inserted
        let found = try FlowDAO.find(db: dbGroup.proto, flowId: writer.flowId)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.host, "example.com")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LocalPackages/KnotStorage --filter StorageWriterTests`
Expected: FAIL (StorageWriter not defined)

- [ ] **Step 3: Implement StorageWriter**

```swift
import Foundation
import os

public class StorageWriter {
    private static let logger = Logger(subsystem: "com.knot.storage", category: "StorageWriter")

    public let taskId: Int64
    public let flowId: String

    private let dbGroup: TaskDatabaseGroup
    private var reqPayloadWriter: PayloadWriter?
    private var rspPayloadWriter: PayloadWriter?
    private var closed = false

    public var reqPayloadRef: String { reqPayloadWriter?.filePath ?? "" }
    public var rspPayloadRef: String { rspPayloadWriter?.filePath ?? "" }

    public init(dbGroup: TaskDatabaseGroup) {
        self.taskId = dbGroup.taskId
        self.flowId = dbGroup.flowIdGenerator.next()
        self.dbGroup = dbGroup
    }

    // MARK: - Payload Writes

    public func writeRequestBody(_ data: Data) {
        guard !closed else { return }
        if reqPayloadWriter == nil {
            let dir = PathManager.rawPayloadDirectory(rootPath: DatabaseManager.rootPath,
                                                       taskId: taskId)
            reqPayloadWriter = try? PayloadWriter(directory: dir, fileName: "\(flowId)_req.bin")
        }
        try? reqPayloadWriter?.append(data)
    }

    public func writeResponseBody(_ data: Data) {
        guard !closed else { return }
        if rspPayloadWriter == nil {
            let dir = PathManager.rawPayloadDirectory(rootPath: DatabaseManager.rootPath,
                                                       taskId: taskId)
            rspPayloadWriter = try? PayloadWriter(directory: dir, fileName: "\(flowId)_rsp.bin")
        }
        try? rspPayloadWriter?.append(data)
    }

    // MARK: - DB Writes

    public func insertFlow(_ record: FlowRecord) {
        dbGroup.protoWriteQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try FlowDAO.insert(db: self.dbGroup.proto, record: record)
            } catch {
                Self.logger.error("insertFlow failed: \(error)")
            }
        }
    }

    public func updateFlow(_ flowId: String, status: FlowStatus? = nil,
                           endedAt: TimeInterval? = nil, errorMessage: String? = nil) {
        dbGroup.protoWriteQueue.async { [weak self] in
            guard let self = self else { return }
            try? FlowDAO.update(db: self.dbGroup.proto, flowId: flowId,
                                status: status, endedAt: endedAt, errorMessage: errorMessage)
        }
    }

    public func insertPacket(_ row: PacketRow) {
        // Delegate to BatchWriter if available, or direct insert
        dbGroup.transportWriteQueue.async { [weak self] in
            guard let self = self else { return }
            try? PacketDAO.insert(db: self.dbGroup.transport, row: row)
        }
    }

    public func insertDecodedEntry(_ entry: DecodedEntry) {
        dbGroup.decodedWriteQueue.async { [weak self] in
            guard let self = self else { return }
            try? DecodedEntryDAO.insert(db: self.dbGroup.decoded, entry: entry)
        }
    }

    public func insertOrUpdateConnection(_ record: TcpConnectionRecord) {
        dbGroup.connectionWriteQueue.async { [weak self] in
            guard let self = self else { return }
            try? TcpConnectionDAO.insertOrUpdate(db: self.dbGroup.connection, record: record)
        }
    }

    // MARK: - Lifecycle

    public func close() {
        guard !closed else { return }
        closed = true
        try? reqPayloadWriter?.flush()
        try? reqPayloadWriter?.close()
        try? rspPayloadWriter?.flush()
        try? rspPayloadWriter?.close()
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path LocalPackages/KnotStorage --filter StorageWriterTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/KnotStorage/Sources/KnotStorage/Writer/StorageWriter.swift
git add LocalPackages/KnotStorage/Tests/KnotStorageTests/StorageWriterTests.swift
git commit -m "feat(KnotStorage): implement StorageWriter with tests"
```

---

### Task 12: Delete original Storage files from TunnelServices

**Files:**
- Delete: all files under `TunnelServices/Sources/TunnelServices/Storage/`

- [ ] **Step 1: Remove the Storage directory**

```bash
rm -rf LocalPackages/TunnelServices/Sources/TunnelServices/Storage/
```

- [ ] **Step 2: Verify TunnelServices no longer builds (expected)**

Run: `swift build --package-path LocalPackages/TunnelServices`
Expected: BUILD FAILURE (many "missing type" errors — this is correct)

- [ ] **Step 3: Commit the deletion**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/
git commit -m "refactor: delete Storage/ from TunnelServices (moved to KnotStorage)"
```

---

### Task 13: Add KnotStorage dependency to TunnelServices and fix imports

**Files:**
- Modify: `LocalPackages/TunnelServices/Package.swift`
- Modify: All TunnelServices .swift files that used Storage types

- [ ] **Step 1: Add KnotStorage to TunnelServices Package.swift**

Add to `dependencies`:
```swift
.package(path: "../KnotStorage"),
```

Add to target dependencies:
```swift
.product(name: "KnotStorage", package: "KnotStorage"),
```

- [ ] **Step 2: Add `import KnotStorage` to all files that used Storage types**

Files to update (add `import KnotStorage` at the top):
- `Framework/SessionRecorder.swift`
- `CaptureTask.swift`
- `MitmService.swift`
- `Proxy/ProxyServer.swift`
- `Plugins/HTTP1/HTTPRecorder.swift`
- `Plugins/WebSocket/WebSocketRecorder.swift`
- `Plugins/GRPC/GRPCRecorder.swift`
- `Plugins/DNS/DNSRecorder.swift`
- `Plugins/HTTP2/HTTP2CaptureHandler.swift` (if it uses FlowRecord)
- `Export/PCAPExporter.swift` (if it uses PacketDAO)
- Any other files that fail to compile

The exact list will be determined by compile errors — fix each one by adding `import KnotStorage`.

- [ ] **Step 3: Create CertExportNIO.swift in TunnelServices**

Move the NIOSSL-dependent certificate conversion code from the old CertExportService into a new file:

Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Utils/CertExportNIO.swift`

This file:
1. Imports NIOSSL, X509, Crypto
2. Provides `NIOSSLCertificate → Data` conversion
3. Calls KnotStorage's CertExportService for PEM file writing

- [ ] **Step 4: Update SessionRecorder to use StorageWriter**

In `Framework/SessionRecorder.swift`:
1. Replace direct PayloadWriter usage with `StorageWriter`
2. Replace `ByteBuffer` writes: `var buf = buffer; storageWriter.writeRequestBody(buf.readData(length: buf.readableBytes)!)`
3. In `recordClosed()`: build FlowRecord via ProtocolRecorder, pass to `storageWriter.insertFlow()`
4. Update ProtocolRecorder calls to use `FlowBuildContext` instead of `SessionRecorder`

- [ ] **Step 5: Update HTTPRecorder and other ProtocolRecorder implementations**

Change `buildFlowRecord(sessionRecorder:)` → `buildFlowRecord(context: FlowBuildContext)` in:
- `Plugins/HTTP1/HTTPRecorder.swift`
- `Plugins/WebSocket/WebSocketRecorder.swift`
- `Plugins/GRPC/GRPCRecorder.swift`
- `Plugins/DNS/DNSRecorder.swift`

- [ ] **Step 6: Update CatalogDAO callers**

Where TunnelServices code calls `CatalogDAO.insertFullTask(db:, task: captureTask)`, change to convert `CaptureTask` → `CaptureTaskRecord` first, then call the refactored DAO.

- [ ] **Step 7: Verify build**

Run: `swift build --package-path LocalPackages/TunnelServices`
Expected: BUILD SUCCESS

- [ ] **Step 8: Commit**

```bash
git add LocalPackages/TunnelServices/
git commit -m "refactor: TunnelServices imports KnotStorage, SessionRecorder uses StorageWriter"
```

---

### Task 14: Run full test suite

- [ ] **Step 1: Run KnotStorage tests**

Run: `swift test --package-path LocalPackages/KnotStorage`
Expected: ALL PASS

- [ ] **Step 2: Run TunnelServices tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter 'WebSocket|HTTP1Integration|HTTP2Integration'`
Expected: ALL PASS (integration tests verify the full pipeline still works)

- [ ] **Step 3: Run stress tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter 'StressTests_HTTP1_Plaintext/testStress_HTTP1_Plaintext_Light'`
Expected: PASS

- [ ] **Step 4: Final commit**

```bash
git commit --allow-empty -m "chore: KnotStorage extraction complete — all tests pass"
```
