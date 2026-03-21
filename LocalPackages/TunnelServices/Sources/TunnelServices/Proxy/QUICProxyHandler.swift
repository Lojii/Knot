//
//  QUICProxyHandler.swift
//  TunnelServices
//
//  Client-facing UDP DatagramChannel handler for QUIC transparent proxy mode.
//  Receives QUIC packets from local clients, routes them through the MITM manager,
//  and forwards resulting packets to real servers via per-session outbound channels.
//

import Foundation
import NIO
import NIOFoundationCompat

// MARK: - Shared Client Address Map

/// Thread-safe wrapper for sharing the client address map between
/// `QUICProxyHandler` and all `QUICServerForwarder` instances.
public final class ClientAddressMap {
    private var storage = [String: SocketAddress]()
    private let lock = NSLock()

    public init() {}

    public func set(_ address: SocketAddress, forKey key: String) {
        lock.lock()
        storage[key] = address
        lock.unlock()
    }

    public func get(_ key: String) -> SocketAddress? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func remove(_ key: String) {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }
}

// MARK: - QUICProxyHandler

/// NIO `ChannelInboundHandler` for the client-facing DatagramChannel.
///
/// Receives `AddressedEnvelope<ByteBuffer>` from the local QUIC client, passes
/// them through `QUICMITMManager.processOutbound`, writes MITM response packets
/// back to the client, and forwards server-bound packets via per-session outbound
/// DatagramChannels (each with a `QUICServerForwarder`).
public final class QUICProxyHandler: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let mitmManager: QUICMITMManager

    /// When set, all packets are forwarded to this target instead of using SNI extraction.
    public var defaultTarget: (host: String, port: Int)?

    /// Outbound DatagramChannels keyed by "ip:port".
    private var serverChannels = [String: Channel]()

    /// Shared map of DCID hex prefix -> client SocketAddress, for routing responses back.
    public let clientAddresses = ClientAddressMap()

    public init(mitmManager: QUICMITMManager, defaultTarget: (host: String, port: Int)? = nil) {
        self.mitmManager = mitmManager
        self.defaultTarget = defaultTarget
    }

    // MARK: - Inbound from Client

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data
        let clientAddr = envelope.remoteAddress

        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        let packetData = Data(bytes)

        // Determine target IP:port
        let dstIP: String
        let dstPort: UInt16
        if let target = defaultTarget {
            dstIP = target.host
            dstPort = UInt16(target.port)
        } else {
            // Try SNI extraction for production; fall back to a default
            let sni = QUICDecoder.extractSNI(packetData)
            dstIP = sni ?? "127.0.0.1"
            dstPort = 443
        }

        // Record client address keyed by DCID hex prefix (first 8 bytes)
        if let header = QUICDecoder.parseHeader(packetData), !header.dcid.isEmpty {
            let dcidKey = header.dcid.prefix(8).map { String(format: "%02x", $0) }.joined()
            clientAddresses.set(clientAddr, forKey: dcidKey)
        }

        // Process through MITM
        let result = mitmManager.processOutbound(packetData, dstIP: dstIP, dstPort: dstPort)

        // Write toApp packets back to client
        for appData in result.toApp {
            var buf = context.channel.allocator.buffer(capacity: appData.count)
            buf.writeBytes(appData)
            let reply = AddressedEnvelope(remoteAddress: clientAddr, data: buf)
            context.write(wrapOutboundOut(reply), promise: nil)
        }
        if !result.toApp.isEmpty {
            context.flush()
        }

        // Forward toServer packets to real server(s)
        for (serverData, ip, port) in result.toServer {
            let key = "\(ip):\(port)"
            if let channel = serverChannels[key] {
                sendToServer(channel: channel, data: serverData, ip: ip, port: port)
            } else {
                // Create outbound channel lazily, pinned to same event loop
                createOutboundChannel(
                    context: context, ip: ip, port: port, key: key,
                    firstPacket: serverData
                )
            }
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[QUICProxyHandler] Error: \(error)", level: .Error)
        context.close(promise: nil)
    }

    // MARK: - Outbound Channel Management

    private func createOutboundChannel(
        context: ChannelHandlerContext,
        ip: String, port: UInt16, key: String,
        firstPacket: Data
    ) {
        let mitmManager = self.mitmManager
        let clientChannel = context.channel
        let clientAddresses = self.clientAddresses

        let bootstrap = DatagramBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(
                    QUICServerForwarder(
                        mitmManager: mitmManager,
                        clientChannel: clientChannel,
                        clientAddresses: clientAddresses
                    )
                )
            }

        bootstrap.bind(host: "0.0.0.0", port: 0).whenComplete { [weak self] result in
            switch result {
            case .success(let channel):
                self?.serverChannels[key] = channel
                self?.sendToServer(channel: channel, data: firstPacket, ip: ip, port: port)
                AxLogger.log("[QUICProxyHandler] Outbound channel created for \(key)", level: .Debug)
            case .failure(let error):
                AxLogger.log("[QUICProxyHandler] Failed to create outbound channel for \(key): \(error)", level: .Error)
            }
        }
    }

    private func sendToServer(channel: Channel, data: Data, ip: String, port: UInt16) {
        guard let addr = try? SocketAddress(ipAddress: ip, port: Int(port)) else {
            AxLogger.log("[QUICProxyHandler] Invalid server address \(ip):\(port)", level: .Error)
            return
        }
        var buf = channel.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        let envelope = AddressedEnvelope(remoteAddress: addr, data: buf)
        channel.writeAndFlush(envelope, promise: nil)
    }

    // MARK: - Cleanup

    public func channelInactive(context: ChannelHandlerContext) {
        for channel in serverChannels.values {
            channel.close(promise: nil)
        }
        serverChannels.removeAll()
        context.fireChannelInactive()
    }
}
