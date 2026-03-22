//
//  LsquicMITMHandler.swift
//  TunnelServices
//
//  QUIC MITM handler using LiteSpeed's lsquic (alternative to quiche).
//  Selected via ProxyConfig.HTTP3.backend = .lsquic
//
//  lsquic advantages over quiche:
//  - Pure C (no Rust dependency)
//  - Smaller binary (31MB vs 43MB)
//  - Supports legacy Google QUIC (Q043/Q046/Q050)
//  - Callback-driven API (more natural for event loops)
//

import Foundation

#if canImport(SwiftLsquic)
import SwiftLsquic
import NIO

// MARK: - Lsquic MITM Session

public class LsquicMITMSession {

    let connectionId: Data
    let serverName: String
    let serverPort: UInt16
    let recorder: SessionRecorder

    private var clientEngine: LsquicEngine?
    private var serverEngine: LsquicEngine?
    private var established = false
    private var clientOutPackets = [Data]()
    private var serverOutPackets = [Data]()

    public init(connectionId: Data, serverName: String, serverPort: UInt16, task: CaptureTask) {
        self.connectionId = connectionId
        self.serverName = serverName
        self.serverPort = serverPort
        self.recorder = SessionRecorder(task: task)
        recorder.session.schemes = "H3"
        recorder.session.host = serverName
    }

    public func setup(certPath: String, keyPath: String) -> Bool {
        // Server engine (accepts from App)
        clientEngine = LsquicEngine(isServer: true)
        clientEngine?.onHeaders = { [weak self] streamId, headers in
            self?.handleClientHeaders(streamId: streamId, headers: headers)
        }
        clientEngine?.onData = { [weak self] streamId, data in
            self?.handleClientData(streamId: streamId, data: data)
        }
        clientEngine?.onConnected = { [weak self] sni in
            AxLogger.log("lsquic MITM: connected from client for \(sni)", level: .Info)
        }
        guard clientEngine?.start(certPath: certPath, keyPath: keyPath) == true else { return false }
        clientEngine?.onPacketsOut = { [weak self] data, _ in
            self?.clientOutPackets.append(data)
            return data.count
        }

        // Client engine (connects to real server)
        serverEngine = LsquicEngine(isServer: false)
        serverEngine?.onHeaders = { [weak self] streamId, headers in
            self?.handleServerHeaders(streamId: streamId, headers: headers)
        }
        serverEngine?.onData = { [weak self] streamId, data in
            self?.handleServerData(streamId: streamId, data: data)
        }
        guard serverEngine?.start() == true else { return false }
        serverEngine?.onPacketsOut = { [weak self] data, _ in
            self?.serverOutPackets.append(data)
            return data.count
        }

        return true
    }

    public func processClientPacket(_ data: Data) -> [Data] {
        clientOutPackets.removeAll(keepingCapacity: true)
        serverOutPackets.removeAll(keepingCapacity: true)
        var localAddr = makeIPv4Addr(ip: "127.0.0.1", port: 0)
        var peerAddr = makeIPv4Addr(ip: "0.0.0.0", port: serverPort)
        clientEngine?.packetIn(data, localAddr: localAddr, peerAddr: peerAddr)
        clientEngine?.processConns()
        return clientOutPackets
    }

    public func pendingServerPackets() -> [Data] {
        let packets = serverOutPackets
        serverOutPackets.removeAll(keepingCapacity: true)
        return packets
    }

    public func processServerPacket(_ data: Data) -> [Data] {
        clientOutPackets.removeAll(keepingCapacity: true)
        serverOutPackets.removeAll(keepingCapacity: true)
        var localAddr = makeIPv4Addr(ip: "127.0.0.1", port: 0)
        var peerAddr = makeIPv4Addr(ip: "0.0.0.0", port: serverPort)
        serverEngine?.packetIn(data, localAddr: localAddr, peerAddr: peerAddr)
        serverEngine?.processConns()
        return clientOutPackets  // Decrypted response → back to app
    }

    // MARK: - HTTP/3 Event Handlers

    private func handleClientHeaders(streamId: UInt64, headers: [(String, String)]) {
        let method = headers.first(where: { $0.0 == ":method" })?.1 ?? "?"
        let path = headers.first(where: { $0.0 == ":path" })?.1 ?? "/"
        let log = "[H3 Request (lsquic)] \(method) \(path)\n" +
                  headers.map { "  \($0.0): \($0.1)" }.joined(separator: "\n") + "\n"
        appendLog(log, to: .REQ)
        recorder.addUpload(log.utf8.count)
    }

    private func handleClientData(streamId: UInt64, data: Data) {
        var buf = ByteBufferAllocator().buffer(capacity: data.count)
        buf.writeBytes(data)
        recorder.recordRequestBody(buf)
        recorder.addUpload(data.count)
    }

    private func handleServerHeaders(streamId: UInt64, headers: [(String, String)]) {
        let status = headers.first(where: { $0.0 == ":status" })?.1 ?? "?"
        let log = "[H3 Response (lsquic)] HTTP/3 \(status)\n" +
                  headers.map { "  \($0.0): \($0.1)" }.joined(separator: "\n") + "\n"
        appendLog(log, to: .RSP)
        recorder.addDownload(log.utf8.count)
    }

    private func handleServerData(streamId: UInt64, data: Data) {
        var buf = ByteBufferAllocator().buffer(capacity: data.count)
        buf.writeBytes(data)
        recorder.recordResponseBody(buf)
        recorder.addDownload(data.count)
    }

    private func appendLog(_ text: String, to fileType: FileType) {
        guard let data = text.data(using: .utf8) else { return }
        var buf = ByteBufferAllocator().buffer(capacity: data.count)
        buf.writeBytes(data)
        if fileType == .REQ {
            recorder.recordRequestBody(buf)
        } else {
            recorder.recordResponseBody(buf)
        }
    }

    public var isClosed: Bool { false }

    private func makeIPv4Addr(ip: String, port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        inet_pton(AF_INET, ip, &addr.sin_addr)
        return addr
    }
}

// MARK: - Lsquic MITM Manager

public class LsquicMITMManager {

    private var sessions = [Data: LsquicMITMSession]()
    private let task: CaptureTask
    private let certPath: String
    private let keyPath: String
    private let lock = NSLock()

    public init(task: CaptureTask, certPath: String, keyPath: String) {
        self.task = task
        self.certPath = certPath
        self.keyPath = keyPath
    }

    public func processOutbound(_ data: Data, dstIP: String, dstPort: UInt16) -> (toApp: [Data], toServer: [(Data, String, UInt16)]) {
        guard let header = QUICDecoder.parseHeader(data) else { return ([], []) }
        let connId = header.dcid

        lock.lock()
        let session: LsquicMITMSession
        if let existing = sessions[connId] {
            session = existing
        } else {
            let sni = QUICDecoder.extractSNI(data) ?? dstIP
            let newSession = LsquicMITMSession(
                connectionId: connId, serverName: sni, serverPort: dstPort, task: task
            )
            guard newSession.setup(certPath: certPath, keyPath: keyPath) else {
                lock.unlock()
                return ([], [])
            }
            sessions[connId] = newSession
            session = newSession
            AxLogger.log("lsquic MITM: New session for \(sni):\(dstPort)", level: .Info)
        }
        lock.unlock()

        let toApp = session.processClientPacket(data)
        let serverPackets = session.pendingServerPackets()
        let toServer = serverPackets.map { ($0, dstIP, dstPort) }
        return (toApp, toServer)
    }

    public func processInbound(_ data: Data, srcIP: String, srcPort: UInt16) -> [Data] {
        guard let header = QUICDecoder.parseHeader(data) else { return [] }
        lock.lock()
        guard let session = sessions[header.dcid] else { lock.unlock(); return [] }
        lock.unlock()
        return session.processServerPacket(data)
    }

    public var activeSessions: Int {
        lock.lock(); defer { lock.unlock() }; return sessions.count
    }

    public func shutdown() {
        lock.lock(); sessions.removeAll(); lock.unlock()
    }
}

#else
// Stub when SwiftLsquic is not available
public class LsquicMITMManager {
    public init(task: CaptureTask, certPath: String, keyPath: String) {}
    public func processOutbound(_ data: Data, dstIP: String, dstPort: UInt16) -> (toApp: [Data], toServer: [(Data, String, UInt16)]) { ([], []) }
    public func processInbound(_ data: Data, srcIP: String, srcPort: UInt16) -> [Data] { [] }
    public var activeSessions: Int { 0 }
    public func shutdown() {}
}
#endif
