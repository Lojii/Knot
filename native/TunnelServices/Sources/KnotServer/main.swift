/// KnotServer — standalone proxy + web API executable.
/// Usage: knot-server [--port PORT]
/// Writes bound port to /tmp/knot-proxy-port

import Foundation
import TunnelServices
import KnotStorage
import KnotWebService
import NIOPosix

let portFile = "/tmp/knot-proxy-port"

// Unbuffered stdout so logs (port/token/lifecycle) appear immediately even when
// this debug server's output is redirected to a file or pipe.
setbuf(stdout, nil)

// MARK: - Setup

// Database root: use app group container if available, else ~/.knot
if let groupURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.Lojii.NIO1901"
) {
    DatabaseManager.rootPath = groupURL.path
    MitmService.storeFolder = groupURL.path.hasSuffix("/") ? groupURL.path : "\(groupURL.path)/"
} else {
    let home = NSHomeDirectory()
    let fallback = "\(home)/.knot/"
    try? FileManager.default.createDirectory(atPath: fallback, withIntermediateDirectories: true)
    DatabaseManager.rootPath = fallback
    MitmService.storeFolder = fallback
}

print("[KnotServer] Root: \(DatabaseManager.rootPath)")

// MARK: - Start Web API only (no task, no proxy)
// Tasks and proxy capture are started on-demand via the Flutter UI.

let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
let webServer = KnotWebServer(preferredPort: 9090, eventLoopGroup: elg)

do {
    let webPort = try webServer.start()
    // Write port so the Flutter app can find us
    try? "\(webPort)".write(toFile: portFile, atomically: true, encoding: .utf8)
    print("[KnotServer] API: http://127.0.0.1:\(webPort)")
    // Print the per-session token so this standalone/debug binary's API is usable
    // (all /api/* routes and the WS upgrade require it).
    print("[KnotServer] Token: \(webServer.authToken)")
} catch {
    print("[KnotServer] Web server failed: \(error)")
    exit(1)
}

// MARK: - Signal handling

signal(SIGINT) { _ in
    try? FileManager.default.removeItem(atPath: portFile)
    exit(0)
}
signal(SIGTERM) { _ in
    try? FileManager.default.removeItem(atPath: portFile)
    exit(0)
}

print("[KnotServer] Running (API only, no capture). Ctrl+C to stop.")
dispatchMain()
