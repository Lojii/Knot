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
            requestHead = head

        case .body:
            break  // CONNECT has no body

        case .end:
            guard let head = requestHead else { return }
            handleConnect(context: context, head: head)
        }
    }

    private func handleConnect(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let request = NetRequest(head)
        request.ssl = true

        // Record request metadata
        recorder.recordRequestHead(head, localAddress: context.channel.remoteAddress, isSSL: true)
        recorder.session.host = request.host
        recorder.session.schemes = "Https"

        // Apply rule matching
        recorder.session.ignore = task.ruleEngine.matching(
            host: recorder.session.host ?? "", uri: head.uri, target: recorder.session.target ?? ""
        )
        if task.ruleEngine.defaultStrategy == .COPY {
            recorder.session.ignore = !recorder.session.ignore
        }

        // Send 200 Connection Established
        let response = HTTPResponseHead(
            version: head.version,
            status: .custom(code: 200, reasonPhrase: "Connection Established"),
            headers: ["content-length": "0"]
        )
        context.write(wrapOutboundOut(.head(response)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

        // Remove all HTTP handlers from pipeline (we're switching to raw bytes or TLS)
        context.pipeline.removeHandler(name: "https.requestDecoder", promise: nil)
        context.pipeline.removeHandler(name: "https.responseEncoder", promise: nil)
        context.pipeline.removeHandler(name: "https.pipelining", promise: nil)
        context.pipeline.removeHandler(name: "https.connect", promise: nil)
        // Don't remove ProtocolRouter - it already removed itself

        // Decision: intercept TLS or tunnel raw bytes?
        let shouldIntercept = task.sslEnable == 1 && !recorder.session.ignore

        if shouldIntercept {
            // Add MITMHandler for TLS interception
            let mitmHandler = MITMHandler(
                task: task,
                recorder: recorder,
                host: request.host,
                port: request.port
            )
            _ = context.pipeline.addHandler(mitmHandler, name: "mitm", position: .first)
        } else {
            // Raw tunnel - no TLS interception
            let tunnel = TunnelHandler(
                recorder: recorder,
                task: task,
                targetHost: request.host,
                targetPort: request.port
            )
            _ = context.pipeline.addHandler(tunnel, name: "tunnel", position: .first)
            recorder.session.note = "no cert config !"
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        recorder.recordError("ConnectHandler error: \(error)")
        context.close(promise: nil)
    }
}
