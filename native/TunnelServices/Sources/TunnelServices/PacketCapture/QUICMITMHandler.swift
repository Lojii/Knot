//
//  QUICMITMHandler.swift
//  TunnelServices
//
//  QUIC Man-in-the-Middle handler for HTTP/3 traffic capture.
//  Uses quiche (Cloudflare) for QUIC + HTTP/3 protocol handling.
//
//  Flow:
//  1. PacketCaptureEngine intercepts UDP:443 packets
//  2. QUICMITMHandler creates two quiche connections:
//     - Server-side: accepts QUIC from the App (with dynamic cert)
//     - Client-side: connects to real server
//  3. HTTP/3 requests/responses are decoded and recorded
//  4. Data is forwarded bidirectionally
//
//  Can be enabled/disabled via ProxyConfig.HTTP3.enabled
//

import Foundation
import NIO
import NIOFoundationCompat

#if canImport(SwiftQuiche)
import SwiftQuiche

// MARK: - QUIC MITM Session

/// Represents a single QUIC MITM session (one App ↔ Proxy ↔ Server pair).
public class QUICMITMSession {

    /// Connection ID → session mapping
    let connectionId: Data
    let serverName: String
    let serverPort: UInt16

    // Server-side (App → Proxy) quiche connection
    var clientConn: QUICConnection?
    // Client-side (Proxy → Real Server) quiche connection
    var serverConn: QUICConnection?

    /// The SCID used by the MITM's server-side (accepts from app) connection.
    /// After handshake, the client uses this as DCID in short header packets.
    private(set) var clientFacingSCID: Data?

    /// The SCID used by the MITM's client-side (connects to real server) connection.
    /// Server response packets will have this as their DCID.
    private(set) var serverSCID: Data?

    // Stored addresses for recv calls (quiche dereferences these)
    private var clientLocalAddr: sockaddr_in = makeIPv4Addr(ip: "127.0.0.1", port: 0)
    private var clientPeerAddr: sockaddr_in = makeIPv4Addr(ip: "0.0.0.0", port: 0)
    private var serverLocalAddr: sockaddr_in = makeIPv4Addr(ip: "127.0.0.1", port: 0)
    private var serverPeerAddr: sockaddr_in = makeIPv4Addr(ip: "0.0.0.0", port: 0)

    // HTTP/3 connections
    var clientH3: HTTP3Connection?
    var serverH3: HTTP3Connection?

    // Session recording
    let recorder: SessionRecorder
    var streamRequests = [UInt64: [(String, String)]]()   // streamId → request headers
    var streamResponses = [UInt64: [(String, String)]]()  // streamId → response headers

    public init(connectionId: Data, serverName: String, serverPort: UInt16, task: CaptureTask) {
        self.connectionId = connectionId
        self.serverName = serverName
        self.serverPort = serverPort
        self.recorder = SessionRecorder(task: task)
        recorder.session.schemes = "H3"
        recorder.session.host = serverName
    }

    // MARK: - Setup

    /// Initialize the MITM connections.
    public func setup(certPath: String, keyPath: String) -> Bool {
        // Server-side config (accepts from App)
        let serverConfig = QUICConfig()
        serverConfig.setApplicationProtocols(["h3"])
        serverConfig.applyDefaults()
        _ = serverConfig.loadCertChain(fromPEM: certPath)
        _ = serverConfig.loadPrivateKey(fromPEM: keyPath)

        // Client-side config (connects to real server)
        let clientConfig = QUICConfig()
        clientConfig.setApplicationProtocols(["h3"])
        clientConfig.applyDefaults()
        clientConfig.verifyPeer(false)  // We're the MITM, skip verification

        // Create connections with dummy sockaddr (quiche needs them for recv calls)
        let serverSideSCID = generateConnectionId()  // MITM's server-side own SCID
        let clientSideSCID = generateConnectionId()   // MITM's client-side own SCID
        self.clientFacingSCID = serverSideSCID
        self.serverSCID = clientSideSCID
        let localAddr = makeIPv4Addr(ip: "127.0.0.1", port: 0)
        let peerAddr = makeIPv4Addr(ip: "0.0.0.0", port: serverPort)
        clientLocalAddr = localAddr
        clientPeerAddr = peerAddr
        serverLocalAddr = localAddr
        serverPeerAddr = peerAddr
        // Server-side connection (accepts from App): SCID=server-chosen, ODCID=client's initial DCID
        clientConn = QUICConnection(scid: serverSideSCID, odcid: connectionId, localAddr: localAddr, peerAddr: peerAddr, config: serverConfig)
        // Client-side connection (connects to real server)
        serverConn = QUICConnection(serverName: serverName, scid: clientSideSCID, localAddr: localAddr, peerAddr: peerAddr, config: clientConfig)

        guard clientConn != nil && serverConn != nil else {
            AxLogger.log("QUIC MITM: Failed to create connections for \(serverName)", level: .Error)
            return false
        }

        return true
    }

    // MARK: - Process Packets

    /// Process an incoming QUIC packet from the App.
    /// Returns (toApp, toServer): packets to send to the client and packets to send to the real server.
    public func processClientPacket(_ data: Data) -> (toApp: [Data], toServer: [Data]) {
        guard let conn = clientConn else { return ([], []) }
        let _ = conn.recv(data, from: clientPeerAddr, to: clientLocalAddr)

        // Check if connection is established → setup HTTP/3
        if conn.isEstablished && clientH3 == nil {
            let h3Config = HTTP3Config()
            clientH3 = HTTP3Connection(quicConn: conn, config: h3Config)
            AxLogger.log("QUIC MITM: HTTP/3 established with client for \(serverName)", level: .Info)
        }

        // Poll HTTP/3 events from client (may forward requests to serverConn)
        if let h3 = clientH3 {
            pollClientEvents(h3, conn: conn)
        }

        // Drain clientConn outbound → these go to the App
        var toApp = [Data]()
        while let packet = conn.send() {
            toApp.append(packet)
        }

        // Drain serverConn outbound → these go to the real server
        var toServer = [Data]()
        if let sConn = serverConn {
            while let packet = sConn.send() {
                toServer.append(packet)
            }
        }

        return (toApp, toServer)
    }

    /// Process a response QUIC packet from the real server.
    /// Returns (toApp, toServer): packets to send to the client and packets to send back to the server.
    public func processServerPacket(_ data: Data) -> (toApp: [Data], toServer: [Data]) {
        guard let conn = serverConn else { return ([], []) }
        let _ = conn.recv(data, from: serverPeerAddr, to: serverLocalAddr)

        if conn.isEstablished && serverH3 == nil {
            let h3Config = HTTP3Config()
            serverH3 = HTTP3Connection(quicConn: conn, config: h3Config)
            AxLogger.log("QUIC MITM: HTTP/3 established with server \(serverName)", level: .Info)
        }

        // Poll HTTP/3 events from server (may forward responses to clientConn)
        if let h3 = serverH3 {
            pollServerEvents(h3, conn: conn)
        }

        // Drain serverConn outbound → these go back to the real server (handshake cont.)
        var toServer = [Data]()
        while let packet = conn.send() {
            toServer.append(packet)
        }

        // Drain clientConn outbound → these go to the App (forwarded responses)
        var toApp = [Data]()
        if let cConn = clientConn {
            while let packet = cConn.send() {
                toApp.append(packet)
            }
        }

        return (toApp, toServer)
    }

    // MARK: - HTTP/3 Event Processing

    private func pollClientEvents(_ h3: HTTP3Connection, conn: QUICConnection) {
        while true {
            let event = h3.poll(quicConn: conn)
            switch event {
            case .headers(let streamId, let headers):
                // Client sent a request
                streamRequests[streamId] = headers
                logRequest(streamId: streamId, headers: headers)

                // Forward request to real server
                if let serverH3 = serverH3, let serverConn = serverConn {
                    let _ = serverH3.sendRequest(quicConn: serverConn, headers: headers, fin: false)
                }

            case .data(let streamId):
                // Client sent body data
                if let body = h3.recvBody(quicConn: conn, streamId: streamId) {
                    logRequestBody(streamId: streamId, body: body)
                    // Forward to server
                    if let serverH3 = serverH3, let serverConn = serverConn {
                        let _ = serverH3.sendBody(quicConn: serverConn, streamId: streamId, data: body, fin: false)
                    }
                }

            case .finished(let streamId):
                // Client finished sending
                if let serverH3 = serverH3, let serverConn = serverConn {
                    let _ = serverH3.sendBody(quicConn: serverConn, streamId: streamId, data: Data(), fin: true)
                }

            case .done:
                return

            default:
                break
            }
        }
    }

    private func pollServerEvents(_ h3: HTTP3Connection, conn: QUICConnection) {
        while true {
            let event = h3.poll(quicConn: conn)
            switch event {
            case .headers(let streamId, let headers):
                // Server sent response headers
                streamResponses[streamId] = headers
                logResponse(streamId: streamId, headers: headers)

                // Forward response to client
                if let clientH3 = clientH3, let clientConn = clientConn {
                    let _ = clientH3.sendResponse(quicConn: clientConn, streamId: streamId, headers: headers, fin: false)
                }

            case .data(let streamId):
                // Server sent response body
                if let body = h3.recvBody(quicConn: conn, streamId: streamId) {
                    logResponseBody(streamId: streamId, body: body)
                    // Forward to client
                    if let clientH3 = clientH3, let clientConn = clientConn {
                        let _ = clientH3.sendBody(quicConn: clientConn, streamId: streamId, data: body, fin: false)
                    }
                }

            case .finished(let streamId):
                if let clientH3 = clientH3, let clientConn = clientConn {
                    let _ = clientH3.sendBody(quicConn: clientConn, streamId: streamId, data: Data(), fin: true)
                }
                recorder.recordResponseEnd()

            case .done:
                return

            default:
                break
            }
        }
    }

    // MARK: - Logging

    private func logRequest(streamId: UInt64, headers: [(String, String)]) {
        let method = headers.first(where: { $0.0 == ":method" })?.1 ?? "?"
        let path = headers.first(where: { $0.0 == ":path" })?.1 ?? "/"
        let authority = headers.first(where: { $0.0 == ":authority" })?.1 ?? serverName

        let log = "[H3 Request] \(method) \(path)\n  authority: \(authority)\n" +
                  headers.map { "  \($0.0): \($0.1)" }.joined(separator: "\n") + "\n"

        if let data = log.data(using: .utf8) {
            var buf = ByteBufferAllocator().buffer(capacity: data.count)
            buf.writeBytes(data)
            recorder.recordRequestBody(buf)
        }
        recorder.addUpload(log.utf8.count)
    }

    private func logRequestBody(streamId: UInt64, body: Data) {
        // Check if it's gRPC
        let isGRPC = streamRequests[streamId]?.contains(where: {
            $0.0 == "content-type" && $0.1.hasPrefix("application/grpc")
        }) ?? false

        if isGRPC {
            GRPCDecoder.logRequestBody(ByteBuffer(data: body), recorder: recorder)
        } else {
            var buf = ByteBufferAllocator().buffer(capacity: body.count)
            buf.writeBytes(body)
            recorder.recordRequestBody(buf)
        }
        recorder.addUpload(body.count)
    }

    private func logResponse(streamId: UInt64, headers: [(String, String)]) {
        let status = headers.first(where: { $0.0 == ":status" })?.1 ?? "?"
        let log = "[H3 Response] HTTP/3 \(status)\n" +
                  headers.map { "  \($0.0): \($0.1)" }.joined(separator: "\n") + "\n"

        if let data = log.data(using: .utf8) {
            var buf = ByteBufferAllocator().buffer(capacity: data.count)
            buf.writeBytes(data)
            recorder.recordResponseBody(buf)
        }
        recorder.addDownload(log.utf8.count)
    }

    private func logResponseBody(streamId: UInt64, body: Data) {
        let isGRPC = streamResponses[streamId]?.contains(where: {
            $0.0 == "content-type" && $0.1.hasPrefix("application/grpc")
        }) ?? false

        if isGRPC {
            GRPCDecoder.logResponseBody(ByteBuffer(data: body), recorder: recorder)
        } else {
            var buf = ByteBufferAllocator().buffer(capacity: body.count)
            buf.writeBytes(body)
            recorder.recordResponseBody(buf)
        }
        recorder.addDownload(body.count)
    }

    private func generateConnectionId() -> Data {
        var id = Data(count: 16)
        _ = id.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return id
    }

    public var isClosed: Bool {
        (clientConn?.isClosed ?? true) || (serverConn?.isClosed ?? true)
    }
}

// MARK: - QUIC MITM Manager

/// Manages all active QUIC MITM sessions.
/// Called by PacketCaptureEngine when UDP:443 packets are intercepted.
public class QUICMITMManager {

    private var sessions = [Data: QUICMITMSession]()  // connectionId → session
    private let task: CaptureTask
    private let certPath: String
    private let keyPath: String
    private let lock = NSLock()

    /// Look up a session by exact DCID match, or by prefix match for short headers
    /// where the DCID length is not known from the packet.
    private func findSession(dcid: Data, isShortHeader: Bool) -> QUICMITMSession? {
        // Try exact match first
        if let session = sessions[dcid] { return session }

        // For short headers, the DCID length is a heuristic (8 bytes by default).
        // The actual DCID may be longer (e.g. 16 bytes). Try prefix matching.
        if isShortHeader {
            for (key, session) in sessions {
                if key.count > dcid.count && key.prefix(dcid.count) == dcid {
                    return session
                }
            }
        }

        return nil
    }

    public init(task: CaptureTask, certPath: String, keyPath: String) {
        self.task = task
        self.certPath = certPath
        self.keyPath = keyPath
    }

    /// Process an outbound QUIC packet (App → Internet).
    /// Returns response packets to write back to the App, and packets to send to the real server.
    public func processOutbound(_ data: Data, dstIP: String, dstPort: UInt16) -> (toApp: [Data], toServer: [(Data, String, UInt16)]) {
        // Extract connection ID from QUIC header
        guard let header = QUICDecoder.parseHeader(data) else {
            return ([], [])
        }

        let connId = header.dcid

        lock.lock()
        let session: QUICMITMSession
        if let existing = findSession(dcid: connId, isShortHeader: !header.isLongHeader) {
            session = existing
        } else {
            // New session
            let sni = QUICDecoder.extractSNI(data) ?? dstIP
            let newSession = QUICMITMSession(
                connectionId: connId, serverName: sni, serverPort: dstPort, task: task
            )
            guard newSession.setup(certPath: certPath, keyPath: keyPath) else {
                lock.unlock()
                return ([], [])
            }
            sessions[connId] = newSession
            // Also index by the MITM's connection IDs for session lookup
            if let clientFacingSCID = newSession.clientFacingSCID {
                sessions[clientFacingSCID] = newSession
            }
            if let serverSCID = newSession.serverSCID {
                sessions[serverSCID] = newSession
            }
            session = newSession
            AxLogger.log("QUIC MITM: New session for \(sni):\(dstPort)", level: .Info)
        }
        lock.unlock()

        // Process through MITM — returns (toApp, toServer)
        let result = session.processClientPacket(data)

        // Wrap toServer packets with destination info
        var toServer = result.toServer.map { (pkt: Data) -> (Data, String, UInt16) in
            (pkt, dstIP, dstPort)
        }

        // Clean up closed sessions
        if session.isClosed {
            lock.lock()
            sessions.removeValue(forKey: connId)
            if let clientFacingSCID = session.clientFacingSCID {
                sessions.removeValue(forKey: clientFacingSCID)
            }
            if let serverSCID = session.serverSCID {
                sessions.removeValue(forKey: serverSCID)
            }
            lock.unlock()
        }

        return (result.toApp, toServer)
    }

    /// Process an inbound QUIC packet (Internet → App).
    /// Returns (toApp, toServer): packets for the client app, and packets to send back to the server.
    public func processInbound(_ data: Data, srcIP: String, srcPort: UInt16) -> (toApp: [Data], toServer: [(Data, String, UInt16)]) {
        guard let header = QUICDecoder.parseHeader(data) else { return ([], []) }

        lock.lock()
        guard let session = findSession(dcid: header.dcid, isShortHeader: !header.isLongHeader) else {
            lock.unlock()
            return ([], [])
        }
        lock.unlock()

        let result = session.processServerPacket(data)
        let toServer = result.toServer.map { (pkt: Data) -> (Data, String, UInt16) in
            (pkt, srcIP, srcPort)
        }
        return (result.toApp, toServer)
    }

    public var activeSessions: Int {
        lock.lock(); defer { lock.unlock() }
        // Each session may be indexed by up to 2 keys (connId + serverSCID)
        // Deduplicate by counting unique object identities
        var unique = Set<ObjectIdentifier>()
        for session in sessions.values {
            unique.insert(ObjectIdentifier(session))
        }
        return unique.count
    }

    public func shutdown() {
        lock.lock()
        sessions.removeAll()
        lock.unlock()
    }
}

#else
// Stub when SwiftQuiche is not available
public class QUICMITMManager {
    public init(task: CaptureTask, certPath: String, keyPath: String) {}
    public func processOutbound(_ data: Data, dstIP: String, dstPort: UInt16) -> (toApp: [Data], toServer: [(Data, String, UInt16)]) { ([], []) }
    public func processInbound(_ data: Data, srcIP: String, srcPort: UInt16) -> (toApp: [Data], toServer: [(Data, String, UInt16)]) { ([], []) }
    public var activeSessions: Int { 0 }
    public func shutdown() {}
}
#endif
