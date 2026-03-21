//
//  WebSocketCaptureHandler.swift
//  TunnelServices
//
//  Captures WebSocket frames flowing through the MITM proxy.
//
//  WebSocket MITM flow:
//  1. Client sends HTTP Upgrade request → detected by HTTPCaptureHandler
//  2. Proxy connects to real server, sends Upgrade request
//  3. Server responds with 101 Switching Protocols
//  4. Both sides switch from HTTP to WebSocket framing
//  5. This handler captures all frames in both directions
//
//  Frame storage: Each WebSocket message is recorded as a line in the session's
//  request body file (client→server) or response body file (server→client).
//  Format: [timestamp] [opcode] [length] [payload_preview]
//

import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket
import NIOSSL
import NIOTLS
import NIOHTTPCompression

// MARK: - WebSocket Upgrade Detector

/// Detects WebSocket upgrade requests inside HTTPCaptureHandler and switches
/// the pipeline to WebSocket mode after the 101 response.
public final class WebSocketUpgradeInterceptor: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart

    private let recorder: SessionRecorder
    private let task: CaptureTask
    private let isSSL: Bool
    private weak var serverChannel: Channel?
    private var upgradeRequest: HTTPRequestHead?

    public init(recorder: SessionRecorder, task: CaptureTask, isSSL: Bool) {
        self.recorder = recorder
        self.task = task
        self.isSSL = isSSL
    }

    /// Configure the interceptor with the upgrade request and inbound channel.
    /// Called by HTTPCaptureHandler when it detects a WebSocket upgrade request,
    /// since the interceptor may not be in the pipeline to observe channelRead.
    public func configure(upgradeRequest: HTTPRequestHead, serverChannel: Channel) {
        self.upgradeRequest = upgradeRequest
        self.serverChannel = serverChannel
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        if case .head(let head) = part {
            serverChannel = context.channel
            if isWebSocketUpgrade(head) {
                upgradeRequest = head
                recorder.session.schemes = isSSL ? "WSS" : "WS"
            }
        }

        // Always forward
        context.fireChannelRead(data)
    }

    /// Called by HTTPCaptureHandler when it receives a 101 response from the server.
    /// At that point, we switch both pipelines to WebSocket framing.
    public func performWebSocketUpgrade(
        context: ChannelHandlerContext,
        clientChannel: Channel
    ) {
        guard let request = upgradeRequest, let serverCh = serverChannel else { return }
        recorder.addProtoFlag(.wsFrameMasked)

        AxLogger.log("WebSocket upgrade for \(request.headers["Host"].first ?? "unknown")", level: .Info)

        // Create frame loggers for both directions
        let clientLogger = WebSocketFrameLogger(recorder: recorder, direction: .clientToServer)
        let serverLogger = WebSocketFrameLogger(recorder: recorder, direction: .serverToClient)

        // Both channels must be reconfigured atomically (within the same event loop turn)
        // to prevent frames from being forwarded to a pipeline with HTTP handlers.
        // We use eventLoop.execute to defer ALL reconfiguration until after the current
        // channelRead callback returns, ensuring no data races.
        let inboundPrefix = isSSL ? "mitm.http" : "http1"
        let outboundPrefix = "client"
        // Reconfigure both pipelines synchronously. Both channels MUST be on
        // the same event loop (the outbound connection is created on the inbound's EL).
        // Doing this synchronously prevents the race condition where data arrives
        // between the channelRead return and an execute block.
        do {
            // === Transform INBOUND channel (client→proxy, aka serverCh) ===
            // 1. Add a bridge handler to absorb raw bytes from HTTP decoder removal
            let bridge = WebSocketUpgradeBridge(
                clientChannel: clientChannel,
                serverCh: serverCh,
                clientLogger: clientLogger,
                direction: .clientToServer
            )
            _ = serverCh.pipeline.addHandler(bridge, name: "ws.bridge")

            // 2. Remove HTTP handlers
            self.removeHTTPHandlersSynchronously(from: serverCh.pipeline, prefix: inboundPrefix)

            // 3. Add WS handlers before the bridge
            _ = serverCh.pipeline.addHandler(
                ByteToMessageHandler(WebSocketFrameDecoder()),
                name: "ws.client.decoder",
                position: .before(bridge)
            )
            _ = serverCh.pipeline.addHandler(
                WebSocketFrameEncoder(),
                name: "ws.client.encoder",
                position: .before(bridge)
            )
            _ = serverCh.pipeline.addHandler(clientLogger,
                name: "ws.client.logger",
                position: .before(bridge)
            )
            _ = serverCh.pipeline.addHandler(
                WebSocketForwarder(peerChannel: clientChannel, direction: .clientToServer),
                name: "ws.client.forwarder",
                position: .before(bridge)
            )

            // 4. Remove the bridge
            serverCh.pipeline.removeHandler(bridge, promise: nil)

            // === Transform OUTBOUND channel (proxy→real server, aka clientChannel) ===
            // Do this after inbound is ready so the outbound forwarder can safely
            // write to the inbound channel.
            self.removeHTTPHandlersSynchronously(from: clientChannel.pipeline, prefix: outboundPrefix)

            _ = clientChannel.pipeline.addHandler(
                ByteToMessageHandler(WebSocketFrameDecoder()),
                name: "ws.server.decoder"
            )
            _ = clientChannel.pipeline.addHandler(
                WebSocketFrameEncoder(),
                name: "ws.server.encoder"
            )
            _ = clientChannel.pipeline.addHandler(serverLogger, name: "ws.server.logger")
            _ = clientChannel.pipeline.addHandler(
                WebSocketForwarder(peerChannel: serverCh, direction: .serverToClient),
                name: "ws.server.forwarder"
            )
        }
    }

    private func isWebSocketUpgrade(_ head: HTTPRequestHead) -> Bool {
        let connection = head.headers["Connection"].first?.lowercased() ?? ""
        let upgrade = head.headers["Upgrade"].first?.lowercased() ?? ""
        return connection.contains("upgrade") && upgrade == "websocket"
    }

    /// Synchronously remove HTTP handlers from the pipeline using syncOperations.
    /// MUST be called on the pipeline's event loop (e.g., inside eventLoop.execute).
    /// Remove HTTP handlers from the pipeline. When called on the event loop,
    /// named handler removal executes synchronously via the internal sync path.
    /// Note: SSL and ALPN handlers are NOT removed — they must stay for WSS connections.
    private func removeHTTPHandlersSynchronously(from pipeline: ChannelPipeline, prefix: String) {
        // Remove named handlers by convention.
        // pipeline.removeHandler(name:promise:) calls syncOperations internally when
        // already on the event loop, so this is effectively synchronous.
        // Note: "ssl" and "alpn" are intentionally NOT removed because
        // WebSocket frames still need to be encrypted for WSS connections.
        // Remove application-level handlers FIRST (responseRelay, capture, etc.)
        // to prevent them from receiving raw IOData forwarded by codec handlers
        // when those are removed (ByteToMessageHandler.leftOverBytesStrategy = .forwardBytes).
        for suffix in ["responseRelay", "capture", "captureHandler", "connect",
                       "pipelining", "decompressor",
                       "responseEncoder", "requestDecoder",
                       "responseDecoder", "requestEncoder"] {
            let name = "\(prefix).\(suffix)"
            pipeline.removeHandler(name: name, promise: nil)
        }

        // Also remove HTTP handlers by type (covers unnamed handlers).
        // syncOperations.handler(type:) + removeHandler is fully synchronous on the EL.
        func removeByType<T: RemovableChannelHandler>(_ type: T.Type) {
            if let handler = try? pipeline.syncOperations.handler(type: type) {
                _ = pipeline.syncOperations.removeHandler(handler)
            }
        }
        removeByType(HTTPRequestEncoder.self)
        removeByType(HTTPResponseEncoder.self)
        removeByType(ByteToMessageHandler<HTTPResponseDecoder>.self)
        removeByType(ByteToMessageHandler<HTTPRequestDecoder>.self)
        removeByType(NIOHTTPResponseDecompressor.self)
        removeByType(HTTPServerPipelineHandler.self)
        removeByType(NIOHTTPRequestHeadersValidator.self)
        removeByType(HTTPServerProtocolErrorHandler.self)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}

// MARK: - WebSocket Frame Logger

/// Records WebSocket frames to the session file system.
final class WebSocketFrameLogger: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = WebSocketFrame

    enum Direction: String {
        case clientToServer = "→"
        case serverToClient = "←"
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private let recorder: SessionRecorder
    private let direction: Direction
    private var frameCount = 0

    init(recorder: SessionRecorder, direction: Direction) {
        self.recorder = recorder
        self.direction = direction
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        frameCount += 1

        // Record the frame
        let entry = formatFrame(frame)

        switch direction {
        case .clientToServer:
            recorder.addUpload(frame.data.readableBytes)
            appendToLog(entry, fileType: .REQ)
        case .serverToClient:
            recorder.addDownload(frame.data.readableBytes)
            appendToLog(entry, fileType: .RSP)
        }

        // Forward to next handler
        context.fireChannelRead(data)
    }

    private func formatFrame(_ frame: WebSocketFrame) -> String {
        let timestamp = Self.isoFormatter.string(from: Date())
        let opcode = opcodeString(frame.opcode)
        let length = frame.data.readableBytes
        let fin = frame.fin ? "FIN" : "..."

        var payload = ""
        switch frame.opcode {
        case .text:
            var data = frame.unmaskedData
            payload = data.readString(length: min(data.readableBytes, 512)) ?? ""
            if length > 512 { payload += "...(truncated)" }
        case .binary:
            payload = "<binary \(length) bytes>"
        case .ping:
            payload = "<ping>"
        case .pong:
            payload = "<pong>"
        case .connectionClose:
            payload = "<close>"
        default:
            payload = "<\(opcode)>"
        }

        return "[\(timestamp)] [\(fin)] [\(opcode)] [\(length)B] \(direction.rawValue) \(payload)\n"
    }

    private func appendToLog(_ entry: String, fileType: FileType) {
        guard let data = entry.data(using: .utf8) else { return }
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        if fileType == .REQ {
            recorder.recordRequestBody(buffer)
        } else {
            recorder.recordResponseBody(buffer)
        }
    }

    private func opcodeString(_ opcode: WebSocketOpcode) -> String {
        switch opcode {
        case .text: return "TEXT"
        case .binary: return "BIN"
        case .ping: return "PING"
        case .pong: return "PONG"
        case .connectionClose: return "CLOSE"
        case .continuation: return "CONT"
        default: return "UNKNOWN"
        }
    }
}

// MARK: - WebSocket Frame Forwarder

/// Forwards WebSocket frames between two channels (client ↔ server).
final class WebSocketForwarder: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private weak var peerChannel: Channel?
    private let direction: WebSocketFrameLogger.Direction

    init(peerChannel: Channel, direction: WebSocketFrameLogger.Direction) {
        self.peerChannel = peerChannel
        self.direction = direction
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        // RFC 6455 Section 5.1: Client→Server frames MUST be masked.
        // Proxy→Server: must mask (proxy acts as client to server)
        // Proxy→Client: must NOT mask (proxy acts as server to client)
        let forwardData = frame.unmaskedData

        let forwardFrame: WebSocketFrame
        if direction == .clientToServer {
            // Proxy → Server: must mask (proxy is client to server per RFC 6455)
            let maskKey = WebSocketMaskingKey([
                UInt8.random(in: 0...255), UInt8.random(in: 0...255),
                UInt8.random(in: 0...255), UInt8.random(in: 0...255)
            ])!
            forwardFrame = WebSocketFrame(fin: frame.fin, opcode: frame.opcode, maskKey: maskKey, data: forwardData)
        } else {
            // Proxy → Client: must NOT mask (proxy is server to client)
            forwardFrame = WebSocketFrame(fin: frame.fin, opcode: frame.opcode, data: forwardData)
        }

        // Handle close frame: forward first, then close after write completes
        if frame.opcode == .connectionClose {
            peerChannel?.writeAndFlush(forwardFrame).whenComplete { [weak self] _ in
                self?.peerChannel?.close(promise: nil)
                context.close(promise: nil)
            }
        } else {
            peerChannel?.writeAndFlush(forwardFrame, promise: nil)
        }
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        // Send close frame to peer if still open
        if let peer = peerChannel, peer.isActive {
            var buffer = context.channel.allocator.buffer(capacity: 2)
            buffer.write(webSocketErrorCode: .goingAway)
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer)
            peer.writeAndFlush(closeFrame).whenComplete { _ in
                peer.close(promise: nil)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[WSForwarder] error: \(error)", level: .Error)
        peerChannel?.close(promise: nil)
        context.close(promise: nil)
    }
}

// MARK: - WebSocket Upgrade Bridge

/// Temporary handler installed at the tail of the inbound pipeline during WebSocket upgrade.
/// Its purpose is to absorb raw bytes that the ByteToMessageHandler<HTTPRequestDecoder>
/// forwards when removed (via leftOverBytesStrategy: .forwardBytes), and any stale
/// HTTPServerRequestPart events still in flight. After the WS handlers are installed
/// before this bridge, it can be removed.
final class WebSocketUpgradeBridge: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = NIOAny

    private let clientChannel: Channel
    private let serverCh: Channel
    private let clientLogger: WebSocketFrameLogger
    private let direction: WebSocketFrameLogger.Direction

    init(clientChannel: Channel, serverCh: Channel, clientLogger: WebSocketFrameLogger, direction: WebSocketFrameLogger.Direction) {
        self.clientChannel = clientChannel
        self.serverCh = serverCh
        self.clientLogger = clientLogger
        self.direction = direction
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Absorb any data that arrives during the upgrade transition.
        // This includes IOData forwarded by the HTTP decoder and any stale HTTP events.
        // Just drop them — the proper WS pipeline will handle subsequent data.
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}
