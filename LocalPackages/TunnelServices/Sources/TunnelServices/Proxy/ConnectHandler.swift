//
//  ConnectHandler.swift
//  TunnelServices
//
//  Handles HTTP CONNECT requests for HTTPS tunneling.
//  After sending 200 Connection Established, either:
//  - Adds MITMHandler for TLS interception (if SSL enabled)
//  - Adds TunnelHandler for raw relay (if SSL disabled or ignored)
//

import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import NIOTLS

public final class ConnectHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private let task: CaptureTask
    private let recorder: SessionRecorder
    private var requestHead: HTTPRequestHead?

    public init(task: CaptureTask, recorder: SessionRecorder) {
        self.task = task
        self.recorder = recorder
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            if head.method == .CONNECT {
                requestHead = head
            } else {
                // Not a CONNECT request — pass through to the next handler (HTTPCaptureHandler)
                context.fireChannelRead(data)
            }

        case .body:
            if requestHead != nil {
                break  // CONNECT has no body
            } else {
                context.fireChannelRead(data)
            }

        case .end:
            if let head = requestHead {
                handleConnect(context: context, head: head)
            } else {
                context.fireChannelRead(data)
            }
        }
    }

    private func handleConnect(context: ChannelHandlerContext, head: HTTPRequestHead) {
        AxLogger.log("[CONNECT] received CONNECT \(head.uri)", level: .Warning)
        let request = NetRequest(head)
        request.ssl = true

        // Record request metadata
        recorder.recordRequestHead(head, localAddress: context.channel.remoteAddress, isSSL: true)
        recorder.session.host = request.host
        recorder.session.schemes = "Https"

        // TODO: Rule matching will be rewritten (whitelist/blacklist/pattern modes).
        // For now, capture all traffic.
        recorder.session.ignore = false

        // Send 200 Connection Established
        let response = HTTPResponseHead(
            version: head.version,
            status: .custom(code: 200, reasonPhrase: "Connection Established"),
            headers: ["content-length": "0"]
        )
        context.write(wrapOutboundOut(.head(response)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

        // Switch pipeline from HTTP to raw bytes (for TLS or tunnel).
        //
        // STRATEGY: Add the next handler (MITM or Dispatcher) FIRST, then remove
        // HTTP handlers. When ByteToMessageHandler<HTTPRequestDecoder> is removed,
        // its leftOverBytesStrategy (.forwardBytes) forwards any buffered bytes
        // (e.g., pipelined TLS ClientHello from Chromium) as IOData. These bytes
        // must reach the newly-added handler (MITMHandler / ProtocolDispatcher),
        // NOT the old HTTPCaptureHandler.
        //
        // Order:
        // 1. Decide MITM or Tunnel
        // 2. Add next handler at .first position
        // 3. Remove all old HTTP handlers (leftover bytes flow to new handler)

        let pipeline = context.pipeline
        let caTrusted = task.isCACertTrusted
        let mitmFailed = task.mitmFailedHosts.shouldTunnel(request.host)
        let shouldIntercept = caTrusted && !mitmFailed

        if !caTrusted {
            AxLogger.log("[CONNECT] \(request.host):\(request.port) → Tunnel (CA not trusted)", level: .Warning)
        } else if mitmFailed {
            AxLogger.log("[CONNECT] \(request.host):\(request.port) → Tunnel (MITM previously failed)", level: .Warning)
        } else {
            AxLogger.log("[CONNECT] \(request.host):\(request.port) → MITM", level: .Warning)
        }

        // Step 1: Add the NEXT handler at .first so it receives leftover bytes
        if shouldIntercept {
            let mitmHandler = MITMHandler(
                task: task, recorder: recorder,
                host: request.host, port: request.port
            )
            try? pipeline.syncOperations.addHandler(mitmHandler, name: "mitm", position: .first)
        } else {
            let tcpChildren = ProtocolRegistry.shared.tcpChildren
            let dispatcher = ProtocolDispatcher(
                task: task, nodes: tcpChildren, recorder: recorder,
                metadata: ProtocolMetadata(innerHost: request.host, innerPort: request.port)
            )
            try? pipeline.syncOperations.addHandler(dispatcher, name: "dispatcher.tunnel", position: .first)
        }

        // Step 2: Remove all old HTTP handlers. Leftover bytes from decoder removal
        // flow to the newly-added handler at .first position.
        let handlerNames = [
            "http1.captureHandler", "https.captureHandler",
            "http1.connect", "https.connect",
            "dispatcher",
            "http1.pipelining", "https.pipelining",
            "http1.responseEncoder", "https.responseEncoder",
            "http1.requestDecoder", "https.requestDecoder",
        ]
        for name in handlerNames {
            if let ctx = try? pipeline.syncOperations.context(name: name) {
                pipeline.syncOperations.removeHandler(context: ctx, promise: nil)
            }
        }

        // Step 3: Remove ourselves (ConnectHandler)
        context.pipeline.syncOperations.removeHandler(self, promise: nil)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        recorder.recordError("ConnectHandler error: \(error)")
        context.close(promise: nil)
    }
}
