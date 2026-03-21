# QUIC/HTTP3 ProxyServer Integration Implementation Plan (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add UDP listening to ProxyServer so QUIC/HTTP3 traffic can be captured and MITM-intercepted without the NetworkExtension system extension.

**Architecture:** NIO `DatagramBootstrap` binds a UDP port on ProxyServer. A `QUICProxyHandler` receives client QUIC packets, routes them through the tested `QUICMITMManager`, and forwards MITM-processed packets to real servers via per-session outbound `DatagramChannel`s. All QUIC work pinned to a single EventLoop.

**Tech Stack:** SwiftNIO (DatagramBootstrap, DatagramChannel), SwiftQuiche, QUICMITMManager

**Spec:** `docs/superpowers/specs/2026-03-21-quic-proxy-integration-design.md`

---

## File Structure

Source paths relative to `LocalPackages/TunnelServices/Sources/TunnelServices/`.
Test paths relative to `LocalPackages/TunnelServices/Tests/TunnelServicesTests/`.

### New Files
- `Proxy/QUICProxyHandler.swift` — Client-facing DatagramChannel handler
- `Proxy/QUICServerForwarder.swift` — Server-facing DatagramChannel handler
- `Integration/QUIC/QUICProxyTests.swift` — UDP proxy integration tests

### Modified Files
- `Config/ProxyConfig.swift` — Add `udpPort` to `HTTP3` enum
- `Proxy/ProxyServer.swift` — Add DatagramBootstrap for UDP, `udpChannel` property

---

## Priority Order

| P | Task | Impact |
|---|------|--------|
| P0 | Task 1: ProxyConfig.HTTP3.udpPort | Config needed before any code |
| P0 | Task 2: QUICProxyHandler | Core: receives client QUIC packets, calls MITM manager |
| P0 | Task 3: QUICServerForwarder | Core: receives server responses, relays back to client |
| P0 | Task 4: ProxyServer UDP bootstrap | Wires everything together |
| P1 | Task 5: QUICProxyTests | Validates end-to-end UDP→MITM→UDP |

---

### Task 1: ProxyConfig.HTTP3.udpPort

**Files:**
- Modify: `Config/ProxyConfig.swift`

- [ ] **Step 1: Add udpPort to HTTP3 enum**

In `ProxyConfig.swift`, inside the `HTTP3` enum (after `idleTimeoutMs`), add:

```swift
    /// UDP port for QUIC transparent proxy mode.
    public static var udpPort: Int = 8443
```

- [ ] **Step 2: Build to verify**

Run: `swift build --package-path LocalPackages/TunnelServices`

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Config/ProxyConfig.swift
git commit -m "feat: add HTTP3.udpPort config for QUIC proxy"
```

---

### Task 2: QUICProxyHandler

**Files:**
- Create: `Proxy/QUICProxyHandler.swift`

**Problem:** Need a NIO `ChannelInboundHandler` for the client-facing DatagramChannel that routes QUIC packets through `QUICMITMManager`.

- [ ] **Step 1: Implement QUICProxyHandler**

Read these files first for API understanding:
- `PacketCapture/QUICMITMHandler.swift` — `QUICMITMManager` API
- `Plugins/Codec/QUICDecoder.swift` — `extractSNI` for target resolution
- `UDP/UDPReceiver.swift` — existing NIO DatagramChannel pattern

```swift
// Proxy/QUICProxyHandler.swift
import Foundation
import NIO
@testable import SwiftQuiche  // if needed for types

/// Handles incoming QUIC packets from clients on the UDP DatagramChannel.
/// Routes packets through QUICMITMManager and manages per-session outbound channels.
public final class QUICProxyHandler: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let task: CaptureTask
    private let mitmManager: QUICMITMManager
    private weak var clientChannel: Channel?

    // Per-server outbound channels: "ip:port" → Channel
    private var serverChannels: [String: Channel] = [:]

    // Client address tracking: connectionId prefix → clientAddr
    private var clientAddresses: [String: SocketAddress] = [:]

    // For testing: fixed target (skip SNI resolution)
    public var defaultTarget: (host: String, port: Int)?

    // DNS cache: SNI → resolved IP
    private var dnsCache: [String: String] = [:]

    public init(task: CaptureTask, mitmManager: QUICMITMManager) {
        self.task = task
        self.mitmManager = mitmManager
    }

    public func channelActive(context: ChannelHandlerContext) {
        clientChannel = context.channel
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let clientAddr = envelope.remoteAddress
        var buf = envelope.data
        guard let bytes = buf.readBytes(length: buf.readableBytes) else { return }
        let packetData = Data(bytes)

        // Resolve target: default (testing) or SNI extraction
        let targetIP: String
        let targetPort: UInt16
        if let dt = defaultTarget {
            targetIP = dt.host
            targetPort = UInt16(dt.port)
        } else {
            // Extract SNI from QUIC Initial packet
            guard let sni = QUICDecoder.extractSNI(packetData) else {
                // Not an Initial or no SNI — try to match existing session by DCID
                // Fall through to processOutbound which will match by connection ID
                targetIP = "0.0.0.0"
                targetPort = 443
                // Still try processOutbound — manager may have a session for this DCID
            }
            if let cached = dnsCache[sni ?? ""] {
                targetIP = cached
                targetPort = 443
            } else if let sni = sni {
                // Async DNS — for now use SNI as host (works for IP literals)
                // TODO: proper async DNS resolution
                targetIP = sni
                targetPort = 443
                dnsCache[sni] = targetIP
            } else {
                targetIP = "0.0.0.0"
                targetPort = 443
            }
        }

        // Track client address by DCID prefix
        if let header = QUICDecoder.parseHeader(packetData) {
            let key = header.dcid.prefix(8).map { String(format: "%02x", $0) }.joined()
            clientAddresses[key] = clientAddr
        }

        // Route through MITM
        let (toApp, toServer) = mitmManager.processOutbound(packetData, dstIP: targetIP, dstPort: targetPort)

        // Send toApp back to client
        for pkt in toApp {
            writeToClient(pkt, clientAddr: clientAddr, context: context)
        }

        // Send toServer to real server via outbound channels
        for (pkt, ip, port) in toServer {
            sendToServer(pkt, serverIP: ip, serverPort: Int(port), clientAddr: clientAddr, context: context)
        }
    }

    // MARK: - Helpers

    private func writeToClient(_ data: Data, clientAddr: SocketAddress, context: ChannelHandlerContext) {
        var buf = context.channel.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        let envelope = AddressedEnvelope(remoteAddress: clientAddr, data: buf)
        context.writeAndFlush(wrapOutboundOut(envelope), promise: nil)
    }

    private func sendToServer(_ data: Data, serverIP: String, serverPort: Int, clientAddr: SocketAddress, context: ChannelHandlerContext) {
        let key = "\(serverIP):\(serverPort)"

        if let ch = serverChannels[key], ch.isActive {
            writeToServerChannel(ch, data: data, serverIP: serverIP, serverPort: serverPort)
            return
        }

        // Create new outbound channel
        let forwarder = QUICServerForwarder(
            mitmManager: mitmManager,
            clientChannel: clientChannel!,
            clientAddresses: clientAddresses
        )
        let bootstrap = DatagramBootstrap(group: context.eventLoop)
            .channelInitializer { channel in
                channel.pipeline.addHandler(forwarder)
            }

        bootstrap.bind(host: "0.0.0.0", port: 0).whenComplete { [weak self] result in
            switch result {
            case .success(let channel):
                self?.serverChannels[key] = channel
                self?.writeToServerChannel(channel, data: data, serverIP: serverIP, serverPort: serverPort)
            case .failure(let error):
                AxLogger.log("[QUICProxy] Failed to create outbound channel: \(error)", level: .Error)
            }
        }
    }

    private func writeToServerChannel(_ channel: Channel, data: Data, serverIP: String, serverPort: Int) {
        do {
            let addr = try SocketAddress(ipAddress: serverIP, port: serverPort)
            var buf = channel.allocator.buffer(capacity: data.count)
            buf.writeBytes(data)
            let envelope = AddressedEnvelope(remoteAddress: addr, data: buf)
            channel.writeAndFlush(envelope, promise: nil)
        } catch {
            AxLogger.log("[QUICProxy] Invalid server address \(serverIP):\(serverPort): \(error)", level: .Error)
        }
    }

    // MARK: - Cleanup

    public func channelInactive(context: ChannelHandlerContext) {
        for (_, ch) in serverChannels {
            ch.close(mode: .all, promise: nil)
        }
        serverChannels.removeAll()
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build --package-path LocalPackages/TunnelServices`

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/QUICProxyHandler.swift
git commit -m "feat: add QUICProxyHandler for client-facing UDP DatagramChannel"
```

---

### Task 3: QUICServerForwarder

**Files:**
- Create: `Proxy/QUICServerForwarder.swift`

- [ ] **Step 1: Implement QUICServerForwarder**

```swift
// Proxy/QUICServerForwarder.swift
import Foundation
import NIO

/// Handles incoming QUIC packets from the real server on an outbound DatagramChannel.
/// Routes responses through QUICMITMManager and relays decrypted packets to the client.
public final class QUICServerForwarder: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private let mitmManager: QUICMITMManager
    private weak var clientChannel: Channel?
    // Shared reference to client address map from QUICProxyHandler
    private let clientAddresses: [String: SocketAddress]

    public init(mitmManager: QUICMITMManager, clientChannel: Channel, clientAddresses: [String: SocketAddress]) {
        self.mitmManager = mitmManager
        self.clientChannel = clientChannel
        self.clientAddresses = clientAddresses
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buf = envelope.data
        guard let bytes = buf.readBytes(length: buf.readableBytes) else { return }
        let packetData = Data(bytes)

        let srcIP = envelope.remoteAddress.ipAddress ?? ""
        let srcPort = UInt16(envelope.remoteAddress.port ?? 0)

        // Process through MITM — returns (toApp, toServer)
        let result = mitmManager.processInbound(packetData, srcIP: srcIP, srcPort: srcPort)

        // Handle toApp: send to client
        if let toApp = result as? [Data] {
            for pkt in toApp {
                sendToClient(pkt)
            }
        }
        // If processInbound returns a tuple (toApp, toServer), handle toServer too
        // The actual return type depends on QUICMITMManager's current API
    }

    private func sendToClient(_ data: Data) {
        guard let clientCh = clientChannel, clientCh.isActive else { return }

        // Find client address from DCID in the packet
        var clientAddr: SocketAddress?
        if let header = QUICDecoder.parseHeader(data) {
            let key = header.dcid.prefix(8).map { String(format: "%02x", $0) }.joined()
            clientAddr = clientAddresses[key]
        }

        guard let addr = clientAddr ?? clientAddresses.values.first else {
            AxLogger.log("[QUICServerForwarder] No client address for response packet", level: .Warning)
            return
        }

        var buf = clientCh.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        let envelope = AddressedEnvelope(remoteAddress: addr, data: buf)
        clientCh.writeAndFlush(envelope, promise: nil)
    }
}
```

**Important:** Read the actual `processInbound` return type from `QUICMITMHandler.swift` to handle the correct type (it may return `[Data]` or `(toApp: [Data], toServer: [(Data, String, UInt16)])` depending on Phase 1 changes).

- [ ] **Step 2: Build to verify**

Run: `swift build --package-path LocalPackages/TunnelServices`

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/QUICServerForwarder.swift
git commit -m "feat: add QUICServerForwarder for server-facing UDP response relay"
```

---

### Task 4: ProxyServer UDP Bootstrap

**Files:**
- Modify: `Proxy/ProxyServer.swift`

- [ ] **Step 1: Add udpChannel property**

Add after `wifiChannel` (around line 17):

```swift
private(set) var udpChannel: Channel?

public var udpBoundPort: Int? {
    udpChannel?.localAddress?.port
}
```

- [ ] **Step 2: Add UDP bootstrap in startServer**

In `startServer()`, after the TCP `bootstrap.bind` and before `channel.closeFuture.wait()`, add:

```swift
// Start QUIC/UDP proxy if HTTP3 is enabled
if ProxyConfig.HTTP3.enabled && task.sslEnable == 1 {
    let certPath: String
    let keyPath: String
    if let certDir = CertStore.certDirectoryURL() {
        certPath = CertStore.filePath(in: certDir, name: ProxyConfig.CertFiles.caCert)
        keyPath = CertStore.filePath(in: certDir, name: ProxyConfig.CertFiles.caKey)
    } else {
        AxLogger.log("[ProxyServer] No cert directory for QUIC MITM", level: .Error)
        certPath = ""
        keyPath = ""
    }

    let mitmManager = QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)

    // Pin all QUIC work to a single event loop
    let quicEventLoop = workerGroup.next()
    let udpBootstrap = DatagramBootstrap(group: quicEventLoop)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .channelInitializer { channel in
            channel.pipeline.addHandler(
                QUICProxyHandler(task: task, mitmManager: mitmManager)
            )
        }

    if let udpCh = try? udpBootstrap.bind(host: host, port: ProxyConfig.HTTP3.udpPort).wait() {
        self.udpChannel = udpCh
        AxLogger.log("[ProxyServer] QUIC UDP proxy bound on \(host):\(udpCh.localAddress?.port ?? 0)", level: .Info)
    } else {
        AxLogger.log("[ProxyServer] Failed to bind QUIC UDP port \(ProxyConfig.HTTP3.udpPort)", level: .Error)
    }
}
```

- [ ] **Step 3: Update stop() to close UDP channel**

In `stop()`, before closing TCP channels, add:

```swift
udpChannel?.close(mode: .all, promise: nil)
udpChannel = nil
```

- [ ] **Step 4: Build and run existing tests**

Run: `swift test --package-path LocalPackages/TunnelServices`
Expected: All existing tests pass (UDP bootstrap only runs when HTTP3.enabled=true)

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/ProxyServer.swift
git commit -m "feat: add DatagramBootstrap UDP listener to ProxyServer for QUIC"
```

---

### Task 5: QUICProxyTests

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/QUIC/QUICProxyTests.swift`

**Problem:** Need to verify the UDP → MITM → UDP pipeline works end-to-end.

- [ ] **Step 1: Extend TestQUICServer for real UDP mode**

The existing `TestQUICServer` works in-memory. For proxy testing, it needs to also accept packets via a real UDP DatagramChannel. Add a method or mode:

```swift
extension TestQUICServer {
    /// Start a real UDP listener that feeds packets to the in-memory server.
    func startUDP(group: EventLoopGroup) throws -> Int {
        // Bind DatagramBootstrap, return port
        // channelRead: extract Data, call self.receive(), send responses back
    }
}
```

- [ ] **Step 2: Implement proxy tests**

```swift
final class QUICProxyTests: XCTestCase {

    func testUDPProxy_BindAndReceive() throws {
        // Just verify DatagramBootstrap binds and the handler is installed
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let task = // ... manual CaptureTask setup ...
        let mitmManager = QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)
        let handler = QUICProxyHandler(task: task, mitmManager: mitmManager)

        let channel = try DatagramBootstrap(group: group)
            .channelInitializer { $0.pipeline.addHandler(handler) }
            .bind(host: "127.0.0.1", port: 0).wait()

        XCTAssertNotNil(channel.localAddress?.port)
        try channel.close().wait()
    }

    func testUDPProxy_QUICHandshake() throws {
        // 1. Start TestQUICServer in UDP mode
        // 2. Start proxy with DatagramBootstrap + QUICProxyHandler
        //    - Set defaultTarget to TestQUICServer's UDP address
        // 3. TestQUICClient sends Initial via UDP to proxy port
        // 4. Proxy routes through MITM → forwards to server
        // 5. Server responds → proxy relays back → client completes handshake
        //
        // This is complex — the client needs to send/receive real UDP.
        // Use a NIO DatagramBootstrap for the test client too.
    }

    func testUDPProxy_H3Request() throws {
        // After handshake, send H3 GET, verify response
    }

    func testUDPProxy_MultiSession() throws {
        // 3 clients → 3 independent sessions
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --package-path LocalPackages/TunnelServices --filter QUICProxy`

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/QUIC/QUICProxyTests.swift
git commit -m "feat: add QUIC proxy integration tests (UDP bind, handshake, H3 request)"
```

---

## Post-Implementation Verification

1. **Build**: `swift build --package-path LocalPackages/TunnelServices` — pass
2. **Existing tests**: `swift test --package-path LocalPackages/TunnelServices` — all pass (HTTP3.enabled defaults to false, so UDP bootstrap doesn't affect existing tests)
3. **QUIC proxy tests**: `swift test --package-path LocalPackages/TunnelServices --filter QUICProxy` — pass
4. **All QUIC tests**: `swift test --package-path LocalPackages/TunnelServices --filter QUIC` — all pass
5. **Manual test**: Enable HTTP3, start ProxyServer, send QUIC packet to UDP port, verify flow recorded
