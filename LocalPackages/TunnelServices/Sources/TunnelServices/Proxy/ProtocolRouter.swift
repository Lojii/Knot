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
import NIOFoundationCompat

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

        if isSOCKS5Greeting(buffer) {
            // SOCKS5 proxy: first byte 0x05
            configureSOCKS5Pipeline(context: context)
        } else if prefix == "CONN" {
            // HTTPS: HTTP CONNECT method → tunnel setup
            configureHTTPSPipeline(context: context)
        } else if ProtocolRouter.httpMethods.contains(where: { prefix.hasPrefix($0.prefix(4)) }) {
            // Plain HTTP request
            configureHTTPPipeline(context: context)
        } else if isTLSClientHello(buffer) {
            // Direct TLS connection — extract SNI and MITM or tunnel
            configureDirectTLSPipeline(context: context, buffer: buffer)
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

    private func configureDirectTLSPipeline(context: ChannelHandlerContext, buffer: ByteBuffer) {
        let recorder = SessionRecorder(task: task)

        // Extract SNI from ClientHello to get the target host
        let sni = extractSNI(from: buffer)
        let host = sni ?? "unknown"
        let port = 443

        recorder.session.host = host
        recorder.session.schemes = "HTTPS"
        recorder.recordRequestHead(
            HTTPRequestHead(version: .http1_1, method: .CONNECT, uri: "\(host):\(port)"),
            localAddress: context.channel.remoteAddress, isSSL: true
        )

        let shouldIntercept = task.sslEnable == 1 && !task.ruleEngine.matching(host: host, uri: "/", target: "")

        if shouldIntercept && sni != nil {
            // MITM: we have the host from SNI, generate dynamic cert
            let mitmHandler = MITMHandler(task: task, recorder: recorder, host: host, port: port)
            _ = context.pipeline.addHandler(mitmHandler, name: "mitm", position: .first)
        } else {
            // Tunnel passthrough with TLS sniff
            recorder.session.schemes = "HTTPS(Tunnel)"
            recorder.ensureHttpRecorder(
                host: host, port: port,
                protocolOverride: "HTTPS",
                method: "DIRECT TLS", uri: host,
                extraMetadata: ["encrypted": true, "decrypted": false]
            )
            _ = context.pipeline.addHandler(
                TLSClientSniffHandler(recorder: recorder), name: "tls.sniff.client", position: .first
            )
            let tunnel = TunnelHandler(recorder: recorder, task: task, targetHost: host, targetPort: port)
            _ = context.pipeline.addHandler(tunnel, name: "tunnel")
        }
    }

    /// Extract SNI (Server Name Indication) from a TLS ClientHello.
    private func extractSNI(from buffer: ByteBuffer) -> String? {
        // TLS record: type(1) + version(2) + length(2)
        // Handshake: type(1) + length(3)
        // ClientHello: version(2) + random(32) + sessionId(var) + cipherSuites(var) + compression(var) + extensions
        guard buffer.readableBytes >= 43 else { return nil }
        let base = buffer.readerIndex

        // Verify TLS handshake + ClientHello
        guard buffer.getInteger(at: base, as: UInt8.self) == 22,      // Handshake
              buffer.getInteger(at: base + 5, as: UInt8.self) == 1     // ClientHello
        else { return nil }

        var pos = base + 5 + 4 + 2 + 32 // skip record(5) + hs header(4) + version(2) + random(32)
        guard pos < base + buffer.readableBytes else { return nil }

        // Skip session ID
        let sidLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
        pos += 1 + sidLen

        // Skip cipher suites
        guard pos + 2 <= base + buffer.readableBytes else { return nil }
        let csLen = Int(buffer.getInteger(at: pos, as: UInt16.self) ?? 0)
        pos += 2 + csLen

        // Skip compression
        guard pos + 1 <= base + buffer.readableBytes else { return nil }
        let compLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
        pos += 1 + compLen

        // Extensions
        guard pos + 2 <= base + buffer.readableBytes else { return nil }
        let extTotalLen = Int(buffer.getInteger(at: pos, as: UInt16.self) ?? 0)
        pos += 2
        let extEnd = pos + extTotalLen

        while pos + 4 <= extEnd && pos + 4 <= base + buffer.readableBytes {
            let extType = buffer.getInteger(at: pos, as: UInt16.self) ?? 0
            let extLen = Int(buffer.getInteger(at: pos + 2, as: UInt16.self) ?? 0)
            if extType == 0x0000 { // SNI
                return TLSSniffUtils.parseSNI(buffer, offset: pos + 4, length: extLen)
            }
            pos += 4 + extLen
        }
        return nil
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

    private func configureSOCKS5Pipeline(context: ChannelHandlerContext) {
        _ = context.pipeline.addHandler(
            SOCKS5ServerHandler(task: task), name: "socks5", position: .first
        )
    }

    // MARK: - Protocol Detection

    private func isSOCKS5Greeting(_ buffer: ByteBuffer) -> Bool {
        guard buffer.readableBytes >= 2 else { return false }
        let version = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) ?? 0
        let methodCount = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) ?? 0
        // SOCKS5: version=0x05, methodCount=1..255, total size = 2 + methodCount
        return version == 0x05 && methodCount > 0 && buffer.readableBytes >= 2 + Int(methodCount)
    }

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
