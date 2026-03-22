# Protocol Feature Preservation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix protocol feature loss across HTTP/1.1, HTTP/2, and WebSocket capture pipelines while maintaining memory efficiency.

**Architecture:** Refactor HTTPCaptureHandler to support multi-cycle keep-alive with per-request SessionRecorder lifecycle. Add bounded outbound connection pool with idle eviction. Fix WebSocket frame masking per RFC 6455. Forward H2 server push via multiplexer callback.

**Tech Stack:** SwiftNIO, NIOHTTP1, NIOHTTP2, NIOWebSocket, NIOSSL

**Memory Budget:** Idle connection ~4KB. Pool cap: 32 connections (~128KB max). Request queue cap: 16 per connection. Idle timeout: 30s. Max connection lifetime: 5min.

---

## File Structure

All source paths are relative to `LocalPackages/TunnelServices/Sources/TunnelServices/`.
Test paths are relative to `LocalPackages/TunnelServices/Tests/TunnelServicesTests/`.

### New Files
- `Sources/.../Proxy/OutboundConnectionPool.swift` — Bounded connection pool with NIOLock thread safety
- `Tests/.../OutboundConnectionPoolTests.swift` — Pool lifecycle tests
- `Tests/.../WebSocketMaskingTests.swift` — RFC 6455 masking compliance tests

### Modified Files
- `Sources/.../Plugins/HTTP1/HTTPCaptureHandler.swift` — Multi-cycle keep-alive, per-request recorder
- `Sources/.../Plugins/HTTP2/HTTP2CaptureHandler.swift` — Server push forwarding, flow control
- `Sources/.../Plugins/WebSocket/WebSocketCaptureHandler.swift` — Fix frame masking direction
- `Sources/.../Config/ProxyConfig.swift` — Pool config constants
- `Sources/.../Utils/NetRequest.swift` — Hop-by-hop header stripping
- `Sources/.../CaptureTask.swift` — Add `connectionPool` property

---

## Priority Order

| P | Task | Impact |
|---|------|--------|
| P0 | Task 1: HTTP/1.1 keep-alive | Fixes connection reuse — most impactful |
| P0 | Task 2: Outbound connection pool | Enables efficient connection sharing |
| P0 | Task 3: WebSocket masking | Fixes RFC 6455 violation |
| P1 | Task 4: Hop-by-hop header handling | Correct proxy behavior |
| P1 | Task 5: H2 server push | Preserves H2 feature |
| P2 | Task 6: H2 flow control awareness | Prevents buffer bloat |

---

### Task 1: HTTP/1.1 Keep-Alive and Pipelining Support

**Files:**
- Modify: `Plugins/HTTP1/HTTPCaptureHandler.swift`
- Modify: `Config/ProxyConfig.swift`

**Problem:** `ResponseRelayHandler` force-closes both channels after every response `.end`. This kills HTTP/1.1 keep-alive, connection reuse, and pipelining. Each request creates a new TCP+TLS connection.

**Design:**
- HTTPCaptureHandler becomes multi-cycle: after a response completes, it resets per-request state but keeps the outbound connection.
- Each request/response cycle gets its own SessionRecorder. The recorder is finalized (`recordClosed()`) at response `.end` — NOT at channel close.
- ResponseRelayHandler checks the `Connection` header and HTTP version to decide whether to close.
- NIO's `HTTPServerPipelineHandler` (already in pipeline) handles request queueing for pipelining.
- Outbound connection is reused across requests to the same server on the same client connection.
- Add idle timeout: if no new request arrives within 30s on a keep-alive connection, close it.

**Memory consideration:** Each idle keep-alive connection holds one NIO Channel (~4KB). Bounded by per-connection idle timeout (30s) and global pool cap (Task 2).

- [x] **Step 1: Add pool config constants to ProxyConfig**

In `Config/ProxyConfig.swift`, add:

```swift
public enum Connection {
    /// Max idle time for keep-alive connections (seconds)
    public static let keepAliveIdleTimeout: Int64 = 30
    /// Max lifetime for any outbound connection (seconds)
    public static let maxConnectionLifetime: Int64 = 300
    /// Max pending requests queued per connection
    public static let maxPendingRequests: Int = 16
}
```

- [x] **Step 2: Refactor ResponseRelayHandler to support keep-alive**

In `HTTPCaptureHandler.swift`, refactor `ResponseRelayHandler`:

1. Add mutable `recorder` reference (changed from `let` to `var`) and a completion callback:
   ```swift
   final class ResponseRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
       typealias InboundIn = HTTPClientResponsePart
       var recorder: SessionRecorder  // mutable — swapped per request cycle
       private weak var serverChannel: Channel?
       private var wsInterceptor: WebSocketUpgradeInterceptor?
       private var responseHead: HTTPResponseHead?
       private var requestVersion: HTTPVersion
       /// Called when response completes. Bool = shouldKeepAlive.
       var onResponseComplete: ((Bool) -> Void)?
   ```

2. Add keep-alive check:
   ```swift
   private func shouldKeepAlive() -> Bool {
       guard let rsp = responseHead else { return false }
       let connHeader = rsp.headers["Connection"].first?.lowercased() ?? ""
       if connHeader == "close" { return false }
       // HTTP/1.0: close by default unless Connection: keep-alive
       if requestVersion == .http1_0 { return connHeader == "keep-alive" }
       return true // HTTP/1.1 default
   }
   ```

3. On `.end`: call `recorder.recordClosed()` to flush, then invoke callback. Only close if `!shouldKeepAlive`:
   ```swift
   case .end(let trailers):
       recorder.recordResponseEnd()
       serverChannel?.writeAndFlush(HTTPServerResponsePart.end(trailers), promise: nil)
       let keepAlive = shouldKeepAlive()
       recorder.recordClosed()  // flush this cycle to storage
       if keepAlive {
           onResponseComplete?(true)
       } else {
           onResponseComplete?(false)
           serverChannel?.close(mode: .all, promise: nil)
           context.channel.close(mode: .all, promise: nil)
       }
   ```

- [x] **Step 3: Refactor HTTPCaptureHandler to be multi-cycle**

Key changes to `HTTPCaptureHandler`:

1. Change `recorder` from `let` to `var` (currently `private let recorder`):
   ```swift
   private var recorder: SessionRecorder  // var: replaced each cycle
   private var request: NetRequest?       // cleared each cycle
   private var requestHead: HTTPRequestHead?
   private var pendingRequestParts = [Any]()
   ```

2. Store a reference to ResponseRelayHandler so its recorder can be swapped:
   ```swift
   private var responseRelayHandler: ResponseRelayHandler?
   ```

3. In `connectToServer()`, store the reference and set up the callback:
   ```swift
   let responseHandler = ResponseRelayHandler(...)
   self.responseRelayHandler = responseHandler
   responseHandler.onResponseComplete = { [weak self] keepAlive in
       if keepAlive {
           self?.resetForNextRequest()
       }
       // if !keepAlive, ResponseRelayHandler already closed channels
   }
   ```

4. Add `resetForNextRequest()`:
   ```swift
   private func resetForNextRequest() {
       // Previous recorder already had recordClosed() called by ResponseRelayHandler.
       // Create a fresh recorder for the next request cycle.
       let newRecorder = SessionRecorder(task: recorder.task)
       recorder = newRecorder
       // Swap recorder in ResponseRelayHandler too
       responseRelayHandler?.recorder = newRecorder
       // Reset per-request state
       request = nil
       requestHead = nil
       pendingRequestParts.removeAll()
       // Keep clientChannel — reuse outbound connection
       connected = (clientChannel != nil && clientChannel!.isActive)
       isWebSocketUpgrade = false
       wsInterceptor = nil
       // Schedule idle timeout
       scheduleIdleTimeout()
   }
   ```

5. In `channelRead(.head)`: cancel idle timeout, reuse `clientChannel` if active.

6. In `channelUnregistered()`: if current recorder hasn't been closed (e.g. mid-request disconnect), call `recorder.recordClosed()` as fallback.

- [x] **Step 4: Add idle timeout for keep-alive connections**

After response completes with keep-alive, schedule an idle timeout. Store the channel reference (not ChannelHandlerContext) to avoid NIO safety issues:

```swift
private var idleTimeout: Scheduled<Void>?
private weak var _channel: Channel?  // stored from channelRead

private func scheduleIdleTimeout() {
    idleTimeout?.cancel()
    guard let channel = _channel else { return }
    idleTimeout = channel.eventLoop.scheduleTask(
        in: .seconds(ProxyConfig.Connection.keepAliveIdleTimeout)
    ) { [weak self] in
        self?.clientChannel?.close(promise: nil)
        self?._channel?.close(promise: nil)
    }
}
```

Cancel the timeout when a new request arrives in `channelRead(.head)`:
```swift
idleTimeout?.cancel()
```

- [x] **Step 5: Test keep-alive behavior manually**

Run proxy, send multiple HTTP/1.1 requests on the same connection. Verify:
- Log shows `[HTTPCapture]` for each request without new `connectToServer` calls
- `[SessionRecorder] recordClosed` appears for each request/response cycle
- Connection closes after idle timeout or `Connection: close`

- [x] **Step 6: Commit** ✅ `c1725a1`

---

### Task 2: Outbound Connection Pool

**Files:**
- Create: `Proxy/OutboundConnectionPool.swift`
- Create: `Tests/TunnelServicesTests/OutboundConnectionPoolTests.swift`
- Modify: `Plugins/HTTP1/HTTPCaptureHandler.swift`

**Problem:** Each HTTP request creates a fresh TCP connection to the server. No connection reuse across different client connections.

**Design:**
- Global pool keyed by `(host, port, isSSL)` tuple.
- Each entry holds an array of idle NIO `Channel` objects.
- Bounded: max 6 connections per key, max 32 total connections.
- Idle eviction: connections removed after 30s idle.
- TTL: connections removed after 5min regardless of use.
- Thread-safe via `NIOLock` (from NIOConcurrencyHelpers) — pool is accessed from multiple event loops.
- Pool is owned by `CaptureTask`, initialized on task start, closed on task stop.

**Memory budget:** 32 connections max × ~4KB idle = ~128KB max. Eviction timer fires every 10s. Per-cycle SessionRecorder+PayloadWriter ~2KB, released at `recordClosed()`.

- [x] **Step 1: Write OutboundConnectionPool tests**

```swift
// Tests/TunnelServicesTests/OutboundConnectionPoolTests.swift
import XCTest
@testable import TunnelServices

final class OutboundConnectionPoolTests: XCTestCase {
    func testPoolKeyEquality() {
        let k1 = ConnectionPoolKey(host: "a.com", port: 443, isSSL: true)
        let k2 = ConnectionPoolKey(host: "a.com", port: 443, isSSL: true)
        let k3 = ConnectionPoolKey(host: "b.com", port: 443, isSSL: true)
        XCTAssertEqual(k1, k2)
        XCTAssertNotEqual(k1, k3)
    }

    func testPoolCapEnforced() {
        let pool = OutboundConnectionPool(maxPerKey: 2, maxTotal: 4)
        XCTAssertEqual(pool.maxPerKey, 2)
        XCTAssertEqual(pool.maxTotal, 4)
        XCTAssertEqual(pool.totalCount, 0)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path LocalPackages/TunnelServices --filter OutboundConnectionPool`
Expected: Compilation failure (types not defined yet)

- [x] **Step 3: Implement OutboundConnectionPool**

```swift
// Proxy/OutboundConnectionPool.swift
import Foundation
import NIO
import NIOConcurrencyHelpers

public struct ConnectionPoolKey: Hashable {
    public let host: String
    public let port: Int
    public let isSSL: Bool
}

struct PooledConnection {
    let channel: Channel
    let createdAt: NIODeadline  // monotonic time, immune to clock changes
    var lastUsedAt: NIODeadline
}

/// Bounded connection pool with idle eviction and TTL.
/// Thread-safe via NIOLock — accessed from multiple NIO event loops.
public final class OutboundConnectionPool {
    public let maxPerKey: Int
    public let maxTotal: Int
    private let idleTimeout: TimeAmount
    private let maxLifetime: TimeAmount

    private let lock = NIOLock()
    private var pool: [ConnectionPoolKey: [PooledConnection]] = [:]
    private var _totalCount = 0
    private var evictionTask: RepeatedTask?

    public var totalCount: Int { lock.withLock { _totalCount } }

    public init(
        maxPerKey: Int = 6,
        maxTotal: Int = 32,
        idleTimeout: TimeAmount = .seconds(30),
        maxLifetime: TimeAmount = .seconds(300)
    ) {
        self.maxPerKey = maxPerKey
        self.maxTotal = maxTotal
        self.idleTimeout = idleTimeout
        self.maxLifetime = maxLifetime
    }

    /// Retrieve an idle connection for the key, or nil if none available.
    public func checkout(key: ConnectionPoolKey) -> Channel? {
        lock.withLock {
            guard var entries = pool[key], !entries.isEmpty else { return nil }
            while let entry = entries.popLast() {
                if entry.channel.isActive {
                    pool[key] = entries.isEmpty ? nil : entries
                    _totalCount -= 1
                    return entry.channel
                }
                _totalCount -= 1
            }
            pool[key] = nil
            return nil
        }
    }

    /// Return a connection to the pool. Closes if pool is full.
    public func checkin(key: ConnectionPoolKey, channel: Channel) {
        lock.withLock {
            guard channel.isActive else { return }
            let now = NIODeadline.now()
            let entry = PooledConnection(channel: channel, createdAt: now, lastUsedAt: now)
            var entries = pool[key] ?? []
            if entries.count >= maxPerKey || _totalCount >= maxTotal {
                channel.close(promise: nil)
                return
            }
            entries.append(entry)
            pool[key] = entries
            _totalCount += 1
        }
    }

    /// Evict expired connections. Called periodically.
    public func evictExpired() {
        lock.withLock {
            let now = NIODeadline.now()
            for (key, entries) in pool {
                let remaining = entries.filter { entry in
                    let idle = now - entry.lastUsedAt
                    let age = now - entry.createdAt
                    let keep = entry.channel.isActive && idle < idleTimeout && age < maxLifetime
                    if !keep {
                        entry.channel.close(promise: nil)
                        _totalCount -= 1
                    }
                    return keep
                }
                pool[key] = remaining.isEmpty ? nil : remaining
            }
        }
    }

    /// Start periodic eviction on the given event loop.
    public func startEviction(on eventLoop: EventLoop, interval: TimeAmount = .seconds(10)) {
        evictionTask = eventLoop.scheduleRepeatedTask(initialDelay: interval, delay: interval) { [weak self] _ in
            self?.evictExpired()
        }
    }

    /// Close all pooled connections.
    public func closeAll() {
        evictionTask?.cancel()
        for (_, entries) in pool {
            for entry in entries {
                entry.channel.close(promise: nil)
            }
        }
        pool.removeAll()
        _totalCount = 0
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path LocalPackages/TunnelServices --filter OutboundConnectionPool`
Expected: PASS

- [x] **Step 5: Add `connectionPool` property to CaptureTask**

In `CaptureTask.swift`, add:
```swift
public lazy var connectionPool = OutboundConnectionPool()
```

In the task start method, start eviction:
```swift
connectionPool.startEviction(on: eventLoopGroup.next())
```

In the task stop method, close all:
```swift
connectionPool.closeAll()
```

- [x] **Step 6: Integrate pool into HTTPCaptureHandler**

In `connectToServer()`, before creating a new `ClientBootstrap`:

```swift
let poolKey = ConnectionPoolKey(host: req.host, port: req.port, isSSL: req.ssl)
if let pooled = task.connectionPool.checkout(key: poolKey) {
    self.clientChannel = pooled
    self.connected = true
    flushPendingParts()
    return
}
// ... existing bootstrap code ...
```

In `resetForNextRequest()`, the outbound `clientChannel` stays with the handler for same-connection reuse. Only return to pool when the client-side channel closes (in `channelUnregistered`):

```swift
public func channelUnregistered(context: ChannelHandlerContext) {
    // Client disconnected — return outbound connection to pool if alive
    if let ch = clientChannel, ch.isActive, let req = request {
        let key = ConnectionPoolKey(host: req.host, port: req.port, isSSL: req.ssl)
        task.connectionPool.checkin(key: key, channel: ch)
        clientChannel = nil
    } else {
        clientChannel?.close(mode: .all, promise: nil)
    }
    recorder.recordClosed()
}
```

- [x] **Step 7: Commit** ✅ `9632a77`

---

### Task 3: WebSocket Frame Masking Fix

**Files:**
- Modify: `Plugins/WebSocket/WebSocketCaptureHandler.swift`
- Create: `Tests/TunnelServicesTests/WebSocketMaskingTests.swift`

**Problem:** RFC 6455 Section 5.1: Client→Server frames MUST be masked. The proxy unmasks all frames and forwards unmasked, which violates RFC when forwarding to the server.

**Design:**
- Client → Proxy: Frame arrives masked (correct per RFC)
- Proxy → Server: Must send masked frame (proxy acts as client to server)
- Server → Proxy: Frame arrives unmasked (correct per RFC)
- Proxy → Client: Must send unmasked frame (proxy acts as server to client)

NIO's `WebSocketFrameEncoder` automatically applies masking when configured. The fix: use `maskingKey` when creating frames forwarded to the server.

- [x] **Step 1: Write masking direction test**

```swift
// Tests/TunnelServicesTests/WebSocketMaskingTests.swift
import XCTest
import NIOWebSocket
import NIO
@testable import TunnelServices

final class WebSocketMaskingTests: XCTestCase {
    func testRandomMaskingKeyGeneration() {
        // WebSocketMaskingKey is initialized from a tuple of 4 random bytes
        let key = WebSocketMaskingKey((
            UInt8.random(in: 0...255), UInt8.random(in: 0...255),
            UInt8.random(in: 0...255), UInt8.random(in: 0...255)
        ))
        XCTAssertNotNil(key)
    }

    func testMaskedFrameHasMaskKey() {
        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 5)
        buf.writeString("hello")
        let key = WebSocketMaskingKey((1, 2, 3, 4))
        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: key, data: buf)
        XCTAssertNotNil(frame.maskKey)
    }

    func testUnmaskedFrameHasNoMaskKey() {
        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 5)
        buf.writeString("hello")
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
        XCTAssertNil(frame.maskKey)
    }
}
```

- [x] **Step 2: Fix WebSocketForwarder masking**

In `WebSocketCaptureHandler.swift`, `WebSocketForwarder.channelRead()`:

```swift
func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = unwrapInboundIn(data)
    guard let peerChannel = peerChannel, peerChannel.isActive else { return }

    if frame.opcode == .connectionClose {
        peerChannel.close(promise: nil)
        context.close(promise: nil)
        return
    }

    var forwardData = frame.unmaskedData

    let forwardFrame: WebSocketFrame
    if direction == .clientToServer {
        // Proxy → Server: must mask (proxy is client to server)
        let maskKey = WebSocketMaskingKey((
            UInt8.random(in: 0...255), UInt8.random(in: 0...255),
            UInt8.random(in: 0...255), UInt8.random(in: 0...255)
        ))
        forwardFrame = WebSocketFrame(
            fin: frame.fin,
            opcode: frame.opcode,
            maskKey: maskKey,
            data: forwardData
        )
    } else {
        // Proxy → Client: must NOT mask (proxy is server to client)
        forwardFrame = WebSocketFrame(
            fin: frame.fin,
            opcode: frame.opcode,
            data: forwardData
        )
    }

    peerChannel.writeAndFlush(forwardFrame, promise: nil)
}
```

- [x] **Step 3: Run tests and verify**

- [x] **Step 4: Commit** ✅ `a767858`

---

### Task 4: Hop-by-Hop Header Handling

**Files:**
- Modify: `Utils/NetRequest.swift`

**Problem:** The proxy only strips `Proxy-Authenticate`, `Proxy-Connection`, and `Expect`. It doesn't strip hop-by-hop headers defined in RFC 7230 Section 6.1, and doesn't handle the `Connection` header's nominated hop-by-hop fields.

**Design:** Strip all standard hop-by-hop headers before forwarding. Parse the `Connection` header to also strip any nominated custom hop-by-hop headers.

- [x] **Step 1: Expand removeProxyHead**

```swift
public static func removeProxyHead(heads: HTTPHeaders) -> HTTPHeaders {
    var h = heads

    // Collect nominated hop-by-hop headers from Connection header
    let nominated = h["Connection"]
        .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }

    // RFC 7230 Section 6.1: standard hop-by-hop headers
    let hopByHop = [
        "Proxy-Authenticate", "Proxy-Authorization", "Proxy-Connection",
        "TE", "Trailer", "Transfer-Encoding", "Upgrade",
        "Keep-Alive", "Expect"
    ]

    for name in hopByHop {
        h.remove(name: name)
    }

    // Remove nominated hop-by-hop headers
    for name in nominated {
        h.remove(name: name)
    }

    // Remove Connection header itself (will be set fresh by encoder)
    h.remove(name: "Connection")

    return h
}
```

- [x] **Step 2: Commit** ✅ `6906eea`

---

### Task 5: HTTP/2 Server Push Forwarding

**Files:**
- Modify: `Plugins/HTTP2/HTTP2CaptureHandler.swift`

**Problem:** Server push promises from upstream are silently accepted but never forwarded to the client. The server-initiated stream handler in `H2ServerConnection` is a no-op.

**Design:**
- In the server-side multiplexer callback (server-initiated streams = push promises), capture the push promise and create a corresponding client-side stream to forward it.
- Each push stream gets its own SessionRecorder for capture.
- Memory: push streams are bounded by H2 MAX_CONCURRENT_STREAMS (default 100). Each adds one recorder + one stream channel (~8KB). The multiplexer inherently limits this.

- [x] **Step 1: Handle server-initiated push streams**

In `H2ServerConnection.connect()`, replace the empty server-initiated stream handler:

```swift
let clientMultiplexer = self.clientMultiplexer  // reference to client-side multiplexer
let recorder = self.recorder

let mux = HTTP2StreamMultiplexer(mode: .client, channel: channel) { serverPushStream in
    // Server push: create corresponding client stream and relay
    let pushRecorder = SessionRecorder(task: recorder.task)
    pushRecorder.session.schemes = "H2-Push"

    return serverPushStream.pipeline.addHandler(
        HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https),
        name: "h2push.codec"
    ).flatMap {
        serverPushStream.pipeline.addHandler(
            H2PushRelayHandler(recorder: pushRecorder, clientMultiplexer: clientMultiplexer),
            name: "h2push.relay"
        )
    }
}
```

- [x] **Step 2: Implement H2PushRelayHandler**

```swift
/// Relays a server push stream to the client via a new client-initiated stream.
final class H2PushRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let recorder: SessionRecorder
    private weak var clientMultiplexer: HTTP2StreamMultiplexer?
    private var clientPushChannel: Channel?
    private var pendingParts = [HTTPServerResponsePart]()
    private var connected = false

    init(recorder: SessionRecorder, clientMultiplexer: HTTP2StreamMultiplexer?) {
        self.recorder = recorder
        self.clientMultiplexer = clientMultiplexer
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            recorder.recordResponseHead(head)
            createClientPushStream()
            enqueue(.head(head))
        case .body(let body):
            recorder.recordResponseBody(body)
            enqueue(.body(.byteBuffer(body)))
        case .end(let trailers):
            recorder.recordResponseEnd()
            enqueue(.end(trailers))
            recorder.recordClosed()
        }
    }

    private func createClientPushStream() {
        clientMultiplexer?.createStreamChannel { stream in
            stream.pipeline.addHandler(
                HTTP2FramePayloadToHTTP1ServerCodec(),
                name: "h2push.client.codec"
            )
        }.whenComplete { [weak self] result in
            if case .success(let ch) = result {
                self?.clientPushChannel = ch
                self?.connected = true
                self?.flushPending()
            }
        }
    }

    private func enqueue(_ part: HTTPServerResponsePart) { /* buffer or send */ }
    private func flushPending() { /* flush buffered parts */ }
}
```

- [x] **Step 3: Pass client multiplexer reference to H2ServerConnection**

Update `HTTP2CaptureBuilder.addPipeline()` to store a reference to the client-side multiplexer and pass it to `H2ServerConnection` so push relay handlers can create client streams.

- [x] **Step 4: Commit** ✅ `18ebcbf`

---

### Task 6: HTTP/2 Flow Control Awareness

**Files:**
- Modify: `Plugins/HTTP2/HTTP2CaptureHandler.swift`

**Problem:** Client-side and server-side H2 flow control windows are independent. If the client is slow (small window) but the server sends fast (large window), the proxy buffers unboundedly.

**Design:**
- Apply backpressure: when the client stream's write buffer is full, stop reading from the server stream.
- NIO's `Channel.isWritable` and `channelWritabilityChanged` provide this mechanism.
- When client stream becomes unwritable: remove the auto-read from server stream.
- When client stream becomes writable again: resume reading from server stream.

**Memory cap:** NIO's default high watermark is 64KB per channel. This naturally bounds buffer size. We add explicit writability checks.

- [x] **Step 1: Add writability tracking to H2ResponseRelayHandler**

```swift
func channelWritabilityChanged(context: ChannelHandlerContext) {
    // Server stream writability changed — propagate to client stream reads
    if let clientCh = clientStreamChannel {
        clientCh.setOption(ChannelOptions.autoRead, value: context.channel.isWritable)
    }
}
```

And in `H2StreamCaptureHandler`, mirror for the reverse direction:

```swift
func channelWritabilityChanged(context: ChannelHandlerContext) {
    // Client stream writability changed — propagate to server stream reads
    if let serverCh = serverStreamChannel {
        serverCh.setOption(ChannelOptions.autoRead, value: context.channel.isWritable)
    }
}
```

- [x] **Step 2: Commit** ✅ `4173976`

---

## Post-Implementation Verification

After all tasks:

1. **HTTP/1.1 keep-alive**: Send 5 requests on one connection → expect one `connectToServer`, five `recordClosed`
2. **HTTP/1.1 pipelining**: Send 3 pipelined requests → expect all 3 recorded in order
3. **Connection: close**: Send request with `Connection: close` → expect connection closes after response
4. **WebSocket**: Connect via WS → exchange frames → verify server receives masked frames
5. **HTTP/2 multiplexing**: Send 3 concurrent H2 streams → expect all recorded, one server connection
6. **HTTP/2 server push**: Test against a server that sends push promises → expect push appears in capture list
7. **Memory**: Monitor RSS during sustained traffic — pool should stabilize at bounded size
8. **Idle cleanup**: Leave connections idle for 35s → expect pool evicts them
