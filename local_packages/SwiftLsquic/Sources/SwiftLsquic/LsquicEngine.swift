//
//  LsquicEngine.swift
//  SwiftLsquic
//
//  Swift wrapper for LiteSpeed's lsquic QUIC + HTTP/3 C library.
//  Provides callback-driven API for QUIC connections.
//

import Foundation
import CLsquic

// MARK: - QUIC Engine (lsquic)

/// Wraps lsquic_engine for managing QUIC connections.
/// lsquic uses a callback-driven model: you provide stream_if callbacks
/// and the engine calls them when events occur.
public class LsquicEngine {

    private var engine: OpaquePointer?
    private var isServer: Bool

    /// Callback for sending UDP packets.
    public var onPacketsOut: ((_ data: Data, _ peerAddr: sockaddr_in) -> Int)?

    /// Callback for received HTTP/3 headers.
    public var onHeaders: ((_ streamId: UInt64, _ headers: [(String, String)]) -> Void)?

    /// Callback for received HTTP/3 body data.
    public var onData: ((_ streamId: UInt64, _ data: Data) -> Void)?

    /// Callback for stream close.
    public var onStreamClose: ((_ streamId: UInt64) -> Void)?

    /// Callback for connection established.
    public var onConnected: ((_ sni: String) -> Void)?

    public init(isServer: Bool) {
        self.isServer = isServer
        lsquic_global_init(isServer ? 1 : 0)
    }

    deinit {
        if let engine = engine {
            lsquic_engine_destroy(engine)
        }
        lsquic_global_cleanup()
    }

    /// Create and start the engine.
    public func start(certPath: String? = nil, keyPath: String? = nil) -> Bool {
        // This is a simplified wrapper. Full implementation would configure
        // engine_api with all callbacks, SSL context, etc.
        // For now, this provides the interface for the MITM manager.
        return true
    }

    /// Feed an incoming UDP packet to the engine.
    public func packetIn(_ data: Data, localAddr: sockaddr_in, peerAddr: sockaddr_in) {
        guard let engine = engine else { return }
        var local = localAddr
        var peer = peerAddr
        data.withUnsafeBytes { buf in
            withUnsafePointer(to: &local) { localPtr in
                withUnsafePointer(to: &peer) { peerPtr in
                    localPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { localSA in
                        peerPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { peerSA in
                            lsquic_engine_packet_in(
                                engine,
                                buf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                                data.count,
                                localSA,
                                peerSA,
                                nil, 0
                            )
                        }
                    }
                }
            }
        }
    }

    /// Process pending connection events and generate outgoing packets.
    public func processConns() {
        guard let engine = engine else { return }
        lsquic_engine_process_conns(engine)
    }

    /// Check if engine has unsent packets.
    public var hasUnsentPackets: Bool {
        guard let engine = engine else { return false }
        return lsquic_engine_has_unsent_packets(engine) != 0
    }

    /// Send any unsent packets.
    public func sendUnsentPackets() {
        guard let engine = engine else { return }
        lsquic_engine_send_unsent_packets(engine)
    }
}

// MARK: - lsquic Version Info

public enum LsquicInfo {
    public static var version: String {
        return "lsquic"
    }

    public static func isVersionSupported(_ version: UInt32) -> Bool {
        // lsquic internally handles version negotiation
        return true
    }
}
