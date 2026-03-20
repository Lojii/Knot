//
//  SOCKS5Plugin.swift
//  TunnelServices
//
//  Unwrap plugin that detects SOCKS5 greeting (first byte 0x05) and
//  adds SOCKS5ServerHandler to the NIO pipeline.
//

import Foundation
import NIO

// MARK: - SOCKS5Plugin

/// Detects a SOCKS5 greeting and configures the pipeline with `SOCKS5ServerHandler`.
///
/// Matching requires:
///  - At least 2 bytes (version + method count)
///  - Version byte == 0x05
///  - Method count > 0
///  - Enough bytes to cover all advertised methods (2 + methodCount)
///
/// This is an *unwrap* plugin: `createRecorder` returns `nil` because SOCKS5
/// is a transport wrapper — the inner protocol owns the recorder after the
/// handshake completes.
public final class SOCKS5Plugin: ProtocolPlugin {
    public let id = "socks5"
    public let displayName = "SOCKS5"

    public init() {}

    // MARK: - ProtocolPlugin

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        guard buffer.readableBytes >= 2 else { return .needMoreData(minimum: 2) }
        let version     = buffer.getInteger(at: buffer.readerIndex,     as: UInt8.self) ?? 0
        let methodCount = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) ?? 0
        guard version == 0x05, methodCount > 0 else { return .no }
        let needed = 2 + Int(methodCount)
        guard buffer.readableBytes >= needed else { return .needMoreData(minimum: needed) }
        return .yes(confidence: 95)
    }

    /// Adds `SOCKS5ServerHandler` to the front of the pipeline.
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let handler = SOCKS5ServerHandler(task: context.task)
        return context.channel.pipeline.addHandler(handler, name: "socks5.server", position: .first)
    }

    /// SOCKS5 is an unwrap/transport layer — the inner protocol owns the recorder.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        return nil
    }
}
