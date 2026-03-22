//
//  QUICServerForwarder.swift
//  TunnelServices
//
//  Server-facing UDP DatagramChannel handler for QUIC transparent proxy mode.
//  Installed on each per-session outbound channel created by QUICProxyHandler.
//  Receives response packets from the real QUIC server, processes them through
//  the MITM manager, and relays the results back to the client.
//

import Foundation
import NIO
import NIOFoundationCompat

/// NIO `ChannelInboundHandler` for outbound (server-facing) DatagramChannels.
///
/// Each instance handles responses from a single real QUIC server endpoint.
/// It shares the `ClientAddressMap` with `QUICProxyHandler` so it can look up
/// the correct client address for routing response packets.
public final class QUICServerForwarder: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    public typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let mitmManager: QUICMITMManager
    private let clientChannel: Channel
    private let clientAddresses: ClientAddressMap

    public init(
        mitmManager: QUICMITMManager,
        clientChannel: Channel,
        clientAddresses: ClientAddressMap
    ) {
        self.mitmManager = mitmManager
        self.clientChannel = clientChannel
        self.clientAddresses = clientAddresses
    }

    // MARK: - Inbound from Server

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data
        let serverAddr = envelope.remoteAddress

        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        let packetData = Data(bytes)

        // Determine source IP:port from the server envelope
        let srcIP: String
        let srcPort: UInt16
        if let ip = serverAddr.ipAddress, let port = serverAddr.port {
            srcIP = ip
            srcPort = UInt16(port)
        } else {
            srcIP = "0.0.0.0"
            srcPort = 0
        }

        // Process through MITM
        let result = mitmManager.processInbound(packetData, srcIP: srcIP, srcPort: srcPort)

        // Write toApp packets back to client
        if !result.toApp.isEmpty {
            // Look up client address from DCID prefix in response packets
            let clientAddr = resolveClientAddress(from: result.toApp)

            if let clientAddr = clientAddr {
                for appData in result.toApp {
                    var buf = clientChannel.allocator.buffer(capacity: appData.count)
                    buf.writeBytes(appData)
                    let reply = AddressedEnvelope(remoteAddress: clientAddr, data: buf)
                    clientChannel.write(reply, promise: nil)
                }
                clientChannel.flush()
            } else {
                AxLogger.log("[QUICServerForwarder] No client address found for response, dropping \(result.toApp.count) packets", level: .Warning)
            }
        }

        // Write toServer continuation packets back to the server via this same outbound channel
        for (serverData, ip, port) in result.toServer {
            guard let addr = try? SocketAddress(ipAddress: ip, port: Int(port)) else { continue }
            var buf = context.channel.allocator.buffer(capacity: serverData.count)
            buf.writeBytes(serverData)
            let envelope = AddressedEnvelope(remoteAddress: addr, data: buf)
            context.write(wrapOutboundOut(envelope), promise: nil)
        }
        if !result.toServer.isEmpty {
            context.flush()
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[QUICServerForwarder] Error: \(error)", level: .Error)
        context.close(promise: nil)
    }

    // MARK: - Client Address Resolution

    /// Resolve the client address by extracting the DCID from the first toApp packet
    /// and looking it up in the shared client address map.
    private func resolveClientAddress(from packets: [Data]) -> SocketAddress? {
        for packet in packets {
            guard let header = QUICDecoder.parseHeader(packet), !header.dcid.isEmpty else {
                continue
            }
            let dcidKey = header.dcid.prefix(8).map { String(format: "%02x", $0) }.joined()
            if let addr = clientAddresses.get(dcidKey) {
                return addr
            }
        }
        return nil
    }
}
