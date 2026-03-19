# macOS HTTP/3 QUIC MITM Design

## Summary

Enable HTTP/3 packet capture on macOS by compiling quiche and lsquic for macOS (arm64 + x86_64), adding macOS slices to existing xcframeworks, and integrating `QUICMITMManager` / `LsquicMITMManager` into `PacketCaptureEngine`. Failed MITM sessions fall back to transparent UDP forwarding.

## Context

- iOS already has full QUIC MITM via `QUICMITMHandler` (quiche) and `LsquicMITMHandler` (lsquic)
- All Swift code is behind `#if canImport(SwiftQuiche)` / `#if canImport(SwiftLsquic)` guards with stubs
- `CQuiche.xcframework` and `CLsquic.xcframework` only contain `ios-arm64` and `ios-arm64-simulator` slices
- `TunnelServices/Package.swift` restricts QUIC dependencies to iOS via `.when(platforms: [.iOS])`
- `PacketCaptureEngine` currently logs QUIC headers and forwards UDP:443 via `udpForwarder` without MITM

## Approach

Extend existing xcframeworks with macOS Universal slices, remove platform restrictions, and wire MITM managers into `PacketCaptureEngine`. This reuses 100% of existing iOS MITM Swift code.

## Design

### 1. Build Scripts

Three new scripts in `scripts/`:

**`scripts/build-quiche-macos.sh`**
- Clones quiche at pinned tag (e.g. `0.22.0`)
- Builds with `cargo build --release --features ffi` for both targets:
  - `aarch64-apple-darwin` (arm64)
  - `x86_64-apple-darwin` (Intel)
- Merges with `lipo -create` into Universal `libquiche.a`
- Copies `quiche.h` header

**`scripts/build-lsquic-macos.sh`**
- Clones lsquic at pinned tag + boringssl submodule
- CMake builds for each architecture:
  - `-DCMAKE_OSX_ARCHITECTURES=arm64`
  - `-DCMAKE_OSX_ARCHITECTURES=x86_64`
- Merges `liblsquic.a` (+ `libssl.a`, `libcrypto.a`) into Universal binaries
- Copies `lsquic.h`, `lsquic_types.h` headers

**`scripts/rebuild-xcframeworks.sh`**
- Calls both build scripts
- Uses `xcodebuild -create-xcframework` to merge existing iOS slices with new macOS slices
- Outputs to `Frameworks/CQuiche.xcframework` and `Frameworks/CLsquic.xcframework`

### 2. xcframework Structure (After)

```
CQuiche.xcframework/
├── ios-arm64/
├── ios-arm64-simulator/
├── macos-arm64_x86_64/              ← NEW
│   └── libCQuiche.a (Universal)
│       └── Headers/CQuiche/quiche.h
└── Info.plist

CLsquic.xcframework/
├── ios-arm64/
├── ios-arm64-simulator/
├── macos-arm64_x86_64/              ← NEW
│   └── libCLsquic.a (Universal)
│       └── Headers/CLsquic/lsquic.h, lsquic_types.h
└── Info.plist
```

### 3. Package.swift Change

In `LocalPackages/TunnelServices/Package.swift`, remove the platform condition:

```swift
// Before:
.product(name: "SwiftQuiche", package: "SwiftQuiche", condition: .when(platforms: [.iOS])),
.product(name: "SwiftLsquic", package: "SwiftLsquic", condition: .when(platforms: [.iOS])),

// After:
.product(name: "SwiftQuiche", package: "SwiftQuiche"),
.product(name: "SwiftLsquic", package: "SwiftLsquic"),
```

This allows `#if canImport(SwiftQuiche)` and `#if canImport(SwiftLsquic)` to resolve to `true` on macOS, activating existing MITM code.

### 4. PacketCaptureEngine Integration

#### New Properties

```swift
#if canImport(SwiftQuiche)
private var quicheMITMManager: QUICMITMManager?
#endif
#if canImport(SwiftLsquic)
private var lsquicMITMManager: LsquicMITMManager?
#endif

private var fallbackConnections = Set<Data>()  // connIds that failed MITM
private let fallbackLock = NSLock()
```

#### New Methods

- `setupQUICMITM(task:certPath:keyPath:)` — initializes the selected MITM manager based on `ProxyConfig.HTTP3.backend`
- `shutdownQUICMITM()` — tears down active sessions

#### Modified: processUDPPacket (port 443 branch)

```
UDP dst:443 arrives
  │
  ├─ HTTP3.enabled == false → drop packet (force HTTP/2 fallback)
  │
  ├─ HTTP3.enabled == true
  │   │
  │   ├─ connId in fallbackConnections? → transparent forwarding (udpForwarder)
  │   │
  │   └─ MITM Manager path
  │       ├─ processOutbound() succeeds
  │       │   ├─ toApp packets → IPPacketBuilder.buildUDPResponse + delegate.writePacket
  │       │   └─ toServer packets → udpForwarder.sendRaw()
  │       │
  │       └─ processOutbound() fails
  │           ├─ Add connId to fallbackConnections
  │           └─ Forward this and future packets via udpForwarder
```

#### Modified: processInboundPacket (UDP:443)

```
Server UDP:443 response arrives
  │
  ├─ connId in fallbackConnections → write directly to client
  │
  └─ Active MITM session exists
      ├─ mitmManager.processInbound(data, srcIP, srcPort)
      ├─ toApp packets → buildUDPResponse + writePacket
      └─ toServer packets (if any) → sendRaw
```

#### Fallback Cleanup

- `fallbackConnections` entries have 30s TTL (matching `ProxyConfig.HTTP3.idleTimeoutMs`)
- Expired entries removed to prevent unbounded growth

#### Session Limit

- Active sessions ≥ `ProxyConfig.HTTP3.maxSessions` (20) → new connections enter fallback directly

### 5. MacPacketTunnelProvider Adaptation

#### Startup (in startTunnel, after mitmServer.run succeeds)

```swift
if ProxyConfig.HTTP3.enabled {
    let certPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caCert
    let keyPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caKey
    captureEngine.setupQUICMITM(task: mitmServer.task,
                                 certPath: certPath, keyPath: keyPath)
}
```

#### App Message Extensions

New IPC commands for runtime control:

| Command | Action |
|---|---|
| `enable_h3` | Set `ProxyConfig.HTTP3.enabled = true`, init MITM manager |
| `disable_h3` | Set `ProxyConfig.HTTP3.enabled = false` |
| `h3_backend_quiche` | Switch to quiche backend |
| `h3_backend_lsquic` | Switch to lsquic backend |

#### Shutdown

`stopTunnel` calls `captureEngine.shutdownQUICMITM()`.

#### No Changes Needed

- `configureTunnel()` — VPN/proxy settings unchanged, UDP flows through tunnel naturally
- `PacketCaptureDelegate` protocol — `writePacket` already sufficient
- `startPacketCapture()` loop — logic unchanged

### 6. Data Recording

Fully reuses iOS recording pipeline. Zero new storage code.

| Data | Recorder | Storage |
|---|---|---|
| HTTP/3 request/response | `SessionRecorder` → `FlowDAO` | proto.db, protocol = "HTTP3" |
| Request/response body | `PayloadWriter` | `{flowId}_req.bin` / `{flowId}_rsp.bin` |
| QUIC connection metadata | `QuicConnectionDAO` | connection.db |
| QUIC streams | `QuicStreamDAO` | connection.db |
| gRPC over HTTP/3 | `GRPCDecoder` (auto-detect `content-type: application/grpc`) | proto.db |

### 7. Fallback Trigger Conditions

| Scenario | Trigger Point | Behavior |
|---|---|---|
| MITM session creation fails | `QUICMITMSession.setup()` returns false | connId → fallback |
| TLS handshake fails | quiche/lsquic handshake error | connId → fallback |
| Active sessions ≥ 20 | `processOutbound` check | connId → fallback |
| Unknown QUIC version | `QUICDecoder.parseHeader()` returns nil | connId → fallback |
| Non-HTTP/3 ALPN | Handshake completes but ALPN ≠ `h3` | connId → fallback |

### 8. Logging

- MITM established: `AxLogger.log("QUIC MITM session established: \(sni)", level: .Info)`
- Fallback triggered: `AxLogger.log("QUIC MITM fallback for \(connId.hex): \(reason)", level: .Warning)`
- Session closed: `AxLogger.log("QUIC MITM session closed: \(sni), streams=\(count)", level: .Info)`

## Files Changed

| File | Change |
|---|---|
| `scripts/build-quiche-macos.sh` | NEW — build quiche for macOS Universal |
| `scripts/build-lsquic-macos.sh` | NEW — build lsquic for macOS Universal |
| `scripts/rebuild-xcframeworks.sh` | NEW — combine iOS + macOS slices |
| `Frameworks/CQuiche.xcframework` | ADD macOS arm64_x86_64 slice |
| `Frameworks/CLsquic.xcframework` | ADD macOS arm64_x86_64 slice |
| `LocalPackages/TunnelServices/Package.swift` | REMOVE `.when(platforms: [.iOS])` from QUIC deps |
| `LocalPackages/TunnelServices/.../PacketCaptureEngine.swift` | ADD MITM manager integration + fallback logic |
| `SystemExtension-macOS/MacPacketTunnelProvider.swift` | ADD MITM init/shutdown + IPC commands |

## Files NOT Changed

- `QUICMITMHandler.swift` — works as-is once `canImport` resolves
- `LsquicMITMHandler.swift` — works as-is once `canImport` resolves
- `SwiftQuiche/` package — works as-is with macOS slice
- `SwiftLsquic/` package — works as-is with macOS slice
- `ProxyConfig.swift` — existing config sufficient
- `SessionRecorder`, `FlowDAO`, `QuicConnectionDAO`, `QuicStreamDAO` — reused as-is
