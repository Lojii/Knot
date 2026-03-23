import Cocoa
import FlutterMacOS

// Uncomment after adding TunnelServices to Xcode Runner target:
// import TunnelServices
// import KnotStorage
// import KnotWebService

@main
class AppDelegate: FlutterAppDelegate {

    // Proxy state — will hold ProxyServer instance once TunnelServices is linked
    // var proxyServer: ProxyServer?
    // var captureTask: CaptureTask?
    var proxyProcess: Process?  // Fallback: external binary

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
        let channel = FlutterMethodChannel(
            name: "com.knot.proxy",
            binaryMessenger: controller.engine.binaryMessenger
        )

        channel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "startProxy":
                self?.startProxy(result: result)
            case "stopProxy":
                self?.stopProxy(result: result)
            case "getStatus":
                self?.getStatus(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    override func applicationWillTerminate(_ notification: Notification) {
        stopProxyProcess()
        // proxyServer?.stop()
    }

    // MARK: - Proxy Start

    /// Start proxy. Two modes:
    /// 1. In-process (when TunnelServices is linked via Xcode — enables debugging)
    /// 2. External binary (knot-server, fallback)
    private func startProxy(result: @escaping FlutterResult) {
        // Check if already running
        if proxyProcess != nil && proxyProcess!.isRunning {
            let port = readPort()
            result(["running": true, "port": port ?? 9090])
            return
        }

        // TODO: When TunnelServices is linked in Xcode, use in-process mode:
        // startInProcess(result: result)
        // return

        // Fallback: run knot-server binary
        startExternalBinary(result: result)
    }

    // MARK: - In-Process Mode (uncomment when TunnelServices linked)

    /*
    private func startInProcess(result: @escaping FlutterResult) {
        // Setup database root
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.Lojii.NIO1901"
        ) {
            DatabaseManager.rootPath = groupURL.path
            MitmService.storeFolder = groupURL.path.hasSuffix("/") ? groupURL.path : "\(groupURL.path)/"
        }

        // Create task
        let task = CaptureTask()
        task.localIP = "127.0.0.1"
        task.localPort = 0
        task.localEnable = 1
        task.wifiEnable = 0
        task.isCACertTrusted = true
        task.ruleEngine = RuleEngine(config: "")
        task.certManager = CertManager()
        task.creatTime = Date().timeIntervalSince1970
        task.startTime = Date().timeIntervalSince1970
        let ts = "\(task.creatTime!)".components(separatedBy: ".")
        task.fileFolder = "task_\(ts.first ?? "0")\(ts.last ?? "0")"

        do {
            let rowId = try CatalogDAO.insertFullTask(db: DatabaseManager.shared.catalogDB, task: task.toCaptureTaskRecord())
            task.id = rowId
            let _ = try DatabaseManager.shared.openTask(task.id)
        } catch {
            NSLog("[Knot] Task creation failed: \(error)")
        }
        task.loadRules()
        self.captureTask = task

        // Start server
        let server = ProxyServer(masterThreads: 1, workerThreads: 2)
        self.proxyServer = server

        server.start(task: task) { startResult in
            switch startResult {
            case .success:
                let port = server.localBoundPort ?? 0
                try? "\(port)".write(toFile: "/tmp/knot-proxy-port", atomically: true, encoding: .utf8)
                NSLog("[Knot] Proxy running on port \(port)")
                result(["running": true, "port": port])
            case .failure(let error):
                NSLog("[Knot] Proxy failed: \(error)")
                result(FlutterError(code: "START_FAILED", message: "\(error)", details: nil))
            }
        }
    }
    */

    // MARK: - External Binary Mode

    private func startExternalBinary(result: @escaping FlutterResult) {
        guard let path = findServerBinary(), FileManager.default.fileExists(atPath: path) else {
            result(FlutterError(code: "NOT_FOUND",
                                message: "knot-server not found. Build it: swift build --package-path native/TunnelServices --product knot-server",
                                details: nil))
            return
        }

        try? FileManager.default.removeItem(atPath: "/tmp/knot-proxy-port")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            proxyProcess = process

            DispatchQueue.global().async {
                var port: Int?
                for _ in 0..<60 {
                    Thread.sleep(forTimeInterval: 0.5)
                    port = self.readPort()
                    if port != nil { break }
                }
                DispatchQueue.main.async {
                    result(["running": true, "port": port ?? 9090])
                }
            }
        } catch {
            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Stop / Status

    private func stopProxy(result: @escaping FlutterResult) {
        stopProxyProcess()
        // proxyServer?.stop()
        // proxyServer = nil
        result(["running": false])
    }

    private func getStatus(result: @escaping FlutterResult) {
        let running = proxyProcess?.isRunning ?? false
        let port = readPort()
        result(["running": running, "port": port ?? 0])
    }

    private func stopProxyProcess() {
        if let process = proxyProcess, process.isRunning {
            process.terminate()
        }
        proxyProcess = nil
        try? FileManager.default.removeItem(atPath: "/tmp/knot-proxy-port")
    }

    private func readPort() -> Int? {
        guard let content = try? String(contentsOfFile: "/tmp/knot-proxy-port", encoding: .utf8) else { return nil }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Find knot-server binary: app bundle first, then project build output
    private func findServerBinary() -> String? {
        if let bundled = Bundle.main.path(forResource: "knot-server", ofType: nil) {
            return bundled
        }

        let projectDir: String
        if let idx = Bundle.main.bundlePath.range(of: "/build/") {
            projectDir = String(Bundle.main.bundlePath[..<idx.lowerBound])
        } else {
            projectDir = FileManager.default.currentDirectoryPath
        }

        for config in ["debug", "release"] {
            let path = "\(projectDir)/native/TunnelServices/.build/arm64-apple-macosx/\(config)/knot-server"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }
}
