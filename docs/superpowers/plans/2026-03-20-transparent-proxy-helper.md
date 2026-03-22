# Transparent Proxy Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a KnotHelper macOS app with NETransparentProxyProvider that intercepts TCP/UDP traffic and forwards it to the main Knot app for capture.

**Architecture:** Phase 1 adds a UDP receiver to the main app (UDPHeaderCodec + UDPReceiver + UDPDispatchHandler). Phase 2 creates the KnotHelper app with System Extension. Phase 3 implements the TransparentProxyProvider with TCP (CONNECT relay) and UDP (header encapsulation) forwarding.

**Tech Stack:** Swift, SwiftNIO, SwiftUI, NetworkExtension framework, XCTest

**Spec:** `docs/superpowers/specs/2026-03-20-transparent-proxy-helper-design.md`

---

## File Structure

### Phase 1: UDP subsystem (main app)

```
LocalPackages/TunnelServices/Sources/TunnelServices/
├── UDP/                              ← New directory
│   ├── UDPHeaderCodec.swift          ← Encode/decode destination address header
│   ├── UDPReceiver.swift             ← NIO DatagramBootstrap listener on UDP:8034
│   └── UDPDispatchHandler.swift      ← Parse header, match UDP plugins, route responses
├── Framework/ProtocolRegistry.swift  ← Add udpChildren accessor
└── MitmService.swift                 ← Start UDPReceiver alongside TCP server

Tests/TunnelServicesTests/
├── UDPHeaderCodecTests.swift         ← Encode/decode round-trip, edge cases
└── UDPDispatchHandlerTests.swift     ← Header parsing, plugin matching
```

### Phase 2 & 3: KnotHelper app

```
KnotHelper/                           ← New: Helper app target
├── KnotHelperApp.swift               ← SwiftUI App entry point
├── HelperWindow.swift                ← UI: on/off, TCP/UDP toggles, status
├── HelperViewModel.swift             ← Extension install/uninstall, IPC, state
├── Assets.xcassets/
├── Info.plist
└── KnotHelper.entitlements

KnotHelperExtension/                  ← New: System Extension target
├── main.swift                        ← NEProvider.startSystemExtensionMode()
├── TransparentProxyProvider.swift    ← NETransparentProxyProvider core
├── TCPFlowHandler.swift              ← TCP flow → CONNECT relay to :8034
├── UDPFlowHandler.swift              ← UDP flow → header encapsulation to :8034
├── Info.plist
└── KnotHelperExtension.entitlements
```

---

## Tasks

### Task 1: UDPHeaderCodec — encode/decode destination address header

The shared codec used by both main app and Helper Extension.

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/UDP/UDPHeaderCodec.swift`
- Test: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/UDPHeaderCodecTests.swift`

- [ ] **Step 1: Write UDPHeaderCodecTests.swift**

```swift
import XCTest
import NIO
@testable import TunnelServices

final class UDPHeaderCodecTests: XCTestCase {
    let allocator = ByteBufferAllocator()

    // MARK: - IPv4

    func testEncodeDecodeIPv4() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "8.8.8.8", port: 53, into: &buf)
        let payload = Data([0x01, 0x02, 0x03])
        buf.writeBytes(payload)

        var readBuf = buf
        let result = UDPHeaderCodec.decode(from: &readBuf)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "8.8.8.8")
        XCTAssertEqual(result?.port, 53)
        XCTAssertEqual(result?.payload.readableBytes, 3)
    }

    func testIPv4HeaderIs7Bytes() {
        var buf = allocator.buffer(capacity: 16)
        UDPHeaderCodec.encode(host: "1.2.3.4", port: 80, into: &buf)
        XCTAssertEqual(buf.readableBytes, 7)  // 1 + 4 + 2
    }

    // MARK: - IPv6

    func testEncodeDecodeIPv6() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "2001:4860:4860::8888", port: 443, into: &buf)
        let payload = Data([0xAA, 0xBB])
        buf.writeBytes(payload)

        var readBuf = buf
        let result = UDPHeaderCodec.decode(from: &readBuf)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "2001:4860:4860::8888")
        XCTAssertEqual(result?.port, 443)
        XCTAssertEqual(result?.payload.readableBytes, 2)
    }

    func testIPv6HeaderIs19Bytes() {
        var buf = allocator.buffer(capacity: 32)
        UDPHeaderCodec.encode(host: "::1", port: 53, into: &buf)
        XCTAssertEqual(buf.readableBytes, 19)  // 1 + 16 + 2
    }

    // MARK: - Domain

    func testEncodeDecodeDomain() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "example.com", port: 443, into: &buf)
        buf.writeBytes([0xFF])  // payload

        var readBuf = buf
        let result = UDPHeaderCodec.decode(from: &readBuf)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "example.com")
        XCTAssertEqual(result?.port, 443)
    }

    func testDomainHeaderSize() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "example.com", port: 80, into: &buf)
        // 1 (type) + 1 (len) + 11 (domain) + 2 (port) = 15
        XCTAssertEqual(buf.readableBytes, 15)
    }

    // MARK: - Edge cases

    func testDecodeEmptyBufferReturnsNil() {
        var buf = allocator.buffer(capacity: 0)
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testDecodeTruncatedBufferReturnsNil() {
        var buf = allocator.buffer(capacity: 3)
        buf.writeBytes([0x01, 0x08, 0x08])  // IPv4 type but only 2 addr bytes
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testDecodeUnknownAddrTypeReturnsNil() {
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x99, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testPortBigEndian() {
        var buf = allocator.buffer(capacity: 16)
        UDPHeaderCodec.encode(host: "1.2.3.4", port: 8034, into: &buf)
        // port 8034 = 0x1F62 → bytes [1F, 62]
        let bytes = buf.getBytes(at: 5, length: 2)!  // after type(1) + addr(4)
        XCTAssertEqual(bytes, [0x1F, 0x62])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/aa123/Documents/Knot-storage-redesign && swift test --package-path LocalPackages/TunnelServices --filter UDPHeaderCodecTests 2>&1 | tail -5
```
Expected: Compilation error — `UDPHeaderCodec` doesn't exist yet.

- [ ] **Step 3: Implement UDPHeaderCodec.swift**

```swift
//
//  UDPHeaderCodec.swift
//  TunnelServices
//
//  Encodes/decodes a destination address header for UDP datagrams.
//  Format: [addrType(1)] [address(variable)] [port(2, big-endian)] [payload...]
//  Address types reuse SOCKS5 encoding: 0x01=IPv4, 0x03=Domain, 0x04=IPv6.
//

import Foundation
import NIO

public enum UDPHeaderCodec {

    // MARK: - Address type constants (SOCKS5 compatible)
    public static let addrTypeIPv4: UInt8   = 0x01
    public static let addrTypeDomain: UInt8 = 0x03
    public static let addrTypeIPv6: UInt8   = 0x04

    // MARK: - Decode result
    public struct DecodedHeader {
        public let host: String
        public let port: Int
        public var payload: ByteBuffer
    }

    // MARK: - Encode

    /// Write destination header into buffer. Caller appends payload after.
    public static func encode(host: String, port: Int, into buffer: inout ByteBuffer) {
        if let ipv4 = IPv4Address(host) {
            buffer.writeInteger(addrTypeIPv4)
            withUnsafeBytes(of: ipv4.rawValue) { buffer.writeBytes($0) }
        } else if let ipv6 = IPv6Address(host) {
            buffer.writeInteger(addrTypeIPv6)
            withUnsafeBytes(of: ipv6.rawValue) { buffer.writeBytes($0) }
        } else {
            // Domain
            let domainBytes = Array(host.utf8)
            buffer.writeInteger(addrTypeDomain)
            buffer.writeInteger(UInt8(domainBytes.count))
            buffer.writeBytes(domainBytes)
        }
        buffer.writeInteger(UInt16(port))  // big-endian by default in NIO
    }

    // MARK: - Decode

    /// Parse header from front of buffer. On success, advances readerIndex past header.
    /// Returns nil if buffer is malformed or too short.
    public static func decode(from buffer: inout ByteBuffer) -> DecodedHeader? {
        guard let addrType = buffer.readInteger(as: UInt8.self) else { return nil }

        let host: String
        switch addrType {
        case addrTypeIPv4:
            guard buffer.readableBytes >= 6 else { return nil }  // 4 addr + 2 port
            guard let a = buffer.readInteger(as: UInt8.self),
                  let b = buffer.readInteger(as: UInt8.self),
                  let c = buffer.readInteger(as: UInt8.self),
                  let d = buffer.readInteger(as: UInt8.self) else { return nil }
            host = "\(a).\(b).\(c).\(d)"

        case addrTypeIPv6:
            guard buffer.readableBytes >= 18 else { return nil }  // 16 addr + 2 port
            var parts = [String]()
            for _ in 0..<8 {
                guard let word = buffer.readInteger(as: UInt16.self) else { return nil }
                parts.append(String(format: "%x", word))
            }
            host = parts.joined(separator: ":")

        case addrTypeDomain:
            guard let len = buffer.readInteger(as: UInt8.self),
                  buffer.readableBytes >= Int(len) + 2 else { return nil }
            guard let domain = buffer.readString(length: Int(len)) else { return nil }
            host = domain

        default:
            return nil
        }

        guard let port = buffer.readInteger(as: UInt16.self) else { return nil }
        let payload = buffer.readSlice(length: buffer.readableBytes) ?? ByteBuffer()

        return DecodedHeader(host: host, port: Int(port), payload: payload)
    }
}

// MARK: - IP Address helpers

private struct IPv4Address {
    let rawValue: UInt32
    init?(_ string: String) {
        var addr = in_addr()
        guard inet_pton(AF_INET, string, &addr) == 1 else { return nil }
        self.rawValue = addr.s_addr
    }
}

private struct IPv6Address {
    let rawValue: in6_addr
    init?(_ string: String) {
        var addr = in6_addr()
        guard inet_pton(AF_INET6, string, &addr) == 1 else { return nil }
        self.rawValue = addr
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/aa123/Documents/Knot-storage-redesign && swift test --package-path LocalPackages/TunnelServices --filter UDPHeaderCodecTests 2>&1 | tail -15
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/UDP/UDPHeaderCodec.swift \
        LocalPackages/TunnelServices/Tests/TunnelServicesTests/UDPHeaderCodecTests.swift
git commit -m "feat: add UDPHeaderCodec for destination address header encode/decode"
```

---

### Task 2: UDPReceiver and UDPDispatchHandler — receive and route UDP datagrams

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/UDP/UDPReceiver.swift`
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/UDP/UDPDispatchHandler.swift`
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/Framework/ProtocolRegistry.swift`
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/MitmService.swift`

- [ ] **Step 1: Add udpChildren to ProtocolRegistry**

Add to `Framework/ProtocolRegistry.swift` after the existing `tcpChildren`:

```swift
/// Convenience accessor for children of the UDP root.
public var udpChildren: [ProtocolNode] {
    roots.first(where: { $0.plugin.id == "udp" })?.children ?? []
}
```

- [ ] **Step 2: Create UDPDispatchHandler.swift**

```swift
//
//  UDPDispatchHandler.swift
//  TunnelServices
//
//  Receives UDP datagrams from the Helper Extension (or manual sends),
//  decodes the destination header, matches against the UDP plugin tree,
//  and stores sender address for response routing.
//

import Foundation
import NIO

public final class UDPDispatchHandler: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let task: CaptureTask
    private weak var channel: Channel?

    /// Maps sender (Helper) address → last activity time for idle cleanup.
    private var senderTracker: [SocketAddress: TimeInterval] = [:]
    private static let idleTimeout: TimeInterval = 30

    public init(task: CaptureTask) {
        self.task = task
    }

    public func channelActive(context: ChannelHandlerContext) {
        self.channel = context.channel
        // Schedule periodic idle cleanup every 10 seconds
        context.eventLoop.scheduleRepeatedTask(
            initialDelay: .seconds(10), delay: .seconds(10)
        ) { [weak self] _ in
            self?.cleanupIdleSenders()
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let senderAddress = envelope.remoteAddress
        var buffer = envelope.data

        // Track sender for response routing
        senderTracker[senderAddress] = Date().timeIntervalSince1970

        // Decode header
        guard let decoded = UDPHeaderCodec.decode(from: &buffer) else {
            AxLogger.log("UDPDispatchHandler: malformed header from \(senderAddress)", level: .Warning)
            return
        }

        AxLogger.log("UDP datagram: \(decoded.host):\(decoded.port) (\(decoded.payload.readableBytes) bytes) from \(senderAddress)", level: .Info)

        // Create recorder for this datagram
        let recorder = SessionRecorder(task: task)
        recorder.session.host = decoded.host
        recorder.session.schemes = "UDP"

        // Match against UDP plugin tree
        let udpChildren = ProtocolRegistry.shared.udpChildren
        let matchCtx = MatchContext(
            localPort: decoded.port,
            remoteAddress: nil,
            parentProtocol: "udp",
            metadata: .empty
        )

        var bestPlugin: ProtocolPlugin?
        var bestConfidence = -1
        for node in udpChildren {
            if case .yes(let c) = node.plugin.canMatch(decoded.payload, context: matchCtx),
               c > bestConfidence {
                bestPlugin = node.plugin
                bestConfidence = c
            }
        }

        if let plugin = bestPlugin {
            AxLogger.log("UDP matched plugin: \(plugin.id)", level: .Info)
            // For now, record as a flow. Full plugin pipeline for UDP is a follow-up.
            recorder.session.schemes = plugin.displayName
        }

        // Record the datagram
        recorder.session.methods = "UDP"
        recorder.session.uri = "\(decoded.host):\(decoded.port)"
        recorder.addUpload(decoded.payload.readableBytes)

        // TODO: When plugins can process UDP and produce responses,
        // send response back to senderAddress with header
        recorder.recordClosed()
    }

    /// Send a response back to the Helper. Called by plugins that produce UDP responses.
    public func sendResponse(to sender: SocketAddress, host: String, port: Int,
                              payload: ByteBuffer, context: ChannelHandlerContext) {
        var responseBuf = context.channel.allocator.buffer(capacity: 19 + payload.readableBytes)
        UDPHeaderCodec.encode(host: host, port: port, into: &responseBuf)
        var payloadCopy = payload
        responseBuf.writeBuffer(&payloadCopy)
        let envelope = AddressedEnvelope(remoteAddress: sender, data: responseBuf)
        context.writeAndFlush(wrapOutboundOut(envelope), promise: nil)
    }

    private func cleanupIdleSenders() {
        let now = Date().timeIntervalSince1970
        senderTracker = senderTracker.filter { now - $0.value < Self.idleTimeout }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("UDPDispatchHandler error: \(error)", level: .Error)
    }
}
```

- [ ] **Step 3: Create UDPReceiver.swift**

```swift
//
//  UDPReceiver.swift
//  TunnelServices
//
//  Binds a NIO DatagramChannel on UDP:8034 to receive forwarded
//  UDP datagrams from the KnotHelper transparent proxy extension.
//

import Foundation
import NIO

public final class UDPReceiver {

    private var channel: Channel?

    /// Start listening for UDP datagrams.
    public func start(group: EventLoopGroup, task: CaptureTask, port: Int) throws {
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(UDPDispatchHandler(task: task))
            }

        let channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        self.channel = channel
        AxLogger.log("UDPReceiver listening on UDP:\(port)", level: .Info)
    }

    /// Stop listening.
    public func stop() {
        channel?.close(promise: nil)
        channel = nil
    }
}
```

- [ ] **Step 4: Wire UDPReceiver into MitmService**

In `MitmService.swift`, add a `udpReceiver` property and start it in `run()`.

Add property near the top (after `var task: CaptureTask!`):
```swift
private var udpReceiver: UDPReceiver?
```

In the `run()` method, after the TCP server bind logic, add:
```swift
// Start UDP receiver for Helper Extension forwarding
do {
    let receiver = UDPReceiver()
    try receiver.start(group: worker, task: task, port: task.localPort)
    self.udpReceiver = receiver
} catch {
    AxLogger.log("Failed to start UDP receiver: \(error)", level: .Error)
}
```

In the `close()` method, add:
```swift
udpReceiver?.stop()
udpReceiver = nil
```

- [ ] **Step 5: Build and test**

```bash
cd /Users/aa123/Documents/Knot-storage-redesign && swift build --package-path LocalPackages/TunnelServices 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

```bash
cd /Users/aa123/Documents/Knot-storage-redesign && swift test --package-path LocalPackages/TunnelServices 2>&1 | tail -20
```
Expected: All tests pass (including UDPHeaderCodecTests from Task 1).

- [ ] **Step 6: Manual test with netcat**

After running the main app, send a test UDP packet:
```bash
# Encode a simple header: IPv4 8.8.8.8:53 + payload "hello"
python3 -c "
import socket, struct
# addrType=0x01, addr=8.8.8.8, port=53, payload=hello
data = bytes([0x01, 8,8,8,8]) + struct.pack('!H', 53) + b'hello'
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.sendto(data, ('127.0.0.1', 8034))
print('Sent', len(data), 'bytes')
"
```
Expected: Knot logs show "UDP datagram: 8.8.8.8:53 (5 bytes)".

- [ ] **Step 7: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/UDP/ \
        LocalPackages/TunnelServices/Sources/TunnelServices/Framework/ProtocolRegistry.swift \
        LocalPackages/TunnelServices/Sources/TunnelServices/MitmService.swift
git commit -m "feat: add UDPReceiver and UDPDispatchHandler for UDP datagram capture

Listens on UDP:8034 alongside existing TCP:8034.
Decodes destination header, matches against UDP plugin tree (DNS etc.),
records datagrams as flows."
```

---

### Task 3: Create KnotHelper app target and UI

This task creates the Xcode targets and implements the Helper app UI. **This task must be done manually in Xcode** for target creation — the code files can be generated.

**Files:**
- Create: `KnotHelper/KnotHelperApp.swift`
- Create: `KnotHelper/HelperWindow.swift`
- Create: `KnotHelper/HelperViewModel.swift`
- Create: `KnotHelper/Info.plist`
- Create: `KnotHelper/KnotHelper.entitlements`

- [ ] **Step 1: Create Xcode targets**

In Xcode:
1. File → New → Target → macOS → App → name: `KnotHelper`, bundle ID: `com.KingMap.KnotHelper`, SwiftUI lifecycle
2. File → New → Target → macOS → System Extension → name: `KnotHelperExtension`, bundle ID: `com.KingMap.KnotHelper.Extension`
3. In KnotHelper target → Build Phases → add "Embed System Extensions" → embed KnotHelperExtension
4. Add `TunnelServices` package dependency to KnotHelperExtension target

- [ ] **Step 2: Set up entitlements**

Create `KnotHelper/KnotHelper.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>app-proxy-provider</string>
    </array>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.Lojii.NIO1901</string>
    </array>
</dict>
</plist>
```

Create `KnotHelperExtension/KnotHelperExtension.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>app-proxy-provider</string>
    </array>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.Lojii.NIO1901</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Write KnotHelperApp.swift**

```swift
import SwiftUI

@main
struct KnotHelperApp: App {
    @StateObject private var viewModel = HelperViewModel()

    var body: some Scene {
        WindowGroup {
            HelperWindow(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 240)
    }
}
```

- [ ] **Step 4: Write HelperWindow.swift**

```swift
import SwiftUI

struct HelperWindow: View {
    @ObservedObject var viewModel: HelperViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status
            HStack {
                Circle()
                    .fill(viewModel.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(viewModel.statusText)
                    .font(.headline)
            }

            Divider()

            // Forward mode
            Text("Forward mode:").font(.subheadline)
            HStack(spacing: 20) {
                Toggle("TCP", isOn: $viewModel.forwardTCP)
                    .toggleStyle(.checkbox)
                Toggle("UDP", isOn: $viewModel.forwardUDP)
                    .toggleStyle(.checkbox)
            }

            // Port
            HStack {
                Text("App port:")
                TextField("8034", text: $viewModel.portText)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // Enable/Disable button
            Button(action: { viewModel.toggleProxy() }) {
                Text(viewModel.isRunning ? "Disable" : "Enable")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            // Main app status
            HStack {
                Text("Main app:")
                Circle()
                    .fill(viewModel.mainAppRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(viewModel.mainAppRunning ? "Running" : "Not detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
```

- [ ] **Step 5: Write HelperViewModel.swift**

```swift
import Foundation
import SystemExtensions
import NetworkExtension

class HelperViewModel: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var forwardTCP = true
    @Published var forwardUDP = true
    @Published var portText = "8034"
    @Published var statusText = "Stopped"
    @Published var mainAppRunning = false

    private let ipc: AppGroupIPC
    private var manager: NETransparentProxyManager?

    override init() {
        self.ipc = AppGroupIPC(groupIdentifier: "group.Lojii.NIO1901")
        super.init()
        loadConfig()
        observeMainApp()
    }

    // MARK: - Config persistence via IPC

    func loadConfig() {
        let defaults = UserDefaults(suiteName: "group.Lojii.NIO1901")
        forwardTCP = defaults?.bool(forKey: "helper.forwardTCP") ?? true
        forwardUDP = defaults?.bool(forKey: "helper.forwardUDP") ?? true
        if let port = defaults?.string(forKey: "helper.port"), !port.isEmpty {
            portText = port
        }
        let appStatus = defaults?.string(forKey: "app.status") ?? "stopped"
        mainAppRunning = appStatus == "running"
    }

    func saveConfig() {
        let defaults = UserDefaults(suiteName: "group.Lojii.NIO1901")
        defaults?.set(forwardTCP, forKey: "helper.forwardTCP")
        defaults?.set(forwardUDP, forKey: "helper.forwardUDP")
        defaults?.set(portText, forKey: "helper.port")
        defaults?.set(isRunning ? "running" : "stopped", forKey: "helper.status")
    }

    func observeMainApp() {
        ipc.listenForMessage(identifier: "app.status") { [weak self] msg in
            DispatchQueue.main.async {
                self?.mainAppRunning = (msg as? String) == "running"
            }
        }
    }

    // MARK: - Extension lifecycle

    func toggleProxy() {
        if isRunning {
            stopProxy()
        } else {
            startProxy()
        }
    }

    private func startProxy() {
        // Step 1: Install system extension if needed
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.KingMap.KnotHelper.Extension",
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func stopProxy() {
        NETransparentProxyManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let manager = managers?.first else { return }
            manager.connection.stopVPNTunnel()
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.statusText = "Stopped"
                self?.saveConfig()
            }
        }
    }

    private func enableProxyManager() {
        NETransparentProxyManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            let manager = managers?.first ?? NETransparentProxyManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.KingMap.KnotHelper.Extension"
            proto.serverAddress = "127.0.0.1"
            manager.protocolConfiguration = proto
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.statusText = "Error: \(error.localizedDescription)"
                    }
                    return
                }
                manager.loadFromPreferences { _ in
                    do {
                        try manager.connection.startVPNTunnel()
                        DispatchQueue.main.async {
                            self.isRunning = true
                            self.statusText = "Connected"
                            self.saveConfig()
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.statusText = "Error: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension HelperViewModel: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        if result == .completed {
            enableProxyManager()
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusText = "Extension error: \(error.localizedDescription)"
        }
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        DispatchQueue.main.async {
            self.statusText = "Waiting for approval in System Settings..."
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }
}
```

- [ ] **Step 6: Build KnotHelper target**

```bash
xcodebuild -scheme KnotHelper -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 7: Commit**

```bash
git add KnotHelper/
git commit -m "feat: create KnotHelper app with UI for transparent proxy control"
```

---

### Task 4: Create KnotHelperExtension — TransparentProxyProvider

**Files:**
- Create: `KnotHelperExtension/main.swift`
- Create: `KnotHelperExtension/TransparentProxyProvider.swift`
- Create: `KnotHelperExtension/TCPFlowHandler.swift`
- Create: `KnotHelperExtension/UDPFlowHandler.swift`
- Create: `KnotHelperExtension/Info.plist`
- Create: `KnotHelperExtension/KnotHelperExtension.entitlements`

- [ ] **Step 1: Write main.swift**

```swift
import Foundation
import NetworkExtension

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
```

- [ ] **Step 2: Write Info.plist for extension**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NetworkExtension</key>
    <dict>
        <key>NEProviderClasses</key>
        <dict>
            <key>com.apple.networkextension.app-proxy</key>
            <string>$(PRODUCT_MODULE_NAME).TransparentProxyProvider</string>
        </dict>
    </dict>
</dict>
</plist>
```

- [ ] **Step 3: Write TransparentProxyProvider.swift**

```swift
import Foundation
import NetworkExtension
import os.log

class TransparentProxyProvider: NETransparentProxyProvider {

    private let logger = Logger(subsystem: "com.KingMap.KnotHelper.Extension", category: "proxy")
    private var shouldForwardTCP = true
    private var shouldForwardUDP = true
    private var targetPort: Int = 8034

    // Bundle IDs to exclude from interception (anti-loop)
    private let excludedBundleIDs: Set<String> = [
        "com.KingMap.KnotApp-macOS",
        "com.KingMap.KnotHelper",
        "com.KingMap.KnotHelper.Extension",
    ]

    // MARK: - Lifecycle

    override func startProxy(options: [String: Any]? = nil,
                              completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting transparent proxy")
        loadConfig()
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        logger.info("Stopping transparent proxy: \(String(describing: reason))")
        completionHandler()
    }

    // MARK: - TCP flow handling

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let tcpFlow = flow as? NEAppProxyTCPFlow else { return false }
        guard shouldForwardTCP else { return false }
        guard !isExcluded(flow) else { return false }

        let handler = TCPFlowHandler(flow: tcpFlow, targetPort: targetPort, logger: logger)
        handler.start()
        return true
    }

    // MARK: - UDP flow handling

    override func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow,
                                    initialRemoteEndpoint remoteEndpoint: NWEndpoint) -> Bool {
        guard shouldForwardUDP else { return false }
        guard !isExcluded(flow) else { return false }

        let handler = UDPFlowHandler(flow: flow, targetPort: targetPort, logger: logger)
        handler.start()
        return true
    }

    // MARK: - Config

    private func loadConfig() {
        let defaults = UserDefaults(suiteName: "group.Lojii.NIO1901")
        shouldForwardTCP = defaults?.bool(forKey: "helper.forwardTCP") ?? true
        shouldForwardUDP = defaults?.bool(forKey: "helper.forwardUDP") ?? true
        if let portStr = defaults?.string(forKey: "helper.port"),
           let port = Int(portStr), port > 0 {
            targetPort = port
        }
    }

    // MARK: - Anti-loop

    private func isExcluded(_ flow: NEAppProxyFlow) -> Bool {
        let bundleID = flow.metaData.sourceAppSigningIdentifier
        if excludedBundleIDs.contains(bundleID) { return true }

        // Exclude localhost-destined traffic
        if let endpoint = (flow as? NEAppProxyTCPFlow)?.remoteEndpoint as? NWHostEndpoint {
            if endpoint.hostname.hasPrefix("127.") || endpoint.hostname == "::1" {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Write TCPFlowHandler.swift**

```swift
import Foundation
import Network
import NetworkExtension
import os.log

/// Handles a single TCP flow by relaying it through HTTP CONNECT to the main app proxy.
class TCPFlowHandler {
    private let flow: NEAppProxyTCPFlow
    private let targetPort: Int
    private let logger: Logger
    private var connection: NWConnection?

    init(flow: NEAppProxyTCPFlow, targetPort: Int, logger: Logger) {
        self.flow = flow
        self.targetPort = targetPort
        self.logger = logger
    }

    func start() {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            if let error = error {
                self?.logger.error("TCP flow open error: \(error.localizedDescription)")
                return
            }
            self?.connectToProxy()
        }
    }

    private func connectToProxy() {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(targetPort)))
        let conn = NWConnection(to: endpoint, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendConnect()
            case .failed(let error):
                self?.logger.error("TCP proxy connection failed: \(error.localizedDescription)")
                self?.cleanup()
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func sendConnect() {
        guard let endpoint = flow.remoteEndpoint as? NWHostEndpoint else {
            cleanup()
            return
        }
        let host = endpoint.hostname
        let port = endpoint.port
        let connectRequest = "CONNECT \(host):\(port) HTTP/1.1\r\nHost: \(host):\(port)\r\n\r\n"

        connection?.send(content: connectRequest.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("CONNECT send error: \(error.localizedDescription)")
                self?.cleanup()
                return
            }
            self?.waitForConnectResponse()
        })
    }

    private func waitForConnectResponse() {
        connection?.receive(minimumIncompleteLength: 12, maximumLength: 1024) { [weak self] data, _, _, error in
            guard let self = self, let data = data else {
                self?.cleanup()
                return
            }
            let response = String(data: data, encoding: .utf8) ?? ""
            if response.contains("200") {
                // CONNECT succeeded, start bidirectional relay
                self.relayFlowToConnection()
                self.relayConnectionToFlow()
            } else {
                self.logger.error("CONNECT failed: \(response.prefix(100))")
                self.cleanup()
            }
        }
    }

    // MARK: - Bidirectional relay

    private func relayFlowToConnection() {
        flow.readData { [weak self] data, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.connection?.send(content: data, completion: .contentProcessed { _ in
                    self.relayFlowToConnection()  // Continue reading
                })
            } else {
                // Flow closed or error
                self.cleanup()
            }
        }
    }

    private func relayConnectionToFlow() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.flow.write(data) { error in
                    if error == nil {
                        self.relayConnectionToFlow()  // Continue reading
                    } else {
                        self.cleanup()
                    }
                }
            } else if isComplete {
                self.cleanup()
            } else {
                self.cleanup()
            }
        }
    }

    private func cleanup() {
        connection?.cancel()
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
    }
}
```

- [ ] **Step 5: Write UDPFlowHandler.swift**

```swift
import Foundation
import Network
import NetworkExtension
import os.log
import TunnelServices  // For UDPHeaderCodec

/// Handles a single UDP flow by forwarding datagrams with address headers to the main app.
class UDPFlowHandler {
    private let flow: NEAppProxyUDPFlow
    private let targetPort: Int
    private let logger: Logger
    private var connection: NWConnection?
    private var idleTimer: DispatchSourceTimer?
    private static let idleTimeout: TimeInterval = 30

    init(flow: NEAppProxyUDPFlow, targetPort: Int, logger: Logger) {
        self.flow = flow
        self.targetPort = targetPort
        self.logger = logger
    }

    func start() {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            if let error = error {
                self?.logger.error("UDP flow open error: \(error.localizedDescription)")
                return
            }
            self?.setupConnection()
        }
    }

    private func setupConnection() {
        // Each UDP flow gets its own NWConnection (distinct ephemeral source port)
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(targetPort)))
        let params = NWParameters.udp
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.startRelaying()
                self?.startIdleTimer()
            case .failed(let error):
                self?.logger.error("UDP proxy connection failed: \(error.localizedDescription)")
                self?.cleanup()
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - Datagram relay

    private func startRelaying() {
        readFromFlow()
        readFromProxy()
    }

    private func readFromFlow() {
        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self = self, let datagrams = datagrams, let endpoints = endpoints else {
                self?.cleanup()
                return
            }
            self.resetIdleTimer()

            for (data, endpoint) in zip(datagrams, endpoints) {
                guard let hostEndpoint = endpoint as? NWHostEndpoint else { continue }
                // Encode: header + payload
                var headerData = Data()
                var buf = ByteBufferAllocator().buffer(capacity: 19 + data.count)
                UDPHeaderCodec.encode(host: hostEndpoint.hostname,
                                      port: Int(hostEndpoint.port) ?? 0,
                                      into: &buf)
                buf.writeBytes(data)
                if let bytes = buf.readBytes(length: buf.readableBytes) {
                    headerData = Data(bytes)
                }
                self.connection?.send(content: headerData, completion: .contentProcessed { _ in })
            }
            // Continue reading
            self.readFromFlow()
        }
    }

    private func readFromProxy() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, let data = data, !data.isEmpty else {
                if error != nil { self?.cleanup() }
                return
            }
            self.resetIdleTimer()

            // Decode header from response
            var buf = ByteBufferAllocator().buffer(capacity: data.count)
            buf.writeBytes(data)
            if let decoded = UDPHeaderCodec.decode(from: &buf) {
                let responseEndpoint = NWHostEndpoint(hostname: decoded.host,
                                                       port: "\(decoded.port)")
                var payloadData = Data()
                if let bytes = decoded.payload.getBytes(at: decoded.payload.readerIndex,
                                                         length: decoded.payload.readableBytes) {
                    payloadData = Data(bytes)
                }
                self.flow.writeDatagrams([payloadData], sentBy: [responseEndpoint]) { error in
                    if error != nil { self.cleanup() }
                }
            }
            // Continue reading
            self.readFromProxy()
        }
    }

    // MARK: - Idle timeout

    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + Self.idleTimeout)
        timer.setEventHandler { [weak self] in
            self?.logger.info("UDP flow idle timeout")
            self?.cleanup()
        }
        timer.resume()
        self.idleTimer = timer
    }

    private func resetIdleTimer() {
        idleTimer?.schedule(deadline: .now() + Self.idleTimeout)
    }

    private func cleanup() {
        idleTimer?.cancel()
        idleTimer = nil
        connection?.cancel()
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
    }
}
```

- [ ] **Step 6: Build KnotHelperExtension**

```bash
xcodebuild -scheme KnotHelperExtension -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 7: Commit**

```bash
git add KnotHelperExtension/
git commit -m "feat: implement NETransparentProxyProvider with TCP CONNECT relay and UDP header forwarding"
```

---

### Task 5: Integration testing and IPC wiring

**Files:**
- Modify: `KnotApp-macOS/Services/macOSTunnelService.swift` — publish app.status via IPC

- [ ] **Step 1: Add IPC status publishing to main app**

In `macOSTunnelService.swift`, after `state.status = .connected(...)`:
```swift
let ipc = AppGroupIPC(groupIdentifier: "group.Lojii.NIO1901")
ipc.passMessage("running", identifier: "app.status")
```

After `state.status = .disconnected`:
```swift
ipc.passMessage("stopped", identifier: "app.status")
```

- [ ] **Step 2: Build all targets**

```bash
xcodebuild -scheme KnotHelper -destination 'platform=macOS' build 2>&1 | tail -10
xcodebuild -scheme KnotApp-macOS -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 3: Manual integration test — TCP**

1. Start Knot.app (proxy on 8034)
2. Start KnotHelper.app → click Enable → approve System Extension
3. Open Safari, visit `http://example.com`
4. Verify: request appears in Knot capture list

- [ ] **Step 4: Manual integration test — UDP**

1. With both apps running and Helper enabled
2. Run: `dig @8.8.8.8 example.com` (DNS over UDP)
3. Verify: UDP datagram appears in Knot capture with host `8.8.8.8:53`

- [ ] **Step 5: Verify anti-loop**

1. With Helper enabled, verify Knot.app's own outbound connections are NOT intercepted
2. Verify no connection loops in Console.app logs

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: wire IPC status publishing and complete integration

Main app publishes running/stopped status via App Group.
Helper reads it to show main app connection status."
```

---

## Summary

| Task | Description | Phase | Complexity |
|------|-------------|-------|------------|
| 1 | UDPHeaderCodec (encode/decode) | Phase 1 | Low |
| 2 | UDPReceiver + dispatch + MitmService wiring | Phase 1 | Medium |
| 3 | KnotHelper app (targets + UI + ViewModel) | Phase 2 | Medium |
| 4 | TransparentProxyProvider + TCP/UDP handlers | Phase 3 | High |
| 5 | Integration testing + IPC wiring | Phase 4 | Medium |

## Known Limitations & Notes

- **Entitlement value:** `app-proxy-provider` is used for `NETransparentProxyProvider` (it's a subclass of `NEAppProxyProvider`). If extension fails to load, try `transparent-proxy` as alternative.
- **PacketTunnel coexistence:** Only one should be active at a time. Helper UI should detect and warn.
- **SIP:** During development, System Extensions require either Developer ID signing or SIP disabled (`csrutil disable`).
- **UDP plugin processing:** Task 2's `UDPDispatchHandler` records datagrams but doesn't fully process them through plugins yet. Full UDP plugin pipeline (DNS decoding, QUIC MITM) is a follow-up.
- **Xcode target creation (Task 3 Step 1):** Must be done manually in Xcode — cannot be fully automated via CLI.
