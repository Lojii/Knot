# Protocol Plugin Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic ProtocolRouter with a pluggable protocol tree where each protocol is a self-contained plugin with match/handle/record capabilities.

**Architecture:** Build a `ProtocolPlugin` protocol and a `ProtocolDispatcher` (ChannelHandler) that walks a compile-time registered protocol tree. Each plugin folder contains its handler, recorder, and detection logic. The dispatcher replaces ProtocolRouter in the NIO pipeline.

**Tech Stack:** Swift, SwiftNIO, XCTest

**Spec:** `docs/superpowers/specs/2026-03-20-protocol-plugin-architecture-design.md`

---

## File Structure

### New files to create

```
Sources/TunnelServices/
├── Framework/
│   ├── ProtocolPlugin.swift          ← Protocol, MatchResult, MatchContext, ProtocolContext, ProtocolMetadata
│   ├── ProtocolNode.swift            ← ProtocolNode struct
│   ├── ProtocolRegistry.swift        ← Singleton, buildDefault(), tcpChildren
│   ├── ProtocolDispatcher.swift      ← ChannelHandler: match → dispatch → forward
│   └── SessionRecorder.swift         ← MOVED from Proxy/ (add setProtocolRecorder)
│
├── Plugins/
│   ├── HTTP1/
│   │   ├── HTTP1Plugin.swift         ← canMatch + buildPipeline
│   │   ├── HTTPCaptureHandler.swift  ← MOVED from Proxy/
│   │   └── HTTPRecorder.swift        ← MOVED from Storage/Protocol/
│   ├── TLS/
│   │   ├── TLSPlugin.swift           ← canMatch(0x16) + buildPipeline (MITM or tunnel)
│   │   ├── MITMHandler.swift         ← MOVED from Proxy/
│   │   └── TLSSniffHandler.swift     ← MOVED from Proxy/
│   ├── SOCKS5/
│   │   └── SOCKS5Plugin.swift        ← canMatch(0x05) + buildPipeline + re-enter TCP
│   ├── HTTP2/
│   │   ├── HTTP2Plugin.swift         ← canMatch(ALPN "h2") + buildPipeline
│   │   ├── HTTP2CaptureHandler.swift ← MOVED from Proxy/
│   │   └── HTTP2CaptureBuilder.swift ← MOVED from Proxy/ (if exists)
│   ├── GRPC/
│   │   ├── GRPCPlugin.swift          ← canMatch(content-type grpc) + buildPipeline
│   │   ├── GRPCCaptureHandler.swift  ← MOVED from Proxy/
│   │   └── GRPCRecorder.swift        ← MOVED from Storage/Protocol/
│   ├── WebSocket/
│   │   ├── WebSocketPlugin.swift     ← canMatch(Upgrade header) + buildPipeline
│   │   ├── WebSocketCaptureHandler.swift ← MOVED from Proxy/
│   │   └── WebSocketRecorder.swift   ← MOVED from Storage/Protocol/
│   ├── DNS/
│   │   ├── DNSPlugin.swift           ← canMatch(port/header) + buildPipeline
│   │   ├── DNSDecoder.swift          ← MOVED from Codec/
│   │   └── DNSRecorder.swift         ← MOVED from Storage/Protocol/
│   ├── Raw/
│   │   ├── RawPlugin.swift           ← Fallback plugin
│   │   └── RawPassthroughHandler.swift ← MOVED from Proxy/ProtocolRouter.swift (bottom section)
│   └── Codec/                        ← Deferred: non-pluginized decoders stay here
│       ├── MQTTDecoder.swift         ← MOVED from Codec/
│       ├── RedisDecoder.swift        ← MOVED from Codec/
│       └── ... (other decoders)
```

### Files to delete

```
Sources/TunnelServices/Detector/           ← Entire directory (5 files)
Sources/TunnelServices/Handler/            ← Entire directory (8 files)
Sources/TunnelServices/Proxy/ProtocolRouter.swift  ← Replaced by ProtocolDispatcher
```

### Files to modify

```
Sources/TunnelServices/MitmService.swift:71-83          ← Replace ProtocolRouter with ProtocolDispatcher
Sources/TunnelServices/Proxy/ProxyServer.swift:74-78    ← Replace ProtocolRouter with ProtocolDispatcher
Sources/TunnelServices/Proxy/ConnectHandler.swift       ← Use ProtocolRegistry.shared.tcpChildren for re-entry
Sources/TunnelServices/Proxy/SOCKSProxyHandler.swift    ← Move into SOCKS5Plugin wrapper
Storage/Protocol/ProtocolRecorder.swift                 ← Stays in place (interface only)
```

### Tests to create

```
Tests/TunnelServicesTests/
├── ProtocolPluginTests.swift         ← MatchResult, MatchContext
├── ProtocolDispatcherTests.swift     ← Matching logic, needMoreData, fallback
├── ProtocolRegistryTests.swift       ← Tree structure, tcpChildren accessor
├── HTTP1PluginTests.swift            ← HTTP method matching
├── TLSPluginTests.swift              ← ClientHello detection
├── SOCKS5PluginTests.swift           ← 0x05 greeting detection
└── RawPluginTests.swift              ← Fallback behavior
```

---

## Tasks

### Task 1: Delete legacy Detector/ and Handler/ directories

These directories contain the old ProtocolDetector → HTTPHandler pipeline that has been fully replaced by ProtocolRouter → HTTPCaptureHandler. The grep confirms no active code references them outside their own files.

**Files:**
- Delete: `Sources/TunnelServices/Detector/ProtocolDetector.swift`
- Delete: `Sources/TunnelServices/Detector/ProtocolMatcher.swift`
- Delete: `Sources/TunnelServices/Detector/HttpMatcher.swift`
- Delete: `Sources/TunnelServices/Detector/HttpsMatcher.swift`
- Delete: `Sources/TunnelServices/Detector/SSLMatcher.swift`
- Delete: `Sources/TunnelServices/Handler/HTTPHandler.swift`
- Delete: `Sources/TunnelServices/Handler/HTTPSHandler.swift`
- Delete: `Sources/TunnelServices/Handler/SSLHandler.swift`
- Delete: `Sources/TunnelServices/Handler/ExchangeHandler.swift`
- Delete: `Sources/TunnelServices/Handler/TunnelProxyHandler.swift`
- Delete: `Sources/TunnelServices/Handler/ChannelWatchHandler.swift`
- Delete: `Sources/TunnelServices/Handler/ChannelActiveAwareHandler.swift`
- Delete: `Sources/TunnelServices/Handler/CloseTimeoutChannelHandler.swift`

- [ ] **Step 1: Verify no active references**

Run:
```bash
cd /Users/aa123/Documents/Knot-storage-redesign
# Search for references outside Detector/ and Handler/ directories
grep -r "ProtocolDetector\|HttpMatcher\|HttpsMatcher\|SSLMatcher\|ProtocolMatcher" \
  --include="*.swift" \
  LocalPackages/TunnelServices/Sources/TunnelServices/ \
  | grep -v "Detector/" | grep -v "Handler/"

grep -r "HTTPHandler\b\|HTTPSHandler\b\|SSLHandler\b\|ExchangeHandler\|TunnelProxyHandler\|ChannelWatchHandler\|ChannelActiveAware\|CloseTimeout" \
  --include="*.swift" \
  LocalPackages/TunnelServices/Sources/TunnelServices/ \
  | grep -v "Detector/" | grep -v "Handler/"
```
Expected: Only the comment in `Proxy/HTTPCaptureHandler.swift:6` referencing the old names. No actual usage.

- [ ] **Step 2: Delete Detector/ directory**

```bash
rm -rf LocalPackages/TunnelServices/Sources/TunnelServices/Detector/
```

- [ ] **Step 3: Delete Handler/ directory**

```bash
rm -rf LocalPackages/TunnelServices/Sources/TunnelServices/Handler/
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/aa123/Documents/Knot-storage-redesign
xcodebuild -scheme TunnelServices -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run existing tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: delete legacy Detector/ and Handler/ directories (13 files)

These were replaced by ProtocolRouter + HTTPCaptureHandler pipeline.
No active code references them."
```

---

### Task 2: Create Framework — ProtocolPlugin protocol and types

**Files:**
- Create: `Sources/TunnelServices/Framework/ProtocolPlugin.swift`
- Test: `Tests/TunnelServicesTests/ProtocolPluginTests.swift`

- [ ] **Step 1: Create Framework directory**

```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Framework
```

- [ ] **Step 2: Write ProtocolPlugin.swift**

```swift
//
//  ProtocolPlugin.swift
//  TunnelServices
//
//  Core protocol plugin interface and supporting types.
//

import Foundation
import NIO
import NIOHTTP1

// MARK: - Match Result

/// Result of protocol detection on incoming bytes.
public enum MatchResult: Equatable {
    /// Protocol matched with given confidence. Higher confidence wins.
    case yes(confidence: Int)
    /// Not this protocol.
    case no
    /// Need more data to decide. Dispatcher will buffer and retry.
    case needMoreData(minimum: Int)

    public static func == (lhs: MatchResult, rhs: MatchResult) -> Bool {
        switch (lhs, rhs) {
        case (.yes(let a), .yes(let b)): return a == b
        case (.no, .no): return true
        case (.needMoreData(let a), .needMoreData(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Protocol Metadata

/// Typed metadata passed from parent plugin to child plugins.
public struct ProtocolMetadata {
    public var parentId: String?
    public var alpnResult: String?
    public var sni: String?
    public var innerHost: String?
    public var innerPort: Int?
    public var isEncrypted: Bool = false
    public var extra: [String: Any] = [:]

    public static let empty = ProtocolMetadata()

    public init() {}
}

// MARK: - Match Context

/// Read-only context available during protocol matching.
public struct MatchContext {
    public let localPort: Int
    public let remoteAddress: SocketAddress?
    public let parentProtocol: String?
    public let metadata: ProtocolMetadata

    public init(localPort: Int, remoteAddress: SocketAddress?,
                parentProtocol: String?, metadata: ProtocolMetadata) {
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.parentProtocol = parentProtocol
        self.metadata = metadata
    }
}

// MARK: - Protocol Context

/// Context available during pipeline construction.
public struct ProtocolContext {
    public let channel: Channel
    public let task: CaptureTask
    public let recorder: SessionRecorder
    public let parentProtocol: String?
    public let childNodes: [ProtocolNode]
    public let metadata: ProtocolMetadata
    public let initialBuffer: ByteBuffer?  // First bytes that triggered detection

    public init(channel: Channel, task: CaptureTask, recorder: SessionRecorder,
                parentProtocol: String?, childNodes: [ProtocolNode],
                metadata: ProtocolMetadata, initialBuffer: ByteBuffer? = nil) {
        self.channel = channel
        self.task = task
        self.recorder = recorder
        self.parentProtocol = parentProtocol
        self.childNodes = childNodes
        self.metadata = metadata
        self.initialBuffer = initialBuffer
    }
}

// MARK: - Protocol Plugin

/// Core interface for protocol plugins. Every protocol implements this.
public protocol ProtocolPlugin: AnyObject {
    /// Unique identifier, e.g. "http1", "tls", "socks5"
    var id: String { get }

    /// Human-readable name, e.g. "HTTP/1.x", "TLS", "SOCKS5"
    var displayName: String { get }

    /// Inspect leading bytes to determine if this protocol matches.
    /// Must be stateless — no side effects.
    func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult

    /// After a match, configure the NIO pipeline for this protocol.
    /// Sync plugins return a succeeded future. Async plugins (TLS) return
    /// a future that completes after handshake.
    func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void>

    /// Create a protocol-specific recorder. Leaf plugins return a recorder;
    /// unwrap plugins (TLS, SOCKS5) return nil.
    func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder?
}
```

- [ ] **Step 3: Write ProtocolPluginTests.swift**

```swift
//
//  ProtocolPluginTests.swift
//  TunnelServicesTests
//

import XCTest
import NIO
@testable import TunnelServices

final class ProtocolPluginTests: XCTestCase {

    func testMatchResultEquality() {
        XCTAssertEqual(MatchResult.yes(confidence: 90), MatchResult.yes(confidence: 90))
        XCTAssertNotEqual(MatchResult.yes(confidence: 90), MatchResult.yes(confidence: 80))
        XCTAssertEqual(MatchResult.no, MatchResult.no)
        XCTAssertEqual(MatchResult.needMoreData(minimum: 4), MatchResult.needMoreData(minimum: 4))
        XCTAssertNotEqual(MatchResult.no, MatchResult.yes(confidence: 0))
    }

    func testProtocolMetadataEmpty() {
        let meta = ProtocolMetadata.empty
        XCTAssertNil(meta.parentId)
        XCTAssertNil(meta.alpnResult)
        XCTAssertNil(meta.sni)
        XCTAssertFalse(meta.isEncrypted)
    }

    func testMatchContextInitialization() {
        var meta = ProtocolMetadata()
        meta.parentId = "tls"
        meta.isEncrypted = true
        let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                               parentProtocol: "tls", metadata: meta)
        XCTAssertEqual(ctx.localPort, 8034)
        XCTAssertEqual(ctx.parentProtocol, "tls")
        XCTAssertTrue(ctx.metadata.isEncrypted)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' \
  -only-testing:TunnelServicesTests/ProtocolPluginTests 2>&1 | tail -10
```
Expected: 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Framework/ProtocolPlugin.swift \
        LocalPackages/TunnelServices/Tests/TunnelServicesTests/ProtocolPluginTests.swift
git commit -m "feat: add ProtocolPlugin protocol and supporting types"
```

---

### Task 3: Create Framework — ProtocolNode and ProtocolRegistry

**Files:**
- Create: `Sources/TunnelServices/Framework/ProtocolNode.swift`
- Create: `Sources/TunnelServices/Framework/ProtocolRegistry.swift`
- Test: `Tests/TunnelServicesTests/ProtocolRegistryTests.swift`

- [ ] **Step 1: Write ProtocolNode.swift**

```swift
//
//  ProtocolNode.swift
//  TunnelServices
//
//  Tree node wrapping a plugin with its children.
//

import Foundation

/// A node in the protocol tree. Each node holds a plugin and its child nodes.
public struct ProtocolNode {
    public let plugin: ProtocolPlugin
    public var children: [ProtocolNode]

    public init(plugin: ProtocolPlugin, children: [ProtocolNode] = []) {
        self.plugin = plugin
        self.children = children
    }
}
```

- [ ] **Step 2: Write ProtocolRegistry.swift**

Start with a minimal registry that has the structure but uses placeholder plugins. Real plugins are wired in Task 5+.

```swift
//
//  ProtocolRegistry.swift
//  TunnelServices
//
//  Compile-time static protocol tree. The single source of truth
//  for which protocols exist and their parent-child relationships.
//

import Foundation

public final class ProtocolRegistry {

    /// Singleton — holds the built tree for SOCKS5/CONNECT re-entry.
    public static let shared = ProtocolRegistry()

    /// The root nodes (TCP, UDP).
    public let roots: [ProtocolNode]

    /// Quick accessor for TCP children — used by SOCKS5/CONNECT re-entry.
    public var tcpChildren: [ProtocolNode] {
        roots.first(where: { $0.plugin.id == "tcp" })?.children ?? []
    }

    private init() {
        self.roots = ProtocolRegistry.buildDefault()
    }

    /// The complete protocol hierarchy.
    /// Add new protocols here — this is the only place to touch.
    static func buildDefault() -> [ProtocolNode] {
        return [
            // TCP root — placeholder, real plugins wired in later tasks
            ProtocolNode(plugin: RootPlugin(id: "tcp", displayName: "TCP")),
            // UDP root
            ProtocolNode(plugin: RootPlugin(id: "udp", displayName: "UDP")),
        ]
    }
}

// MARK: - Root Plugin (placeholder for transport layer roots)

/// Root plugins never match — they just hold children.
final class RootPlugin: ProtocolPlugin {
    let id: String
    let displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult { .no }

    func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        context.channel.eventLoop.makeSucceededVoidFuture()
    }

    func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? { nil }
}
```

- [ ] **Step 3: Write ProtocolRegistryTests.swift**

```swift
//
//  ProtocolRegistryTests.swift
//  TunnelServicesTests
//

import XCTest
@testable import TunnelServices

final class ProtocolRegistryTests: XCTestCase {

    func testSharedSingletonExists() {
        let registry = ProtocolRegistry.shared
        XCTAssertFalse(registry.roots.isEmpty)
    }

    func testHasTCPAndUDPRoots() {
        let ids = ProtocolRegistry.shared.roots.map { $0.plugin.id }
        XCTAssertTrue(ids.contains("tcp"))
        XCTAssertTrue(ids.contains("udp"))
    }

    func testTCPChildrenAccessor() {
        // Initially empty — children are added when real plugins are wired
        let children = ProtocolRegistry.shared.tcpChildren
        // Just verify it doesn't crash
        XCTAssertNotNil(children)
    }

    func testRootPluginNeverMatches() {
        let root = RootPlugin(id: "tcp", displayName: "TCP")
        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 4)
        buf.writeString("GET ")
        let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                               parentProtocol: nil, metadata: .empty)
        XCTAssertEqual(root.canMatch(buf, context: ctx), .no)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' \
  -only-testing:TunnelServicesTests/ProtocolRegistryTests 2>&1 | tail -10
```
Expected: 4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Framework/ProtocolNode.swift \
        LocalPackages/TunnelServices/Sources/TunnelServices/Framework/ProtocolRegistry.swift \
        LocalPackages/TunnelServices/Tests/TunnelServicesTests/ProtocolRegistryTests.swift
git commit -m "feat: add ProtocolNode and ProtocolRegistry with TCP/UDP roots"
```

---

### Task 4: Create Framework — ProtocolDispatcher

**Files:**
- Create: `Sources/TunnelServices/Framework/ProtocolDispatcher.swift`
- Test: `Tests/TunnelServicesTests/ProtocolDispatcherTests.swift`

- [ ] **Step 1: Write ProtocolDispatcher.swift**

```swift
//
//  ProtocolDispatcher.swift
//  TunnelServices
//
//  NIO ChannelHandler that walks the protocol tree.
//  Replaces ProtocolRouter with a generic, recursive dispatch mechanism.
//

import Foundation
import NIO

public final class ProtocolDispatcher: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private let nodes: [ProtocolNode]
    private let task: CaptureTask
    private let recorder: SessionRecorder
    private let parentMeta: ProtocolMetadata
    private let rawFallback: ProtocolNode

    private var pendingBuffer: ByteBuffer?
    private let maxBufferSize: Int = 4096
    private var detected = false

    public init(nodes: [ProtocolNode], task: CaptureTask,
                recorder: SessionRecorder, parentMeta: ProtocolMetadata = .empty) {
        self.nodes = nodes
        self.task = task
        self.recorder = recorder
        self.parentMeta = parentMeta
        self.rawFallback = ProtocolNode(plugin: RawPlugin(), children: [])
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Proxy-enabled check
        if let local = context.channel.localAddress?.description {
            let isLocal = local.contains(ProxyConfig.LocalProxy.host)
            if (isLocal && task.localEnable == 0) || (!isLocal && task.wifiEnable == 0) {
                context.close(promise: nil)
                return
            }
        }

        guard !detected else {
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

        // Try all children
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

        // Wait for more data if needed
        if best == nil && anyNeedMore && accumulated.readableBytes < maxBufferSize {
            return
        }

        // Dispatch
        detected = true
        let winner = best?.node ?? rawFallback

        let protoCtx = ProtocolContext(
            channel: context.channel, task: task,
            recorder: recorder,
            parentProtocol: matchCtx.parentProtocol,
            childNodes: winner.children,
            metadata: parentMeta,
            initialBuffer: accumulated
        )

        // Chain on buildPipeline future
        let future = winner.plugin.buildPipeline(context: protoCtx)
        future.hop(to: context.eventLoop).whenComplete { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                if let buf = self.pendingBuffer {
                    context.fireChannelRead(NIOAny(buf))
                }
                context.pipeline.removeHandler(self, promise: nil)
            case .failure(let error):
                AxLogger.log("Plugin \(winner.plugin.id) pipeline failed: \(error)", level: .Error)
                self.recorder.recordError("Plugin \(winner.plugin.id) failed: \(error)")
                context.close(promise: nil)
            }
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if !detected {
            recorder.recordClosed()
        }
        context.fireChannelInactive()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
```

Note: This references `RawPlugin` which will be created in Task 7. For compilation, create a minimal stub now and replace it later.

- [ ] **Step 2: Create minimal RawPlugin stub for compilation**

Create `Sources/TunnelServices/Plugins/Raw/RawPlugin.swift`:

```swift
//
//  RawPlugin.swift
//  TunnelServices
//
//  Fallback plugin for unrecognized protocols.
//

import Foundation
import NIO

public final class RawPlugin: ProtocolPlugin {
    public let id = "raw"
    public let displayName = "Unknown"

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        .yes(confidence: 0)  // Always matches as last resort
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let recorder = context.recorder
        let firstBytes: Data
        if let buf = context.initialBuffer {
            firstBytes = Data(buffer: buf)
        } else {
            firstBytes = Data()
        }
        let peer = context.channel.remoteAddress?.description
        let local = context.channel.localAddress?.description
        recorder.recordRawConnection(peerAddress: peer, localAddress: local, firstBytes: firstBytes)
        _ = context.channel.pipeline.addHandler(
            RawPassthroughHandler(recorder: recorder), name: "raw.passthrough"
        )
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? { nil }
}
```

- [ ] **Step 3: Create Plugins/Raw directory and move RawPassthroughHandler**

Extract `RawPassthroughHandler` from `Proxy/ProtocolRouter.swift` (lines 217-240) into `Sources/TunnelServices/Plugins/Raw/RawPassthroughHandler.swift`:

```swift
//
//  RawPassthroughHandler.swift
//  TunnelServices
//
//  Keeps connections open for unrecognized protocols.
//  Records byte counts and calls recordClosed() when the connection ends.
//

import Foundation
import NIO

public final class RawPassthroughHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer

    private let recorder: SessionRecorder

    public init(recorder: SessionRecorder) {
        self.recorder = recorder
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        recorder.addUpload(buffer.readableBytes)
    }

    public func channelUnregistered(context: ChannelHandlerContext) {
        recorder.recordClosed()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
```

- [ ] **Step 4: Write ProtocolDispatcherTests.swift**

```swift
//
//  ProtocolDispatcherTests.swift
//  TunnelServicesTests
//

import XCTest
import NIO
@testable import TunnelServices

/// Minimal test plugin for dispatcher tests.
private final class StubPlugin: ProtocolPlugin {
    let id: String
    let displayName: String
    let matchPrefix: String
    let confidence: Int
    var buildPipelineCalled = false

    init(id: String, matchPrefix: String, confidence: Int) {
        self.id = id
        self.displayName = id
        self.matchPrefix = matchPrefix
        self.confidence = confidence
    }

    func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        guard buffer.readableBytes >= matchPrefix.count else {
            return .needMoreData(minimum: matchPrefix.count)
        }
        let prefix = buffer.getString(at: buffer.readerIndex, length: matchPrefix.count) ?? ""
        return prefix == matchPrefix ? .yes(confidence: confidence) : .no
    }

    func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        buildPipelineCalled = true
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? { nil }
}

final class ProtocolDispatcherTests: XCTestCase {

    func testHighestConfidenceWins() {
        let lowPlugin = StubPlugin(id: "low", matchPrefix: "GET ", confidence: 50)
        let highPlugin = StubPlugin(id: "high", matchPrefix: "GET ", confidence: 90)

        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 10)
        buf.writeString("GET /index")

        let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                               parentProtocol: nil, metadata: .empty)

        // Simulate matching
        var best: (plugin: StubPlugin, confidence: Int)?
        for plugin in [lowPlugin, highPlugin] {
            if case .yes(let c) = plugin.canMatch(buf, context: ctx) {
                if best == nil || c > best!.confidence {
                    best = (plugin, c)
                }
            }
        }
        XCTAssertEqual(best?.plugin.id, "high")
    }

    func testArrayOrderBreaksTie() {
        let first = StubPlugin(id: "first", matchPrefix: "XX", confidence: 80)
        let second = StubPlugin(id: "second", matchPrefix: "XX", confidence: 80)

        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 4)
        buf.writeString("XX..")

        let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                               parentProtocol: nil, metadata: .empty)

        // With > (not >=), first match at equal confidence is kept
        var best: (plugin: StubPlugin, confidence: Int)?
        for plugin in [first, second] {
            if case .yes(let c) = plugin.canMatch(buf, context: ctx) {
                if best == nil || c > best!.confidence {
                    best = (plugin, c)
                }
            }
        }
        XCTAssertEqual(best?.plugin.id, "first")
    }

    func testNeedMoreDataWithInsufficientBytes() {
        let plugin = StubPlugin(id: "test", matchPrefix: "CONNECT", confidence: 90)

        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 3)
        buf.writeString("CON")  // Only 3 bytes, plugin needs 7

        let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                               parentProtocol: nil, metadata: .empty)
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .needMoreData(minimum: 7))
    }

    func testNoMatchReturnsNil() {
        let plugin = StubPlugin(id: "http", matchPrefix: "GET ", confidence: 90)

        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x16, 0x03, 0x01, 0x00])  // TLS ClientHello prefix

        let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                               parentProtocol: nil, metadata: .empty)
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .no)
    }
}
```

- [ ] **Step 5: Verify build and run tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' \
  -only-testing:TunnelServicesTests/ProtocolDispatcherTests 2>&1 | tail -10
```
Expected: 4 tests passed.

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Framework/ProtocolDispatcher.swift \
        LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/Raw/RawPlugin.swift \
        LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/Raw/RawPassthroughHandler.swift \
        LocalPackages/TunnelServices/Tests/TunnelServicesTests/ProtocolDispatcherTests.swift
git commit -m "feat: add ProtocolDispatcher with buffering, fallback, and error handling"
```

---

### Task 5: Create HTTP1Plugin and move HTTP1 files

**Files:**
- Create: `Sources/TunnelServices/Plugins/HTTP1/HTTP1Plugin.swift`
- Move: `Proxy/HTTPCaptureHandler.swift` → `Plugins/HTTP1/HTTPCaptureHandler.swift`
- Move: `Storage/Protocol/HTTPRecorder.swift` → `Plugins/HTTP1/HTTPRecorder.swift`
- Test: `Tests/TunnelServicesTests/HTTP1PluginTests.swift`

- [ ] **Step 1: Write HTTP1Plugin.swift**

```swift
//
//  HTTP1Plugin.swift
//  TunnelServices
//
//  HTTP/1.x protocol plugin. Matches HTTP method prefixes (GET, POST, etc.)
//  and HTTP CONNECT for HTTPS tunneling.
//

import Foundation
import NIO
import NIOHTTP1

public final class HTTP1Plugin: ProtocolPlugin {
    public let id = "http1"
    public let displayName = "HTTP/1.x"

    private static let httpMethods = ["GET ", "POST", "PUT ", "HEAD", "OPTI", "PATC", "DELE", "TRAC", "CONN"]

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        guard buffer.readableBytes >= 4 else {
            return .needMoreData(minimum: 4)
        }
        let prefix = buffer.getString(at: buffer.readerIndex, length: 4) ?? ""
        let isHTTP = HTTP1Plugin.httpMethods.contains(where: { prefix.hasPrefix($0.prefix(4)) })
        return isHTTP ? .yes(confidence: 90) : .no
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let recorder = context.recorder
        let pipeline = context.channel.pipeline
        let isSSL = context.metadata.isEncrypted

        // Check if this is a CONNECT request (HTTPS tunneling)
        // We peek at the prefix to decide pipeline shape
        // Full CONNECT handling is inside ConnectHandler
        if context.metadata.parentId == nil || context.metadata.parentId == "socks5" {
            // Top-level HTTP or HTTP after SOCKS5 unwrap
            // Could be plain HTTP or HTTP CONNECT — add full HTTP pipeline
            // ConnectHandler will handle CONNECT specifically
            return pipeline.addHandler(
                ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)),
                name: "http.requestDecoder"
            ).flatMap {
                pipeline.addHandler(HTTPResponseEncoder(), name: "http.responseEncoder")
            }.flatMap {
                pipeline.addHandler(HTTPServerPipelineHandler(), name: "http.pipelining")
            }.flatMap {
                // Add both ConnectHandler (for CONNECT) and CaptureHandler (for plain HTTP)
                // ConnectHandler checks if method is CONNECT, if not it passes through
                pipeline.addHandler(
                    HTTPCaptureHandler(recorder: recorder, isSSL: false),
                    name: "http.capture"
                )
            }
        } else {
            // HTTP under TLS — this is decrypted HTTPS
            return pipeline.addHandler(
                ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)),
                name: "mitm.http.requestDecoder"
            ).flatMap {
                pipeline.addHandler(HTTPResponseEncoder(), name: "mitm.http.responseEncoder")
            }.flatMap {
                pipeline.addHandler(HTTPServerPipelineHandler(), name: "mitm.http.pipelining")
            }.flatMap {
                pipeline.addHandler(
                    HTTPCaptureHandler(recorder: recorder, isSSL: true),
                    name: "mitm.http.capture"
                )
            }
        }
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        let isSSL = context.metadata.isEncrypted
        return HTTPRecorder(
            flowId: flowId,
            host: context.metadata.sni ?? context.metadata.innerHost ?? "",
            port: isSSL ? 443 : 80,
            protocolOverride: isSSL ? "HTTPS" : nil,
            extraMetadata: isSSL ? ["encrypted": false, "decrypted": true] : [:]
        )
    }
}
```

- [ ] **Step 2: Move HTTPCaptureHandler.swift**

```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP1
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/HTTPCaptureHandler.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP1/
```

- [ ] **Step 3: Move HTTPRecorder.swift**

```bash
mv LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/HTTPRecorder.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP1/
```

- [ ] **Step 4: Write HTTP1PluginTests.swift**

```swift
//
//  HTTP1PluginTests.swift
//  TunnelServicesTests
//

import XCTest
import NIO
@testable import TunnelServices

final class HTTP1PluginTests: XCTestCase {
    let plugin = HTTP1Plugin()
    let allocator = ByteBufferAllocator()
    let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                           parentProtocol: nil, metadata: .empty)

    func testMatchesGET() {
        var buf = allocator.buffer(capacity: 20)
        buf.writeString("GET /index.html HTTP/1.1")
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .yes(confidence: 90))
    }

    func testMatchesPOST() {
        var buf = allocator.buffer(capacity: 20)
        buf.writeString("POST /api/data HTTP/1.1")
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .yes(confidence: 90))
    }

    func testMatchesCONNECT() {
        var buf = allocator.buffer(capacity: 30)
        buf.writeString("CONNECT example.com:443 HTTP/1.1")
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .yes(confidence: 90))
    }

    func testDoesNotMatchTLS() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x16, 0x03, 0x01, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .no)
    }

    func testDoesNotMatchSOCKS5() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x05, 0x01, 0x00, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .no)
    }

    func testNeedMoreDataWithFewerThan4Bytes() {
        var buf = allocator.buffer(capacity: 2)
        buf.writeString("GE")
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .needMoreData(minimum: 4))
    }

    func testPluginId() {
        XCTAssertEqual(plugin.id, "http1")
    }
}
```

- [ ] **Step 5: Verify build and run all tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass (including existing HTTPRecorderTests which should still work after the move).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: create HTTP1Plugin, move HTTPCaptureHandler and HTTPRecorder into Plugins/HTTP1/"
```

---

### Task 6: Create TLSPlugin and move TLS files

**Files:**
- Create: `Sources/TunnelServices/Plugins/TLS/TLSPlugin.swift`
- Move: `Proxy/MITMHandler.swift` → `Plugins/TLS/MITMHandler.swift`
- Move: `Proxy/TLSSniffHandler.swift` → `Plugins/TLS/TLSSniffHandler.swift`
- Move: `Proxy/OCSPChecker.swift` → `Plugins/TLS/OCSPChecker.swift` (if exists)
- Test: `Tests/TunnelServicesTests/TLSPluginTests.swift`

- [ ] **Step 1: Write TLSPlugin.swift**

```swift
//
//  TLSPlugin.swift
//  TunnelServices
//
//  TLS protocol plugin (Unwrap type).
//  Detects TLS ClientHello (0x16), performs MITM or tunnel passthrough,
//  then re-detects child protocols on decrypted data.
//

import Foundation
import NIO
import NIOSSL
import NIOTLS

public final class TLSPlugin: ProtocolPlugin {
    public let id = "tls"
    public let displayName = "TLS"

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        guard buffer.readableBytes >= 3 else {
            return .needMoreData(minimum: 3)
        }
        let b1 = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) ?? 0
        let b2 = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) ?? 0
        let b3 = buffer.getInteger(at: buffer.readerIndex + 2, as: UInt8.self) ?? 0
        let isTLS = b1 == 22 && b2 <= 3 && b3 <= 3
        return isTLS ? .yes(confidence: 100) : .no
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let task = context.task
        let recorder = context.recorder
        let channel = context.channel
        let childNodes = context.childNodes
        let host = context.metadata.sni ?? context.metadata.innerHost ?? "unknown"
        let port = context.metadata.innerPort ?? 443

        recorder.session.host = host
        recorder.session.schemes = "HTTPS"

        let shouldIntercept = task.sslEnable == 1
            && !task.ruleEngine.matching(host: host, uri: "/", target: "")

        if shouldIntercept {
            // MITM path — MITMHandler handles TLS handshake, then uses ALPN
            // to create child ProtocolDispatcher with our childNodes
            let mitmHandler = MITMHandler(
                task: task, recorder: recorder, host: host, port: port
            )
            // Store childNodes on MITMHandler so it can create child dispatcher
            // after handshake (MITMHandler will need modification for this)
            _ = channel.pipeline.addHandler(mitmHandler, name: "mitm", position: .first)
            return channel.eventLoop.makeSucceededVoidFuture()
        } else {
            // Tunnel passthrough — sniff TLS handshake for metadata
            recorder.session.schemes = "HTTPS(Tunnel)"
            recorder.ensureHttpRecorder(
                host: host, port: port,
                protocolOverride: "HTTPS",
                method: "TUNNEL", uri: "\(host):\(port)",
                extraMetadata: ["encrypted": true, "decrypted": false]
            )
            _ = channel.pipeline.addHandler(
                TLSClientSniffHandler(recorder: recorder),
                name: "tls.sniff.client", position: .first
            )
            let tunnel = TunnelHandler(
                recorder: recorder, task: task,
                targetHost: host, targetPort: port
            )
            _ = channel.pipeline.addHandler(tunnel, name: "tunnel")
            return channel.eventLoop.makeSucceededVoidFuture()
        }
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        nil  // Unwrap plugin — child protocol creates the recorder
    }
}
```

- [ ] **Step 2: Move TLS-related files**

```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/TLS
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/MITMHandler.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/TLS/
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/TLSSniffHandler.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/TLS/
# Move OCSPChecker if it exists
[ -f LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/OCSPChecker.swift ] && \
  mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/OCSPChecker.swift \
     LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/TLS/
```

- [ ] **Step 3: Write TLSPluginTests.swift**

```swift
//
//  TLSPluginTests.swift
//  TunnelServicesTests
//

import XCTest
import NIO
@testable import TunnelServices

final class TLSPluginTests: XCTestCase {
    let plugin = TLSPlugin()
    let allocator = ByteBufferAllocator()
    let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                           parentProtocol: nil, metadata: .empty)

    func testMatchesTLSClientHello() {
        var buf = allocator.buffer(capacity: 5)
        buf.writeBytes([0x16, 0x03, 0x01, 0x00, 0xF1])  // TLS 1.0 ClientHello
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .yes(confidence: 100))
    }

    func testMatchesTLS12() {
        var buf = allocator.buffer(capacity: 5)
        buf.writeBytes([0x16, 0x03, 0x03, 0x01, 0x00])  // TLS 1.2
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .yes(confidence: 100))
    }

    func testDoesNotMatchHTTP() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeString("GET ")
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .no)
    }

    func testDoesNotMatchSOCKS5() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x05, 0x01, 0x00, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .no)
    }

    func testNeedMoreData() {
        var buf = allocator.buffer(capacity: 2)
        buf.writeBytes([0x16, 0x03])
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .needMoreData(minimum: 3))
    }

    func testPluginId() {
        XCTAssertEqual(plugin.id, "tls")
        XCTAssertEqual(plugin.displayName, "TLS")
    }
}
```

- [ ] **Step 4: Verify build and tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: create TLSPlugin, move MITMHandler and TLSSniffHandler into Plugins/TLS/"
```

---

### Task 7: Create SOCKS5Plugin and move SOCKS5 files

**Files:**
- Create: `Sources/TunnelServices/Plugins/SOCKS5/SOCKS5Plugin.swift`
- Move: `Proxy/SOCKSProxyHandler.swift` → `Plugins/SOCKS5/SOCKS5ServerHandler.swift`
- Test: `Tests/TunnelServicesTests/SOCKS5PluginTests.swift`

- [ ] **Step 1: Write SOCKS5Plugin.swift**

```swift
//
//  SOCKS5Plugin.swift
//  TunnelServices
//
//  SOCKS5 protocol plugin (Unwrap type).
//  Detects SOCKS5 greeting (0x05), handles handshake,
//  then re-enters TCP subtree for the inner connection.
//

import Foundation
import NIO

public final class SOCKS5Plugin: ProtocolPlugin {
    public let id = "socks5"
    public let displayName = "SOCKS5"

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        guard buffer.readableBytes >= 2 else {
            return .needMoreData(minimum: 2)
        }
        let version = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) ?? 0
        let methodCount = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) ?? 0
        guard version == 0x05, methodCount > 0 else { return .no }
        let needed = 2 + Int(methodCount)
        guard buffer.readableBytes >= needed else {
            return .needMoreData(minimum: needed)
        }
        return .yes(confidence: 95)
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        _ = context.channel.pipeline.addHandler(
            SOCKS5ServerHandler(task: context.task),
            name: "socks5", position: .first
        )
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        nil  // Unwrap plugin — inner protocol creates the recorder
    }
}
```

- [ ] **Step 2: Move SOCKSProxyHandler.swift**

```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/SOCKS5
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/SOCKSProxyHandler.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/SOCKS5/SOCKS5ServerHandler.swift
```

- [ ] **Step 3: Write SOCKS5PluginTests.swift**

```swift
//
//  SOCKS5PluginTests.swift
//  TunnelServicesTests
//

import XCTest
import NIO
@testable import TunnelServices

final class SOCKS5PluginTests: XCTestCase {
    let plugin = SOCKS5Plugin()
    let allocator = ByteBufferAllocator()
    let ctx = MatchContext(localPort: 8034, remoteAddress: nil,
                           parentProtocol: nil, metadata: .empty)

    func testMatchesSOCKS5Greeting() {
        var buf = allocator.buffer(capacity: 3)
        buf.writeBytes([0x05, 0x01, 0x00])  // SOCKS5, 1 method, NO_AUTH
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .yes(confidence: 95))
    }

    func testMatchesSOCKS5WithMultipleMethods() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x05, 0x02, 0x00, 0x02])  // 2 methods: NO_AUTH + USERNAME
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .yes(confidence: 95))
    }

    func testDoesNotMatchHTTP() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeString("GET ")
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .no)
    }

    func testDoesNotMatchTLS() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([0x16, 0x03, 0x01, 0x00])
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .no)
    }

    func testNeedMoreData() {
        var buf = allocator.buffer(capacity: 1)
        buf.writeBytes([0x05])
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .needMoreData(minimum: 2))
    }

    func testIncompleteGreetingNeedsMoreData() {
        // Version 0x05, claims 2 methods, but only 1 byte of methods present
        var buf = allocator.buffer(capacity: 3)
        buf.writeBytes([0x05, 0x02, 0x00])  // Missing second method byte
        XCTAssertEqual(plugin.canMatch(buf, context: ctx), .needMoreData(minimum: 4))
    }
}
```

- [ ] **Step 4: Verify build and tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: create SOCKS5Plugin, move SOCKS5ServerHandler into Plugins/SOCKS5/"
```

---

### Task 8: Create remaining plugins (HTTP2, gRPC, WebSocket, DNS) and move files

This task moves the remaining protocol handlers into their plugin folders. These are simpler since they're child protocols (detected by parent, not by byte prefix).

**Files:**
- Create: `Plugins/HTTP2/HTTP2Plugin.swift`
- Create: `Plugins/GRPC/GRPCPlugin.swift`
- Create: `Plugins/WebSocket/WebSocketPlugin.swift`
- Create: `Plugins/DNS/DNSPlugin.swift`
- Move: Multiple handler and recorder files

- [ ] **Step 1: Create HTTP2Plugin and move files**

Create `Plugins/HTTP2/HTTP2Plugin.swift`:
```swift
//
//  HTTP2Plugin.swift
//  TunnelServices
//
//  HTTP/2 protocol plugin. Detected via ALPN "h2" from parent TLS.
//

import Foundation
import NIO

public final class HTTP2Plugin: ProtocolPlugin {
    public let id = "http2"
    public let displayName = "HTTP/2"

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        // HTTP/2 is detected via ALPN, not byte prefix
        if context.metadata.alpnResult == "h2" {
            return .yes(confidence: 100)
        }
        return .no
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        // HTTP2CaptureBuilder.addPipeline expects a ChannelHandlerContext.
        // Since we're called from the dispatcher's whenComplete closure,
        // we add handlers directly to the channel pipeline instead.
        return HTTP2CaptureBuilder.addHTTP2Pipeline(
            channel: context.channel, recorder: context.recorder
        )
        // Note: HTTP2CaptureBuilder may need a small refactor to accept
        // Channel instead of ChannelHandlerContext. If the existing API
        // cannot be changed, wrap the call through the channel's pipeline.
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? { nil }
}
```

Move files:
```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP2
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/HTTP2CaptureHandler.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP2/
# Move HTTP2CaptureBuilder if it exists as separate file
[ -f LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/HTTP2CaptureBuilder.swift ] && \
  mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/HTTP2CaptureBuilder.swift \
     LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/HTTP2/
```

- [ ] **Step 2: Create GRPCPlugin and move files**

Create `Plugins/GRPC/GRPCPlugin.swift`:
```swift
//
//  GRPCPlugin.swift
//  TunnelServices
//
//  gRPC protocol plugin. Child of HTTP/2, detected by content-type.
//

import Foundation
import NIO

public final class GRPCPlugin: ProtocolPlugin {
    public let id = "grpc"
    public let displayName = "gRPC"

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        // gRPC detection happens inside HTTP/2 stream handler
        // by checking content-type header. This plugin is a placeholder
        // for the tree structure — actual detection is in HTTP2CaptureHandler.
        .no
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        context.channel.eventLoop.makeSucceededVoidFuture()
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        GRPCRecorder(flowId: flowId)
    }
}
```

Move files:
```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/GRPC
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/GRPCCaptureHandler.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/GRPC/
mv LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/GRPCRecorder.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/GRPC/
```

- [ ] **Step 3: Create WebSocketPlugin and move files**

Create `Plugins/WebSocket/WebSocketPlugin.swift`:
```swift
//
//  WebSocketPlugin.swift
//  TunnelServices
//
//  WebSocket protocol plugin. Child of HTTP/1.x, detected via Upgrade header.
//

import Foundation
import NIO

public final class WebSocketPlugin: ProtocolPlugin {
    public let id = "websocket"
    public let displayName = "WebSocket"

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        // WebSocket is detected by HTTP Upgrade header, not byte prefix.
        // HTTP1Plugin drives detection internally.
        .no
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let recorder = context.recorder
        _ = context.channel.pipeline.addHandler(
            WebSocketCaptureHandler(recorder: recorder),
            name: "ws.capture"
        )
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        WebSocketRecorder(flowId: flowId)
    }
}
```

Move files:
```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/WebSocket
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/WebSocketCaptureHandler.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/WebSocket/
mv LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/WebSocketRecorder.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/WebSocket/
```

- [ ] **Step 4: Create DNSPlugin and move files**

Create `Plugins/DNS/DNSPlugin.swift`:
```swift
//
//  DNSPlugin.swift
//  TunnelServices
//
//  DNS protocol plugin. Matches DNS queries by port or header structure.
//

import Foundation
import NIO

public final class DNSPlugin: ProtocolPlugin {
    public let id = "dns"
    public let displayName = "DNS"

    public init() {}

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        // DNS is typically on port 53 (UDP) or detected by header
        if context.localPort == 53 { return .yes(confidence: 95) }
        // Could also match DNS header structure (12-byte header, QR bit, etc.)
        guard buffer.readableBytes >= 12 else { return .no }
        return .no  // Conservative — port-based for now
    }

    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        context.channel.eventLoop.makeSucceededVoidFuture()
    }

    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        DNSRecorder(flowId: flowId)
    }
}
```

Move files:
```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/DNS
mv LocalPackages/TunnelServices/Sources/TunnelServices/Codec/DNSDecoder.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/DNS/
mv LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/DNSRecorder.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/DNS/
```

- [ ] **Step 5: Move remaining Codec/ decoders to Plugins/Codec/**

```bash
mkdir -p LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/Codec
mv LocalPackages/TunnelServices/Sources/TunnelServices/Codec/*.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Plugins/Codec/
rmdir LocalPackages/TunnelServices/Sources/TunnelServices/Codec/ 2>/dev/null || true
```

- [ ] **Step 6: Verify build and tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass. File moves within the same Swift package target don't break imports.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: create HTTP2, gRPC, WebSocket, DNS plugins and reorganize files

Move protocol handlers and recorders into their respective plugin folders.
Move remaining Codec/ decoders to Plugins/Codec/."
```

---

### Task 9: Wire up ProtocolRegistry with real plugins

**Files:**
- Modify: `Sources/TunnelServices/Framework/ProtocolRegistry.swift`
- Modify: `Tests/TunnelServicesTests/ProtocolRegistryTests.swift`

- [ ] **Step 1: Update ProtocolRegistry.buildDefault() with real plugins**

Replace the placeholder `buildDefault()` in `Framework/ProtocolRegistry.swift`:

```swift
static func buildDefault() -> [ProtocolNode] {
    return [
        // ── TCP root ──
        ProtocolNode(plugin: RootPlugin(id: "tcp", displayName: "TCP"), children: [
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
        ]),

        // ── UDP root ──
        ProtocolNode(plugin: RootPlugin(id: "udp", displayName: "UDP"), children: [
            ProtocolNode(plugin: DNSPlugin(), children: []),
        ]),
    ]
}
```

- [ ] **Step 2: Update ProtocolRegistryTests**

Add to `ProtocolRegistryTests.swift`:

```swift
func testTCPChildrenContainsHTTP1() {
    let children = ProtocolRegistry.shared.tcpChildren
    let ids = children.map { $0.plugin.id }
    XCTAssertTrue(ids.contains("http1"))
    XCTAssertTrue(ids.contains("tls"))
    XCTAssertTrue(ids.contains("socks5"))
}

func testTLSChildrenContainsHTTP1AndHTTP2() {
    let tlsNode = ProtocolRegistry.shared.tcpChildren.first(where: { $0.plugin.id == "tls" })
    XCTAssertNotNil(tlsNode)
    let childIds = tlsNode!.children.map { $0.plugin.id }
    XCTAssertTrue(childIds.contains("http1"))
    XCTAssertTrue(childIds.contains("http2"))
}
```

- [ ] **Step 3: Run tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' \
  -only-testing:TunnelServicesTests/ProtocolRegistryTests 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire ProtocolRegistry with real protocol plugins"
```

---

### Task 10: Move SessionRecorder to Framework/ and generalize

**Files:**
- Move: `Proxy/SessionRecorder.swift` → `Framework/SessionRecorder.swift`
- Modify: Add `setProtocolRecorder()` method

- [ ] **Step 1: Move SessionRecorder**

```bash
mv LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/SessionRecorder.swift \
   LocalPackages/TunnelServices/Sources/TunnelServices/Framework/
```

- [ ] **Step 2: Add setProtocolRecorder method**

Add to `SessionRecorder`:

```swift
// Add a new generic property alongside the existing httpRecorder
private var _protocolRecorder: ProtocolRecorder?

/// Set the protocol-specific recorder. Called by leaf plugins.
public func setProtocolRecorder(_ recorder: ProtocolRecorder) {
    self._protocolRecorder = recorder
    // Also set httpRecorder for backward compat (existing code reads it)
    if let httpRec = recorder as? HTTPRecorder {
        self.httpRecorder = httpRec
    }
}
```

In `recordClosed()`, update to use the generic recorder as fallback:
```swift
// Build FlowRecord and insert into protocol.db
if let recorder = _protocolRecorder ?? httpRecorder, let group = dbGroup {
    let flowRecord = recorder.buildFlowRecord()
    try? FlowDAO.insert(db: group.proto, record: flowRecord)
}
```

This ensures non-HTTP protocols (WebSocket, DNS, gRPC) also produce FlowRecords.

- [ ] **Step 3: Verify build and tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: move SessionRecorder to Framework/, add setProtocolRecorder()"
```

---

### Task 11: Replace ProtocolRouter with ProtocolDispatcher in MitmService and ProxyServer

This is the final wiring — the moment the new architecture goes live.

**Files:**
- Modify: `Sources/TunnelServices/MitmService.swift` (lines 71-83)
- Modify: `Sources/TunnelServices/Proxy/ProxyServer.swift` (lines 74-78)
- Delete: `Sources/TunnelServices/Proxy/ProtocolRouter.swift`

- [ ] **Step 1: Update MitmService.swift**

Replace ProtocolRouter with ProtocolDispatcher in both bootstrap initializers:

```swift
// Line 71-73: localBootstrap
.childChannelInitializer { [task] channel in
    let recorder = SessionRecorder(task: task)
    let tcpChildren = ProtocolRegistry.shared.tcpChildren
    return channel.pipeline.addHandler(
        ProtocolDispatcher(nodes: tcpChildren, task: task, recorder: recorder),
        name: "dispatcher", position: .first
    )
}

// Line 81-83: wifiBootstrap
.childChannelInitializer { [task] channel in
    let recorder = SessionRecorder(task: task)
    let tcpChildren = ProtocolRegistry.shared.tcpChildren
    return channel.pipeline.addHandler(
        ProtocolDispatcher(nodes: tcpChildren, task: task, recorder: recorder),
        name: "dispatcher", position: .first
    )
}
```

- [ ] **Step 2: Update ProxyServer.swift**

Replace ProtocolRouter with ProtocolDispatcher:

```swift
// Lines 74-78
.childChannelInitializer { channel in
    let recorder = SessionRecorder(task: task)
    let tcpChildren = ProtocolRegistry.shared.tcpChildren
    return channel.pipeline.addHandler(
        ProtocolDispatcher(nodes: tcpChildren, task: task, recorder: recorder),
        name: "dispatcher", position: .first
    )
}
```

- [ ] **Step 3: Update ConnectHandler.swift for TCP re-entry**

In `ConnectHandler.swift`, after sending 200 Connection Established, when the non-MITM path needs to re-enter TCP detection, use ProtocolDispatcher:

Replace the direct TunnelHandler/TLSSniffHandler setup with:
```swift
// For MITM path: keep existing MITMHandler setup (it uses TLSPlugin internally)
// For tunnel path: use ProtocolDispatcher to re-detect the inner protocol
let tcpChildren = ProtocolRegistry.shared.tcpChildren
var meta = ProtocolMetadata()
meta.parentId = "connect"
meta.innerHost = request.host
meta.innerPort = request.port
let dispatcher = ProtocolDispatcher(
    nodes: tcpChildren, task: task, recorder: recorder, parentMeta: meta
)
_ = context.pipeline.addHandler(dispatcher, name: "dispatcher")
```

- [ ] **Step 4: Delete ProtocolRouter.swift**

```bash
rm LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/ProtocolRouter.swift
```

- [ ] **Step 5: Verify build**

```bash
xcodebuild -scheme TunnelServices -destination 'platform=macOS' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED. If there are compilation errors, fix references to the deleted ProtocolRouter.

- [ ] **Step 6: Run all tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: replace ProtocolRouter with ProtocolDispatcher in MitmService and ProxyServer

The protocol plugin architecture is now live. ProtocolRouter is deleted.
All connections are routed through ProtocolDispatcher → protocol tree."
```

---

### Task 12: Clean up empty directories and verify

**Files:**
- Verify: Empty directories are removed
- Verify: All protocol paths work

- [ ] **Step 1: Remove empty directories**

```bash
# Remove Codec/ if empty (contents moved to Plugins/Codec/)
rmdir LocalPackages/TunnelServices/Sources/TunnelServices/Codec/ 2>/dev/null || true
# Remove Detector/ if somehow still present
rmdir LocalPackages/TunnelServices/Sources/TunnelServices/Detector/ 2>/dev/null || true
# Remove Handler/ if somehow still present
rmdir LocalPackages/TunnelServices/Sources/TunnelServices/Handler/ 2>/dev/null || true
```

- [ ] **Step 2: Verify ProtocolRecorder.swift interface stays in Storage/**

```bash
ls LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Protocol/ProtocolRecorder.swift
```
Expected: File exists (interface only, implementations are in Plugins/).

- [ ] **Step 3: Run full build for macOS**

```bash
xcodebuild -scheme "Knot" -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 4: Run all TunnelServices tests**

```bash
xcodebuild test -scheme TunnelServices -destination 'platform=macOS' 2>&1 | tail -20
```

- [ ] **Step 5: Commit final cleanup**

```bash
git add -A
git commit -m "chore: clean up empty directories after plugin migration"
```

---

## Summary

| Task | Description | Files | Type |
|------|-------------|-------|------|
| 1 | Delete legacy Detector/ + Handler/ | 13 deleted | Cleanup |
| 2 | ProtocolPlugin protocol + types | 2 created | Framework |
| 3 | ProtocolNode + ProtocolRegistry | 3 created | Framework |
| 4 | ProtocolDispatcher + RawPlugin | 4 created | Framework |
| 5 | HTTP1Plugin + move files | 1 created, 2 moved | Plugin |
| 6 | TLSPlugin + move files | 1 created, 2-3 moved | Plugin |
| 7 | SOCKS5Plugin + move files | 1 created, 1 moved | Plugin |
| 8 | HTTP2/gRPC/WebSocket/DNS plugins | 4 created, ~8 moved | Plugin |
| 9 | Wire registry with real plugins | 1 modified | Wiring |
| 10 | Move SessionRecorder to Framework | 1 moved | Refactor |
| 11 | Replace ProtocolRouter → Dispatcher | 3 modified, 1 deleted | Wiring |
| 12 | Clean up + verify | Cleanup | Verify |

## Known Limitations & Deferred Work

- **TLS SNI at buildPipeline time:** When TLSPlugin.buildPipeline runs for a direct TLS connection (no CONNECT/SOCKS5 parent), `context.metadata.sni` is nil because SNI hasn't been extracted yet. The host falls back to "unknown" until TLSSniffHandler or MITMHandler discovers it. This matches the existing ProtocolRouter behavior.
- **Deferred plugins:** The spec tree includes MQTT, Redis, NTP, QUIC, and HTTP/3 as leaf/subtree plugins. These are deferred — their decoders remain in `Plugins/Codec/` and are not wired into `buildDefault()`. Each becomes a full plugin when needed.
- **HTTP2CaptureBuilder API:** May need a small refactor to accept `Channel` instead of `ChannelHandlerContext`. The implementer should check the actual signature and adapt.
- **ProtocolMetadata is not Equatable** due to the `extra: [String: Any]` field. This is by design — the escape hatch dict cannot be auto-equated.
