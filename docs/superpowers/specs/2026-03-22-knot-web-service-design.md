# KnotWebService + KnotStorage Module Design

## Goal

Extract storage and web API into two independent modules so that browser, desktop, and mobile clients all consume data from one unified HTTP+WebSocket service. The web service runs independently of the capture engine — it serves historical data when TunnelServices is not active, and adds real-time push when it is.

## Architecture

### Module Dependency Graph

```
TunnelServices → KnotWebService → KnotStorage → SQLite.swift
                                       ↑
UI App ─────────→ KnotWebService ──────┘
```

No circular dependencies. `KnotStorage` has zero NIO dependency — files that currently import NIOCore (`PayloadWriter`, `PayloadDecoder`, `DecodeScheduler`) have their `ByteBuffer` overloads removed; callers pass `Data` instead. `CertExportService` is split: PEM-from-Data stays in KnotStorage, `NIOSSLCertificate`-to-DER conversion stays in TunnelServices.

### Package Layout

```
LocalPackages/
├── KnotStorage/
│   ├── Sources/KnotStorage/
│   │   ├── Database/         DatabaseManager, TaskDatabaseGroup
│   │   ├── Schema/           CatalogSchema, ProtocolSchema, TransportSchema,
│   │   │                     DecodedSchema, StateSchema, ConnectionSchema
│   │   ├── DAO/              CatalogDAO, FlowDAO, FlowDAO+Count, PacketDAO,
│   │   │                     DecodedEntryDAO, TcpConnectionDAO, QuicConnectionDAO,
│   │   │                     QuicStreamDAO, ModifyLogDAO, TaskStatsDAO
│   │   ├── Model/            FlowRecord, PacketRow, DecodedEntry,
│   │   │                     ConnectionRecord, QuicConnectionRecord, QuicStreamRecord,
│   │   │                     SearchKeyMapping, ProtoFlag, ConnectionReuseType, FlowStatus
│   │   ├── Payload/          PayloadWriter, PayloadReader, PayloadDecoder,
│   │   │                     DecompressStream, TextAccumulator
│   │   ├── Protocol/         ProtocolRecorder (protocol definition only),
│   │   │                     SearchKeyMapping
│   │   ├── Migration/        LegacyMigrator
│   │   └── Util/             PathManager, FlowIdGenerator, BatchWriter,
│   │                         TaskStatsSync, CertExportService (PEM-from-Data only),
│   │                         DecodeScheduler
│   └── Package.swift         deps: SQLite.swift (no NIO)
│
├── KnotWebService/
│   ├── Sources/KnotWebService/
│   │   ├── Server/           KnotWebServer, PortAllocator
│   │   ├── Routes/           TaskRoutes, FlowRoutes, PayloadRoutes
│   │   ├── WebSocket/        LivePushManager
│   │   ├── Bridge/           LiveBridge protocol
│   │   └── HTML/             DashboardHTML (moved from TunnelServices)
│   └── Package.swift         deps: KnotStorage, NIOCore, NIOPosix, NIOHTTP1, NIOWebSocket
│
├── TunnelServices/
│   └── Package.swift         deps: KnotStorage, KnotWebService, NIO, NIOSSL, NIOHTTP2...
```

## KnotStorage Module

### Responsibility

Manage SQLite databases and file-based payloads. Provide pure Swift read/write interfaces with no NIO dependency.

### Migration from TunnelServices

All files under `TunnelServices/Storage/` move to `KnotStorage/` with no logic changes:

- **Database/**: DatabaseManager (singleton, manages catalog + per-task DB pools), TaskDatabaseGroup (bundles 5 DBs + serial write queues per task)
- **Schema/**: 6 schema files defining table structure with migration support
- **DAO/**: 12 DAO files (static enums with type-safe queries)
- **Model/**: Struct-based models (FlowRecord, PacketRow, DecodedEntry, etc.)
- **Payload/**: PayloadWriter (streaming write, 32KB flush threshold), PayloadReader (range reads, chunk iterator), PayloadDecoder (decompression)
- **Util/**: PathManager (centralized path computation), FlowIdGenerator (thread-safe), BatchWriter (batched packet inserts), TaskStatsSync (periodic stats sync)

### New: StorageWriter

Thin facade over PayloadWriter + DAOs. Owns the PayloadWriter instances and flowId. Accepts `Data` (not `ByteBuffer`).

```swift
public class StorageWriter {
    public let taskId: Int64
    public let flowId: String

    // Owned resources
    private let dbGroup: TaskDatabaseGroup
    private var reqPayloadWriter: PayloadWriter?
    private var rspPayloadWriter: PayloadWriter?

    public init(taskId: Int64, dbGroup: TaskDatabaseGroup) {
        self.taskId = taskId
        self.dbGroup = dbGroup
        self.flowId = dbGroup.flowIdGenerator.next()
        // PayloadWriter created lazily on first body write
    }

    // --- Payload writes ---
    public func writeRequestBody(_ data: Data)   // → reqPayloadWriter.append()
    public func writeResponseBody(_ data: Data)   // → rspPayloadWriter.append()

    // --- DB writes (delegate to DAOs on serial write queues) ---
    public func insertFlow(_ record: FlowRecord)              // → FlowDAO.insert() on protoWriteQueue
    public func updateFlow(_ flowId: String, ...)              // → FlowDAO.update()
    public func insertPacket(_ row: PacketRow)                 // → BatchWriter.enqueue()
    public func insertDecodedEntry(_ entry: DecodedEntry)      // → DecodedEntryDAO.insert()
    public func insertOrUpdateConnection(_ record: TcpConnectionRecord) // → TcpConnectionDAO
    public func close()                                        // flush writers + finalize batch
}
```

**Relationship to ProtocolRecorder:** `ProtocolRecorder.buildFlowRecord()` signature changes from taking `SessionRecorder?` to taking `StorageWriter?` — only needs flowId and payload refs, no NIO types. HTTPRecorder and other ProtocolRecorder implementations stay in TunnelServices but call `storageWriter.insertFlow(record)` to persist.

### SessionRecorder Refactoring (in TunnelServices)

SessionRecorder stays in TunnelServices. Refactored to:
- Create a `StorageWriter` in init (via KnotStorage API), owns it for the flow's lifetime
- Convert NIO types: `ByteBuffer → Data` before passing to StorageWriter
- Orchestrate protocol recorders (HTTPRecorder etc.) which build `FlowRecord`
- Notify LiveBridge on flow completion (`bridge.onNewFlow?()`)

```swift
// Before (in SessionRecorder):
recorder.recordRequestBody(byteBuffer)  // writes directly to PayloadWriter + NIO ByteBuffer

// After:
func recordRequestBody(_ buffer: ByteBuffer) {
    var buf = buffer
    if let data = buf.readData(length: buf.readableBytes) {
        storageWriter.writeRequestBody(data)  // pure Data, no NIO in KnotStorage
    }
}

func recordClosed() {
    let record = protocolRecorder.buildFlowRecord(storageWriter: storageWriter)
    storageWriter.insertFlow(record)
    storageWriter.close()
    liveBridge?.onNewFlow?(record.toDictionary())  // push to WebSocket
}
```

## KnotWebService Module

### Responsibility

HTTP+WebSocket server that provides REST APIs for data query and real-time push for live capture data. Replaces the existing DashboardServer.

### Entry Point

```swift
public class KnotWebServer {
    /// Create server with port preference.
    /// eventLoopGroup: pass workerGroup from TunnelServices to share threads,
    /// or nil to create an internal 2-thread group.
    public init(
        preferredPort: Int = 9090,
        maxPortRetries: Int = 10,
        eventLoopGroup: EventLoopGroup? = nil
    )

    /// Start server. Returns actual bound port.
    public func start() throws -> Int

    /// Inject live data source (called by TunnelServices after proxy starts).
    public func attachLiveBridge(_ bridge: LiveBridge)

    /// Detach live data source (called when proxy stops).
    public func detachLiveBridge()

    /// Actual bound port (nil if not started).
    public var boundPort: Int? { get }

    /// Stop server gracefully.
    public func stop()
}
```

### Port Allocation (Strategy C: fixed + fallback)

```swift
func bindWithRetry(host: String, preferredPort: Int, maxRetries: Int) throws -> Channel {
    for offset in 0..<maxRetries {
        let port = preferredPort + offset
        if let ch = try? bootstrap.bind(host: host, port: port).wait() {
            return ch
        }
    }
    throw PortAllocationError.exhausted
}
```

Tries 9090 → 9091 → ... up to 9099. Caller reads `boundPort` after start.

### LiveBridge Protocol

Defined in KnotWebService. Implemented by TunnelServices.

```swift
public protocol LiveBridge: AnyObject {
    var onNewFlow: (([String: Any]) -> Void)? { get set }
    var onFlowUpdate: (([String: Any]) -> Void)? { get set }
    var onMetrics: (([String: Any]) -> Void)? { get set }
    var onStats: (([String: Any]) -> Void)? { get set }
    var onRetest: (([String: Any]) -> Void)? { get set }
    var onSurfProgress: (([String: Any]) -> Void)? { get set }
}
```

All six event types from the existing DashboardServer are preserved. KnotWebServer sets the callbacks when `attachLiveBridge` is called. LivePushManager broadcasts received data to all WebSocket clients.

TunnelServices implements:

```swift
class ProxyLiveBridge: LiveBridge {
    var onNewFlow: (([String: Any]) -> Void)?
    var onFlowUpdate: (([String: Any]) -> Void)?
    var onMetrics: (([String: Any]) -> Void)?
    var onStats: (([String: Any]) -> Void)?
    var onRetest: (([String: Any]) -> Void)?
    var onSurfProgress: (([String: Any]) -> Void)?
}
```

SessionRecorder calls `bridge.onNewFlow?(flowData)` in `recordClosed()`.

**MetricsCollector scheduling:** With DashboardServer deleted, the periodic metrics timer moves to `ProxyServer`. ProxyServer creates a `RepeatedTask` on the EventLoop that calls `MetricsCollector.collect()` and pushes via `bridge.onMetrics?()`. Timer starts when `attachLiveBridge` is called, stops on `detachLiveBridge`.

### REST API

All responses are `application/json` with consistent envelope:
```json
{ "code": 0, "data": ... }
```

Error responses:
```json
{ "code": 404, "error": "Flow not found" }
```

#### Task Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/tasks` | List all capture tasks |
| GET | `/api/tasks/{id}` | Task detail (name, times, flow count, bytes) |

#### Flow Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/tasks/{id}/flows` | Paginated flow list. Query params: `page`, `size`, `protocol`, `host`, `status`, `sort` |
| GET | `/api/tasks/{id}/flows/search?q=` | Full-text search via FTS5 |
| GET | `/api/tasks/{id}/flows/stats` | Aggregate stats: protocol distribution, status counts, total bytes |
| GET | `/api/tasks/{id}/flows/{fid}` | Single flow detail: metadata, timing waterfall, connection info, cert chain |

#### Payload Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/tasks/{id}/flows/{fid}/request` | Request body, chunked transfer. Query: `preview=true` for first 4KB |
| GET | `/api/tasks/{id}/flows/{fid}/response` | Response body, chunked transfer. Query: `preview=true` for first 4KB |
| GET | `/api/tasks/{id}/flows/{fid}/decoded` | Decoded/decompressed content |

Payload routes use `PayloadReader.chunks()` to stream 64KB chunks via HTTP chunked transfer encoding. Memory peak < 128KB per request.

#### WebSocket

| Path | Description |
|------|-------------|
| `/ws` | Real-time push. Messages are JSON with `type` field |

Message types:
- `{"type": "flow", "data": {...}}` — new flow completed
- `{"type": "flow_update", "data": {...}}` — flow status change
- `{"type": "metrics", "data": {...}}` — system metrics (CPU, memory, connections)
- `{"type": "stats", "data": {...}}` — aggregated stats snapshot
- `{"type": "retest", "data": {...}}` — retest result
- `{"type": "surf_progress", "data": {...}}` — browser test progress

No messages pushed when LiveBridge is not attached (historical mode).

Clients can filter by connecting with `?taskId={id}` query parameter. Without it, all events are received.

### HTML Dashboard

`DashboardHTML.swift` moves from TunnelServices to KnotWebService. Served at `GET /`. Updated to use the new REST API endpoints for initial data load, WebSocket for live updates.

### Existing DashboardServer

Deleted from TunnelServices. All functionality replaced by KnotWebServer:
- HTML dashboard → `GET /`
- `/api/stats` → `GET /api/tasks/{id}/flows/stats`
- WebSocket push → LivePushManager via LiveBridge
- MetricsCollector → stays in TunnelServices, pushes via LiveBridge

## Two Operating Modes

### Mode A: Historical Query Only (TunnelServices not started)

```
App starts
  → KnotWebServer(preferredPort: 9090).start()
  → REST API available, queries SQLite via KnotStorage
  → WebSocket connectable but no live push (no LiveBridge)
```

### Mode B: Capture + Live View (TunnelServices started)

```
App starts
  → KnotWebServer.start()                          // Web service up
  → TunnelServices.start()                          // Capture engine up
  → let bridge = ProxyLiveBridge()
  → webServer.attachLiveBridge(bridge)              // Wire push
  → During capture:
      SessionRecorder.recordClosed()
        → storageWriter.insertFlow(record)          // Write to DB
        → bridge.onNewFlow?(flowData)               // Push to WebSocket
  → User stops capture:
      TunnelServices.stop()
      webServer.detachLiveBridge()                  // Stop push
  → Web service keeps running, REST API still serves history
```

Web service lifecycle is independent of capture engine.

## Cross-Cutting Concerns

### CORS

All REST API responses include `Access-Control-Allow-Origin: *` to support browser clients on different origins (e.g., developer tools, external dashboards). The HTML dashboard is served same-origin so CORS is not required for it, but external consumers need it.

### DatabaseManager Initialization

`DatabaseManager.shared` is initialized lazily on first access. Both KnotWebService (REST reads) and TunnelServices (capture writes) call `openTask`/`closeTask` which mutates the internal `activePools` dictionary. The existing `NSLock` is sufficient — pool operations are fast (dictionary lookup/insert) and infrequent (once per task open/close, not per query). High REST API load uses the already-opened `TaskDatabaseGroup` connections directly.

### Task Management Scope

Task creation/deletion is handled by the native app layer (macOS/iOS), not the web service. `GET /api/tasks` and `GET /api/tasks/{id}` are read-only. If task CRUD is needed via API later, it can be added incrementally.

## Error Handling

### Port Conflict
Try preferred port, increment up to maxRetries times. All fail → throw `PortAllocationError.exhausted`. Caller decides fallback.

### Large Payloads
PayloadReader streams 64KB chunks. HTTP chunked transfer encoding. Memory peak < 128KB. No full body load.

### Database Concurrency
REST API performs read-only queries. WAL mode allows concurrent reads without blocking TunnelServices writes. DatabaseManager's serial write queues prevent contention.

### WebSocket Management
LivePushManager uses `NIOLockedValueBox` for thread-safe connection tracking. Registers via `handlerAdded` (not `channelActive`). Auto-removes on `channelInactive`. No clients → callbacks short-circuit.

### EventLoopGroup
KnotWebServer accepts external EventLoopGroup injection. TunnelServices passes its workerGroup to share threads. Standalone mode creates internal 2-thread group.

## What Moves Where

| Current Location | New Location | Notes |
|-----------------|--------------|-------|
| TunnelServices/Storage/Database/* | KnotStorage/Database/ | DatabaseManager, TaskDatabaseGroup |
| TunnelServices/Storage/Schema/* | KnotStorage/Schema/ | 6 schema files, no change |
| TunnelServices/Storage/DAO/* | KnotStorage/DAO/ | 12 DAO files, no change |
| TunnelServices/Storage/Model/* | KnotStorage/Model/ | All model structs + enums |
| TunnelServices/Storage/Payload/* | KnotStorage/Payload/ | Remove ByteBuffer overloads from PayloadWriter |
| TunnelServices/Storage/Protocol/* | KnotStorage/Protocol/ | ProtocolRecorder protocol (definition only) |
| TunnelServices/Storage/Migration/* | KnotStorage/Migration/ | LegacyMigrator |
| TunnelServices/Storage/Util/* | KnotStorage/Util/ | PathManager, FlowIdGenerator, BatchWriter, etc. |
| TunnelServices/Storage/CertExportService | **Split** | PEM-from-Data → KnotStorage; NIOSSL conversion → TunnelServices |
| TunnelServices/Dashboard/DashboardServer.swift | **Deleted** | Replaced by KnotWebServer |
| TunnelServices/Dashboard/DashboardHTML.swift | KnotWebService/HTML/ | Moved |
| TunnelServices/Dashboard/MetricsCollector.swift | TunnelServices (stays) | Pushes via LiveBridge; timer in ProxyServer |
| TunnelServices/CaptureTask.dashboardServer | CaptureTask.liveBridge | Type: `DashboardPushable` → `LiveBridge` |
| SessionRecorder DB/File writes | Delegates to StorageWriter | NIO adapting stays in SessionRecorder |
| ProtocolRecorder.buildFlowRecord(SessionRecorder?) | buildFlowRecord(StorageWriter?) | Remove SessionRecorder dependency |
