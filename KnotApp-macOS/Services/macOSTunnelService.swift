import Foundation
import os.log
import KnotCore
import TunnelServices

private let log = Logger(subsystem: "com.KingMap.KnotApp-macOS", category: "TunnelService")

/// macOS tunnel service — runs the MITM proxy server in-process.
///
/// Unlike iOS (which requires a Network Extension / VPN tunnel), macOS can run
/// the proxy server directly in the main app process. The user configures their
/// system HTTP proxy (System Settings → Network → Wi-Fi → Proxies) to point at
/// the local proxy address, or apps can be configured individually.
///
/// This avoids the System Extension installation complexity (requires /Applications,
/// user approval, SIP considerations) and is the approach used by tools like
/// Charles Proxy and Proxyman.
final class macOSTunnelService: NSObject, TunnelServiceProtocol {

    let state = TunnelServiceState()
    private var mitmServer: MitmService?
    private let startDate = Date()

    override init() {
        super.init()
        log.info("macOSTunnelService init (in-process proxy mode)")
    }

    // MARK: - TunnelServiceProtocol

    func startCapture(config: CaptureConfig) async throws {
        log.info("startCapture: preparing MitmService...")
        await MainActor.run { state.status = .connecting }

        guard let server = MitmService.prepare() else {
            log.error("startCapture: MitmService.prepare() returned nil")
            await MainActor.run { state.status = .error("MitmService.prepare() 失败") }
            throw NSError(domain: "macOSTunnelService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "代理服务初始化失败"])
        }
        log.info("startCapture: MitmService prepared, task.localIP=\(server.task.localIP), localPort=\(server.task.localPort)")

        mitmServer = server

        // run() starts the NIO server on a background thread; the callback fires
        // once the local proxy is listening (or fails).
        log.info("startCapture: calling mitmServer.run()...")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.run { [weak self] result in
                switch result {
                case .success:
                    log.info("startCapture: proxy server started successfully")
                    Task { @MainActor in
                        self?.state.status = .connected(since: Date())
                    }
                    continuation.resume()
                case .failure(let error):
                    log.error("startCapture: proxy server failed: \(error.localizedDescription)")
                    Task { @MainActor in
                        self?.state.status = .error(error.localizedDescription)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }

        let host = server.task.localIP
        let port = server.task.localPort
        log.info("startCapture: proxy listening on \(host):\(port)")
        log.info("startCapture: configure system proxy → \(host):\(port) to capture traffic")
    }

    func stopCapture() async throws {
        log.info("stopCapture: stopping proxy server...")
        await MainActor.run { state.status = .disconnecting }

        mitmServer?.close {
            log.info("stopCapture: proxy server closed")
        }
        mitmServer = nil

        await MainActor.run { state.status = .disconnected }
        log.info("stopCapture: done")
    }

    func installExtension() async throws {
        // No system extension needed for in-process mode
        log.info("installExtension: no-op (in-process proxy mode)")
    }

    func uninstallExtension() async throws {
        // No system extension needed for in-process mode
        log.info("uninstallExtension: no-op (in-process proxy mode)")
    }
}
