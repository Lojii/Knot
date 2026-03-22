# Protocol Plugin Architecture Design

## Goal

Replace the monolithic `ProtocolRouter` (hard-coded if-else chain) with a pluggable protocol tree where each protocol is a self-contained plugin that registers into a parent-child hierarchy. The tree is walked recursively: each layer detects, handles, and optionally unwraps data before passing it to child plugins for further detection.

## Architecture

The system models network protocols as a tree. Root nodes are transport layers (TCP, UDP). Each node is a **ProtocolPlugin** that can match incoming bytes, build a NIO pipeline, and optionally declare children for sub-protocol detection after its own processing (e.g., TLS decrypts, then children detect HTTP).

Registration is **compile-time static** — the full tree is declared in `ProtocolRegistry.buildDefault()`. No runtime discovery or dynamic loading.

Plugins return NIO `ChannelHandler`s directly. The framework manages handler lifecycle (add/remove from pipeline) but does not abstract away NIO.

## Scope

**In scope:**
- Protocol handler chain (current `Proxy/` handlers) → plugin architecture
- Protocol recorders (`HTTPRecorder`, `GRPCRecorder`, etc.) → bundled with their plugin
- Legacy `Detector/` and `Handler/` directories → deleted (already unused in main path)

**Out of scope:**
- Storage layer (DAO, Schema, Model, Payload) — already well-organized, stays as-is
- PacketCapture engine (IPPacketParser, UDPForwarder) — system-level, not protocol-specific
- Config, Rule, Utils, Export, HttpService — unchanged

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Registration | Compile-time static | Knot is an app, not a framework. No third-party extensions needed. |
| NIO relationship | Plugins return ChannelHandlers | TLS/HTTP2 deeply depend on NIO APIs. Abstracting away NIO adds adapter code with no benefit. |
| Migration | Clean legacy first, then build | Legacy Detector/Handler code is already off the main path. Remove dead code before building new architecture. |
| Recorder ownership | Bundled with plugin | Handler and recorder are tightly coupled. Keeping them together reduces cross-module dependencies. |

---

## Section 1: Core Plugin Protocol

```swift
/// Protocol match result
enum MatchResult {
    case yes(confidence: Int)       // Matched. Higher confidence wins when multiple plugins match.
    case no                          // Not this protocol.
    case needMoreData(minimum: Int)  // Need at least `minimum` bytes to decide.
}

/// Core plugin interface — every protocol implements this
protocol ProtocolPlugin: AnyObject {
    /// Unique identifier, e.g. "http1", "tls", "socks5"
    var id: String { get }

    /// Human-readable name, e.g. "HTTP/1.x", "TLS", "SOCKS5"
    var displayName: String { get }

    /// Inspect leading bytes to determine if this protocol matches.
    /// Must be stateless — no side effects.
    func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult

    /// After a successful match, configure the NIO pipeline for this protocol.
    /// - Sync plugins (HTTP1, Raw, etc.): add handlers and return a succeeded future.
    /// - Async plugins (TLS): return a future that completes after handshake.
    /// - The dispatcher chains on this future before forwarding data (see Section 6).
    func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void>

    /// Create a protocol-specific recorder (leaf plugins only).
    /// Unwrap plugins (TLS, SOCKS5) return nil — they add metadata instead.
    /// Implementations must preserve `searchKeyMapping` for FlowDAO query compatibility.
    func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder?
}

/// Context available during matching (read-only, no side effects)
struct MatchContext {
    let localPort: Int
    let remoteAddress: SocketAddress?
    let parentProtocol: String?     // Parent plugin id, e.g. "tls"
    let metadata: ProtocolMetadata  // Typed info from parent (see below)
}

/// Context available during pipeline construction
struct ProtocolContext {
    let channel: Channel
    let task: CaptureTask
    let recorder: SessionRecorder
    let parentProtocol: String?
    let childNodes: [ProtocolNode]  // This plugin's children from the tree
    let metadata: ProtocolMetadata  // ALPN, SNI, etc. from parent
}

/// Typed metadata passed from parent plugin to child (replaces [String: Any])
struct ProtocolMetadata {
    var parentId: String?
    var alpnResult: String?         // TLS → child: negotiated protocol
    var sni: String?                // TLS → child: server name indication
    var innerHost: String?          // SOCKS5/CONNECT → child: tunnel target host
    var innerPort: Int?             // SOCKS5/CONNECT → child: tunnel target port
    var isEncrypted: Bool = false   // Whether traffic has been through TLS
    var extra: [String: Any] = [:]  // Escape hatch for plugin-specific data

    static let empty = ProtocolMetadata()
}
```

### Key points

- `canMatch` is pure detection — no state mutation, no pipeline changes.
- `buildPipeline` returns `EventLoopFuture<Void>` — the dispatcher chains on it before forwarding data. Sync plugins return an already-succeeded future. Async plugins (TLS) return a future that completes after handshake.
- `ProtocolMetadata` is a typed struct instead of `[String: Any]` — compiler catches typos, IDE auto-completes. The `extra` dict is an escape hatch for plugin-specific data.
- `ProtocolContext.childNodes` gives unwrap plugins access to their children from the tree, so they can create child dispatchers without needing a global registry reference.
- `confidence` resolves conflicts when multiple plugins match. **Tie-breaking**: when two plugins have equal confidence, the one declared first in `buildDefault()` wins (array order is the tiebreaker).
- `ProtocolRecorder` implementations must preserve the existing `searchKeyMapping` static property for FlowDAO query compatibility.

---

## Section 2: Protocol Tree & Registry

```swift
/// Tree node: wraps a plugin with its children
struct ProtocolNode {
    let plugin: ProtocolPlugin
    var children: [ProtocolNode]
}

/// Compile-time static tree construction
final class ProtocolRegistry {

    /// Singleton — holds the built tree for SOCKS5/CONNECT re-entry
    static let shared = ProtocolRegistry()

    /// The root nodes (TCP, UDP)
    let roots: [ProtocolNode]

    /// Quick accessor for TCP children — used by SOCKS5/CONNECT re-entry
    var tcpChildren: [ProtocolNode] {
        roots.first(where: { $0.plugin.id == "tcp" })?.children ?? []
    }

    private init() {
        self.roots = ProtocolRegistry.buildDefault()
    }

    /// The complete protocol hierarchy
    static func buildDefault() -> [ProtocolNode] {
        return [
            // ── TCP root ──
            ProtocolNode(plugin: TCPRootPlugin(), children: [
                ProtocolNode(plugin: HTTP1Plugin(), children: [
                    ProtocolNode(plugin: WebSocketPlugin(), children: []),
                ]),
                ProtocolNode(plugin: TLSPlugin(), children: [
                    ProtocolNode(plugin: HTTP1Plugin(), children: [
                        ProtocolNode(plugin: WebSocketPlugin(), children: []),
                    ]),
                    ProtocolNode(plugin: HTTP2Plugin(), children: [
                        ProtocolNode(plugin: GRPCPlugin(), children: []),
                    ]),
                ]),
                ProtocolNode(plugin: SOCKS5Plugin(), children: []),
                ProtocolNode(plugin: MQTTPlugin(), children: []),
                ProtocolNode(plugin: RedisPlugin(), children: []),
            ]),

            // ── UDP root ──
            ProtocolNode(plugin: UDPRootPlugin(), children: [
                ProtocolNode(plugin: DNSPlugin(), children: []),
                ProtocolNode(plugin: QUICPlugin(), children: [
                    ProtocolNode(plugin: HTTP3Plugin(), children: []),
                ]),
                ProtocolNode(plugin: NTPPlugin(), children: []),
            ]),
        ]
    }
}
```

### Key points

- Same plugin class can appear at multiple positions (e.g., `HTTP1Plugin` under both TCP and TLS). Different instances, same class. `MatchContext.parentProtocol` tells the plugin where it sits.
- SOCKS5 declares no children — after unwrapping, it re-enters the TCP subtree via `ProtocolRegistry.shared.tcpChildren`.
- WebSocket is a child of HTTP1 — it's detected via HTTP Upgrade header after HTTP parsing begins.
- The entire tree is visible in one function. Adding a new protocol = adding a line here + creating the plugin folder.

---

## Section 3: Match & Dispatch Flow

### ProtocolDispatcher

The dispatcher is itself a `ChannelInboundHandler`. It receives raw bytes, walks the current tree level, picks the best match, and hands off to the winning plugin.

```swift
final class ProtocolDispatcher: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private let nodes: [ProtocolNode]
    private let task: CaptureTask
    private let recorder: SessionRecorder
    private let parentMeta: ProtocolMetadata

    init(nodes: [ProtocolNode], task: CaptureTask,
         recorder: SessionRecorder, parentMeta: ProtocolMetadata = .empty) { ... }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)

        // 1. Try all children, pick highest confidence
        // 2. Handle needMoreData — buffer and wait
        // 3. No match → RawPlugin fallback
        // 4. Match → winner.plugin.buildPipeline()
        // 5. Chain on future → forward data → remove self

        // See Section 6 for full implementation
    }
}
```

### Three plugin roles

| Role | Behavior | Examples |
|------|----------|----------|
| **Leaf** | Match → build pipeline → done. No children. | MQTT, Redis, DNS, NTP |
| **Unwrap** | Match → process/handshake → re-detect children with unwrapped data. May be async (TLS handshake) or trigger TCP subtree re-entry (SOCKS5, CONNECT). | TLS, SOCKS5, HTTP CONNECT |
| **Inspect** | Match → capture data → may also have sub-protocol children. | HTTP1 (→ WebSocket), HTTP2 (→ gRPC) |

### Unwrap plugin re-detection

When an unwrap plugin finishes its work (e.g., TLS handshake complete), it creates a **new ProtocolDispatcher** with its children (available via `context.childNodes`) and inserts it into the pipeline:

```swift
// Inside TLSPlugin, after handshake:
var childMeta = ProtocolMetadata()
childMeta.parentId = "tls"
childMeta.alpnResult = alpnResult
childMeta.sni = sni
childMeta.isEncrypted = true
let childDispatcher = ProtocolDispatcher(
    nodes: context.childNodes,  // from ProtocolContext, set by dispatcher
    task: context.task,
    recorder: context.recorder,
    parentMeta: childMeta
)
context.channel.pipeline.addHandler(childDispatcher)
```

### SOCKS5 / HTTP CONNECT re-entry

These protocols unwrap a tunnel, producing a new TCP stream. Instead of detecting their own children, they re-enter the TCP root via the registry singleton:

```swift
// Inside SOCKS5Plugin, after unwrap:
let tcpNodes = ProtocolRegistry.shared.tcpChildren
var meta = ProtocolMetadata()
meta.parentId = "socks5"
meta.innerHost = host
meta.innerPort = port
let dispatcher = ProtocolDispatcher(
    nodes: tcpNodes, task: task, recorder: recorder,
    parentMeta: meta
)
channel.pipeline.addHandler(dispatcher)
```

### WebSocket sub-protocol detection

WebSocket is a child of HTTP1, but unlike byte-prefix detection, it's detected via HTTP `Upgrade: websocket` header *after* HTTP parsing has started. HTTP1Plugin drives this internally:

```swift
// Inside HTTP1Plugin's HTTPCaptureHandler, when Upgrade header is detected:
if isWebSocketUpgrade(head) {
    // HTTP1Plugin checks its own children for a WebSocketPlugin
    for child in childNodes {
        if case .yes = child.plugin.canMatch(buffer, context: matchCtx) {
            child.plugin.buildPipeline(context: childCtx)
            break
        }
    }
}
```

This means Inspect plugins are responsible for driving their own child detection at the appropriate moment, rather than relying on the dispatcher.

### Full example: HTTPS via proxy

```
① Bytes arrive on TCP:8034
   Dispatcher tries TCP children → HTTP1Plugin matches "CONN..." (.yes, 90)

② HTTP1Plugin.buildPipeline() → decodes CONNECT example.com:443
   Sends 200 → strips HTTP handlers → re-enters TCP subtree

③ New Dispatcher tries TCP children → TLSPlugin matches 0x16 (.yes, 100)

④ TLSPlugin.buildPipeline() → TLS handshake (async)
   ALPN negotiated: "http/1.1"
   → Creates child Dispatcher with TLS children

⑤ Child Dispatcher → HTTP1Plugin matches "GET /..." (.yes, 90)

⑥ HTTP1Plugin.buildPipeline(parent: "tls")
   → HTTPCaptureHandler(isSSL: true) + HTTPRecorder
   → Capturing decrypted HTTPS traffic ✓
```

---

## Section 4: Recording Integration

### Ownership model

```
SessionRecorder (per connection — framework layer)
├── Manages: flowId, PayloadWriter, TcpConnectionRecord
├── Calls: plugin.createRecorder(flowId:context:)
└── On close: recorder.buildFlowRecord() → FlowDAO.insert()
        │
        ├── ProtocolRecorder (plugin layer)
        │   Created by leaf plugin (HTTP1, gRPC, DNS, etc.)
        │   Records protocol-specific metadata
        │
        └── PayloadWriter (framework layer)
            Streams request/response bodies to disk
```

### Rules

- **SessionRecorder** stays in Framework/ — it manages the connection lifecycle, TCP record, flowId generation. Not protocol-specific.
- **ProtocolRecorder** belongs to the plugin — `HTTP1Plugin` creates `HTTPRecorder`, `GRPCPlugin` creates `GRPCRecorder`. The plugin knows its own data format.
- **Unwrap plugins don't create recorders** — TLS and SOCKS5 don't produce FlowRecords. They add metadata (SNI, cipher suite, etc.) to SessionRecorder, which the inner protocol's recorder includes when building the final FlowRecord.
- **One final ProtocolRecorder per connection** — created by the innermost leaf/inspect plugin. For a TLS→HTTP1 connection, HTTPRecorder is the recorder; TLS just contributed metadata.

---

## Section 5: Directory Structure

```
TunnelServices/
├── Framework/                          ← Plugin infrastructure
│   ├── ProtocolPlugin.swift            ← Protocol + MatchResult + MatchContext + ProtocolContext
│   ├── ProtocolNode.swift              ← Tree node struct
│   ├── ProtocolRegistry.swift          ← Static tree builder
│   ├── ProtocolDispatcher.swift        ← Match & dispatch ChannelHandler
│   └── SessionRecorder.swift           ← Per-connection lifecycle
│
├── Plugins/                            ← Each protocol = one folder
│   ├── HTTP1/
│   │   ├── HTTP1Plugin.swift           ← canMatch + buildPipeline
│   │   ├── HTTPCaptureHandler.swift    ← NIO handler
│   │   └── HTTPRecorder.swift          ← ProtocolRecorder impl
│   ├── HTTP2/
│   │   ├── HTTP2Plugin.swift
│   │   ├── HTTP2CaptureHandler.swift
│   │   └── HTTP2CaptureBuilder.swift
│   ├── HTTP3/
│   │   ├── HTTP3Plugin.swift
│   │   ├── QUICPlugin.swift
│   │   ├── QUICMITMHandler.swift
│   │   └── LsquicMITMHandler.swift
│   ├── TLS/
│   │   ├── TLSPlugin.swift            ← Unwrap: handshake → re-detect children
│   │   ├── MITMHandler.swift
│   │   ├── TLSSniffHandler.swift
│   │   └── OCSPChecker.swift
│   ├── SOCKS5/
│   │   └── SOCKS5Plugin.swift          ← Unwrap: decode → re-enter TCP subtree
│   ├── WebSocket/
│   │   ├── WebSocketPlugin.swift
│   │   ├── WebSocketCaptureHandler.swift
│   │   └── WebSocketRecorder.swift
│   ├── GRPC/
│   │   ├── GRPCPlugin.swift
│   │   ├── GRPCCaptureHandler.swift
│   │   └── GRPCRecorder.swift
│   ├── DNS/
│   │   ├── DNSPlugin.swift
│   │   ├── DNSDecoder.swift
│   │   └── DNSRecorder.swift
│   ├── Raw/
│   │   ├── RawPlugin.swift             ← Fallback for unrecognized protocols
│   │   └── RawPassthroughHandler.swift
│   └── Codec/                          ← Not yet pluginized decoders
│       ├── MQTTDecoder.swift
│       ├── RedisDecoder.swift
│       ├── SMTPDecoder.swift
│       ├── HAProxyDecoder.swift
│       ├── MemcacheDecoder.swift
│       ├── NTPDecoder.swift
│       ├── STOMPDecoder.swift
│       └── XMLFormatter.swift
│
├── Proxy/                              ← Server bootstrap & shared handlers
│   ├── MitmService.swift
│   ├── ProxyServer.swift
│   ├── ConnectHandler.swift            ← HTTP CONNECT (unwrap, re-enters TCP)
│   ├── TunnelHandler.swift             ← Raw TCP relay (used by TLS tunnel, SOCKS5, etc.)
│   ├── IPFilterHandler.swift
│   ├── BreakpointHandler.swift
│   ├── TrafficShapingHandler.swift
│   ├── TimeoutHandler.swift
│   ├── PipelineLogHandler.swift
│   └── RequestReplayer.swift
│
├── Storage/                            ← Unchanged
│   ├── DAO/
│   ├── Model/
│   ├── Schema/
│   ├── Payload/
│   ├── Protocol/
│   │   └── ProtocolRecorder.swift      ← Interface only (implementations move to plugins)
│   ├── Migration/
│   ├── DatabaseManager.swift
│   ├── TaskDatabaseGroup.swift
│   └── ...
│
├── PacketCapture/                      ← IPPacketParser + UDPForwarder stay
│   ├── IPPacketParser.swift
│   ├── PacketCaptureEngine.swift
│   └── UDPForwarder.swift
│
├── Config/                             ← Unchanged
├── Rule/                               ← Unchanged
├── Export/                             ← Unchanged
├── HttpService/                        ← Unchanged
└── Utils/                              ← Unchanged
```

### Plugin folder convention

Every plugin folder follows the same pattern:

| File | Required | Purpose |
|------|----------|---------|
| `*Plugin.swift` | Yes | Entry point: `canMatch()` + `buildPipeline()` |
| `*Handler.swift` | No | NIO ChannelHandler(s) |
| `*Recorder.swift` | No | ProtocolRecorder implementation (leaf plugins only) |
| `*Decoder.swift` | No | Wire format decoding |

---

## Section 6: ProtocolDispatcher Implementation

The dispatcher is the engine that drives the protocol tree. It is itself a `ChannelInboundHandler` that:

1. Checks proxy-enabled state (local/wifi) before processing
2. Receives the first bytes of a connection
3. Iterates all children of the current tree level, calling `canMatch()`
4. Handles `needMoreData` by buffering and waiting for more bytes
5. Picks the plugin with the highest confidence (array order breaks ties)
6. Calls `buildPipeline()` on the winner, chaining on the returned future
7. After the future completes, forwards the buffered data and removes itself

```swift
final class ProtocolDispatcher: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private let nodes: [ProtocolNode]
    private let task: CaptureTask
    private let recorder: SessionRecorder
    private let parentMeta: ProtocolMetadata
    private let rawFallback: ProtocolNode  // Pre-built Raw fallback node

    // Buffering for needMoreData
    private var pendingBuffer: ByteBuffer?
    private var maxBufferSize: Int = 4096  // Max bytes to buffer before forcing Raw fallback
    private var detected = false

    init(nodes: [ProtocolNode], task: CaptureTask,
         recorder: SessionRecorder, parentMeta: ProtocolMetadata = .empty) {
        self.nodes = nodes
        self.task = task
        self.recorder = recorder
        self.parentMeta = parentMeta
        self.rawFallback = ProtocolNode(plugin: RawPlugin(), children: [])
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Proxy-enabled check (carried over from ProtocolRouter)
        if let local = context.channel.localAddress?.description {
            let isLocal = local.contains(ProxyConfig.LocalProxy.host)
            if (isLocal && task.localEnable == 0) || (!isLocal && task.wifiEnable == 0) {
                context.close(promise: nil)
                return
            }
        }

        guard !detected else {
            // Already dispatched — forward to pipeline
            context.fireChannelRead(data)
            return
        }

        // Accumulate bytes
        var buffer = unwrapInboundIn(data)
        if var pending = pendingBuffer {
            pending.writeBuffer(&buffer)
            pendingBuffer = pending
        } else {
            pendingBuffer = buffer
        }

        guard let accumulated = pendingBuffer else { return }

        let matchCtx = MatchContext(
            localPort: context.channel.localAddress?.port ?? 0,
            remoteAddress: context.channel.remoteAddress,
            parentProtocol: parentMeta.parentId,
            metadata: parentMeta
        )

        // Try all children, track best match and any needMoreData
        var best: (node: ProtocolNode, confidence: Int)?
        var anyNeedMore = false

        for node in nodes {
            switch node.plugin.canMatch(accumulated, context: matchCtx) {
            case .yes(let c):
                if best == nil || c > best!.confidence {
                    best = (node, c)
                }
            case .needMoreData:
                anyNeedMore = true
            case .no:
                break
            }
        }

        // If no definitive match yet and some plugins need more data, wait
        // (unless we've buffered too much — then fall back to Raw)
        if best == nil && anyNeedMore && accumulated.readableBytes < maxBufferSize {
            return  // Wait for next channelRead
        }

        // Dispatch to winner or Raw fallback
        detected = true
        let winner = best?.node ?? rawFallback

        let protoCtx = ProtocolContext(
            channel: context.channel, task: task,
            recorder: recorder,
            parentProtocol: parentMeta.parentId,
            childNodes: winner.children,
            metadata: parentMeta
        )

        // Chain on buildPipeline future — forward data only after pipeline is ready
        winner.plugin.buildPipeline(context: protoCtx).whenComplete { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                // Pipeline ready — forward buffered data
                if let buf = self.pendingBuffer {
                    context.fireChannelRead(NIOAny(buf))
                }
                context.pipeline.removeHandler(self, promise: nil)
            case .failure(let error):
                // buildPipeline failed — log, record error, close
                AxLogger.log("Plugin \(winner.plugin.id) pipeline failed: \(error)", level: .Error)
                self.recorder.recordError("Plugin \(winner.plugin.id) failed: \(error)")
                context.close(promise: nil)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        // Connection closed before detection completed — clean up
        if !detected {
            recorder.recordClosed()
        }
        context.fireChannelInactive()
    }
}
```

### Key behaviors

| Scenario | Behavior |
|----------|----------|
| Clear match found | `buildPipeline()` → chain on future → forward data → remove self |
| `needMoreData` returned | Buffer bytes, wait for next `channelRead`. Max 4KB before Raw fallback. |
| No match | Fallback to `RawPlugin` — records connection attempt, keeps channel open |
| `buildPipeline` fails | Log error, record via `SessionRecorder`, close channel |
| Confidence tie | First plugin in `buildDefault()` array order wins |
| Connection closes mid-detection | `channelInactive` calls `recorder.recordClosed()` for cleanup |
| Proxy disabled (localEnable/wifiEnable) | Close channel immediately, before any detection |

### Thread safety note

The dispatcher stores mutable state (`pendingBuffer`, `detected`). The `whenComplete` closure from `buildPipeline()` must execute on the channel's `EventLoop`. NIO handlers are inherently single-threaded per channel, but plugins that offload work (e.g., TLS to a different thread) must ensure the returned future completes on `context.eventLoop`. The dispatcher should assert this: `context.eventLoop.assertInEventLoop()` at the start of the `whenComplete` callback, or use `future.hop(to: context.eventLoop)` to guarantee it.

---

## Section 7: SessionRecorder Migration

The current `SessionRecorder` is HTTP-centric — it has `recordRequestHead(HTTPRequestHead)`, `recordResponseHead(HTTPResponseHead)`, and hardcodes `HTTPRecorder` as a private field. To serve as a protocol-agnostic framework component, it needs targeted changes:

### What stays (framework responsibilities)
- flowId generation, PayloadWriter management, TcpConnectionRecord lifecycle
- `recordClosed()` → calls `protocolRecorder.buildFlowRecord()` → `FlowDAO.insert()` (already exists)
- `recordError(_ message: String)` → records error state (already exists)
- Connection timing: `recordConnected()`, `recordHandshakeComplete()`
- Traffic counters: `addUpload()`, `addDownload()`
- Metadata accumulation: `mergeMetadata()` (for TLS info from unwrap plugins)

### What changes
- Remove hardcoded `HTTPRecorder` creation from `init` — instead, expose `setProtocolRecorder(_ recorder: ProtocolRecorder)` so plugins set it
- Generalize `recordRequestHead(HTTPRequestHead)` → keep as a convenience but also add `recordProtocolEvent(_ event: String, metadata: [String: Any])` for non-HTTP plugins
- Keep HTTP-specific convenience methods but mark them as extensions, not core API
- The `session: ProxySession` property stays for now (handlers still read it) — fully removing it is a separate follow-up

### What does NOT change
- `ProtocolRecorder` protocol interface — `buildFlowRecord()`, `searchKeyMapping` — stays intact for FlowDAO compatibility
- `FlowDAO` query layer — no changes needed

---

## Migration Plan (High-Level)

### Phase 1: Clean up legacy code
- Delete `Detector/` directory (ProtocolDetector, all Matchers)
- Delete `Handler/` directory (HTTPHandler, HTTPSHandler, SSLHandler, etc.)
- Verify no remaining references in active code paths

### Phase 2: Build framework
- Create `Framework/` with ProtocolPlugin protocol, ProtocolNode, ProtocolRegistry, ProtocolDispatcher
- Move SessionRecorder to Framework/, generalize it (see Section 7)

### Phase 3: Migrate existing handlers to plugins
- Create plugin folders under `Plugins/`
- Move existing handlers into their protocol folders
- Wrap each in a `*Plugin.swift` implementing `ProtocolPlugin`
- Move recorders from `Storage/Protocol/` to plugin folders
- Priority order: HTTP1 → TLS → SOCKS5 → HTTP2/gRPC → WebSocket → DNS → Raw
- Codec/ decoders (MQTT, Redis, SMTP, etc.) are **deferred** — they stay in `Plugins/Codec/` as plain decoders. They become full plugins in a follow-up when needed (the tree in `buildDefault()` lists them as placeholders with stub `canMatch` implementations).

### Phase 4: Wire up
- Replace `ProtocolRouter` usage in `MitmService` with `ProtocolDispatcher` + `ProtocolRegistry.buildDefault()`
- Verify all protocol paths work end-to-end

### Phase 5: Clean up
- Remove old `ProtocolRouter`
- Remove empty directories
- Update Package.swift if needed
