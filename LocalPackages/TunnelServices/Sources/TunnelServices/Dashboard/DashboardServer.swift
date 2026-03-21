//
//  DashboardServer.swift
//  TunnelServices
//
//  NIO HTTP+WebSocket server that serves a real-time proxy dashboard.
//  Binds to a separate port (default 9090) to avoid proxy loop.
//

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOConcurrencyHelpers

// MARK: - DashboardServer

public final class DashboardServer: DashboardPushable, @unchecked Sendable {

    private let group: EventLoopGroup
    private var serverChannel: Channel?
    private weak var task: CaptureTask?
    private var metricsTask: RepeatedTask?

    /// Thread-safe storage for active WebSocket client channels.
    private let wsConnections = NIOLockedValueBox<[ObjectIdentifier: Channel]>([:])

    // MARK: Stats counters

    private let totalFlows = NIOLockedValueBox<Int64>(0)
    private let completedFlows = NIOLockedValueBox<Int64>(0)
    private let failedFlows = NIOLockedValueBox<Int64>(0)
    private let activeConnections = NIOLockedValueBox<Int64>(0)
    private let totalBytes = NIOLockedValueBox<Int64>(0)

    // Protocol distribution
    private let httpCount = NIOLockedValueBox<Int64>(0)
    private let httpsCount = NIOLockedValueBox<Int64>(0)
    private let h2Count = NIOLockedValueBox<Int64>(0)
    private let wsCount = NIOLockedValueBox<Int64>(0)
    private let wssCount = NIOLockedValueBox<Int64>(0)

    // MARK: DashboardPushable

    public var hasClients: Bool {
        wsConnections.withLockedValue { !$0.isEmpty }
    }

    // MARK: Init

    public init(group: EventLoopGroup) {
        self.group = group
    }

    // MARK: Lifecycle

    /// Bind the dashboard HTTP+WS server on the given port.
    /// Optionally accepts a CaptureTask to enable periodic system metrics push.
    public func start(port: Int = 9090, task: CaptureTask? = nil) throws {
        self.task = task
        let server = self

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                let upgrader = NIOWebSocketServerUpgrader(
                    shouldUpgrade: { channel, _ in
                        channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                    },
                    upgradePipelineHandler: { channel, _ in
                        let removeErrorHandler: EventLoopFuture<Void>
                        if let handler = try? channel.pipeline.syncOperations.handler(type: HTTPServerProtocolErrorHandler.self) {
                            removeErrorHandler = channel.pipeline.removeHandler(handler)
                        } else {
                            removeErrorHandler = channel.eventLoop.makeSucceededVoidFuture()
                        }
                        return removeErrorHandler.flatMap {
                            channel.pipeline.addHandler(DashboardWebSocketHandler(server: server))
                        }
                    }
                )

                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (
                        upgraders: [upgrader],
                        completionHandler: { _ in }
                    )
                ).flatMap {
                    channel.pipeline.addHandler(DashboardHTTPHandler(server: server))
                }
            }

        let channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        self.serverChannel = channel
        let boundPort = channel.localAddress?.port ?? port
        print("[Dashboard] Server listening on http://127.0.0.1:\(boundPort)")

        // Start periodic metrics push (collected off-EventLoop via DispatchQueue)
        let startTime = Date().timeIntervalSince1970
        let intervalMs = ProxyConfig.Dashboard.metricsIntervalMs
        self.metricsTask = channel.eventLoop.scheduleRepeatedTask(
            initialDelay: .milliseconds(Int64(intervalMs)),
            delay: .milliseconds(Int64(intervalMs))
        ) { [weak self] _ in
            guard let self = self, self.hasClients, let task = self.task else { return }
            DispatchQueue.global().async { [weak self] in
                guard let self = self else { return }
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
                self.pushMetrics(data)
            }
        }
    }

    /// Gracefully stop the dashboard server.
    public func stop() {
        metricsTask?.cancel()
        metricsTask = nil
        try? serverChannel?.close().wait()
        serverChannel = nil
    }

    // MARK: - Push Methods

    public func pushFlow(_ flowData: [String: Any]) {
        guard hasClients else { return }

        // Update counters
        totalFlows.withLockedValue { $0 += 1 }

        if let status = flowData["status"] as? Int, status >= 400 {
            failedFlows.withLockedValue { $0 += 1 }
        } else if let failed = flowData["failed"] as? Bool, failed {
            failedFlows.withLockedValue { $0 += 1 }
        } else {
            completedFlows.withLockedValue { $0 += 1 }
        }

        if let size = flowData["size"] as? Int64 {
            totalBytes.withLockedValue { $0 += size }
        } else if let size = flowData["size"] as? Int {
            totalBytes.withLockedValue { $0 += Int64(size) }
        }

        // Update protocol counters
        if let proto = flowData["protocol"] as? String {
            switch proto.lowercased() {
            case "http":  httpCount.withLockedValue { $0 += 1 }
            case "https": httpsCount.withLockedValue { $0 += 1 }
            case "h2":    h2Count.withLockedValue { $0 += 1 }
            case "ws":    wsCount.withLockedValue { $0 += 1 }
            case "wss":   wssCount.withLockedValue { $0 += 1 }
            default:      break
            }
        }

        guard let json = try? JSONSerialization.data(
            withJSONObject: ["type": "flow", "data": flowData]
        ) else { return }
        let text = String(data: json, encoding: .utf8) ?? ""
        broadcastText(text)
    }

    public func pushStats(_ stats: [String: Any]) {
        guard hasClients else { return }
        guard let json = try? JSONSerialization.data(
            withJSONObject: ["type": "stats", "data": stats]
        ) else { return }
        let text = String(data: json, encoding: .utf8) ?? ""
        broadcastText(text)
    }

    public func pushMetrics(_ metrics: [String: Any]) {
        guard hasClients else { return }
        guard let json = try? JSONSerialization.data(
            withJSONObject: ["type": "metrics", "data": metrics]
        ) else { return }
        let text = String(data: json, encoding: .utf8) ?? ""
        broadcastText(text)
    }

    public func pushRetest(_ result: [String: Any]) {
        guard hasClients else { return }
        guard let json = try? JSONSerialization.data(
            withJSONObject: ["type": "retest", "data": result]
        ) else { return }
        let text = String(data: json, encoding: .utf8) ?? ""
        broadcastText(text)
    }

    public func pushSurfProgress(_ progress: [String: Any]) {
        guard hasClients else { return }
        guard let json = try? JSONSerialization.data(
            withJSONObject: ["type": "surf_progress", "data": progress]
        ) else { return }
        let text = String(data: json, encoding: .utf8) ?? ""
        broadcastText(text)
    }

    // MARK: - Broadcast

    private func broadcastText(_ text: String) {
        let connections = wsConnections.withLockedValue { Array($0.values) }
        for channel in connections {
            var buf = channel.allocator.buffer(capacity: text.utf8.count)
            buf.writeString(text)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
            channel.writeAndFlush(frame, promise: nil)
        }
    }

    // MARK: - Connection Tracking

    fileprivate func addConnection(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        wsConnections.withLockedValue { $0[id] = channel }
    }

    fileprivate func removeConnection(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        wsConnections.withLockedValue { _ = $0.removeValue(forKey: id) }
    }

    // MARK: - Stats Snapshot

    fileprivate func statsJSON() -> String {
        let stats: [String: Any] = [
            "totalFlows": totalFlows.withLockedValue { $0 },
            "completedFlows": completedFlows.withLockedValue { $0 },
            "failedFlows": failedFlows.withLockedValue { $0 },
            "activeConnections": activeConnections.withLockedValue { $0 },
            "totalBytes": totalBytes.withLockedValue { $0 },
            "protocols": [
                "http": httpCount.withLockedValue { $0 },
                "https": httpsCount.withLockedValue { $0 },
                "h2": h2Count.withLockedValue { $0 },
                "ws": wsCount.withLockedValue { $0 },
                "wss": wssCount.withLockedValue { $0 },
            ],
            "wsClients": wsConnections.withLockedValue { $0.count },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: stats) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - DashboardHTTPHandler

private final class DashboardHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: DashboardServer
    private var requestURI: String = "/"

    init(server: DashboardServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestURI = head.uri

        case .body:
            break

        case .end:
            sendResponse(context: context)
        }
    }

    private func sendResponse(context: ChannelHandlerContext) {
        switch requestURI {
        case "/", "/index.html":
            sendHTML(context: context)
        case "/api/stats":
            sendStatsJSON(context: context)
        default:
            send404(context: context)
        }
    }

    private func sendHTML(context: ChannelHandlerContext) {
        let body = DashboardHTML.html
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "text/html; charset=utf-8")
        headers.add(name: "content-length", value: "\(body.utf8.count)")
        headers.add(name: "cache-control", value: "no-cache")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func sendStatsJSON(context: ChannelHandlerContext) {
        let body = server.statsJSON()
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "application/json; charset=utf-8")
        headers.add(name: "content-length", value: "\(body.utf8.count)")
        headers.add(name: "cache-control", value: "no-cache")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func send404(context: ChannelHandlerContext) {
        let body = "Not Found"
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "text/plain")
        headers.add(name: "content-length", value: "\(body.utf8.count)")

        let head = HTTPResponseHead(version: .http1_1, status: .notFound, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - DashboardWebSocketHandler

private final class DashboardWebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let server: DashboardServer

    init(server: DashboardServer) {
        self.server = server
    }

    func channelActive(context: ChannelHandlerContext) {
        server.addConnection(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.removeConnection(context.channel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .ping:
            let pongData = frame.unmaskedData
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: pongData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        case .connectionClose:
            let closeData = frame.unmaskedData
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeData)
            context.writeAndFlush(wrapOutboundOut(closeFrame)).whenComplete { _ in
                context.close(promise: nil)
            }

        default:
            // Dashboard is push-only; ignore text/binary from clients
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        server.removeConnection(context.channel)
        context.close(promise: nil)
    }
}
