# KnotWebService Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an HTTP+WebSocket API server module that provides REST APIs for historical data query and real-time push for live capture, replacing the existing DashboardServer.

**Architecture:** New `LocalPackages/KnotWebService` Swift package. NIO HTTP server with REST routing (tasks, flows, payloads) + WebSocket push via LiveBridge protocol. DashboardServer deleted from TunnelServices and replaced. Port allocation uses strategy C (9090 + fallback).

**Tech Stack:** Swift, NIOCore, NIOPosix, NIOHTTP1, NIOWebSocket, KnotStorage (SQLite)

**Spec:** `docs/superpowers/specs/2026-03-22-knot-web-service-design.md`

**Prerequisite:** KnotStorage extraction complete (Plan 1).

---

## File Structure

### New Files (KnotWebService package)

```
LocalPackages/KnotWebService/
├── Package.swift
├── Sources/KnotWebService/
│   ├── Server/
│   │   ├── KnotWebServer.swift          # Public entry point: init, start, stop, attachLiveBridge
│   │   ├── PortAllocator.swift          # bindWithRetry logic (strategy C)
│   │   └── HTTPRouter.swift             # Request routing: path matching → handler dispatch
│   ├── Routes/
│   │   ├── TaskRoutes.swift             # GET /api/tasks, GET /api/tasks/{id}
│   │   ├── FlowRoutes.swift             # GET /api/tasks/{id}/flows, /search, /stats, /{fid}
│   │   ├── PayloadRoutes.swift          # GET .../request, .../response, .../decoded (chunked)
│   │   └── ResponseHelper.swift         # JSON envelope, error response, CORS headers
│   ├── WebSocket/
│   │   ├── LivePushManager.swift        # WS connection tracking + broadcast
│   │   └── WebSocketHandler.swift       # Per-connection WS handler (ping/pong/close)
│   ├── Bridge/
│   │   └── LiveBridge.swift             # Protocol definition (6 callbacks)
│   └── HTML/
│       └── DashboardHTML.swift          # Moved from TunnelServices (static HTML)
└── Tests/KnotWebServiceTests/
    ├── PortAllocatorTests.swift
    ├── TaskRoutesTests.swift
    ├── FlowRoutesTests.swift
    └── LivePushManagerTests.swift
```

### Modified Files (TunnelServices)

```
LocalPackages/TunnelServices/
├── Package.swift                        # Add KnotWebService dependency
├── Sources/TunnelServices/
│   ├── Dashboard/                       # DELETE entire directory (DashboardServer, DashboardHTML, MetricsCollector)
│   ├── Proxy/ProxyServer.swift          # Replace DashboardServer with KnotWebServer, schedule metrics timer
│   ├── CaptureTask.swift                # Replace DashboardPushable with LiveBridge
│   ├── Framework/SessionRecorder.swift  # Replace dashboard.pushFlow with bridge.onNewFlow
│   └── Bridge/
│       └── ProxyLiveBridge.swift        # NEW: LiveBridge implementation
```

---

### Task 1: Create KnotWebService package scaffold

**Files:**
- Create: `LocalPackages/KnotWebService/Package.swift`
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Bridge/LiveBridge.swift`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p LocalPackages/KnotWebService/Sources/KnotWebService/{Server,Routes,WebSocket,Bridge,HTML}
mkdir -p LocalPackages/KnotWebService/Tests/KnotWebServiceTests
```

- [ ] **Step 2: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnotWebService",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "KnotWebService", targets: ["KnotWebService"]),
    ],
    dependencies: [
        .package(path: "../KnotStorage"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "KnotWebService",
            dependencies: [
                "KnotStorage",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "KnotWebServiceTests",
            dependencies: ["KnotWebService"]
        ),
    ]
)
```

**NOTE:** Check the exact swift-nio URL and version used in TunnelServices Package.swift and use the same.

- [ ] **Step 3: Create LiveBridge.swift**

```swift
import Foundation

/// Protocol for injecting real-time capture data into the web service.
/// Defined in KnotWebService, implemented by TunnelServices (ProxyLiveBridge).
/// When no LiveBridge is attached, the web service operates in historical-only mode.
public protocol LiveBridge: AnyObject {
    var onNewFlow: (([String: Any]) -> Void)? { get set }
    var onFlowUpdate: (([String: Any]) -> Void)? { get set }
    var onMetrics: (([String: Any]) -> Void)? { get set }
    var onStats: (([String: Any]) -> Void)? { get set }
    var onRetest: (([String: Any]) -> Void)? { get set }
    var onSurfProgress: (([String: Any]) -> Void)? { get set }
}
```

- [ ] **Step 4: Verify package resolves**

Run: `swift package --package-path LocalPackages/KnotWebService resolve`

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/KnotWebService/
git commit -m "feat(KnotWebService): scaffold package with LiveBridge protocol"
```

---

### Task 2: Implement PortAllocator + ResponseHelper + HTTPRouter

**Files:**
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Server/PortAllocator.swift`
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Routes/ResponseHelper.swift`
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Server/HTTPRouter.swift`

- [ ] **Step 1: Create PortAllocator.swift**

Strategy C: try preferred port, increment up to maxRetries times.

```swift
import NIOCore
import NIOPosix
import NIOHTTP1

public enum PortAllocationError: Error {
    case exhausted(preferredPort: Int, maxRetries: Int)
}

enum PortAllocator {
    static func bindWithRetry(
        bootstrap: ServerBootstrap,
        host: String,
        preferredPort: Int,
        maxRetries: Int
    ) throws -> Channel {
        for offset in 0..<maxRetries {
            let port = preferredPort + offset
            if let ch = try? bootstrap.bind(host: host, port: port).wait() {
                return ch
            }
        }
        throw PortAllocationError.exhausted(preferredPort: preferredPort, maxRetries: maxRetries)
    }
}
```

- [ ] **Step 2: Create ResponseHelper.swift**

JSON envelope helpers + CORS headers.

```swift
import Foundation
import NIOCore
import NIOHTTP1

enum ResponseHelper {
    /// Standard JSON success response: {"code": 0, "data": ...}
    static func jsonResponse(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus = .ok,
        body: Any
    ) {
        let envelope: [String: Any] = ["code": 0, "data": body]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope),
              let text = String(data: data, encoding: .utf8) else {
            errorResponse(context: context, status: .internalServerError, message: "JSON serialization failed")
            return
        }
        sendHTTP(context: context, status: status, contentType: "application/json", body: text)
    }

    /// Error response: {"code": N, "error": "message"}
    static func errorResponse(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        message: String
    ) {
        let envelope: [String: Any] = ["code": Int(status.code), "error": message]
        let data = (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? "{}"
        sendHTTP(context: context, status: status, contentType: "application/json", body: text)
    }

    /// Send raw HTTP response with CORS headers
    static func sendHTTP(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        contentType: String,
        body: String
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: contentType)
        headers.add(name: "content-length", value: "\(body.utf8.count)")
        headers.add(name: "access-control-allow-origin", value: "*")
        headers.add(name: "cache-control", value: "no-cache")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
    }
}
```

- [ ] **Step 3: Create HTTPRouter.swift**

Simple path-based router that dispatches to route handlers.

```swift
import NIOCore
import NIOHTTP1
import KnotStorage

/// Routes incoming HTTP requests to the appropriate handler.
final class HTTPRouter: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let pushManager: LivePushManager
    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?

    init(pushManager: LivePushManager) {
        self.pushManager = pushManager
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            requestBody = nil
        case .body(var body):
            if requestBody == nil {
                requestBody = body
            } else {
                requestBody?.writeBuffer(&body)
            }
        case .end:
            guard let head = requestHead else { return }
            route(context: context, head: head)
            requestHead = nil
            requestBody = nil
        }
    }

    private func route(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let uri = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
        let components = uri.split(separator: "/").map(String.init)

        // GET / → HTML dashboard
        if uri == "/" || uri == "/index.html" {
            DashboardHTML.serve(context: context)
            return
        }

        // API routes: /api/...
        guard components.count >= 2, components[0] == "api" else {
            ResponseHelper.errorResponse(context: context, status: .notFound, message: "Not Found")
            return
        }

        let query = parseQuery(head.uri)

        switch (head.method, components.dropFirst().map { $0 }) {
        // GET /api/tasks
        case (.GET, ["tasks"]):
            TaskRoutes.list(context: context)

        // GET /api/tasks/{id}
        case (.GET, ["tasks", let idStr]) where Int64(idStr) != nil:
            TaskRoutes.detail(context: context, taskId: Int64(idStr)!)

        // GET /api/tasks/{id}/flows
        case (.GET, ["tasks", let idStr, "flows"]) where Int64(idStr) != nil:
            FlowRoutes.list(context: context, taskId: Int64(idStr)!, query: query)

        // GET /api/tasks/{id}/flows/search
        case (.GET, ["tasks", let idStr, "flows", "search"]) where Int64(idStr) != nil:
            FlowRoutes.search(context: context, taskId: Int64(idStr)!, query: query)

        // GET /api/tasks/{id}/flows/stats
        case (.GET, ["tasks", let idStr, "flows", "stats"]) where Int64(idStr) != nil:
            FlowRoutes.stats(context: context, taskId: Int64(idStr)!)

        // GET /api/tasks/{id}/flows/{fid}
        case (.GET, ["tasks", let idStr, "flows", let fid]) where Int64(idStr) != nil:
            FlowRoutes.detail(context: context, taskId: Int64(idStr)!, flowId: fid)

        // GET /api/tasks/{id}/flows/{fid}/request
        case (.GET, ["tasks", let idStr, "flows", let fid, "request"]) where Int64(idStr) != nil:
            PayloadRoutes.request(context: context, taskId: Int64(idStr)!, flowId: fid, query: query)

        // GET /api/tasks/{id}/flows/{fid}/response
        case (.GET, ["tasks", let idStr, "flows", let fid, "response"]) where Int64(idStr) != nil:
            PayloadRoutes.response(context: context, taskId: Int64(idStr)!, flowId: fid, query: query)

        // GET /api/tasks/{id}/flows/{fid}/decoded
        case (.GET, ["tasks", let idStr, "flows", let fid, "decoded"]) where Int64(idStr) != nil:
            PayloadRoutes.decoded(context: context, taskId: Int64(idStr)!, flowId: fid)

        default:
            ResponseHelper.errorResponse(context: context, status: .notFound, message: "Not Found")
        }
    }

    private func parseQuery(_ uri: String) -> [String: String] {
        guard let queryStart = uri.firstIndex(of: "?") else { return [:] }
        let queryString = uri[uri.index(after: queryStart)...]
        var result: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return result
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
```

- [ ] **Step 4: Verify build** (will fail on missing types — that's ok, just ensure no syntax errors)

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/KnotWebService/Sources/
git commit -m "feat(KnotWebService): add PortAllocator, ResponseHelper, HTTPRouter"
```

---

### Task 3: Implement WebSocket handler + LivePushManager

**Files:**
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/WebSocket/LivePushManager.swift`
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/WebSocket/WebSocketHandler.swift`

- [ ] **Step 1: Create LivePushManager.swift**

Thread-safe WS connection tracking + broadcast. Wires LiveBridge callbacks to WS broadcast.

```swift
import Foundation
import NIOCore
import NIOWebSocket
import NIOConcurrencyHelpers

/// Manages WebSocket connections and broadcasts live data from LiveBridge.
public final class LivePushManager: @unchecked Sendable {
    private let connections = NIOLockedValueBox<[ObjectIdentifier: Channel]>([:])

    public var hasClients: Bool {
        connections.withLockedValue { !$0.isEmpty }
    }

    public init() {}

    func addConnection(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        connections.withLockedValue { $0[id] = channel }
    }

    func removeConnection(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        connections.withLockedValue { _ = $0.removeValue(forKey: id) }
    }

    /// Attach a LiveBridge — sets callbacks that broadcast to all WS clients.
    public func attach(_ bridge: LiveBridge) {
        bridge.onNewFlow = { [weak self] data in self?.broadcast(type: "flow", data: data) }
        bridge.onFlowUpdate = { [weak self] data in self?.broadcast(type: "flow_update", data: data) }
        bridge.onMetrics = { [weak self] data in self?.broadcast(type: "metrics", data: data) }
        bridge.onStats = { [weak self] data in self?.broadcast(type: "stats", data: data) }
        bridge.onRetest = { [weak self] data in self?.broadcast(type: "retest", data: data) }
        bridge.onSurfProgress = { [weak self] data in self?.broadcast(type: "surf_progress", data: data) }
    }

    /// Detach — clears all callbacks.
    public func detach(_ bridge: LiveBridge) {
        bridge.onNewFlow = nil
        bridge.onFlowUpdate = nil
        bridge.onMetrics = nil
        bridge.onStats = nil
        bridge.onRetest = nil
        bridge.onSurfProgress = nil
    }

    private func broadcast(type: String, data: [String: Any]) {
        guard hasClients else { return }
        guard let json = try? JSONSerialization.data(withJSONObject: ["type": type, "data": data]),
              let text = String(data: json, encoding: .utf8) else { return }

        let channels = connections.withLockedValue { Array($0.values) }
        for channel in channels {
            var buf = channel.allocator.buffer(capacity: text.utf8.count)
            buf.writeString(text)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
            channel.writeAndFlush(frame, promise: nil)
        }
    }
}
```

- [ ] **Step 2: Create WebSocketHandler.swift**

```swift
import NIOCore
import NIOWebSocket

/// Per-connection WebSocket handler. Handles ping/pong/close and registers with LivePushManager.
final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let pushManager: LivePushManager

    init(pushManager: LivePushManager) {
        self.pushManager = pushManager
    }

    func handlerAdded(context: ChannelHandlerContext) {
        pushManager.addConnection(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        pushManager.removeConnection(context.channel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(close)).whenComplete { _ in
                context.close(promise: nil)
            }
        default:
            break // push-only; ignore text/binary from clients
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        pushManager.removeConnection(context.channel)
        context.close(promise: nil)
    }
}
```

- [ ] **Step 3: Verify build**
- [ ] **Step 4: Commit**

```bash
git add LocalPackages/KnotWebService/Sources/KnotWebService/WebSocket/
git commit -m "feat(KnotWebService): add LivePushManager and WebSocketHandler"
```

---

### Task 4: Implement REST route handlers (TaskRoutes, FlowRoutes, PayloadRoutes)

**Files:**
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Routes/TaskRoutes.swift`
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Routes/FlowRoutes.swift`
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Routes/PayloadRoutes.swift`

- [ ] **Step 1: Create TaskRoutes.swift**

```swift
import Foundation
import NIOCore
import NIOHTTP1
import KnotStorage

enum TaskRoutes {
    /// GET /api/tasks — list all capture tasks
    static func list(context: ChannelHandlerContext) {
        do {
            let tasks = try CatalogDAO.findAllTasks(db: DatabaseManager.shared.catalogDB)
            let data = tasks.map { taskToDict($0) }
            ResponseHelper.jsonResponse(context: context, body: data)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError, message: "\(error)")
        }
    }

    /// GET /api/tasks/{id} — task detail
    static func detail(context: ChannelHandlerContext, taskId: Int64) {
        // Query catalog for task by ID, return detail JSON
        // Implementation reads from CatalogDAO
    }

    private static func taskToDict(_ task: CaptureTaskRecord) -> [String: Any] {
        return [
            "id": task.id,
            "name": task.name,
            "createdAt": task.createdAt,
            "status": task.status,
            // Add other fields as needed from CaptureTaskRecord
        ]
    }
}
```

Read the actual `CatalogDAO` and `CaptureTaskRecord` APIs in KnotStorage to implement correctly.

- [ ] **Step 2: Create FlowRoutes.swift**

Handles: list (paginated), search (FTS5), stats (aggregate), detail (single flow).

Read `FlowDAO` API in KnotStorage to see exact method signatures for `query()`, `find()`, `count()`.

Key parameters for list:
- `page` (default 1), `size` (default 50)
- `protocol`, `host`, `status` (filters)
- `sort` (default "started_at DESC")

For stats: use `FlowDAO+Count` methods to get protocol distribution and status counts.

- [ ] **Step 3: Create PayloadRoutes.swift**

Handles: request body, response body, decoded content.

Use `PayloadReader` from KnotStorage for chunked streaming:
```swift
// For large payloads, use chunked transfer encoding
let reader = PayloadReader(filePath: payloadRef)
// Stream 64KB chunks
for chunk in reader.chunks(size: 65536) {
    // Write chunk to HTTP response
}
```

For `?preview=true`, read only first 4KB.

- [ ] **Step 4: Verify build**
- [ ] **Step 5: Commit**

```bash
git add LocalPackages/KnotWebService/Sources/KnotWebService/Routes/
git commit -m "feat(KnotWebService): add TaskRoutes, FlowRoutes, PayloadRoutes"
```

---

### Task 5: Implement KnotWebServer (main entry point) + move DashboardHTML

**Files:**
- Create: `LocalPackages/KnotWebService/Sources/KnotWebService/Server/KnotWebServer.swift`
- Move: `TunnelServices/Dashboard/DashboardHTML.swift` → `KnotWebService/HTML/DashboardHTML.swift`

- [ ] **Step 1: Move DashboardHTML.swift**

```bash
cp LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/DashboardHTML.swift \
   LocalPackages/KnotWebService/Sources/KnotWebService/HTML/
```

Add a static `serve(context:)` method:
```swift
extension DashboardHTML {
    static func serve(context: ChannelHandlerContext) {
        ResponseHelper.sendHTTP(context: context, status: .ok,
                                contentType: "text/html; charset=utf-8", body: html)
    }
}
```

- [ ] **Step 2: Create KnotWebServer.swift**

```swift
import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import os

public final class KnotWebServer: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.knot.webservice", category: "Server")

    private let preferredPort: Int
    private let maxPortRetries: Int
    private let eventLoopGroup: EventLoopGroup
    private let ownsEventLoopGroup: Bool

    private var serverChannel: Channel?
    private let pushManager = LivePushManager()
    private var liveBridge: LiveBridge?

    public private(set) var boundPort: Int?

    public init(preferredPort: Int = 9090, maxPortRetries: Int = 10,
                eventLoopGroup: EventLoopGroup? = nil) {
        self.preferredPort = preferredPort
        self.maxPortRetries = maxPortRetries
        if let group = eventLoopGroup {
            self.eventLoopGroup = group
            self.ownsEventLoopGroup = false
        } else {
            self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
            self.ownsEventLoopGroup = true
        }
    }

    public func start() throws -> Int {
        let pm = pushManager
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, _ in channel.eventLoop.makeSucceededFuture(HTTPHeaders()) },
            upgradePipelineHandler: { channel, _ in
                // Remove HTTP handler before WS handler is added
                if let h = try? channel.pipeline.syncOperations.handler(type: HTTPRouter.self) {
                    try? channel.pipeline.syncOperations.removeHandler(h)
                }
                if let h = try? channel.pipeline.syncOperations.handler(type: HTTPServerProtocolErrorHandler.self) {
                    try? channel.pipeline.syncOperations.removeHandler(h)
                }
                return channel.pipeline.addHandler(WebSocketHandler(pushManager: pm))
            }
        )

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
                ).flatMap {
                    channel.pipeline.addHandler(HTTPRouter(pushManager: pm))
                }
            }

        let channel = try PortAllocator.bindWithRetry(
            bootstrap: bootstrap, host: "127.0.0.1",
            preferredPort: preferredPort, maxRetries: maxPortRetries
        )

        self.serverChannel = channel
        self.boundPort = channel.localAddress?.port
        Self.logger.info("KnotWebServer listening on http://127.0.0.1:\(self.boundPort ?? 0)")
        return self.boundPort ?? 0
    }

    public func attachLiveBridge(_ bridge: LiveBridge) {
        self.liveBridge = bridge
        pushManager.attach(bridge)
    }

    public func detachLiveBridge() {
        if let bridge = liveBridge {
            pushManager.detach(bridge)
        }
        self.liveBridge = nil
    }

    public func stop() {
        if let bridge = liveBridge {
            pushManager.detach(bridge)
        }
        liveBridge = nil
        try? serverChannel?.close().wait()
        serverChannel = nil
        boundPort = nil
        if ownsEventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }
}
```

- [ ] **Step 3: Verify full build**

Run: `swift build --package-path LocalPackages/KnotWebService`
Expected: BUILD SUCCESS

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/KnotWebService/
git commit -m "feat(KnotWebService): implement KnotWebServer with HTTP+WS pipeline"
```

---

### Task 6: Replace DashboardServer in TunnelServices with KnotWebServer

**Files:**
- Delete: `LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/DashboardServer.swift`
- Delete: `LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/DashboardHTML.swift`
- Keep: `LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/MetricsCollector.swift` (stays)
- Modify: `LocalPackages/TunnelServices/Package.swift` (add KnotWebService dep)
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/ProxyServer.swift`
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/CaptureTask.swift`
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Framework/SessionRecorder.swift`
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Bridge/ProxyLiveBridge.swift`

- [ ] **Step 1: Add KnotWebService to TunnelServices Package.swift**

Add to dependencies: `.package(path: "../KnotWebService"),`
Add to target deps: `.product(name: "KnotWebService", package: "KnotWebService"),`

- [ ] **Step 2: Create ProxyLiveBridge.swift**

```swift
import Foundation
import KnotWebService

/// TunnelServices implementation of LiveBridge.
/// KnotWebServer sets callbacks; SessionRecorder/MetricsCollector call them.
public class ProxyLiveBridge: LiveBridge {
    public var onNewFlow: (([String: Any]) -> Void)?
    public var onFlowUpdate: (([String: Any]) -> Void)?
    public var onMetrics: (([String: Any]) -> Void)?
    public var onStats: (([String: Any]) -> Void)?
    public var onRetest: (([String: Any]) -> Void)?
    public var onSurfProgress: (([String: Any]) -> Void)?

    public init() {}
}
```

- [ ] **Step 3: Update CaptureTask.swift**

Replace:
- `DashboardPushable` protocol → delete
- `dashboardServer: DashboardPushable?` → `liveBridge: ProxyLiveBridge?`

- [ ] **Step 4: Update SessionRecorder.swift**

In `recordClosed()`, replace `dashboard.pushFlow(flowData)` with:
```swift
task.liveBridge?.onNewFlow?(flowData)
```

- [ ] **Step 5: Update ProxyServer.swift**

Replace DashboardServer with KnotWebServer:
```swift
import KnotWebService

// In start():
let webServer = KnotWebServer(preferredPort: 9090, eventLoopGroup: self.workerGroup)
let port = try webServer.start()
self.webServer = webServer

let bridge = ProxyLiveBridge()
webServer.attachLiveBridge(bridge)
task.liveBridge = bridge

// Schedule metrics timer (moved from DashboardServer)
self.metricsTask = channel.eventLoop.scheduleRepeatedTask(...) {
    let metrics = MetricsCollector.collect(task: task, startTime: startTime)
    bridge.onMetrics?(metricsData)
}
```

- [ ] **Step 6: Delete DashboardServer.swift and DashboardHTML.swift**

```bash
rm LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/DashboardServer.swift
rm LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/DashboardHTML.swift
```

Keep MetricsCollector.swift in Dashboard/ directory.

- [ ] **Step 7: Fix all compilation errors**

Run `swift build --package-path LocalPackages/TunnelServices` and fix any remaining references to DashboardServer, DashboardPushable, etc.

- [ ] **Step 8: Verify build**

Run: `swift build --package-path LocalPackages/TunnelServices`
Expected: BUILD SUCCESS

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: replace DashboardServer with KnotWebServer, add ProxyLiveBridge"
```

---

### Task 7: Write tests and verify full integration

**Files:**
- Create: `LocalPackages/KnotWebService/Tests/KnotWebServiceTests/KnotWebServerTests.swift`

- [ ] **Step 1: Write KnotWebServer integration test**

Test that:
1. KnotWebServer starts and binds a port
2. HTTP GET / returns HTML
3. HTTP GET /api/tasks returns JSON
4. WebSocket connects and receives push when LiveBridge fires
5. Port fallback works (bind two servers, second gets +1 port)

- [ ] **Step 2: Run KnotWebService tests**

Run: `swift test --package-path LocalPackages/KnotWebService`
Expected: ALL PASS

- [ ] **Step 3: Run TunnelServices integration tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter 'WebSocket|HTTP1Integration|HTTP2Integration'`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(KnotWebService): add integration tests for web server and routes"
```
