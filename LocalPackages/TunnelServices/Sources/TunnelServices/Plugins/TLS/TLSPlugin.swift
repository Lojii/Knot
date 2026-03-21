//
//  TLSPlugin.swift
//  TunnelServices
//
//  Unwrap plugin that detects a TLS ClientHello (content type 0x16) and
//  either MITM-intercepts the stream (when sslEnable is on) or falls back
//  to tunnel passthrough with passive sniffing.
//

import Foundation
import NIO
import NIOHTTP1

// MARK: - TLSPlugin

/// Detects TLS ClientHello and configures the appropriate pipeline:
/// - MITM path when `task.sslEnable == 1` and the host is not rule-ignored.
/// - Tunnel passthrough + passive TLS sniff otherwise.
///
/// This is an *unwrap* plugin: `createRecorder` returns `nil` because TLS
/// itself does not record traffic — the inner protocol (HTTP/1.x, HTTP/2)
/// creates its own recorder after the handshake.
public final class TLSPlugin: ProtocolPlugin {

    public let id = "tls"
    public let displayName = "TLS"

    public init() {}

    // MARK: - ProtocolPlugin

    /// Matches a TLS handshake record (first byte == 0x16, version bytes ≤ 0x03).
    /// At least 3 bytes are required.
    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        guard buffer.readableBytes >= 3 else { return .needMoreData(minimum: 3) }
        let b1 = buffer.getInteger(at: buffer.readerIndex,     as: UInt8.self) ?? 0
        let b2 = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) ?? 0
        let b3 = buffer.getInteger(at: buffer.readerIndex + 2, as: UInt8.self) ?? 0
        return (b1 == 22 && b2 <= 3 && b3 <= 3) ? .yes(confidence: 100) : .no
    }

    /// Builds the TLS pipeline.
    ///
    /// Replaces the former `ProtocolRouter.configureDirectTLSPipeline(_:buffer:)`:
    /// - Extracts SNI from the ClientHello.
    /// - Sets `recorder.session.host` and `recorder.session.schemes`.
    /// - Adds `MITMHandler` when interception is enabled and SNI is available.
    /// - Falls back to `TLSClientSniffHandler` + `TunnelHandler` otherwise.
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let task     = context.task
        let recorder = context.recorder
        let channel  = context.channel
        let buffer   = context.initialBuffer

        // Extract SNI from the buffered ClientHello (may be nil for non-SNI clients).
        let sni  = buffer.flatMap { extractSNI(from: $0) }
        let host = sni ?? context.metadata.innerHost ?? "unknown"
        let port = context.metadata.innerPort ?? 443

        recorder.session.host    = host
        recorder.session.schemes = "HTTPS"
        recorder.recordRequestHead(
            HTTPRequestHead(version: .http1_1, method: .CONNECT, uri: "\(host):\(port)"),
            localAddress: channel.remoteAddress, isSSL: true
        )

        // MITM if CA is trusted. Future: rule engine controls per-host interception.
        let shouldIntercept = task.isCACertTrusted
        AxLogger.log("[TLSPlugin] host=\(host) sslEnable=\(task.sslEnable) sni=\(sni ?? "nil") → \(shouldIntercept ? "MITM" : "Tunnel")", level: .Warning)

        if shouldIntercept && sni != nil {
            // MITM path — generate a dynamic cert and decrypt the stream.
            let mitmHandler = MITMHandler(task: task, recorder: recorder, host: host, port: port)
            return channel.pipeline.addHandler(mitmHandler, name: "mitm")
        } else {
            // Tunnel passthrough with passive TLS sniffing.
            AxLogger.log("[TLSPlugin] Tunnel path: host=\(host) port=\(port) sni=\(sni ?? "nil") innerHost=\(context.metadata.innerHost ?? "nil")", level: .Warning)
            recorder.addProtoFlag(.tlsTunnel)
            recorder.session.schemes = "HTTPS(Tunnel)"
            recorder.ensureHttpRecorder(
                host: host, port: port,
                protocolOverride: "HTTPS",
                method: "DIRECT TLS", uri: host,
                extraMetadata: ["encrypted": true, "decrypted": false]
            )
            return channel.pipeline.addHandler(
                TLSClientSniffHandler(recorder: recorder),
                name: "tls.sniff.client"
            ).flatMap {
                let tunnel = TunnelHandler(recorder: recorder, task: task,
                                           targetHost: host, targetPort: port)
                return channel.pipeline.addHandler(tunnel, name: "tunnel")
            }
        }
    }

    /// TLS is an unwrap/transport layer — the inner protocol owns the recorder.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        return nil
    }

    // MARK: - SNI Extraction

    /// Extract the SNI hostname from a TLS ClientHello byte buffer.
    /// Replaces the former `ProtocolRouter.extractSNI(from:)`.
    private func extractSNI(from buffer: ByteBuffer) -> String? {
        guard buffer.readableBytes >= 43 else { return nil }
        let base = buffer.readerIndex

        guard buffer.getInteger(at: base,     as: UInt8.self) == 22,  // Handshake content type
              buffer.getInteger(at: base + 5, as: UInt8.self) == 1    // ClientHello
        else { return nil }

        // skip: record header(5) + handshake header(4) + client version(2) + random(32)
        var pos = base + 5 + 4 + 2 + 32
        guard pos < base + buffer.readableBytes else { return nil }

        // Skip session ID
        let sidLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
        pos += 1 + sidLen

        // Skip cipher suites
        guard pos + 2 <= base + buffer.readableBytes else { return nil }
        let csLen = Int(buffer.getInteger(at: pos, as: UInt16.self) ?? 0)
        pos += 2 + csLen

        // Skip compression methods
        guard pos + 1 <= base + buffer.readableBytes else { return nil }
        let compLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
        pos += 1 + compLen

        // Walk extensions looking for SNI (type 0x0000)
        guard pos + 2 <= base + buffer.readableBytes else { return nil }
        let extTotalLen = Int(buffer.getInteger(at: pos, as: UInt16.self) ?? 0)
        pos += 2
        let extEnd = pos + extTotalLen

        while pos + 4 <= extEnd && pos + 4 <= base + buffer.readableBytes {
            let extType = buffer.getInteger(at: pos,     as: UInt16.self) ?? 0
            let extLen  = Int(buffer.getInteger(at: pos + 2, as: UInt16.self) ?? 0)
            if extType == 0x0000 {
                return TLSSniffUtils.parseSNI(buffer, offset: pos + 4, length: extLen)
            }
            pos += 4 + extLen
        }
        return nil
    }
}
