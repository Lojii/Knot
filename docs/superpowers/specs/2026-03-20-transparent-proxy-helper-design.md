# Transparent Proxy Helper App Design

## Goal

Create a standalone macOS helper app (KnotHelper) containing a NETransparentProxyProvider System Extension that intercepts TCP and UDP traffic at the OS level and forwards it to the main Knot app's proxy port for capture and analysis.

## Architecture

KnotHelper is an independent app installed alongside Knot.app. It contains a System Extension that uses `NETransparentProxyProvider` to intercept application-layer TCP and UDP flows. TCP flows are relayed directly to Knot's existing HTTP/SOCKS5 proxy (TCP:8034). UDP flows are forwarded with a small header containing the destination address to Knot's new UDP listener (UDP:8034). The main Knot app parses the header and routes UDP data through its existing plugin architecture (DNS/QUIC/NTP).

Communication between KnotHelper and Knot uses the existing App Group IPC mechanism (`group.Lojii.NIO1901`) for configuration sync.

## Scope

**In scope:**
- KnotHelper app with lightweight UI (window with on/off, TCP/UDP toggles, status)
- NETransparentProxyProvider System Extension for TCP and UDP interception
- UDP header codec for destination address encapsulation
- UDP receiver in main Knot app (DatagramBootstrap on port 8034)
- App Group IPC for configuration sync

**Out of scope:**
- Modifying existing TCP proxy pipeline (ProtocolDispatcher handles TCP as-is)
- Modifying existing SystemExtension-macOS (PacketTunnel) — coexists independently
- App Store distribution concerns (independent distribution assumed)
- iOS (macOS only)

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Extension type | NETransparentProxyProvider | App-layer flow interception, natural TCP/UDP separation, no TUN interface, no system route changes |
| Relationship to existing PacketTunnel | Coexist independently | Different purposes, no interference |
| UDP data format | Raw datagram with header | Self-contained, no separate control channel needed |
| UDP port | Same as TCP (8034) | TCP and UDP are different protocol stacks, same port number doesn't conflict |
| TCP forwarding method | HTTP CONNECT to main app proxy | Main app already handles CONNECT, zero additional code needed |
| IPC mechanism | App Group UserDefaults + Darwin notifications | Already implemented (`AppGroupIPC`), proven to work |
| Helper distribution | Bundled in main app DMG | Single download, optional install |

---

## Section 1: Overall Architecture

```
┌──────────────────────────────────────┐
│  KnotHelper.app (/Applications)       │
│  ├── UI: Window (on/off, TCP/UDP)     │
│  └── SystemExtension:                 │
│      NETransparentProxyProvider       │
│      │                                │
│      ├── handleNewFlow(TCPFlow)       │
│      │   → HTTP CONNECT to :8034     │
│      │   → bidirectional relay        │
│      │                                │
│      └── handleNewFlow(UDPFlow)       │
│          → prepend address header     │
│          → send UDP to :8034          │
│          → receive response → client  │
└──────────┬───────────────────────────┘
           │ localhost:8034
           ▼
┌──────────────────────────────────────┐
│  Knot.app (main app)                  │
│  ├── TCP:8034  HTTP/SOCKS5 proxy      │  ← existing
│  ├── UDP:8034  UDP receiver           │  ← new
│  │   → parse header → restore dest    │
│  │   → match UDP plugin tree          │
│  │   → DNS / QUIC / NTP / Raw         │
│  └── App Group IPC                    │
│      group.Lojii.NIO1901             │
└──────────────────────────────────────┘
```

### Coexistence with PacketTunnel

The existing SystemExtension-macOS (NEPacketTunnelProvider) is a separate extension. **Only one should be active at a time.** When the PacketTunnel VPN is active, it routes all traffic through a TUN interface — if the Helper's transparent proxy is also active, traffic would be intercepted twice. The Helper UI should check `NETunnelProviderManager` status and warn/disable when the PacketTunnel is running. Similarly, the main app's System Extension toggle should disable the Helper if it's running.

---

## Section 2: UDP Header Format

Every UDP datagram forwarded from Helper to main app is prefixed with a destination address header:

```
┌─────────┬──────────────────┬─────────┬─────────────────┐
│ addrType│ destination addr │  port   │  original UDP   │
│ (1 byte)│ (variable)       │(2 bytes)│  payload        │
└─────────┴──────────────────┴─────────┴─────────────────┘
```

### Address types (reuses SOCKS5 encoding)

| addrType | Address field | Total header size |
|----------|--------------|-------------------|
| `0x01` (IPv4) | 4 bytes | 7 bytes |
| `0x04` (IPv6) | 16 bytes | 19 bytes |
| `0x03` (Domain) | 1 byte length + domain string | 4 + domain length |

Port is big-endian (network byte order).

### Examples

DNS query to 8.8.8.8:53:
```
[01] [08 08 08 08] [00 35] [DNS query bytes...]
```

QUIC to [2001:4860:4860::8888]:443:
```
[04] [20 01 48 60 48 60 00 00 00 00 00 00 00 00 88 88] [01 BB] [QUIC bytes...]
```

### Response format

Responses from main app back to Helper use the same header format. Helper parses the header to determine which `NEAppProxyUDPFlow` to write the response to.

### Flow multiplexing

Each `NEAppProxyUDPFlow` on the Helper side opens its own `NWConnection` to 127.0.0.1:8034 with a distinct ephemeral source port. The main app's `UDPReceiver` tracks the `remoteAddress` (IP:port) of each incoming datagram. When sending a response, the main app sends it back to that same `remoteAddress`, which routes it to the correct `NWConnection` on the Helper side and thus the correct `NEAppProxyUDPFlow`.

This means no flow-ID is needed in the header — the OS-level source port serves as the natural flow identifier.

### Idle timeout

UDP flows with no activity (no datagram in either direction) for 30 seconds are cleaned up. The Helper closes the `NWConnection` and cancels the `NEAppProxyUDPFlow`. The main app's `UDPReceiver` evicts stale entries from its response routing table after the same timeout.

### No length field

UDP datagrams are message-oriented — one send = one receive. No framing or length prefix needed.

### Header size summary

All sizes are header-only (payload follows immediately). Formula: `1 (addrType) + address_bytes + 2 (port)`.

---

## Section 3: NETransparentProxyProvider

### Core class: TransparentProxyProvider

```swift
class TransparentProxyProvider: NETransparentProxyProvider {

    override func startProxy(options: [String: Any]?, completionHandler: @escaping (Error?) -> Void) {
        // Read config from App Group UserDefaults
        // Initialize connection state
        completionHandler(nil)
    }

    // TCP flows
    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let tcpFlow = flow as? NEAppProxyTCPFlow else { return false }
        guard !isExcludedApp(flow) else { return false }
        guard !isLoopback(flow) else { return false }
        return shouldForwardTCP ? handleTCP(tcpFlow) : false
    }

    // UDP flows — note: NETransparentProxyProvider may call this separate override
    // instead of handleNewFlow for UDP. Implement both to be safe.
    override func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow,
                                    initialRemoteEndpoint remoteEndpoint: NWEndpoint) -> Bool {
        guard !isExcludedApp(flow) else { return false }
        guard !isLoopback(flow) else { return false }
        return shouldForwardUDP ? handleUDP(flow) : false
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Clean up connections
        completionHandler()
    }
}
```

### TCP flow handling

```
TCPFlow arrives
  → flow.open() to get remote endpoint
  → Create NWConnection to 127.0.0.1:8034
  → Send: "CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n"
  → Wait for "200 Connection Established"
  → Bidirectional relay: flow.readData ↔ connection.send
  → On flow close or error: clean up both sides
```

Using HTTP CONNECT means the main app's existing pipeline handles everything:
1. `ProtocolDispatcher` matches "CONN..." → `HTTP1Plugin`
2. `HTTP1Plugin.buildPipeline()` adds HTTP decoder + `HTTPCaptureHandler`
3. `HTTPCaptureHandler` sees CONNECT method → hands off to `ConnectHandler`
4. `ConnectHandler` sends 200, sets up TLS/tunnel for the inner connection

No new TCP handling code needed in the main app.

### UDP flow handling

```
UDPFlow arrives
  → flow.open()
  → Create NWConnection (UDP) to 127.0.0.1:8034
  → Read loop:
      datagrams = flow.readDatagrams()
      for each (data, endpoint):
        header = UDPHeaderCodec.encode(endpoint)
        connection.send(header + data)
  → Receive loop:
      connection.receive():
        (dstAddr, payload) = UDPHeaderCodec.decode(data)
        flow.writeDatagrams([payload], sentBy: [dstAddr])
  → On flow close: clean up connection
```

### Anti-loop exclusions

The extension MUST exclude these to prevent infinite loops:
- Flows from `com.KingMap.KnotApp-macOS` (main app making outbound connections)
- Flows from `com.KingMap.KnotHelper` (helper app itself)
- Flows to `127.0.0.0/8` (localhost — the forwarding destination)

Check via `flow.metaData.sourceAppSigningIdentifier` and remote endpoint.

---

## Section 4: Main App Changes (UDP Receiver)

### New: UDPReceiver

A NIO DatagramChannel that listens on UDP:8034, parses the header, and routes to the plugin tree.

```swift
class UDPReceiver {
    func start(group: EventLoopGroup, task: CaptureTask) {
        DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(UDPDispatchHandler(task: task))
            }
            .bind(host: "127.0.0.1", port: ProxyConfig.LocalProxy.port)
    }
}

class UDPDispatchHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let senderAddress = envelope.remoteAddress  // Helper's address (for responses)

        // 1. Decode header
        let (dstHost, dstPort, payload) = UDPHeaderCodec.decode(envelope.data)

        // 2. Create SessionRecorder
        let recorder = SessionRecorder(task: task)

        // 3. Match against UDP plugin tree
        let udpChildren = ProtocolRegistry.shared.udpChildren
        // ... match and dispatch (similar to ProtocolDispatcher but for datagrams)

        // 4. Store senderAddress for response routing
    }
}
```

### Integration with MitmService

```swift
// In MitmService.run():
// After starting TCP server (existing), also start UDP receiver:
udpReceiver = UDPReceiver()
udpReceiver.start(group: workerGroup, task: task)
```

### What changes in existing code

| Component | Change |
|-----------|--------|
| `MitmService.swift` | Add `UDPReceiver` startup in `run()` |
| `ProxyConfig.swift` | Add `UDP` section (port shares with LocalProxy.port) |
| `ProtocolRegistry.swift` | Add `udpChildren` accessor (mirrors `tcpChildren`) |
| New `UDP/UDPReceiver.swift` | DatagramBootstrap + dispatch handler |
| New `UDP/UDPHeaderCodec.swift` | Encode/decode header (shared with Helper Extension) |

### What does NOT change

- ProtocolDispatcher (TCP only, unchanged)
- Existing TCP proxy pipeline
- Plugin architecture (UDP plugins already registered in tree)
- Storage layer (SessionRecorder already supports non-HTTP recording)

---

## Section 5: Helper App UI & IPC

### Window layout (~300x200)

```
┌─────────────────────────────┐
│  Knot Network Helper        │
├─────────────────────────────┤
│                             │
│  Status: ● Connected        │
│                             │
│  Forward mode:              │
│  ☑ TCP    ☑ UDP             │
│                             │
│  App port: [8034]           │
│                             │
│  [ Enable ] / [ Disable ]   │
│                             │
│  Main app: ● Running        │
└─────────────────────────────┘
```

### IPC via App Group

Uses existing `AppGroupIPC` (UserDefaults + Darwin notifications) through `group.Lojii.NIO1901`.

| Key | Direction | Type | Description |
|-----|-----------|------|-------------|
| `helper.enabled` | Helper → App | Bool | Extension is active |
| `helper.forwardTCP` | Helper → App | Bool | TCP forwarding enabled |
| `helper.forwardUDP` | Helper → App | Bool | UDP forwarding enabled |
| `helper.status` | Helper → App | String | "running" / "stopped" / "error" |
| `helper.port` | Bidirectional | Int | Port to forward to (main app writes, Helper reads) |
| `app.status` | App → Helper | String | "running" / "stopped" |

### Extension lifecycle

```
User clicks "Enable"
  → HelperViewModel calls OSSystemExtensionManager.shared.submitRequest(...)
  → System prompts user to allow extension in System Settings
  → Extension loads → NETransparentProxyManager.shared().saveToPreferences()
  → Start proxy via manager.connection.startVPNTunnel()
  → Update helper.status = "running"

User clicks "Disable"
  → NETransparentProxyManager.shared().connection.stopVPNTunnel()
  → Update helper.status = "stopped"
```

---

## Section 6: Project Structure & Signing

### New targets

| Target | Bundle ID | Product | Entitlements |
|--------|-----------|---------|-------------|
| KnotHelper | `com.KingMap.KnotHelper` | .app | app-proxy-provider, app-groups |
| KnotHelperExtension | `com.KingMap.KnotHelper.Extension` | .systemExtension | app-proxy-provider, app-groups |

### File structure

```
Knot-storage-redesign/
├── KnotHelper/                          ← New: Helper app
│   ├── KnotHelperApp.swift              ← SwiftUI App entry
│   ├── HelperWindow.swift               ← UI window
│   ├── HelperViewModel.swift            ← State + extension install/uninstall
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── KnotHelper.entitlements
│
├── KnotHelperExtension/                 ← New: System Extension
│   ├── main.swift                       ← NEProvider.startSystemExtensionMode()
│   ├── TransparentProxyProvider.swift   ← NETransparentProxyProvider core
│   ├── TCPFlowHandler.swift             ← TCP relay via CONNECT
│   ├── UDPFlowHandler.swift             ← UDP header encapsulation + relay
│   ├── Info.plist
│   └── KnotHelperExtension.entitlements
│
├── LocalPackages/TunnelServices/        ← Existing, minor additions
│   └── Sources/TunnelServices/
│       ├── MitmService.swift            ← Add UDPReceiver startup
│       ├── UDP/                         ← New: UDP subsystem
│       │   ├── UDPReceiver.swift        ← DatagramBootstrap listener
│       │   ├── UDPDispatchHandler.swift ← Header parse + plugin dispatch
│       │   └── UDPHeaderCodec.swift     ← Shared encode/decode
│       └── Config/ProxyConfig.swift     ← Add UDP config section
```

### Entitlements

**KnotHelper.entitlements:**
```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>app-proxy-provider</string>
</array>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.Lojii.NIO1901</string>
</array>
```

**KnotHelperExtension.entitlements:**
```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>app-proxy-provider</string>
</array>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.Lojii.NIO1901</string>
</array>
```

> **Note:** `NETransparentProxyProvider` is a subclass of `NEAppProxyProvider`, so the entitlement value is `app-proxy-provider`. Verify during development — if the extension fails to load, try `transparent-proxy` as an alternative value (Apple documentation is inconsistent on this point).

### Sharing UDPHeaderCodec

KnotHelperExtension depends on the TunnelServices package (same as existing SystemExtension-macOS). This allows `UDPHeaderCodec` to be written once and used by both the Helper Extension and the main app.

### Distribution

KnotHelper.app is included in the Knot DMG alongside Knot.app. Users optionally drag it to /Applications. The main app can display a prompt suggesting installation when UDP capture is needed.

---

## Migration Plan (High-Level)

### Port coexistence note

TCP:8034 and UDP:8034 are different sockets on different protocol stacks — they don't conflict. The `UDPReceiver` binds with `SO_REUSEADDR`. This is standard on macOS and requires no special configuration. The TCP `ServerBootstrap` already sets `SO_REUSEADDR` on its server channel.

### Phase 1: UDP subsystem in main app
- Create `UDP/UDPHeaderCodec.swift` (encode/decode)
- **Unit tests for UDPHeaderCodec** (encode→decode round-trip, IPv4/IPv6/domain, malformed input)
- Create `UDP/UDPReceiver.swift` (DatagramBootstrap)
- Create `UDP/UDPDispatchHandler.swift` (parse + route to plugins)
- Add `udpChildren` to ProtocolRegistry
- Wire UDPReceiver startup in MitmService
- Test with manual UDP sends

### Phase 2: Helper app shell
- Create KnotHelper target (SwiftUI app)
- Create KnotHelperExtension target (System Extension)
- Set up entitlements, Info.plist, bundle IDs
- Implement HelperWindow UI + HelperViewModel
- Implement extension install/uninstall flow

### Phase 3: TransparentProxyProvider
- Implement TransparentProxyProvider (startProxy, handleNewFlow, stopProxy)
- Implement TCPFlowHandler (CONNECT relay)
- Implement UDPFlowHandler (header encapsulation)
- Anti-loop exclusions
- IPC config reading

### Phase 4: Integration & testing
- End-to-end TCP: browser → Helper → Knot → capture
- End-to-end UDP: DNS query → Helper → Knot → capture
- QUIC: browser QUIC → Helper → Knot → QUIC plugin
- Verify no traffic loops
- Verify coexistence with existing PacketTunnel extension
