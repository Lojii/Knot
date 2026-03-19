# macOS HTTP/3 QUIC MITM Design

## Summary

Enable HTTP/3 packet capture on macOS by compiling quiche and lsquic for macOS (arm64 + x86_64), adding macOS slices to existing xcframeworks, and integrating `QUICMITMManager` / `LsquicMITMManager` into `PacketCaptureEngine`. Failed MITM sessions fall back to transparent UDP forwarding.

## Context

- iOS already has full QUIC MITM via `QUICMITMHandler` (quiche) and `LsquicMITMHandler` (lsquic)
- All Swift code is behind `#if canImport(SwiftQuiche)` / `#if canImport(SwiftLsquic)` guards with stubs
- `CQuiche.xcframework` and `CLsquic.xcframework` only contain `ios-arm64` and `ios-arm64-simulator` slices
- `TunnelServices/Package.swift` restricts QUIC dependencies to iOS via `.when(platforms: [.iOS])`
- `PacketCaptureEngine` currently logs QUIC headers and forwards UDP:443 via `udpForwarder` without MITM
- Existing iOS build scripts: `Scripts/build_quiche_xcframework.sh`, `Scripts/build_lsquic_xcframework.sh`

## Approach

Extend existing xcframeworks with macOS Universal slices, remove platform restrictions, and wire MITM managers into `PacketCaptureEngine`. This reuses 100% of existing iOS MITM Swift code.

## Design

### 1. Build Scripts

Extend the two existing iOS build scripts with `--platform macos` support, and add a combined rebuild script:

**`Scripts/build_quiche_xcframework.sh --platform macos`**
- Reuses existing clone + iOS build logic
- Adds macOS targets: `cargo build --release --features ffi` for:
  - `aarch64-apple-darwin` (arm64)
  - `x86_64-apple-darwin` (Intel)
- `lipo -create` into Universal `libquiche.a`
- Copies `quiche.h` header + `module.modulemap`

**`Scripts/build_lsquic_xcframework.sh --platform macos`**
- Reuses existing clone + iOS build logic
- Adds macOS CMake builds:
  - `-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_SYSTEM_NAME=Darwin`
  - `-DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_SYSTEM_NAME=Darwin`
- **BoringSSL symbol collision prevention**: Build lsquic's bundled BoringSSL with `-DBORINGSSL_PREFIX=lsquic_` to prefix all exported symbols (`SSL_*` → `lsquic_SSL_*`, `EVP_*` → `lsquic_EVP_*`). This avoids duplicate symbol conflicts with swift-nio-ssl's `CNIOBoringSSL` which is linked into the same System Extension binary.
- `lipo -create` for `liblsquic.a` (BoringSSL statically linked with prefix)
- Copies `lsquic.h`, `lsquic_types.h` + `module.modulemap`

**`Scripts/rebuild_xcframeworks.sh`** (NEW)
- Calls both scripts with `--platform all` (iOS + macOS)
- Uses `xcodebuild -create-xcframework` to combine all slices
- Outputs to `Frameworks/CQuiche.xcframework` and `Frameworks/CLsquic.xcframework`

### 1a. BoringSSL Symbol Collision Mitigation

The macOS System Extension links both `swift-nio-ssl` (CNIOBoringSSL) and lsquic into a single binary. Both vendor BoringSSL, causing duplicate `SSL_*`/`EVP_*`/`BN_*` symbols.

**Solution**: Build lsquic's BoringSSL with `-DBORINGSSL_PREFIX=lsquic_`:
```bash
cmake ../third_party/boringssl \
    -DBORINGSSL_PREFIX=lsquic_ \
    -DBORINGSSL_PREFIX_SYMBOLS=../third_party/boringssl/util/SYMBOLS.txt \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_SYSTEM_NAME=Darwin
```

This is a standard BoringSSL feature — the `SYMBOLS.txt` file lists all public symbols, and the prefix flag generates a header that `#define`s each to a prefixed version. lsquic picks up the prefixed symbols via includes. No source patches needed.

Note: quiche does NOT have this problem — it statically links its own BoringSSL copy inside `libquiche.a` with Rust symbol mangling, so no C-level symbol conflicts.

### 2. xcframework Structure (After)

```
CQuiche.xcframework/
├── ios-arm64/
│   └── libCQuiche.a + Headers/ + module.modulemap
├── ios-arm64-simulator/
│   └── libCQuiche.a + Headers/ + module.modulemap
├── macos-arm64_x86_64/              ← NEW
│   └── libCQuiche.a (Universal)
│       └── Headers/CQuiche/quiche.h + module.modulemap
└── Info.plist

CLsquic.xcframework/
├── ios-arm64/
│   └── libCLsquic.a + Headers/ + module.modulemap
├── ios-arm64-simulator/
│   └── libCLsquic.a + Headers/ + module.modulemap
├── macos-arm64_x86_64/              ← NEW
│   └── libCLsquic.a (Universal, BoringSSL prefixed)
│       └── Headers/CLsquic/lsquic.h, lsquic_types.h + module.modulemap
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

// connIds that failed MITM → transparent forwarding. Key = connId, Value = expiry timestamp.
private var fallbackConnections = [Data: TimeInterval]()
private let fallbackLock = NSLock()
```

#### New Methods

- `setupQUICMITM(task:certPath:keyPath:)` — initializes the selected MITM manager based on `ProxyConfig.HTTP3.backend`
- `shutdownQUICMITM()` — tears down active sessions

#### Concurrency Model

All MITM manager calls happen on the `packetFlow.readPackets` callback queue (provider main queue). The MITM managers (`QUICMITMManager`, `LsquicMITMManager`) use internal `NSLock` for session map access. `QUICMITMSession` methods are NOT thread-safe — this is OK because both outbound processing and the `udpForwarder` response callback are dispatched onto the same serial processing queue via `DispatchQueue(label: "com.knot.quic.mitm")` added to `PacketCaptureEngine`. All MITM session access is serialized through this queue.

#### Modified: processUDPPacket (port 443 branch)

```
UDP dst:443 arrives
  │
  ├─ HTTP3.enabled == false → drop packet (force HTTP/2 fallback)
  │
  ├─ HTTP3.enabled == true
  │   │
  │   ├─ connId in fallbackConnections (and not expired)? → transparent forwarding (udpForwarder)
  │   │
  │   └─ MITM Manager path
  │       ├─ processOutbound() succeeds
  │       │   ├─ toApp packets → IPPacketBuilder.buildUDPResponse + delegate.writePacket
  │       │   └─ toServer packets → udpForwarder.sendRaw()
  │       │
  │       └─ processOutbound() fails
  │           ├─ Add connId to fallbackConnections with TTL
  │           └─ Forward this and future packets via udpForwarder
```

#### Inbound Path: UDP:443 Response Handling

**Important**: Inbound UDP responses do NOT arrive via `processInboundPacket()`. They arrive via the `udpForwarder.forward()` completion callback (line 240 of PacketCaptureEngine.swift). The integration point for MITM inbound is inside this callback:

```
udpForwarder.forward(packet) callback fires with responseData
  │
  ├─ HTTP3.enabled == false OR connId in fallbackConnections
  │   → Normal path: buildUDPResponse + writePacket (existing behavior)
  │
  └─ Active MITM session exists
      ├─ Dispatch to quicMITMQueue (serial queue)
      ├─ mitmManager.processInbound(responseData, srcIP, srcPort)
      ├─ toApp packets → buildUDPResponse + delegate.writePacket
      └─ toServer packets (if any) → udpForwarder.sendRaw()
```

For fallback connections, the existing `udpForwarder` path is used unchanged — server responses flow through to the client transparently.

#### Fallback Cleanup

- `fallbackConnections` uses `[Data: TimeInterval]` — value is expiry timestamp (`Date().timeIntervalSince1970 + 30`)
- Lazy cleanup: on each `processUDPPacket` call for port 443, expired entries are removed (amortized O(1))
- Additional cleanup on `shutdownQUICMITM()`

#### Session Limit

- Active sessions ≥ `ProxyConfig.HTTP3.maxSessions` (20) → new connections enter fallback directly

#### Short Header DCID Length

`QUICDecoder.parseShortHeader()` uses a heuristic of `min(8, data.count - 1)` for DCID length. After the QUIC handshake, all packets use short headers. If the actual DCID length differs from 8, session lookup may fail. To address this:
- `QUICMITMManager` maintains a `[Data: QUICMITMSession]` session map keyed by DCID
- On session creation (from Initial packet, which has explicit DCID length), the actual DCID length is recorded
- `PacketCaptureEngine` passes the full UDP payload to the MITM manager, which tries lookup with the known DCID length first, falling back to the 8-byte heuristic
- If both lookups miss, the packet goes to fallback (transparent forwarding) — no data loss

### 5. MacPacketTunnelProvider Adaptation

#### CaptureTask Lifecycle

`setupQUICMITM` requires a valid `CaptureTask`. On macOS, `mitmServer.task` is initialized during `MitmService.prepare()` and is valid after `mitmServer.run()` succeeds. However, the task represents a user-initiated capture session — if the tunnel starts without an active task, MITM initialization is deferred.

The `enable_h3` IPC command handles deferred init: when the user enables HTTP/3 at runtime, the command checks for a valid task and initializes the MITM manager at that point.

#### Startup (in startTunnel, after mitmServer.run succeeds)

```swift
if ProxyConfig.HTTP3.enabled, let task = mitmServer?.task, task.isActive {
    let certPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caCert
    let keyPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caKey
    captureEngine.setupQUICMITM(task: task,
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
| QUIC Version Negotiation | `parseHeader` returns version 0 / `.unknown` type | connId → fallback |
| Non-HTTP/3 ALPN | Handshake completes but ALPN ≠ `h3` | connId → fallback |

### 8. lsquic Packet Output Fix

`LsquicMITMHandler.processClientPacket()` and `processServerPacket()` currently return empty arrays (`[]`). Outbound packets are emitted via the `onPacketsOut` callback, but this callback is not wired to return packets to the caller. This must be fixed for lsquic backend to function on macOS (and iOS).

**Fix**: Buffer packets emitted by `onPacketsOut` during a `processClientPacket` / `processServerPacket` call, then return them as the method's return value. This is a change to `LsquicMITMHandler.swift` (moves from "Files NOT Changed" to "Files Changed").

### 9. Known Limitations

- **IPv6 QUIC**: `IPPacketBuilder.buildUDPResponse` only handles IPv4. IPv6 QUIC response packets will be empty. This is a pre-existing limitation in the packet builder, not introduced by this design. IPv6 support can be added as a follow-up.
- **Distribution model**: This design assumes Developer ID / direct distribution. App Store distribution would require `com.apple.security.app-sandbox` entitlement in the System Extension, which may restrict cert/key file access paths. Not in scope.

### 10. Logging

- MITM established: `AxLogger.log("QUIC MITM session established: \(sni)", level: .Info)`
- Fallback triggered: `AxLogger.log("QUIC MITM fallback for \(connId.hex): \(reason)", level: .Warning)`
- Session closed: `AxLogger.log("QUIC MITM session closed: \(sni), streams=\(count)", level: .Info)`

## Files Changed

| File | Change |
|---|---|
| `Scripts/build_quiche_xcframework.sh` | MODIFY — add `--platform macos` flag for macOS Universal build |
| `Scripts/build_lsquic_xcframework.sh` | MODIFY — add `--platform macos` flag + BoringSSL prefix build |
| `Scripts/rebuild_xcframeworks.sh` | NEW — combined script to build all platforms + assemble xcframeworks |
| `Frameworks/CQuiche.xcframework` | ADD macOS arm64_x86_64 slice + modulemap |
| `Frameworks/CLsquic.xcframework` | ADD macOS arm64_x86_64 slice (prefixed BoringSSL) + modulemap |
| `LocalPackages/TunnelServices/Package.swift` | REMOVE `.when(platforms: [.iOS])` from QUIC deps |
| `LocalPackages/TunnelServices/.../PacketCaptureEngine.swift` | ADD MITM manager integration + fallback logic + serial queue |
| `LocalPackages/TunnelServices/.../LsquicMITMHandler.swift` | FIX packet output — buffer `onPacketsOut` and return from process methods |
| `SystemExtension-macOS/MacPacketTunnelProvider.swift` | ADD MITM init/shutdown + IPC commands |

## Files NOT Changed

- `QUICMITMHandler.swift` — works as-is once `canImport` resolves
- `SwiftQuiche/` package — works as-is with macOS slice
- `SwiftLsquic/` package — works as-is with macOS slice
- `ProxyConfig.swift` — existing config sufficient
- `SessionRecorder`, `FlowDAO`, `QuicConnectionDAO`, `QuicStreamDAO` — reused as-is
