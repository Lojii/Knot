//
//  ProtocolRouter.swift
//  TunnelServices
//
//  First handler in the pipeline. Inspects the initial bytes to determine
//  whether the client is sending plain HTTP or an HTTP CONNECT request (for HTTPS).
//  Then configures the appropriate pipeline and removes itself.
//

import Foundation
import NIO
import NIOHTTP1
import NIOSSL

public final class ProtocolRouter: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private let task: CaptureTask
    private static let httpMethods = ["GET ", "POST", "PUT ", "HEAD", "OPTI", "PATC", "DELE", "TRAC", "CONN"]

    public init(task: CaptureTask) {
        self.task = task
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Check if this channel's listener is still enabled
        if let local = context.channel.localAddress?.description {
            let isLocal = local.contains(ProxyConfig.LocalProxy.host)
            if (isLocal && task.localEnable == 0) || (!isLocal && task.wifiEnable == 0) {
                context.close(promise: nil)
                return
            }
        }

        let buffer = unwrapInboundIn(data)
        guard buffer.readableBytes >= 4 else {
            context.close(promise: nil)
            return
        }

        let prefix = buffer.getString(at: buffer.readerIndex, length: 4) ?? ""

        if prefix == "CONN" {
            // HTTPS: HTTP CONNECT method → tunnel setup
            configureHTTPSPipeline(context: context)
        } else if ProtocolRouter.httpMethods.contains(where: { prefix.hasPrefix($0.prefix(4)) }) {
            // Plain HTTP request
            configureHTTPPipeline(context: context)
        } else if isTLSClientHello(buffer) {
            // Direct TLS connection (rare - usually comes via CONNECT)
            configureTunnelPipeline(context: context)
        } else {
            // Unknown protocol — still record the connection attempt
            configureRawPipeline(context: context, firstBytes: buffer)
        }

        // Forward the data to the newly configured pipeline
        context.fireChannelRead(data)
        context.pipeline.removeHandler(self, promise: nil)
    }

    // MARK: - Pipeline Configuration

    private func configureHTTPPipeline(context: ChannelHandlerContext) {
        let recorder = SessionRecorder(task: task)

        _ = context.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)), name: "http.requestDecoder")
        _ = context.pipeline.addHandler(HTTPResponseEncoder(), name: "http.responseEncoder")
        _ = context.pipeline.addHandler(HTTPServerPipelineHandler(), name: "http.pipelining")
        _ = context.pipeline.addHandler(HTTPCaptureHandler(recorder: recorder, isSSL: false), name: "http.capture")
    }

    private func configureHTTPSPipeline(context: ChannelHandlerContext) {
        let recorder = SessionRecorder(task: task)

        _ = context.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)), name: "https.requestDecoder")
        _ = context.pipeline.addHandler(HTTPResponseEncoder(), name: "https.responseEncoder")
        _ = context.pipeline.addHandler(HTTPServerPipelineHandler(), name: "https.pipelining")
        _ = context.pipeline.addHandler(ConnectHandler(task: task, recorder: recorder), name: "https.connect")
    }

    private func configureTunnelPipeline(context: ChannelHandlerContext) {
        let recorder = SessionRecorder(task: task)
        _ = context.pipeline.addHandler(TunnelHandler(recorder: recorder, task: task), name: "tunnel")
    }

    private func configureRawPipeline(context: ChannelHandlerContext, firstBytes: ByteBuffer) {
        let recorder = SessionRecorder(task: task)
        let data = Data(buffer: firstBytes)
        let peer = context.channel.remoteAddress?.description
        let local = context.channel.localAddress?.description
        recorder.recordRawConnection(peerAddress: peer, localAddress: local, firstBytes: data)
        // Keep connection open — add a handler that records any further data,
        // then lets the client/server close naturally.
        _ = context.pipeline.addHandler(
            RawPassthroughHandler(recorder: recorder), name: "raw.passthrough"
        )
    }

    // MARK: - TLS Detection

    private func isTLSClientHello(_ buffer: ByteBuffer) -> Bool {
        guard buffer.readableBytes >= 3 else { return false }
        let b1 = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) ?? 0
        let b2 = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) ?? 0
        let b3 = buffer.getInteger(at: buffer.readerIndex + 2, as: UInt8.self) ?? 0
        return b1 == 22 && b2 <= 3 && b3 <= 3  // TLS Handshake record
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - Raw Passthrough Handler

/// Keeps the connection open for unrecognized protocols.
/// Records byte counts and calls recordClosed() when the connection ends.
final class RawPassthroughHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private let recorder: SessionRecorder

    init(recorder: SessionRecorder) {
        self.recorder = recorder
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        recorder.addUpload(buffer.readableBytes)
        // Data goes nowhere — no target server for unrecognized proxy protocol.
        // The connection stays open until the client closes it.
    }

    func channelUnregistered(context: ChannelHandlerContext) {
        recorder.recordClosed()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
