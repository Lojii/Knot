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
        guard let request = upgradeRequest, let serverCh = serverChannel else {
            AxLogger.log("[WS Upgrade] ABORTED: upgradeRequest=\(upgradeRequest != nil) serverChannel=\(serverChannel != nil)", level: .Error)
            return
        }
        recorder.addProtoFlag(.wsFrameMasked)

        AxLogger.log("[WS Upgrade] START for \(request.headers["Host"].first ?? "unknown"), serverCh=\(serverCh) clientCh=\(clientChannel) sameEL=\(serverCh.eventLoop === clientChannel.eventLoop)", level: .Warning)

        // Create frame loggers for both directions
        let clientLogger = WebSocketFrameLogger(recorder: recorder, direction: .clientToServer)
        let serverLogger = WebSocketFrameLogger(recorder: recorder, direction: .serverToClient)

        // === Pipeline reconfiguration using PipelineGateHandler ===
        //
        // Gate pattern: add a gate at the END of each pipeline, close it,
        // then freely remove/add handlers. IOData from decoder removal is
        // safely buffered by the gate. After reconfiguration, open the gate
        // to flush buffered data through the new WS pipeline.
        //
        // This avoids the NIO fatalError where IOData reaches a handler
        // expecting HTTPClientResponsePart or HTTPServerRequestPart.

        let inboundPrefix = isSSL ? "mitm.http" : "http1"
        let outboundPrefix = "client"

        // === INBOUND channel (client → proxy, aka serverCh) ===
        let inboundGate = PipelineGateHandler()
        addHandlerLogging(serverCh.pipeline, inboundGate, name: "ws.inbound.gate")
        inboundGate.shut()

        self.removeHTTPHandlersSynchronously(from: serverCh.pipeline, prefix: inboundPrefix)

        addHandlerLogging(serverCh.pipeline,
            ByteToMessageHandler(WebSocketFrameDecoder()),
            name: "ws.client.decoder", position: .before(inboundGate))
        addHandlerLogging(serverCh.pipeline,
            WebSocketFrameEncoder(),
            name: "ws.client.encoder", position: .before(inboundGate))
        addHandlerLogging(serverCh.pipeline,
            clientLogger,
            name: "ws.client.logger", position: .before(inboundGate))
        addHandlerLogging(serverCh.pipeline,
            WebSocketForwarder(peerChannel: clientChannel, direction: .clientToServer),
            name: "ws.client.forwarder", position: .before(inboundGate))

        // CRITICAL: ensure HTTPResponseEncoder is gone from inbound pipeline.
        // If it remains, WebSocketForwarder writing WS frames to this channel
        // will hit the encoder → fatalError (expects HTTPServerResponsePart).
        if let enc = try? serverCh.pipeline.syncOperations.handler(type: HTTPResponseEncoder.self) {
            try? serverCh.pipeline.syncOperations.removeHandler(enc)
            AxLogger.log("[WS Upgrade] removed lingering HTTPResponseEncoder from inbound", level: .Warning)
        }
        if let err = try? serverCh.pipeline.syncOperations.handler(type: HTTPServerProtocolErrorHandler.self) {
            try? serverCh.pipeline.syncOperations.removeHandler(err)
        }
        // Also remove NIOHTTPResponseHeadersValidator (outbound handler from configureHTTPServerPipeline)
        if let val = try? serverCh.pipeline.syncOperations.handler(type: NIOHTTPResponseHeadersValidator.self) {
            try? serverCh.pipeline.syncOperations.removeHandler(val)
        }

        AxLogger.log("[WS Upgrade] inbound pipeline ready, opening gate", level: .Warning)
        inboundGate.openAndRemove()

        // === OUTBOUND channel (proxy → real server, aka clientChannel) ===
        // Check EL alignment
        let onOutboundEL = clientChannel.eventLoop.inEventLoop
        AxLogger.log("[WS Upgrade] outbound EL: inEventLoop=\(onOutboundEL), inbound EL same=\(serverCh.eventLoop === clientChannel.eventLoop)", level: .Warning)

        let outboundGate = PipelineGateHandler()
        if onOutboundEL {
            try? clientChannel.pipeline.syncOperations.addHandler(outboundGate, name: "ws.outbound.gate")
        } else {
            // Cross-EL: use submit + wait with timeout to avoid indefinite deadlock.
            AxLogger.log("[WS Upgrade] cross-EL! Dispatching outbound gate to outbound EL", level: .Warning)
            let sem = DispatchSemaphore(value: 0)
            clientChannel.eventLoop.execute {
                try? clientChannel.pipeline.syncOperations.addHandler(outboundGate, name: "ws.outbound.gate")
                sem.signal()
            }
            // Timeout after 5s to prevent deadlock — if it fires, WS upgrade
            // will be incomplete but the proxy won't hang.
            if sem.wait(timeout: .now() + .seconds(5)) == .timedOut {
                AxLogger.log("[WS Upgrade] TIMEOUT waiting for outbound gate — aborting WS upgrade", level: .Error)
                return
            }
        }
        outboundGate.shut()

        // Remove HTTP handlers — gate buffers any leftover IOData
        self.removeHTTPHandlersSynchronously(from: clientChannel.pipeline, prefix: outboundPrefix)

        // Add WS handlers — use chained futures for correct ordering on outbound EL
        clientChannel.pipeline.addHandler(
            ByteToMessageHandler(WebSocketFrameDecoder()), name: "ws.server.decoder",
            position: .before(outboundGate)
        ).flatMap { _ in
            clientChannel.pipeline.addHandler(
                WebSocketFrameEncoder(), name: "ws.server.encoder",
                position: .before(outboundGate))
        }.flatMap { _ in
            clientChannel.pipeline.addHandler(serverLogger, name: "ws.server.logger",
                position: .before(outboundGate))
        }.flatMap { _ in
            clientChannel.pipeline.addHandler(
                WebSocketForwarder(peerChannel: serverCh, direction: .serverToClient),
                name: "ws.server.forwarder", position: .before(outboundGate))
        }.whenComplete { result in
            AxLogger.log("[WS Upgrade] outbound pipeline ready, opening gate. result=\(result)", level: .Warning)
            outboundGate.openAndRemove()
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
    /// Remove HTTP handlers from the pipeline.
    /// Works on both same-EL (sync) and cross-EL (async with wait) pipelines.
    /// The PipelineGateHandler at the end of the pipeline buffers any IOData
    /// from decoder removal, so handler ordering is less critical now.
    private func removeHTTPHandlersSynchronously(from pipeline: ChannelPipeline, prefix: String) {
        // Remove by name first (application handlers before codecs)
        for suffix in ["responseRelay", "capture", "captureHandler", "ruleInterceptor",
                       "connect", "pipelining", "decompressor",
                       "responseEncoder", "requestDecoder",
                       "responseDecoder", "requestEncoder"] {
            let name = "\(prefix).\(suffix)"
            // Try sync first, fall back to async
            if let ctx = try? pipeline.syncOperations.context(name: name) {
                pipeline.syncOperations.removeHandler(context: ctx, promise: nil)
            } else {
                // Async removal — fire and forget (gate buffers any data)
                pipeline.removeHandler(name: name, promise: nil)
            }
        }

        // Remove by type as fallback (covers unnamed handlers from configureHTTPServerPipeline)
        func removeByType<T: RemovableChannelHandler>(_ type: T.Type) {
            if let handler = try? pipeline.syncOperations.handler(type: type) {
                _ = pipeline.syncOperations.removeHandler(handler)
            } else {
                // Can't use syncOperations — skip (gate handles any leaks)
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

    /// Helper: add handler via syncOperations with error logging instead of silent try?.
    private func addHandlerLogging(
        _ pipeline: ChannelPipeline,
        _ handler: ChannelHandler,
        name: String,
        position: NIOCore.ChannelPipeline.SynchronousOperations.Position = .last
    ) {
        do {
            try pipeline.syncOperations.addHandler(handler, name: name, position: position)
        } catch {
            AxLogger.log("[WS Upgrade] FAILED to add \(name): \(error)", level: .Error)
        }
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

// WebSocketUpgradeBridge removed — replaced by PipelineGateHandler
