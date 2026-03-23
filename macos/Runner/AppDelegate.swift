import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    var proxyProcess: Process?

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
    }

    // MARK: - Proxy Management

    private func startProxy(result: @escaping FlutterResult) {
        if proxyProcess != nil && proxyProcess!.isRunning {
            let port = readPort()
            result(["running": true, "port": port ?? 9090])
            return
        }

        // Find knot-server binary
        let serverPath = findServerBinary()
        guard let path = serverPath, FileManager.default.fileExists(atPath: path) else {
            result(FlutterError(code: "NOT_FOUND",
                                message: "knot-server binary not found. Run: swift build --package-path native/TunnelServices --product knot-server",
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
            result(FlutterError(code: "START_FAILED",
                                message: error.localizedDescription,
                                details: nil))
        }
    }

    private func stopProxy(result: @escaping FlutterResult) {
        stopProxyProcess()
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
        guard let content = try? String(contentsOfFile: "/tmp/knot-proxy-port",
                                         encoding: .utf8) else { return nil }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Find the knot-server binary. Search order:
    /// 1. App bundle Resources/ (for packaged distribution)
    /// 2. Project build output (for development)
    private func findServerBinary() -> String? {
        // 1. Bundled binary
        if let bundled = Bundle.main.path(forResource: "knot-server", ofType: nil) {
            return bundled
        }

        // 2. Development: project root / native/TunnelServices/.build/.../knot-server
        let projectDir: String
        if let idx = Bundle.main.bundlePath.range(of: "/build/") {
            projectDir = String(Bundle.main.bundlePath[..<idx.lowerBound])
        } else {
            projectDir = FileManager.default.currentDirectoryPath
        }

        let debugPath = "\(projectDir)/native/TunnelServices/.build/arm64-apple-macosx/debug/knot-server"
        if FileManager.default.fileExists(atPath: debugPath) {
            return debugPath
        }

        let releasePath = "\(projectDir)/native/TunnelServices/.build/arm64-apple-macosx/release/knot-server"
        if FileManager.default.fileExists(atPath: releasePath) {
            return releasePath
        }

        return nil
    }
}
