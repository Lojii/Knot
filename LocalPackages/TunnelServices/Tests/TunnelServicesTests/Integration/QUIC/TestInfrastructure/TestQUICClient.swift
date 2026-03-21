//
//  TestQUICClient.swift
//  TunnelServicesTests
//
//  In-memory H3 client for QUIC integration tests.
//  No UDP socket — exchanges raw Data packets with TestQUICServer.
//

import Foundation
import XCTest
@testable import TunnelServices
import SwiftQuiche

/// Represents a received H3 response.
struct H3Response {
    var headers: [(String, String)]
    var body: Data
}

class TestQUICClient {
    private(set) var conn: QUICConnection?
    private(set) var h3Conn: HTTP3Connection?
    private var config: QUICConfig
    private var h3Config: HTTP3Config

    private let localAddr: sockaddr_in
    private let peerAddr: sockaddr_in

    /// Tracks partial responses by stream ID.
    private var partialResponses: [UInt64: H3Response] = [:]
    /// Completed responses ready for retrieval.
    private var completedResponses: [H3Response] = []

    init(serverName: String = "localhost") throws {
        let cfg = QUICConfig()
        cfg.verifyPeer(false)
        cfg.setApplicationProtocols(["h3"])
        cfg.applyDefaults()

        self.config = cfg
        self.h3Config = HTTP3Config()
        self.localAddr = makeIPv4Addr(ip: "127.0.0.1", port: 5555)
        self.peerAddr = makeIPv4Addr(ip: "127.0.0.1", port: 4433)

        let scid = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        guard let connection = QUICConnection(
            serverName: serverName,
            scid: scid,
            localAddr: localAddr,
            peerAddr: peerAddr,
            config: cfg
        ) else {
            throw NSError(domain: "TestQUICClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create QUIC connection"])
        }
        self.conn = connection
    }

    /// Start connection -- returns Initial packets (ClientHello) to send to server.
    func startConnection() -> [Data] {
        return drainOutbound()
    }

    /// Feed received packets from server and return outgoing packets.
    func receive(_ packets: [Data]) -> [Data] {
        guard let conn = conn else { return [] }

        for packet in packets {
            let _ = conn.recv(packet, from: peerAddr, to: localAddr)
        }

        // If connection is established and no H3 yet, create it
        if conn.isEstablished && h3Conn == nil {
            h3Conn = HTTP3Connection(quicConn: conn, config: h3Config)
        }

        // Poll for any H3 events
        pollH3Events()

        return drainOutbound()
    }

    /// Drain all pending outbound packets.
    func drainOutbound() -> [Data] {
        guard let conn = conn else { return [] }
        var packets = [Data]()
        while let pkt = conn.send() {
            packets.append(pkt)
        }
        return packets
    }

    /// Whether the QUIC handshake is complete.
    var isEstablished: Bool {
        conn?.isEstablished ?? false
    }

    /// Send an H3 request. Returns outgoing QUIC packets.
    func sendRequest(
        method: String = "GET",
        path: String = "/",
        authority: String = "localhost",
        body: Data? = nil
    ) -> [Data] {
        guard let conn = conn, let h3 = h3Conn else { return [] }

        let headers: [(String, String)] = [
            (":method", method),
            (":path", path),
            (":authority", authority),
            (":scheme", "https"),
        ]

        let fin = (body == nil || body!.isEmpty)
        let streamId = h3.sendRequest(quicConn: conn, headers: headers, fin: fin)
        guard streamId >= 0 else { return drainOutbound() }

        if let body = body, !body.isEmpty {
            let _ = h3.sendBody(quicConn: conn, streamId: UInt64(streamId), data: body, fin: true)
        }

        return drainOutbound()
    }

    /// Poll for received H3 responses. Returns all completed responses.
    func pollResponses() -> [(headers: [(String, String)], body: Data)] {
        pollH3Events()
        let result = completedResponses.map { ($0.headers, $0.body) }
        completedResponses.removeAll()
        return result
    }

    // MARK: - Private

    private func pollH3Events() {
        guard let conn = conn, let h3 = h3Conn else { return }

        while true {
            let event = h3.poll(quicConn: conn)
            switch event {
            case .headers(let streamId, let headers):
                partialResponses[streamId] = H3Response(headers: headers, body: Data())

            case .data(let streamId):
                if let data = h3.recvBody(quicConn: conn, streamId: streamId) {
                    partialResponses[streamId]?.body.append(data)
                }

            case .finished(let streamId):
                if let response = partialResponses.removeValue(forKey: streamId) {
                    completedResponses.append(response)
                }

            case .done:
                return

            default:
                break
            }
        }
    }
}
