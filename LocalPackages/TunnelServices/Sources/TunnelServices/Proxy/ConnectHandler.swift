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

        // Remove all HTTP handlers from pipeline (we're switching to raw bytes or TLS)
        // Use syncOperations for reliable synchronous removal
        let pipeline = context.pipeline
        let handlerNames = [
            "http1.requestDecoder", "http1.responseEncoder", "http1.pipelining",
            "http1.captureHandler",
            "https.requestDecoder", "https.responseEncoder", "https.pipelining",
            "https.captureHandler",
            "dispatcher"
        ]
        for name in handlerNames {
            if let ctx = try? pipeline.syncOperations.context(name: name) {
                pipeline.syncOperations.removeHandler(context: ctx, promise: nil)
            }
        }

        // Remove ConnectHandler itself from the pipeline
        context.pipeline.removeHandler(context: context, promise: nil)

        // Decision: intercept TLS or tunnel raw bytes?
        let shouldIntercept = task.sslEnable == 1 && !recorder.session.ignore

        AxLogger.log("[CONNECT] \(request.host):\(request.port) sslEnable=\(task.sslEnable) ignore=\(recorder.session.ignore) → \(shouldIntercept ? "MITM" : "Tunnel")", level: .Warning)

        if shouldIntercept {
            // Add MITMHandler for TLS interception (handled by TLSPlugin in the tree)
            let mitmHandler = MITMHandler(
                task: task,
                recorder: recorder,
                host: request.host,
                port: request.port
            )
            _ = context.pipeline.addHandler(mitmHandler, name: "mitm", position: .first)
        } else {
            // Re-detect inner protocol via ProtocolDispatcher
            let tcpChildren = ProtocolRegistry.shared.tcpChildren
            let dispatcher = ProtocolDispatcher(
                task: task, nodes: tcpChildren, recorder: recorder
            )
            _ = context.pipeline.addHandler(dispatcher, name: "dispatcher")
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        recorder.recordError("ConnectHandler error: \(error)")
        context.close(promise: nil)
    }
}
