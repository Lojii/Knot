//
//  KnotWebServer.swift
//  KnotWebService
//
//  Public entry point: HTTP + WebSocket server for the Knot dashboard.
//

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

public final class KnotWebServer: @unchecked Sendable {

    private let preferredPort: Int
    private let maxPortRetries: Int
    private let group: EventLoopGroup
    private let ownsGroup: Bool
    private var serverChannel: Channel?

    /// The port the web server is actually bound to (available after `start()`).
    public var boundPort: Int? {
        serverChannel?.localAddress?.port
    }

    private let pushManager = LivePushManager()

    // MARK: - Init

    /// - Parameters:
    ///   - preferredPort: First port to try binding.
    ///   - maxPortRetries: How many consecutive ports to try before giving up.
    ///   - eventLoopGroup: External ELG. If nil, the server creates (and owns) its own.
    public init(
        preferredPort: Int = 9090,
        maxPortRetries: Int = 10,
        eventLoopGroup: EventLoopGroup? = nil
    ) {
        self.preferredPort = preferredPort
        self.maxPortRetries = maxPortRetries
        if let elg = eventLoopGroup {
            self.group = elg
            self.ownsGroup = false
        } else {
            self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.ownsGroup = true
        }
    }

    // MARK: - Lifecycle

    /// Start the HTTP + WebSocket server. Returns the actual bound port.
    @discardableResult
    public func start() throws -> Int {
        let pm = self.pushManager

        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, _ in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ in
                // Remove HTTPRouter and HTTPServerProtocolErrorHandler BEFORE
                // the HTTP codec removal forwards leftover bytes as IOData.
                if let h = try? channel.pipeline.syncOperations.handler(type: HTTPRouter.self) {
                    _ = channel.pipeline.removeHandler(h)
                }
                if let h = try? channel.pipeline.syncOperations.handler(type: HTTPServerProtocolErrorHandler.self) {
                    _ = channel.pipeline.removeHandler(h)
                }
                return channel.pipeline.addHandler(WebSocketHandler(pushManager: pm))
            }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (
                        upgraders: [upgrader],
                        completionHandler: { _ in }
                    )
                ).flatMap {
                    channel.pipeline.addHandler(HTTPRouter())
                }
            }

        let channel = try PortAllocator.bindWithRetry(
            bootstrap: bootstrap,
            host: "127.0.0.1",
            preferredPort: preferredPort,
            maxRetries: maxPortRetries
        )
        self.serverChannel = channel
        let boundPort = channel.localAddress?.port ?? preferredPort
        return boundPort
    }

    // MARK: - LiveBridge

    /// Attach a LiveBridge so push events are forwarded to connected WebSocket clients.
    public func attachLiveBridge(_ bridge: LiveBridge) {
        pushManager.attach(bridge)
    }

    /// Detach the current LiveBridge (stops forwarding).
    public func detachLiveBridge(_ bridge: LiveBridge) {
        pushManager.detach(bridge)
    }

    // MARK: - Shutdown

    /// Stop the server and (if owned) shut down the EventLoopGroup.
    public func stop() {
        try? serverChannel?.close().wait()
        serverChannel = nil
        if ownsGroup {
            try? group.syncShutdownGracefully()
        }
    }
}
