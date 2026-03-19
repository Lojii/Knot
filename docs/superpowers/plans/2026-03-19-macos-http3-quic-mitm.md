# macOS HTTP/3 QUIC MITM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable HTTP/3 packet capture on macOS by compiling quiche/lsquic for macOS, integrating QUIC MITM managers into PacketCaptureEngine with fallback-to-transparent for failed sessions.

**Architecture:** Extend existing iOS xcframeworks with macOS Universal slices, remove platform guards in Package.swift, wire QUICMITMManager/LsquicMITMManager into PacketCaptureEngine's UDP:443 path with a serial dispatch queue for thread safety, and adapt MacPacketTunnelProvider for MITM lifecycle management.

**Tech Stack:** Swift, SwiftNIO, quiche (Rust/C FFI), lsquic (C), CMake, Cargo, BoringSSL, NEPacketTunnelProvider

**Spec:** `docs/superpowers/specs/2026-03-19-macos-http3-quic-mitm-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Scripts/build_quiche_xcframework.sh` | Modify | Add `--platform macos` for macOS arm64 + x86_64 builds |
| `Scripts/build_lsquic_xcframework.sh` | Modify | Add `--platform macos` + BoringSSL prefix build |
| `Scripts/rebuild_xcframeworks.sh` | Create | Combined script: build all platforms, assemble xcframeworks |
| `LocalPackages/TunnelServices/Package.swift` | Modify | Remove `.when(platforms: [.iOS])` from QUIC deps |
| `LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/PacketCaptureEngine.swift` | Modify | Add MITM integration, fallback logic, serial queue |
| `LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/UDPForwarder.swift` | Modify | Add `sendRaw` method for MITM server-bound packets |
| `LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/LsquicMITMHandler.swift` | Modify | Fix packet output buffering + split toApp/toServer in manager |
| `SystemExtension-macOS/MacPacketTunnelProvider.swift` | Modify | Add MITM init/shutdown + IPC commands |

---

## Task 1: Extend quiche build script for macOS

**Files:**
- Modify: `Scripts/build_quiche_xcframework.sh`

- [ ] **Step 1: Read the existing script to understand current structure**

Read `Scripts/build_quiche_xcframework.sh` (84 lines). It clones quiche, builds for `aarch64-apple-ios` and `aarch64-apple-ios-sim`, prepares headers with modulemap, and creates xcframework.

- [ ] **Step 2: Add platform argument parsing and macOS build targets**

Add positional platform argument (values: `ios`, `macos`, `all`; default: `all`). Usage: `./build_quiche_xcframework.sh macos`. Add macOS builds after the existing iOS builds:

```bash
# Add after line 6 (set -euo pipefail):
PLATFORM="${1:-all}"  # ios, macos, all

# Add after Step 4 (iOS Simulator build, line 52):
# Step 4b: Build for macOS (Universal)
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    echo "--- Build for macOS (aarch64-apple-darwin) ---"
    unset CFLAGS CARGO_TARGET_AARCH64_APPLE_IOS_LINKER CC_aarch64_apple_ios AR_aarch64_apple_ios
    unset CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER CC_aarch64_apple_ios_sim AR_aarch64_apple_ios_sim
    export MACOSX_DEPLOYMENT_TARGET=14.0
    cargo build \
        --package quiche \
        --release \
        --features ffi \
        --target aarch64-apple-darwin \
        2>&1 | tail -5

    echo "--- Build for macOS (x86_64-apple-darwin) ---"
    cargo build \
        --package quiche \
        --release \
        --features ffi \
        --target x86_64-apple-darwin \
        2>&1 | tail -5

    echo "--- Create macOS Universal binary ---"
    mkdir -p target/universal-macos/release
    lipo -create \
        target/aarch64-apple-darwin/release/libquiche.a \
        target/x86_64-apple-darwin/release/libquiche.a \
        -output target/universal-macos/release/libquiche.a
fi
```

- [ ] **Step 3: Update xcframework creation to include macOS slice**

Modify the `xcodebuild -create-xcframework` command to conditionally include the macOS library:

```bash
# Replace existing Step 6 (lines 68-78):
echo "--- Create XCFramework ---"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/CQuiche.xcframework"

XCFW_ARGS=()
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "target/aarch64-apple-ios/release/libquiche.a" -headers "$HEADER_DIR")
    XCFW_ARGS+=(-library "target/aarch64-apple-ios-sim/release/libquiche.a" -headers "$HEADER_DIR")
fi
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "target/universal-macos/release/libquiche.a" -headers "$HEADER_DIR")
fi

xcodebuild -create-xcframework \
    "${XCFW_ARGS[@]}" \
    -output "$OUTPUT_DIR/CQuiche.xcframework"
```

Note: The existing script uses `Quiche.xcframework` at lines 71/78 but the project expects `CQuiche.xcframework`. The Step 3 replacement already uses `CQuiche.xcframework`. Also add `rm -rf "$OUTPUT_DIR/Quiche.xcframework"` to clean up the old name.

- [ ] **Step 4: Verify script syntax**

Run: `bash -n Scripts/build_quiche_xcframework.sh && echo "Syntax OK"`
Expected: "Syntax OK" (no syntax errors). Actual builds require Rust toolchain + network and are run manually in Task 8.

- [ ] **Step 5: Commit**

```bash
git add Scripts/build_quiche_xcframework.sh
git commit -m "build: add macOS Universal support to quiche build script"
```

---

## Task 2: Extend lsquic build script for macOS with BoringSSL prefix

**Files:**
- Modify: `Scripts/build_lsquic_xcframework.sh`

- [ ] **Step 1: Add platform argument parsing**

Add after line 9 (`set -euo pipefail`):

```bash
PLATFORM="${1:-all}"  # ios, macos, all
```

- [ ] **Step 2: Add macOS BoringSSL build with symbol prefix**

Add after ALL iOS builds are complete (after line 92 — the `cd ..` that follows the Simulator lsquic build). This ensures iOS builds are untouched before starting macOS:

```bash
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    # Build BoringSSL for macOS with symbol prefix to avoid collision with swift-nio-ssl
    echo "--- Build BoringSSL for macOS (prefixed) ---"
    mkdir -p boringssl-build-macos && cd boringssl-build-macos
    cmake ../third_party/boringssl \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DBORINGSSL_PREFIX=lsquic_ \
        -DBORINGSSL_PREFIX_SYMBOLS=../third_party/boringssl/util/SYMBOLS.txt \
        -DBUILD_SHARED_LIBS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    BSSL_MACOS="$WORK_DIR/lsquic/boringssl-build-macos"
    cd ..
fi
```

- [ ] **Step 3: Add macOS lsquic build**

Add after the macOS BoringSSL build:

```bash
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    echo "--- Build lsquic for macOS (Universal) ---"
    mkdir -p build-macos && cd build-macos
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DBORINGSSL_DIR="$BSSL_MACOS" \
        -DLSQUIC_BIN=OFF \
        -DLSQUIC_TESTS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release --target lsquic -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    MACOS_LIB="$WORK_DIR/lsquic/build-macos/src/liblsquic/liblsquic.a"
    cd ..

    echo "--- Merge macOS libraries ---"
    libtool -static -o "$WORK_DIR/merged/liblsquic-macos.a" \
        "$MACOS_LIB" \
        "$BSSL_MACOS/ssl/libssl.a" \
        "$BSSL_MACOS/crypto/libcrypto.a"
fi
```

- [ ] **Step 4: Update xcframework creation to include macOS slice**

```bash
# Replace existing Step 8 (lines 126-135):
echo "--- Create XCFramework ---"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/CLsquic.xcframework"

XCFW_ARGS=()
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "$WORK_DIR/merged/liblsquic-ios.a" -headers "$HEADER_DIR")
    XCFW_ARGS+=(-library "$WORK_DIR/merged/liblsquic-sim.a" -headers "$HEADER_DIR")
fi
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "$WORK_DIR/merged/liblsquic-macos.a" -headers "$HEADER_DIR")
fi

xcodebuild -create-xcframework \
    "${XCFW_ARGS[@]}" \
    -output "$OUTPUT_DIR/CLsquic.xcframework"
```

- [ ] **Step 5: Commit**

```bash
git add Scripts/build_lsquic_xcframework.sh
git commit -m "build: add macOS Universal support to lsquic build script with BoringSSL prefix"
```

---

## Task 3: Create combined rebuild script

**Files:**
- Create: `Scripts/rebuild_xcframeworks.sh`

- [ ] **Step 1: Write the combined script**

```bash
#!/bin/bash
#
# rebuild_xcframeworks.sh
# Rebuilds all QUIC xcframeworks for all platforms.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM="${1:-all}"  # ios, macos, all

echo "=== Rebuilding QUIC XCFrameworks (platform: $PLATFORM) ==="

echo ""
echo ">>> Building quiche..."
"$SCRIPT_DIR/build_quiche_xcframework.sh" "$PLATFORM"

echo ""
echo ">>> Building lsquic..."
"$SCRIPT_DIR/build_lsquic_xcframework.sh" "$PLATFORM"

echo ""
echo "=== All XCFrameworks rebuilt ==="
ls -lh "$SCRIPT_DIR/../Frameworks/"*.xcframework/*/lib*.a 2>/dev/null || true
```

- [ ] **Step 2: Make executable**

Run: `chmod +x Scripts/rebuild_xcframeworks.sh`

- [ ] **Step 3: Commit**

```bash
git add Scripts/rebuild_xcframeworks.sh
git commit -m "build: add combined rebuild script for all QUIC xcframeworks"
```

---

## Task 4: Remove iOS-only platform restriction from Package.swift

**Files:**
- Modify: `LocalPackages/TunnelServices/Package.swift:62-64`

- [ ] **Step 1: Remove the platform condition**

In `LocalPackages/TunnelServices/Package.swift`, change lines 62-64:

```swift
// Before:
                // QUIC (iOS-only: xcframeworks have no macOS slice)
                .product(name: "SwiftQuiche", package: "SwiftQuiche", condition: .when(platforms: [.iOS])),
                .product(name: "SwiftLsquic", package: "SwiftLsquic", condition: .when(platforms: [.iOS])),

// After:
                // QUIC (all platforms)
                .product(name: "SwiftQuiche", package: "SwiftQuiche"),
                .product(name: "SwiftLsquic", package: "SwiftLsquic"),
```

- [ ] **Step 2: Verify package resolution**

Run: `cd LocalPackages/TunnelServices && swift package resolve 2>&1 | tail -5`

Note: This will fail if the macOS xcframework slices haven't been built yet. That's expected — the build scripts (Tasks 1-3) must be run first to produce the macOS binaries. At this stage, verify the Package.swift parses correctly (no syntax errors).

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Package.swift
git commit -m "build: enable SwiftQuiche and SwiftLsquic for all platforms"
```

---

## Task 5: Fix lsquic packet output buffering and toServer population

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/LsquicMITMHandler.swift`

Two bugs: (1) `processClientPacket` and `processServerPacket` return `[]` because `onPacketsOut` packets are never collected. (2) `LsquicMITMManager.processOutbound` at line 183 returns `(toApp, [])` — toServer is always empty, so lsquic never sends packets to the real server.

Fix: Use separate buffers for client-engine output (→ toApp) and server-engine output (→ toServer).

- [ ] **Step 1: Add separate packet buffers to LsquicMITMSession**

Add after line 32 (`private var established = false`):

```swift
    // Separate buffers: client engine output → sent back to app, server engine output → sent to real server
    private var clientOutPackets = [Data]()
    private var serverOutPackets = [Data]()
```

- [ ] **Step 2: Wire onPacketsOut callbacks in setup() with separate buffers**

Add after line 55 (`guard clientEngine?.start(certPath: certPath, keyPath: keyPath) == true else { return false }`), before server engine setup:

```swift
        // Client engine packets go back to the app
        clientEngine?.onPacketsOut = { [weak self] data, _ in
            self?.clientOutPackets.append(data)
            return data.count
        }
```

And after line 65 (`guard serverEngine?.start() == true else { return false }`):

```swift
        // Server engine packets go to the real server
        serverEngine?.onPacketsOut = { [weak self] data, _ in
            self?.serverOutPackets.append(data)
            return data.count
        }
```

The second parameter of `onPacketsOut` is the peer address (`sockaddr_in`) — ignored here because the caller already knows the destination.

- [ ] **Step 3: Fix processClientPacket to return client-engine buffered packets**

Replace lines 70-77:

```swift
    public func processClientPacket(_ data: Data) -> [Data] {
        clientOutPackets.removeAll(keepingCapacity: true)
        serverOutPackets.removeAll(keepingCapacity: true)
        var localAddr = makeIPv4Addr(ip: "127.0.0.1", port: 0)
        var peerAddr = makeIPv4Addr(ip: "0.0.0.0", port: serverPort)
        clientEngine?.packetIn(data, localAddr: localAddr, peerAddr: peerAddr)
        clientEngine?.processConns()
        return clientOutPackets
    }

    /// Returns packets that the server engine wants to send to the real server.
    public func pendingServerPackets() -> [Data] {
        let packets = serverOutPackets
        serverOutPackets.removeAll(keepingCapacity: true)
        return packets
    }
```

- [ ] **Step 4: Fix processServerPacket to return server-engine buffered packets**

Replace lines 79-85:

```swift
    public func processServerPacket(_ data: Data) -> [Data] {
        clientOutPackets.removeAll(keepingCapacity: true)
        serverOutPackets.removeAll(keepingCapacity: true)
        var localAddr = makeIPv4Addr(ip: "127.0.0.1", port: 0)
        var peerAddr = makeIPv4Addr(ip: "0.0.0.0", port: serverPort)
        serverEngine?.packetIn(data, localAddr: localAddr, peerAddr: peerAddr)
        serverEngine?.processConns()
        return clientOutPackets  // Decrypted response packets → back to app
    }
```

- [ ] **Step 5: Fix LsquicMITMManager.processOutbound to populate toServer**

Replace line 182-183 in `LsquicMITMManager.processOutbound`:

```swift
        // Before:
        let toApp = session.processClientPacket(data)
        return (toApp, [])

        // After:
        let toApp = session.processClientPacket(data)
        let serverPackets = session.pendingServerPackets()
        let toServer = serverPackets.map { ($0, dstIP, dstPort) }
        return (toApp, toServer)
```

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/LsquicMITMHandler.swift
git commit -m "fix: buffer lsquic packets separately for toApp/toServer and populate both in processOutbound"
```

---

## Task 6: Integrate MITM managers into PacketCaptureEngine

**Files:**
- Modify: `LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/PacketCaptureEngine.swift`

This is the core integration task. We add MITM manager properties, a serial queue, fallback tracking, and modify the UDP:443 processing path.

**Concurrency note**: Both `QUICMITMManager` and `LsquicMITMManager` have internal `NSLock` for their session maps. The `quicMITMQueue` serial queue serializes all MITM work (outbound processing + inbound callbacks). The internal `NSLock` is redundant when all access goes through the queue, but it's pre-existing iOS code and is harmless (lock is uncontended). We keep it to avoid cross-platform divergence.

- [ ] **Step 1: Add MITM properties and serial queue**

Add after line 57 (`private var pcapWriter: PCAPWriter?`):

```swift
    // QUIC MITM — all MITM access is serialized through quicMITMQueue.
    // The managers' internal NSLock is retained for iOS compatibility but is effectively uncontended.
    private var quicMITMManager: QUICMITMManager?
    private var lsquicMITMManager: LsquicMITMManager?
    private let quicMITMQueue = DispatchQueue(label: "com.knot.quic.mitm")
    private var fallbackConnections = [Data: TimeInterval]()  // connId → expiry timestamp
```

- [ ] **Step 2: Add setupQUICMITM and shutdownQUICMITM methods**

Add after `shutdown()` (line 87):

```swift
    // MARK: - QUIC MITM Setup

    /// Initialize the QUIC MITM manager. Call after MitmService is running.
    public func setupQUICMITM(task: CaptureTask, certPath: String, keyPath: String) {
        quicMITMQueue.sync {
            switch ProxyConfig.HTTP3.backend {
            case .quiche:
                self.quicMITMManager = QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)
                AxLogger.log("QUIC MITM: initialized quiche backend", level: .Info)
            case .lsquic:
                self.lsquicMITMManager = LsquicMITMManager(task: task, certPath: certPath, keyPath: keyPath)
                AxLogger.log("QUIC MITM: initialized lsquic backend", level: .Info)
            }
        }
    }

    /// Shut down all QUIC MITM sessions.
    public func shutdownQUICMITM() {
        quicMITMQueue.sync {
            quicMITMManager?.shutdown()
            quicMITMManager = nil
            lsquicMITMManager?.shutdown()
            lsquicMITMManager = nil
            fallbackConnections.removeAll()
        }
    }

    /// Current active MITM session count.
    public var quicMITMSessionCount: Int {
        quicMITMManager?.activeSessions ?? lsquicMITMManager?.activeSessions ?? 0
    }
```

- [ ] **Step 3: Add MITM helper methods**

Add after the setup methods:

```swift
    // MARK: - QUIC MITM Helpers

    private func isInFallback(_ connId: Data) -> Bool {
        if let expiry = fallbackConnections[connId] {
            if Date().timeIntervalSince1970 < expiry {
                return true
            }
            fallbackConnections.removeValue(forKey: connId)
        }
        return false
    }

    private func addToFallback(_ connId: Data, reason: String) {
        let expiry = Date().timeIntervalSince1970 + Double(ProxyConfig.HTTP3.idleTimeoutMs) / 1000.0
        fallbackConnections[connId] = expiry
        AxLogger.log("QUIC MITM fallback for \(connId.map { String(format: "%02x", $0) }.joined()): \(reason)", level: .Warning)
    }

    private func processQUICMITMOutbound(_ data: Data, packet: IPPacket, dstIP: String, dstPort: UInt16) {
        guard let header = QUICDecoder.parseHeader(data) else {
            // Can't parse → fallback (forward transparently)
            forwardUDPTransparently(packet: packet)
            return
        }

        let connId = header.dcid

        // Check fallback
        if isInFallback(connId) {
            forwardUDPTransparently(packet: packet)
            return
        }

        // Check session limit
        let activeCount = quicMITMSessionCount
        if activeCount >= ProxyConfig.HTTP3.maxSessions {
            addToFallback(connId, reason: "session limit reached (\(activeCount)/\(ProxyConfig.HTTP3.maxSessions))")
            forwardUDPTransparently(packet: packet)
            return
        }

        // Check Version Negotiation (version 0)
        if header.version == 0 {
            addToFallback(connId, reason: "Version Negotiation packet")
            forwardUDPTransparently(packet: packet)
            return
        }

        // Try MITM
        let result: (toApp: [Data], toServer: [(Data, String, UInt16)])
        if let manager = quicMITMManager {
            result = manager.processOutbound(data, dstIP: dstIP, dstPort: dstPort)
        } else if let manager = lsquicMITMManager {
            result = manager.processOutbound(data, dstIP: dstIP, dstPort: dstPort)
        } else {
            forwardUDPTransparently(packet: packet)
            return
        }

        // If MITM returned nothing (setup failed), fallback
        if result.toApp.isEmpty && result.toServer.isEmpty {
            addToFallback(connId, reason: "MITM session setup failed")
            forwardUDPTransparently(packet: packet)
            return
        }

        // Send toApp packets back to client
        for pkt in result.toApp {
            let responseData = IPPacketBuilder.buildUDPResponse(originalPacket: packet, payload: pkt)
            delegate?.writePacket(responseData, protocolNumber: packet.version == 4 ? AF_INET : AF_INET6)
        }

        // Send toServer packets to real server
        for (pkt, ip, port) in result.toServer {
            udpForwarder.sendRaw(data: pkt, host: ip, port: port) { [weak self] responseData in
                guard let self = self, let responseData = responseData else { return }
                self.quicMITMQueue.async {
                    self.processQUICMITMInbound(responseData, originalPacket: packet, srcIP: ip, srcPort: port)
                }
            }
        }
    }

    private func processQUICMITMInbound(_ data: Data, originalPacket: IPPacket, srcIP: String, srcPort: UInt16) {
        let toApp: [Data]
        if let manager = quicMITMManager {
            toApp = manager.processInbound(data, srcIP: srcIP, srcPort: srcPort)
        } else if let manager = lsquicMITMManager {
            toApp = manager.processInbound(data, srcIP: srcIP, srcPort: srcPort)
        } else {
            return
        }

        for pkt in toApp {
            let responseData = IPPacketBuilder.buildUDPResponse(originalPacket: originalPacket, payload: pkt)
            delegate?.writePacket(responseData, protocolNumber: originalPacket.version == 4 ? AF_INET : AF_INET6)
        }
    }

    private func forwardUDPTransparently(packet: IPPacket) {
        udpForwarder.forward(packet: packet) { [weak self] responseData in
            guard let self = self, let responseData = responseData else { return }
            let responsePacketData = IPPacketBuilder.buildUDPResponse(originalPacket: packet, payload: responseData)
            self.processInboundPacket(responsePacketData)
            self.delegate?.writePacket(responsePacketData, protocolNumber: packet.version == 4 ? AF_INET : AF_INET6)
        }
    }
```

- [ ] **Step 4: Modify processUDPPacket port 443 branch**

Replace lines 214-218 (the `case 443` branch in `processUDPPacket`). The key change: when HTTP3 is enabled, route to MITM. When disabled, drop the packet (force h2 fallback).

**Important**: The `return` at the end exits `processUDPPacket` entirely. This skips the generic logging (lines 230-236) and generic `udpForwarder.forward` (lines 239-256) that would normally run for all ports. We duplicate the logging inside the case 443 block so QUIC packets are still logged and captured in PCAP. This is intentional — port 443 is fully self-contained.

Change the `case 443:` section to:

```swift
        case 443: // QUIC
            decodedProtocol = "QUIC"
            if let quic = QUICDecoder.parseHeader(appData) {
                detail = QUICDecoder.format(quic)
            }

            // Log + PCAP (duplicated here because we return early, skipping generic logging below)
            let summary443 = IPPacketParser.format(packet)
            let captured443 = CapturedPacket(
                timestamp: Date(), direction: direction, ipPacket: packet,
                decodedProtocol: decodedProtocol, summary: summary443, detail: detail
            )
            delegate?.didCapturePacket(captured443)
            writeToPCAP(packet: packet, rawData: rawData, direction: direction)

            if direction == .outbound {
                if ProxyConfig.HTTP3.enabled {
                    // MITM path — dispatched to serial queue for thread safety
                    quicMITMQueue.async { [weak self] in
                        self?.processQUICMITMOutbound(appData, packet: packet,
                                                       dstIP: packet.destinationIP,
                                                       dstPort: udp.destinationPort)
                    }
                }
                // When HTTP3.enabled == false: drop packet → client falls back to TCP/HTTP2
            }
            return  // Exit processUDPPacket — skip generic forwarding for port 443
```

- [ ] **Step 5: Add `sendRaw` method to UDPForwarder**

The MITM toServer path needs to send raw UDP data and receive responses. The existing `sendUDP` requires an `IPPacket` parameter (for `PendingExchange` tracking) so we cannot reuse it directly. Add a standalone `sendRaw` that reuses the NWConnection pool but skips `PendingExchange`:

Add to `UDPForwarder.swift` (after line 100, before `shutdown()`):

```swift
    /// Send raw UDP data to a specific host:port and call completion with the response.
    /// Used by QUIC MITM to forward server-bound packets without an IPPacket.
    public func sendRaw(data: Data, host: String, port: UInt16, completion: @escaping (Data?) -> Void) {
        let key = "\(host):\(port)"
        queue.async { [weak self] in
            guard let self = self else { completion(nil); return }

            // Get or create connection (same pool as forward())
            let connection: NWConnection
            if let existing = self.connections[key], existing.state == .ready {
                connection = existing
            } else {
                self.connections[key]?.cancel()
                let nwHost = NWEndpoint.Host(host)
                let nwPort = NWEndpoint.Port(rawValue: port)!
                let newConn = NWConnection(host: nwHost, port: nwPort, using: .udp)
                newConn.stateUpdateHandler = { [weak self] state in
                    if case .failed = state {
                        self?.connections.removeValue(forKey: key)
                    }
                }
                newConn.start(queue: self.queue)
                self.connections[key] = newConn
                connection = newConn
            }

            // Send and receive (no PendingExchange tracking needed)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    AxLogger.log("UDP sendRaw error to \(key): \(error)", level: .Error)
                    completion(nil)
                    return
                }
                connection.receiveMessage { content, _, _, error in
                    if let error = error {
                        AxLogger.log("UDP sendRaw receive error from \(key): \(error)", level: .Error)
                        completion(nil)
                        return
                    }
                    completion(content)
                }
            })
        }
    }
```

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/PacketCaptureEngine.swift
git add LocalPackages/TunnelServices/Sources/TunnelServices/PacketCapture/UDPForwarder.swift
git commit -m "feat: integrate QUIC MITM managers into PacketCaptureEngine with fallback"
```

---

## Task 7: Adapt MacPacketTunnelProvider

**Files:**
- Modify: `SystemExtension-macOS/MacPacketTunnelProvider.swift`

- [ ] **Step 1: Add MITM initialization in startTunnel**

After line 48 (`self?.startPacketCapture()`), add MITM setup:

```swift
                    // Initialize QUIC MITM if enabled and task is active
                    if ProxyConfig.HTTP3.enabled {
                        let certPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caCert
                        let keyPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caKey
                        self?.captureEngine.setupQUICMITM(
                            task: server.task,
                            certPath: certPath,
                            keyPath: keyPath
                        )
                        log.info("startTunnel: QUIC MITM initialized (backend: \(ProxyConfig.HTTP3.backend.rawValue))")
                    }
```

- [ ] **Step 2: Add MITM shutdown in stopTunnel**

After line 147 (`captureEngine.shutdown()`), add:

```swift
        captureEngine.shutdownQUICMITM()
```

- [ ] **Step 3: Add IPC commands in handleAppMessage**

Add new cases in the `switch command` block (after line 171, before `default:`):

```swift
        case "enable_h3":
            ProxyConfig.HTTP3.enabled = true
            if let task = mitmServer?.task {
                let certPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caCert
                let keyPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caKey
                captureEngine.setupQUICMITM(task: task, certPath: certPath, keyPath: keyPath)
            }
            completionHandler?("h3_enabled".data(using: .utf8))
        case "disable_h3":
            ProxyConfig.HTTP3.enabled = false
            captureEngine.shutdownQUICMITM()
            completionHandler?("h3_disabled".data(using: .utf8))
        case "h3_backend_quiche":
            ProxyConfig.HTTP3.backend = .quiche
            completionHandler?("backend_quiche".data(using: .utf8))
        case "h3_backend_lsquic":
            ProxyConfig.HTTP3.backend = .lsquic
            completionHandler?("backend_lsquic".data(using: .utf8))
        case "h3_status":
            let status = "{\"enabled\":\(ProxyConfig.HTTP3.enabled),\"backend\":\"\(ProxyConfig.HTTP3.backend.rawValue)\",\"sessions\":\(captureEngine.quicMITMSessionCount)}"
            completionHandler?(status.data(using: .utf8))
```

- [ ] **Step 4: Commit**

```bash
git add SystemExtension-macOS/MacPacketTunnelProvider.swift
git commit -m "feat: add QUIC MITM lifecycle management to MacPacketTunnelProvider"
```

---

## Task 8: Build xcframeworks and verify compilation

This task requires running the build scripts to produce macOS xcframework slices, then verifying the full project compiles.

- [ ] **Step 1: Run the quiche build script for macOS**

Run: `bash Scripts/build_quiche_xcframework.sh macos`

Expected: Universal `libquiche.a` created in `Frameworks/CQuiche.xcframework/macos-arm64_x86_64/`

- [ ] **Step 2: Run the lsquic build script for macOS**

Run: `bash Scripts/build_lsquic_xcframework.sh macos`

Expected: Universal `liblsquic.a` (with prefixed BoringSSL) created in `Frameworks/CLsquic.xcframework/macos-arm64_x86_64/`

- [ ] **Step 3: Verify xcframework structure**

Run: `find Frameworks/*.xcframework -name "*.a" -exec ls -lh {} \;`

Expected: See `ios-arm64`, `ios-arm64-simulator`, and `macos-arm64_x86_64` directories for both frameworks.

- [ ] **Step 4: Build the macOS System Extension target**

Run: `xcodebuild build -project Knot.xcodeproj -scheme SystemExtension-macOS -destination 'platform=macOS' 2>&1 | tail -20`

Expected: Build succeeds. The `#if canImport(SwiftQuiche)` and `#if canImport(SwiftLsquic)` guards now resolve to true, activating all MITM code on macOS.

- [ ] **Step 5: Verify no BoringSSL symbol conflicts**

Run: `nm Frameworks/CLsquic.xcframework/macos-arm64_x86_64/libCLsquic.a 2>/dev/null | grep " T _SSL_" | head -5`

Expected: Symbols should be prefixed like `_lsquic_SSL_*`, not bare `_SSL_*`.

- [ ] **Step 6: Commit xcframework binaries**

```bash
git add Frameworks/CQuiche.xcframework/ Frameworks/CLsquic.xcframework/
git commit -m "build: add macOS Universal slices to QUIC xcframeworks"
```
