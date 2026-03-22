//
//  TestQUICServer.swift
//  TunnelServicesTests
//
//  In-memory H3 echo server for QUIC integration tests.
//  No UDP socket — receives/returns raw Data packets.
//

import Foundation
import XCTest
@testable import TunnelServices
@testable import SwiftQuiche
import CQuiche

/// Tracks state for a single H3 request being assembled.
private struct PendingRequest {
    var headers: [(String, String)] = []
    var body: Data = Data()
    var finished: Bool = false
}

/// Reference-type wrapper so multiple dictionary keys can share the same connection state.
private class ConnectionEntry {
    let quic: QUICConnection
    var h3: HTTP3Connection?

    init(quic: QUICConnection) {
        self.quic = quic
        self.h3 = nil
    }
}

class TestQUICServer {
    private var config: QUICConfig
    /// Map from connection ID (either initial DCID or server SCID) to shared connection entry.
    private var connections: [Data: ConnectionEntry] = [:]
    /// Deduplicated list of all connection entries.
    private var allEntries: [ConnectionEntry] = []
    private var h3Config: HTTP3Config
    private var pendingRequests: [UInt64: PendingRequest] = [:]  // streamId -> request
    private(set) var requestCount: Int = 0

    private let localAddr: sockaddr_in
    private let peerAddr: sockaddr_in

    init(certPath: String, keyPath: String) throws {
        let cfg = QUICConfig()
        guard cfg.loadCertChain(fromPEM: certPath) else {
            throw NSError(domain: "TestQUICServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load cert from \(certPath)"])
        }
        guard cfg.loadPrivateKey(fromPEM: keyPath) else {
            throw NSError(domain: "TestQUICServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load key from \(keyPath)"])
        }
        cfg.setApplicationProtocols(["h3"])
        cfg.verifyPeer(false)
        cfg.applyDefaults()

        self.config = cfg
        self.h3Config = HTTP3Config()
        self.localAddr = makeIPv4Addr(ip: "127.0.0.1", port: 4433)
        self.peerAddr = makeIPv4Addr(ip: "127.0.0.1", port: 5555)
    }

    /// Generate test certs (leaf cert for "localhost" signed by a self-signed CA).
    /// Returns file paths to PEM cert and key on disk.
    static func generateTestCerts() throws -> (certPath: String, keyPath: String) {
        let (caCert, caKey, rsaKey) = try CertGenerator.generateCA()
        let leafCert = try CertGenerator.generateCert(
            host: "localhost",
            rsaKey: rsaKey,
            caKey: caKey,
            caCert: caCert
        )

        let certPEM = try CertGenerator.toPEM(leafCert)
        let keyPEM = rsaKey.pemRepresentation

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quic-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let certPath = tmpDir.appendingPathComponent("cert.pem").path
        let keyPath = tmpDir.appendingPathComponent("key.pem").path
        try certPEM.write(toFile: certPath, atomically: true, encoding: .utf8)
        try keyPEM.write(toFile: keyPath, atomically: true, encoding: .utf8)

        return (certPath, keyPath)
    }

    /// Feed a client packet. Returns response packets to send back.
    func receive(_ packet: Data) -> [Data] {
        // Extract DCID from the packet to find or create the connection
        guard let dcid = extractDCID(from: packet) else {
            return []
        }

        // Look up existing connection by DCID, or create a new one
        let entry: ConnectionEntry
        if let existing = connections[dcid] {
            entry = existing
        } else {
            let scid = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            guard let conn = QUICConnection(
                scid: scid,
                odcid: dcid,
                localAddr: localAddr,
                peerAddr: peerAddr,
                config: config
            ) else {
                return []
            }
            let newEntry = ConnectionEntry(quic: conn)
            // Index by both the initial DCID and the server's own SCID
            connections[dcid] = newEntry
            connections[scid] = newEntry
            allEntries.append(newEntry)
            entry = newEntry
        }

        let conn = entry.quic

        // Feed the packet with proper addresses
        let _ = conn.recv(packet, from: peerAddr, to: localAddr)

        // If connection is established and no H3 yet, create it
        if conn.isEstablished && entry.h3 == nil {
            entry.h3 = HTTP3Connection(quicConn: conn, config: h3Config)
        }

        // Poll H3 events if we have an H3 connection
        if let h3 = entry.h3 {
            pollH3Events(conn: conn, h3: h3)
        }

        // Drain outbound packets
        return drainPackets(from: conn)
    }

    /// Drain any pending outbound packets from all connections.
    func pendingOutbound() -> [Data] {
        var packets = [Data]()
        for entry in allEntries {
            let conn = entry.quic

            // Also poll H3 events before draining
            if let h3 = entry.h3 {
                pollH3Events(conn: conn, h3: h3)
            }

            packets.append(contentsOf: drainPackets(from: conn))
        }
        return packets
    }

    // MARK: - Private

    private func extractDCID(from packet: Data) -> Data? {
        var version: UInt32 = 0
        var pktType: UInt8 = 0
        var scid = [UInt8](repeating: 0, count: Int(QUICHE_MAX_CONN_ID_LEN))
        var scidLen = scid.count
        var dcid = [UInt8](repeating: 0, count: Int(QUICHE_MAX_CONN_ID_LEN))
        var dcidLen = dcid.count
        var token = [UInt8](repeating: 0, count: 1024)
        var tokenLen = token.count

        let result = packet.withUnsafeBytes { bufPtr -> Int32 in
            guard let base = bufPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return quiche_header_info(
                base, packet.count,
                16,  // dcid length for server (local SCID length)
                &version, &pktType,
                &scid, &scidLen,
                &dcid, &dcidLen,
                &token, &tokenLen
            )
        }

        guard result >= 0 else { return nil }
        return Data(dcid[..<dcidLen])
    }

    private func pollH3Events(conn: QUICConnection, h3: HTTP3Connection) {
        for _ in 0..<100 {  // safety limit
            let event = h3.poll(quicConn: conn)
            switch event {
            case .headers(let streamId, let headers):
                pendingRequests[streamId] = PendingRequest(headers: headers)

            case .data(let streamId):
                if let body = h3.recvBody(quicConn: conn, streamId: streamId) {
                    pendingRequests[streamId]?.body.append(body)
                }

            case .finished(let streamId):
                pendingRequests[streamId]?.finished = true
                if let req = pendingRequests.removeValue(forKey: streamId) {
                    sendEchoResponse(conn: conn, h3: h3, streamId: streamId, request: req)
                    requestCount += 1
                }

            case .done:
                return

            default:
                break
            }
        }
    }

    private func sendEchoResponse(conn: QUICConnection, h3: HTTP3Connection, streamId: UInt64, request: PendingRequest) {
        let path = request.headers.first(where: { $0.0 == ":path" })?.1 ?? "/"
        let responseBody = "echo: \(path)".data(using: .utf8) ?? Data()

        let responseHeaders: [(String, String)] = [
            (":status", "200"),
            ("content-type", "text/plain"),
            ("content-length", "\(responseBody.count)"),
        ]

        let _ = h3.sendResponse(quicConn: conn, streamId: streamId, headers: responseHeaders, fin: responseBody.isEmpty)
        if !responseBody.isEmpty {
            let _ = h3.sendBody(quicConn: conn, streamId: streamId, data: responseBody, fin: true)
        }
    }

    private func drainPackets(from conn: QUICConnection) -> [Data] {
        var packets = [Data]()
        while let pkt = conn.send() {
            packets.append(pkt)
        }
        return packets
    }
}
