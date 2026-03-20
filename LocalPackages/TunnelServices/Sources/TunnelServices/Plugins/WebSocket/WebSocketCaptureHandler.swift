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

        AxLogger.log("WebSocket upgrade for \(request.headers["Host"].first ?? "unknown")", level: .Info)

        // Create frame loggers for both directions
        let clientLogger = WebSocketFrameLogger(recorder: recorder, direction: .clientToServer)
        let serverLogger = WebSocketFrameLogger(recorder: recorder, direction: .serverToClient)

        // === Transform SERVER channel (client→proxy) to WebSocket ===
        // Remove HTTP handlers
        removeHTTPHandlers(from: context.pipeline, prefix: isSSL ? "mitm.http" : "http")

        // Add WebSocket frame decoder/encoder for the client side
        _ = context.pipeline.addHandler(
            ByteToMessageHandler(WebSocketFrameDecoder()),
            name: "ws.client.decoder"
        )
        _ = context.pipeline.addHandler(
            WebSocketFrameEncoder(),
            name: "ws.client.encoder"
        )
        _ = context.pipeline.addHandler(clientLogger, name: "ws.client.logger")
        _ = context.pipeline.addHandler(
            WebSocketForwarder(peerChannel: clientChannel, direction: .clientToServer),
            name: "ws.client.forwarder"
        )

        // === Transform CLIENT channel (proxy→server) to WebSocket ===
        removeHTTPHandlers(from: clientChannel.pipeline, prefix: "client")

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

    private func isWebSocketUpgrade(_ head: HTTPRequestHead) -> Bool {
        let connection = head.headers["Connection"].first?.lowercased() ?? ""
        let upgrade = head.headers["Upgrade"].first?.lowercased() ?? ""
        return connection.contains("upgrade") && upgrade == "websocket"
    }

    private func removeHTTPHandlers(from pipeline: ChannelPipeline, prefix: String) {
        // Remove common HTTP handler names
        for suffix in ["capture", "pipelining", "responseEncoder", "requestDecoder",
                       "responseDecoder", "requestEncoder", "decompressor", "responseRelay"] {
            pipeline.removeHandler(name: "\(prefix).\(suffix)", promise: nil)
        }
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
        let timestamp = ISO8601DateFormatter().string(from: Date())
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

        // Create a new frame without the mask (proxies should unmask before forwarding)
        var forwardData = frame.unmaskedData
        let forwardFrame = WebSocketFrame(
            fin: frame.fin,
            opcode: frame.opcode,
            data: forwardData
        )

        peerChannel?.writeAndFlush(forwardFrame, promise: nil)

        // Handle close frame
        if frame.opcode == .connectionClose {
            peerChannel?.close(promise: nil)
            context.close(promise: nil)
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
        peerChannel?.close(promise: nil)
        context.close(promise: nil)
    }
}
