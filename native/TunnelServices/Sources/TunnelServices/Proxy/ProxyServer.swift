//
//  ProxyServer.swift
//  TunnelServices
//
//  Clean server bootstrap and lifecycle management.
//  Replaces the bootstrap configuration in MitmService.
//

import Foundation
import NIO
import KnotWebService

public class ProxyServer {

    private let masterGroup: MultiThreadedEventLoopGroup
    private let workerGroup: MultiThreadedEventLoopGroup
    private(set) var localChannel: Channel?
    private var wifiChannel: Channel?
    private(set) var udpChannel: Channel?
    private var webServer: KnotWebServer?
    private var liveBridge: ProxyLiveBridge?
    private var metricsTask: RepeatedTask?

    /// Whether the server has been intentionally stopped (vs. unexpected crash).
    private var intentionallyStopped = false
    /// Maximum auto-restart attempts before giving up.
    private static let maxRestartAttempts = 3
    /// Delay between restart attempts (seconds).
    private static let restartDelaySeconds: UInt32 = 2

    /// The port the local server is actually bound to (useful when binding to port 0).
    public var localBoundPort: Int? {
        localChannel?.localAddress?.port
    }

    public var udpBoundPort: Int? {
        udpChannel?.localAddress?.port
    }

    public init(
        masterThreads: Int = System.coreCount,
        workerThreads: Int = System.coreCount * 3
    ) {
        self.masterGroup = MultiThreadedEventLoopGroup(numberOfThreads: masterThreads)
        self.workerGroup = MultiThreadedEventLoopGroup(numberOfThreads: workerThreads)
    }

    // MARK: - Server Lifecycle

    public func start(task: CaptureTask, callback: @escaping (Result<Void, Error>) -> Void) {
        task.startTime = Date().timeIntervalSince1970
        task.createFileFolder()
        task.numberOfUse = task.numberOfUse + 1
        try? task.update()

        if task.localEnable == 1 {
            DispatchQueue.global().async {
                // Start real-time web server (if dashboard enabled)
                if ProxyConfig.Dashboard.enabled {
                    let webServer = KnotWebServer(
                        preferredPort: ProxyConfig.Dashboard.port,
                        eventLoopGroup: self.workerGroup
                    )
                    do {
                        let port = try webServer.start()
                        self.webServer = webServer
                        let bridge = ProxyLiveBridge()
                        webServer.attachLiveBridge(bridge)
                        self.liveBridge = bridge
                        task.liveBridge = bridge
                        AxLogger.log("[ProxyServer] Dashboard: http://127.0.0.1:\(port)", level: .Info)

                        // Start periodic metrics push on a worker event loop
                        let startTime = Date().timeIntervalSince1970
                        let intervalMs = ProxyConfig.Dashboard.metricsIntervalMs
                        let el = self.workerGroup.next()
                        self.metricsTask = el.scheduleRepeatedTask(
                            initialDelay: .milliseconds(Int64(intervalMs)),
                            delay: .milliseconds(Int64(intervalMs))
                        ) { [weak self, weak task] _ in
                            guard let self = self, let bridge = self.liveBridge, let task = task else { return }
                            DispatchQueue.global().async {
                                let metrics = MetricsCollector.collect(task: task, startTime: startTime)
                                let data: [String: Any] = [
                                    "memory": ["rss_mb": metrics.rssMB, "rss_bytes": metrics.rssBytes],
                                    "cpu": ["usage_percent": metrics.cpuPercent, "thread_count": metrics.threadCount],
                                    "connections": [
                                        "pool_total": metrics.poolTotal,
                                        "pool_breakdown": metrics.poolBreakdown.map { ["key": $0.key, "count": $0.count] },
                                        "mitm_failed_hosts": metrics.mitmFailedHosts
                                    ],
                                    "totals": ["uptime_s": metrics.uptimeSeconds]
                                ]
                                bridge.onMetrics?(data)
                            }
                        }
                    } catch {
                        AxLogger.log("[ProxyServer] WebServer failed: \(error)", level: .Error)
                    }
                }

                self.startServer(
                    host: task.localIP,
                    port: task.localPort,
                    task: task,
                    isWifi: false
                ) { result in
                    switch result {
                    case .success:
                        callback(.success(()))
                    case .failure(let error):
                        callback(.failure(error))
                    }
                }
            }
        }

        if task.wifiEnable == 1, task.wifiIP != "" {
            DispatchQueue.global().async {
                self.startServer(
                    host: task.wifiIP,
                    port: task.wifiPort,
                    task: task,
                    isWifi: true
                ) { _ in }
            }
        }
    }

    private func startServer(
        host: String,
        port: Int,
        task: CaptureTask,
        isWifi: Bool,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        let bootstrap = ServerBootstrap(group: masterGroup, childGroup: workerGroup)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                let recorder = SessionRecorder(task: task)
                let tcpChildren = ProtocolRegistry.shared.tcpChildren
                // Add protocol dispatcher + catch-all error handler at the tail.
                // The catch-all ensures no unhandled error crashes the EventLoop.
                return channel.pipeline.addHandler(
                    ProtocolDispatcher(task: task, nodes: tcpChildren, recorder: recorder),
                    name: "dispatcher", position: .first
                ).flatMap {
                    channel.pipeline.addHandler(
                        CatchAllErrorHandler(), name: "catchAll", position: .last
                    )
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: false)
            .childChannelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(ProxyConfig.SSL.connectTimeout))

        guard let channel = try? bootstrap.bind(host: host, port: port).wait() else {
            let errorMsg = "\(isWifi ? "Wifi" : "Local") Address was unable to bind. \(host):\(port)"
            AxLogger.log(errorMsg, level: .Error)
            if isWifi {
                task.wifiState = -1
            } else {
                task.localState = -1
                task.note = task.note + errorMsg
            }
            try? task.update()
            callback(.failure(ServerChannelError(errCode: -1, localizedDescription: errorMsg)))
            return
        }

        if isWifi {
            wifiChannel = channel
            task.wifiState = 1
        } else {
            localChannel = channel
            task.localState = 1
        }
        try? task.update()

        AxLogger.log("\(isWifi ? "Wifi" : "Local") Server started on \(channel.localAddress?.description ?? "unknown")", level: .Info)
        callback(.success(()))

        // Start QUIC/UDP proxy if HTTP3 is enabled
        if !isWifi && ProxyConfig.HTTP3.enabled && task.isCACertTrusted {
            let certPath: String
            let keyPath: String
            if let certDir = CertStore.certDirectoryURL() {
                certPath = CertStore.filePath(in: certDir, name: ProxyConfig.CertFiles.caCert)
                keyPath = CertStore.filePath(in: certDir, name: ProxyConfig.CertFiles.caKey)
            } else {
                certPath = ""
                keyPath = ""
            }

            let mitmManager = QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)

            // Pin all QUIC work to a single event loop to avoid NSLock contention
            let quicEventLoop = self.workerGroup.next()
            let udpBootstrap = DatagramBootstrap(group: quicEventLoop)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(
                        QUICProxyHandler(mitmManager: mitmManager)
                    )
                }

            if let udpCh = try? udpBootstrap.bind(host: host, port: ProxyConfig.HTTP3.udpPort).wait() {
                self.udpChannel = udpCh
                AxLogger.log("[ProxyServer] QUIC UDP proxy bound on \(host):\(udpCh.localAddress?.port ?? 0)", level: .Info)
            } else {
                AxLogger.log("[ProxyServer] Failed to bind QUIC UDP port", level: .Error)
            }
        }

        // Block until channel closes, then auto-restart if not intentional.
        try? channel.closeFuture.wait()

        if isWifi {
            task.wifiState = 0
        } else {
            task.localState = 0
        }
        try? task.update()

        // Auto-restart: if the server channel closed unexpectedly (not via stop()),
        // restart it up to maxRestartAttempts times with exponential backoff.
        if !intentionallyStopped {
            AxLogger.log("[ProxyServer] \(isWifi ? "Wifi" : "Local") server channel closed unexpectedly — attempting auto-restart", level: .Error)
            for attempt in 1...Self.maxRestartAttempts {
                guard !intentionallyStopped else { break }
                let delay = Self.restartDelaySeconds * UInt32(attempt)
                AxLogger.log("[ProxyServer] Restart attempt \(attempt)/\(Self.maxRestartAttempts) in \(delay)s...", level: .Warning)
                sleep(delay)
                guard !intentionallyStopped else { break }

                // Recursive call — will block until the restarted channel closes too
                self.startServer(host: host, port: port, task: task, isWifi: isWifi) { result in
                    switch result {
                    case .success:
                        AxLogger.log("[ProxyServer] Auto-restart succeeded on attempt \(attempt)", level: .Info)
                    case .failure(let error):
                        AxLogger.log("[ProxyServer] Auto-restart attempt \(attempt) failed: \(error)", level: .Error)
                    }
                }
                // If we get here, the restarted server also closed.
                // If it was intentional, break; otherwise loop and retry.
                if intentionallyStopped { break }
            }
            if !intentionallyStopped {
                AxLogger.log("[ProxyServer] All \(Self.maxRestartAttempts) restart attempts exhausted", level: .Error)
            }
        }
    }

    // MARK: - Shutdown

    public func stop(completionHandler: (() -> Void)? = nil) {
        intentionallyStopped = true

        metricsTask?.cancel()
        metricsTask = nil
        webServer?.stop()
        webServer = nil
        liveBridge = nil

        udpChannel?.close(mode: .all, promise: nil)
        udpChannel = nil

        localChannel?.close(mode: .input, promise: nil)
        wifiChannel?.close(mode: .input, promise: nil)

        masterGroup.shutdownGracefully { error in
            if let e = error {
                AxLogger.log("master shutdown error: \(e)", level: .Error)
            }
        }
        workerGroup.shutdownGracefully { error in
            if let e = error {
                AxLogger.log("worker shutdown error: \(e)", level: .Error)
            }
        }

        completionHandler?()
    }

    public func stopWifi() {
        wifiChannel?.close(mode: .input, promise: nil)
        wifiChannel = nil
    }
}

// MARK: - Catch-All Error Handler

/// Last-resort error handler at the tail of every child channel pipeline.
/// Prevents unhandled errors from crashing the EventLoop thread.
/// All protocol-specific handlers should have their own errorCaught;
/// this handler catches anything that slips through.
final class CatchAllErrorHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = NIOAny
    typealias InboundOut = NIOAny

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let remote = context.channel.remoteAddress?.description ?? "unknown"
        AxLogger.log("[CatchAll] Unhandled error on \(remote): \(error)", level: .Error)
        // Close the channel gracefully — don't propagate further.
        context.close(promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Pass through — this handler only catches errors.
        context.fireChannelRead(data)
    }
}
