/// KnotServer — standalone proxy + web API executable.
/// Usage: knot-server [--port PORT]
/// Writes bound port to /tmp/knot-proxy-port

import Foundation
import TunnelServices
import KnotStorage

let portFile = "/tmp/knot-proxy-port"

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

// MARK: - Create Task

let task = CaptureTask()
task.localIP = "127.0.0.1"
task.localPort = 0
task.localEnable = 1
task.wifiEnable = 0
task.isCACertTrusted = true
task.ruleEngine = RuleEngine(config: "")
task.certManager = CertManager()  // Loads certs from CertStore automatically
task.creatTime = Date().timeIntervalSince1970
task.startTime = Date().timeIntervalSince1970

let ts = "\(task.creatTime!)".components(separatedBy: ".")
task.fileFolder = "task_\(ts.first ?? "0")\(ts.last ?? "0")"

// Register in catalog DB
do {
    let catalogDB = DatabaseManager.shared.catalogDB
    let rowId = try CatalogDAO.insertFullTask(db: catalogDB, task: task.toCaptureTaskRecord())
    task.id = rowId
    let _ = try DatabaseManager.shared.openTask(task.id)
    print("[KnotServer] Task \(task.id) created")
} catch {
    print("[KnotServer] Task creation failed: \(error)")
}

task.loadRules()

// MARK: - Start Server

let server = ProxyServer(masterThreads: 1, workerThreads: 2)

server.start(task: task) { result in
    switch result {
    case .success:
        let port = server.localBoundPort ?? 0
        try? "\(port)".write(toFile: portFile, atomically: true, encoding: .utf8)
        print("[KnotServer] Proxy: 127.0.0.1:\(port)")
        print("[KnotServer] API:   http://127.0.0.1:9090")
    case .failure(let error):
        print("[KnotServer] Failed: \(error)")
        exit(1)
    }
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

print("[KnotServer] Running. Ctrl+C to stop.")
dispatchMain()
