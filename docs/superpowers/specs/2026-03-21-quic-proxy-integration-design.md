# QUIC/HTTP3 ProxyServer Integration Design (Phase 2)

**Goal:** Add UDP listening to ProxyServer so it can receive, MITM-intercept, and forward QUIC/HTTP3 traffic — enabling H3 capture without requiring the NetworkExtension system extension.

**Approach:** Add a NIO `DatagramBootstrap` UDP listener to ProxyServer. A `QUICProxyHandler` on the client-facing DatagramChannel routes incoming QUIC packets through the existing (tested) `QUICMITMManager`. Per-session outbound DatagramChannels forward MITM-processed packets to real servers. Responses flow back through `QUICServerForwarder` on the outbound channels.

**Depends on:** Phase 1 (QUIC MITM testing) — `QUICMITMManager` is tested and working.

---

## Architecture

### Current (TCP only)

```
Client → TCP → ProxyServer (ServerBootstrap :8080) → ProtocolDispatcher → Real Server
```

### New (TCP + UDP)

```
Client → TCP → ProxyServer (ServerBootstrap :8080) → ProtocolDispatcher → Real Server
Client → UDP → ProxyServer (DatagramBootstrap :8443) → QUICProxyHandler → QUICMITMManager
                                                          ↓ toApp → back to Client
                                                          ↓ toServer → Outbound DatagramChannel → Real Server
                                                                         ↓ response
                                                                       QUICServerForwarder → QUICMITMManager
                                                                         ↓ toApp → back to Client
```

### Data Flow

1. Client sends QUIC Initial packet (UDP) to proxy's UDP port
2. `QUICProxyHandler.channelRead` receives `AddressedEnvelope<ByteBuffer>`
3. Extract target from SNI in QUIC Initial (or use default target for testing)
4. Call `QUICMITMManager.processOutbound(data, dstIP, dstPort)` → `(toApp, toServer)`
5. `toApp` packets: write back to client via client DatagramChannel
6. `toServer` packets: forward to real server via per-session outbound DatagramChannel
7. `QUICServerForwarder.channelRead` on outbound channel receives server response
8. Call `QUICMITMManager.processInbound(data, srcIP, srcPort)` → `toApp`
9. `toApp` packets: write back to client via client DatagramChannel

---

## New Components

### QUICProxyHandler

NIO `ChannelInboundHandler` on the client-facing UDP DatagramChannel.

```swift
final class QUICProxyHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let task: CaptureTask
    private let mitmManager: QUICMITMManager
    private weak var clientChannel: Channel?

    // Per-server outbound channels: "ip:port" → Channel
    private var serverChannels: [String: Channel] = [:]

    // Client address tracking: connectionId → clientAddr
    private var clientAddresses: [Data: SocketAddress] = [:]

    // For testing: skip SNI resolution, use fixed target
    var defaultTarget: (host: String, port: Int)?
}
```

**Target resolution:**
- First QUIC Initial from a new connection: extract SNI via `QUICDecoder.extractSNI()`
- DNS-resolve SNI to IP address (synchronous `getaddrinfo` on EL, or cache)
- Port is always 443 (QUIC standard)
- For tests: `defaultTarget` overrides SNI resolution

**Outbound channel management:**
- One outbound DatagramChannel per unique `(serverIP, serverPort)`
- Created lazily on first packet to that server
- Bound to `0.0.0.0:0` (ephemeral port)
- `QUICServerForwarder` installed as handler, holds weak ref to client channel + client address

**Idle cleanup:**
- 30-second timer scans `serverChannels`, closes channels with no recent activity
- Mirrors `OutboundConnectionPool` idle eviction pattern

### QUICServerForwarder

NIO `ChannelInboundHandler` on each outbound DatagramChannel (facing the real server).

```swift
final class QUICServerForwarder: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private let mitmManager: QUICMITMManager
    private weak var clientChannel: Channel?
    private let clientAddr: SocketAddress
    private let serverIP: String
    private let serverPort: UInt16
}
```

Receives server responses → calls `mitmManager.processInbound()` → writes decrypted packets back to client via `clientChannel`.

### ProxyConfig Extension

```swift
public enum QUIC {
    /// UDP port for QUIC proxy (transparent mode)
    public static var udpPort: Int = 8443
}
```

### ProxyServer Extension

In `ProxyServer.start()`, after TCP bind:

```swift
if ProxyConfig.HTTP3.enabled && task.sslEnable == 1 {
    let certPath = task.certManager.certPath  // CA cert PEM
    let keyPath = task.certManager.keyPath     // CA key PEM
    let mitmManager = QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)

    let udpBootstrap = DatagramBootstrap(group: workerGroup)
        .channelInitializer { channel in
            channel.pipeline.addHandler(
                QUICProxyHandler(task: task, mitmManager: mitmManager)
            )
        }

    let udpChannel = try udpBootstrap.bind(host: host, port: ProxyConfig.QUIC.udpPort).wait()
    self.udpChannel = udpChannel
    task.connectionPool.startEviction(on: workerGroup.next())  // reuse existing pool eviction
}
```

Stop method extended to close `udpChannel`.

---

## File Structure

### New Files (Source)
- `Sources/TunnelServices/Proxy/QUICProxyHandler.swift` — Client-facing UDP handler + target resolution + outbound channel management
- `Sources/TunnelServices/Proxy/QUICServerForwarder.swift` — Server-facing UDP handler + response relay

### Modified Files (Source)
- `Sources/TunnelServices/Proxy/ProxyServer.swift` — Add DatagramBootstrap for UDP
- `Sources/TunnelServices/Config/ProxyConfig.swift` — Add `QUIC.udpPort`

### New Files (Test)
- `Tests/TunnelServicesTests/Integration/QUIC/QUICProxyTests.swift` — UDP port + packet routing tests

### Modified Files (Test)
- `Tests/TunnelServicesTests/Integration/QUIC/TestInfrastructure/TestQUICServer.swift` — Add real UDP mode (bind port, receive/send via DatagramChannel)
- `Tests/TunnelServicesTests/Integration/QUIC/TestInfrastructure/TestQUICClient.swift` — Add real UDP mode (send/receive via DatagramChannel)

---

## Testing Strategy

Phase 1 already validates `QUICMITMManager` correctness (37 tests). Phase 2 tests focus on the NIO DatagramChannel plumbing:

| Test | What it validates |
|------|-------------------|
| `testUDPProxy_BindAndReceive` | DatagramBootstrap binds, receives a raw UDP packet, handler fires |
| `testUDPProxy_QUICHandshake` | TestQUICClient sends QUIC Initial via real UDP → proxy → QUICMITMManager → outbound channel → TestQUICServer (real UDP) → response flows back → handshake completes |
| `testUDPProxy_H3Request` | After handshake, H3 GET → response received by client |
| `testUDPProxy_MultiSession` | 3 clients with different connection IDs → 3 independent sessions |
| `testUDPProxy_OutboundChannelCreation` | First packet creates outbound channel; second packet to same server reuses it |
| `testUDPProxy_FlowRecording` | After H3 request, FlowDAO/QuicConnectionDAO have records |

### Test infrastructure extensions:

**TestQUICServer — real UDP mode:**
```swift
class TestQUICServer {
    enum Mode {
        case inMemory        // existing: receive/return Data directly
        case udp(port: Int)  // new: bind DatagramChannel, receive/send via UDP
    }
}
```

**TestQUICClient — real UDP mode:**
```swift
class TestQUICClient {
    enum Mode {
        case inMemory                    // existing
        case udp(proxyHost: String, proxyPort: Int)  // new: send via DatagramChannel to proxy
    }
}
```

---

## Error Handling

- **SNI extraction failure:** If Initial packet has no SNI and no `defaultTarget`, drop packet and log
- **DNS resolution failure:** Log error, drop packet, MITM manager creates fallback entry
- **Outbound channel bind failure:** Log, return empty toServer (MITM falls back)
- **Client disconnect:** Outbound channel cleanup via idle timer (no explicit disconnect signal in UDP)
- **Server unreachable:** Outbound channel receives no responses; session times out via QUIC idle timeout (30s)

---

## Out of Scope

- pf/iptables rule generation (user configures transparent redirect separately)
- CONNECT-UDP (RFC 9298) support
- SOCKS5 UDP ASSOCIATE
- 0-RTT session resumption
- Connection migration (QUIC allows IP changes mid-connection)
