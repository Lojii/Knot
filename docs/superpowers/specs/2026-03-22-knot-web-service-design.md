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

No circular dependencies. `KnotStorage` has zero NIO dependency.

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
│   │   │                     ConnectionRecord, QuicConnectionRecord, QuicStreamRecord
│   │   ├── Payload/          PayloadWriter, PayloadReader, PayloadDecoder,
│   │   │                     DecompressStream, TextAccumulator
│   │   └── Util/             PathManager, FlowIdGenerator, BatchWriter,
│   │                         TaskStatsSync, CertExportService, DecodeScheduler
│   └── Package.swift         deps: SQLite.swift
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

Extracted from SessionRecorder's DB/File write logic. Accepts `Data` (not `ByteBuffer`).

```swift
public class StorageWriter {
    public let taskId: Int64
    public let flowId: String

    public init(taskId: Int64, dbGroup: TaskDatabaseGroup)

    public func writeRequestBody(_ data: Data)
    public func writeResponseBody(_ data: Data)
    public func insertFlow(_ record: FlowRecord)
    public func updateFlow(flowId: String, updates: FlowUpdate)
    public func insertPacket(_ row: PacketRow)
    public func insertDecodedEntry(_ entry: DecodedEntry)
    public func insertConnection(_ record: TcpConnectionRecord)
    public func close()  // flush + cleanup
}
```

### SessionRecorder Refactoring (in TunnelServices)

SessionRecorder stays in TunnelServices. Refactored to:
- Hold a `StorageWriter` internally for all DB/File operations
- Keep NIO-specific adapting: `ByteBuffer → Data` conversion
- Keep protocol recording orchestration (HTTPRecorder, etc.)
- Keep LiveBridge notification (`bridge.onNewFlow?()`)

```swift
// Before (in SessionRecorder):
recorder.recordRequestBody(byteBuffer)  // writes directly to PayloadWriter

// After:
func recordRequestBody(_ buffer: ByteBuffer) {
    var buf = buffer
    if let data = buf.readData(length: buf.readableBytes) {
        storageWriter.writeRequestBody(data)
    }
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
}
```

KnotWebServer sets the callbacks when `attachLiveBridge` is called. LivePushManager broadcasts received data to all WebSocket clients.

TunnelServices implements:

```swift
class ProxyLiveBridge: LiveBridge {
    var onNewFlow: (([String: Any]) -> Void)?
    var onFlowUpdate: (([String: Any]) -> Void)?
    var onMetrics: (([String: Any]) -> Void)?
}
```

SessionRecorder calls `bridge.onNewFlow?(flowData)` in `recordClosed()`.
MetricsCollector calls `bridge.onMetrics?(data)` on its timer.

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

No messages pushed when LiveBridge is not attached (historical mode).

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
| TunnelServices/Storage/* | KnotStorage/ | All files, no logic change |
| TunnelServices/Dashboard/DashboardServer.swift | **Deleted** | Replaced by KnotWebServer |
| TunnelServices/Dashboard/DashboardHTML.swift | KnotWebService/HTML/ | Moved |
| TunnelServices/Dashboard/MetricsCollector.swift | TunnelServices (stays) | Pushes via LiveBridge |
| TunnelServices/CaptureTask.dashboardServer | TunnelServices/CaptureTask.liveBridge | Type changes to LiveBridge |
| SessionRecorder DB/File writes | Delegates to StorageWriter | NIO adapting stays in SessionRecorder |
