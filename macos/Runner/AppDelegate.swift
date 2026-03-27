import Cocoa
import FlutterMacOS

// Uncomment after adding TunnelServices to Xcode Runner target:
 import TunnelServices
 import KnotStorage
 import KnotWebService
 import NIOPosix

@main
class AppDelegate: FlutterAppDelegate {

    // Proxy state — will hold ProxyServer instance once TunnelServices is linked
     var proxyServer: ProxyServer?
     var captureTask: CaptureTask?
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
            case "getCertStatus":
                self?.getCertStatus(result: result)
            case "installCert":
                self?.installCert(result: result)
            case "exportCertDER":
                self?.exportCertDER(result: result)
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
        // Check if already running — in-process mode
        if let server = proxyServer, server.localBoundPort != nil {
            let apiPort = server.webBoundPort ?? 0
            result(["running": true, "port": apiPort, "proxyPort": server.localBoundPort ?? 0])
            return
        }
        // Check if already running — external binary mode
        if proxyProcess != nil && proxyProcess!.isRunning {
            let port = readPort()
            result(["running": true, "port": port ?? 9090])
            return
        }

        // In-process mode (TunnelServices linked)
        startInProcess(result: result)
    }

    // MARK: - In-Process Mode (uncomment when TunnelServices linked)

    
    private func startInProcess(result: @escaping FlutterResult) {
        // Setup database root
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.Lojii.NIO1901"
        ) {
            DatabaseManager.rootPath = groupURL.path
            MitmService.storeFolder = groupURL.path.hasSuffix("/") ? groupURL.path : "\(groupURL.path)/"
        }

        // Start Web API only — NO task creation, NO proxy capture.
        // Tasks are created on-demand when user clicks Start in the UI.
        let webServer = KnotWebServer(
            preferredPort: 9090,
            eventLoopGroup: MultiThreadedEventLoopGroup(numberOfThreads: 2)
        )
        do {
            let webPort = try webServer.start()
            try? "\(webPort)".write(toFile: "/tmp/knot-proxy-port", atomically: true, encoding: .utf8)
            NSLog("[Knot] API on port \(webPort)")
            result(["running": true, "port": webPort])
        } catch {
            NSLog("[Knot] Web server failed: \(error)")
            result(FlutterError(code: "START_FAILED", message: "\(error)", details: nil))
        }
    }
    

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
        // In-process mode
        if let server = proxyServer, server.localBoundPort != nil {
            let apiPort = server.webBoundPort ?? 0
            result(["running": true, "port": apiPort])
            return
        }
        // External binary mode
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

    // MARK: - Certificate Management

    /// Get CA cert trust status: "none" / "installed" / "trusted"
    private func getCertStatus(result: @escaping FlutterResult) {
        guard let certDir = CertStore.certDirectoryURL() else {
            result(["status": "none", "path": ""])
            return
        }
        let derPath = certDir.appendingPathComponent(ProxyConfig.CertFiles.caCertDER).path
        guard FileManager.default.fileExists(atPath: derPath),
              let derData = try? Data(contentsOf: URL(fileURLWithPath: derPath)),
              let secCert = SecCertificateCreateWithData(nil, derData as CFData) else {
            result(["status": "none", "path": derPath])
            return
        }

        // Check if trusted via SecTrustSettings
        var trustResult: SecTrustSettingsResult = .invalid
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(secCert, .user, &trustSettings)

        if status == errSecSuccess, let settings = trustSettings as? [[String: Any]] {
            for dict in settings {
                if let resultValue = dict[kSecTrustSettingsResult as String] as? Int {
                    trustResult = SecTrustSettingsResult(rawValue: UInt32(resultValue)) ?? .invalid
                }
            }
            if trustResult == .trustRoot || trustResult == .trustAsRoot {
                result(["status": "trusted", "path": derPath])
                return
            }
        }

        // Check if cert exists in keychain at all
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSubjectKeyID as String: derData.prefix(20), // rough check
        ]
        var item: CFTypeRef?
        let findStatus = SecItemCopyMatching(query as CFDictionary, &item)
        if findStatus == errSecSuccess {
            result(["status": "installed", "path": derPath])
        } else {
            result(["status": "none", "path": derPath])
        }
    }

    /// Install CA cert to macOS Keychain + set as trusted.
    /// This will trigger a system password prompt.
    private func installCert(result: @escaping FlutterResult) {
        guard let certDir = CertStore.certDirectoryURL() else {
            result(FlutterError(code: "NO_CERT", message: "Certificate directory not found", details: nil))
            return
        }
        let derPath = certDir.appendingPathComponent(ProxyConfig.CertFiles.caCertDER).path
        guard let derData = try? Data(contentsOf: URL(fileURLWithPath: derPath)),
              let secCert = SecCertificateCreateWithData(nil, derData as CFData) else {
            result(FlutterError(code: "NO_CERT", message: "CA certificate not found or invalid", details: nil))
            return
        }

        // Add to Keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
        ]
        var addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            addStatus = errSecSuccess // Already installed
        }

        if addStatus != errSecSuccess {
            result(FlutterError(code: "KEYCHAIN_FAIL",
                                message: "Failed to add cert to Keychain: \(addStatus)",
                                details: nil))
            return
        }

        // Set as trusted root — this triggers system password dialog
        let trustSettings: [String: Any] = [
            kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue
        ]
        let trustStatus = SecTrustSettingsSetTrustSettings(secCert, .user, [trustSettings] as CFArray)

        if trustStatus == errSecSuccess {
            NSLog("[Knot] CA certificate installed and trusted")
            result(["status": "trusted"])
        } else if trustStatus == errSecAuthFailed {
            // User cancelled the password prompt
            NSLog("[Knot] User cancelled trust authorization")
            result(["status": "installed"]) // Cert is in keychain but not trusted
        } else {
            NSLog("[Knot] Trust settings failed: \(trustStatus)")
            result(FlutterError(code: "TRUST_FAIL",
                                message: "Failed to set trust: \(trustStatus)",
                                details: nil))
        }
    }

    /// Export CA cert DER bytes (for manual installation / saving to file).
    private func exportCertDER(result: @escaping FlutterResult) {
        guard let certDir = CertStore.certDirectoryURL() else {
            result(FlutterError(code: "NO_CERT", message: "Certificate directory not found", details: nil))
            return
        }
        let derPath = certDir.appendingPathComponent(ProxyConfig.CertFiles.caCertDER).path
        guard let derData = try? Data(contentsOf: URL(fileURLWithPath: derPath)) else {
            result(FlutterError(code: "NO_CERT", message: "CA certificate not found", details: nil))
            return
        }
        result(FlutterStandardTypedData(bytes: derData))
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
