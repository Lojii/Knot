//
//  TunnelHandler.swift
//  TunnelServices
//
//  Raw TCP tunnel for connections that should not be TLS-intercepted.
//  Simply relays bytes bidirectionally between client and server.
//

import Foundation
import NIO

public final class TunnelHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private let recorder: SessionRecorder
    private let task: CaptureTask
    private let targetHost: String
    private let targetPort: Int
    private var clientChannel: Channel?
    private var pendingData = [ByteBuffer]()
    private var connected = false
    private var connecting = false

    public init(recorder: SessionRecorder, task: CaptureTask,
                targetHost: String = "", targetPort: Int = 0) {
        self.recorder = recorder
        self.task = task
        self.targetHost = targetHost
        self.targetPort = targetPort
        AxLogger.log("[Tunnel] init: target=\(targetHost):\(targetPort)", level: .Warning)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        recorder.addUpload(buffer.readableBytes)
        AxLogger.log("[Tunnel] channelRead \(targetHost):\(targetPort), bytes=\(buffer.readableBytes), connected=\(connected), hasChannel=\(clientChannel != nil)", level: .Warning)

        if clientChannel == nil && !connecting && !targetHost.isEmpty {
            connecting = true
            connectToServer(context: context)
        }

        if connected, let channel = clientChannel, channel.isActive {
            channel.writeAndFlush(buffer, promise: nil)
        } else {
            pendingData.append(buffer)
        }
    }

    private func connectToServer(context: ChannelHandlerContext) {
        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { [weak self] channel in
                guard let self = self else { return channel.eventLoop.makeSucceededVoidFuture() }
                // Add TLS server sniff handler to extract ServerHello + Certificate
                let serverSniff = TLSServerSniffHandler(recorder: self.recorder)
                let relay = TunnelRelayHandler(
                    recorder: self.recorder,
                    peerChannel: context.channel
                )
                return channel.pipeline.addHandler(serverSniff, name: "tls.sniff.server").flatMap {
                    channel.pipeline.addHandler(relay, name: "tunnel.relay")
                }
            }

        AxLogger.log("[Tunnel] connecting to \(targetHost):\(targetPort)...", level: .Warning)
        // Capture channel (not context) to avoid holding ChannelHandlerContext outside handler
        let inboundChannel = context.channel
        let future = bootstrap.connect(host: targetHost, port: targetPort)
        future.whenComplete { [weak self] result in
            switch result {
            case .success(let channel):
                AxLogger.log("[Tunnel] connected to \(self?.targetHost ?? ""):\(self?.targetPort ?? 0), pending=\(self?.pendingData.count ?? 0)", level: .Warning)
                self?.clientChannel = channel
                self?.connected = true
                self?.recorder.recordConnected(remoteAddress: channel.remoteAddress)
                self?.flushPending()
            case .failure(let error):
                AxLogger.log("[Tunnel] connect FAILED to \(self?.targetHost ?? ""):\(self?.targetPort ?? 0): \(error)", level: .Error)
                self?.recorder.recordError("\(self?.targetHost ?? "") connect error: \(error)")
                self?.recorder.session.sstate = "failure"
                inboundChannel.close(promise: nil)
            }
        }
    }

    private func flushPending() {
        guard let channel = clientChannel, channel.isActive else {
            AxLogger.log("[Tunnel] flushPending: channel nil or inactive, pending=\(pendingData.count)", level: .Warning)
            return
        }
        AxLogger.log("[Tunnel] flushPending: flushing \(pendingData.count) buffers to \(targetHost):\(targetPort)", level: .Warning)
        for buf in pendingData {
            channel.writeAndFlush(buf, promise: nil)
        }
        pendingData.removeAll()
    }

    public func channelUnregistered(context: ChannelHandlerContext) {
        AxLogger.log("[Tunnel] channelUnregistered for \(targetHost):\(targetPort), connected=\(connected)", level: .Warning)
        clientChannel?.close(mode: .all, promise: nil)
        recorder.recordClosed()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[Tunnel] Error for \(targetHost):\(targetPort): \(error)", level: .Error)
        recorder.recordError("Tunnel error for \(targetHost): \(error)")
        clientChannel?.close(mode: .all, promise: nil)
        context.close(promise: nil)
    }
}

/// Relays data from real server back to the client.
final class TunnelRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private let recorder: SessionRecorder
    private weak var peerChannel: Channel?

    init(recorder: SessionRecorder, peerChannel: Channel) {
        self.recorder = recorder
        self.peerChannel = peerChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        AxLogger.log("[TunnelRelay] server → client, bytes=\(buffer.readableBytes)", level: .Warning)
        recorder.addDownload(buffer.readableBytes)
        peerChannel?.writeAndFlush(buffer, promise: nil)
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        AxLogger.log("[TunnelRelay] server channel unregistered, closing peer", level: .Warning)
        peerChannel?.close(mode: .all, promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[TunnelRelay] Error relaying from server: \(error)", level: .Error)
        peerChannel?.close(mode: .all, promise: nil)
        context.close(promise: nil)
    }
}
