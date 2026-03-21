//
//  SessionRecorder.swift
//  TunnelServices
//
//  Pure data recording logic, completely decoupled from NIO pipeline.
//  Extracts session field population from handler code.
//

import Foundation
import NIOHTTP1
import NIO
import NIOSSL

// MARK: - Protocol Metadata Types

public struct ProtoFlag: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let keepAlive           = ProtoFlag(rawValue: 0x0001)
    public static let pipelining          = ProtoFlag(rawValue: 0x0002)
    public static let h2Multiplexing      = ProtoFlag(rawValue: 0x0004)
    public static let h2ServerPush        = ProtoFlag(rawValue: 0x0008)
    public static let h2FlowControl       = ProtoFlag(rawValue: 0x0010)
    public static let wsFrameMasked       = ProtoFlag(rawValue: 0x0020)
    public static let tlsMITM             = ProtoFlag(rawValue: 0x0040)
    public static let tlsTunnel           = ProtoFlag(rawValue: 0x0080)
    public static let tlsHandshakeOK      = ProtoFlag(rawValue: 0x0100)
    public static let tlsHandshakeFail    = ProtoFlag(rawValue: 0x0200)
    public static let tlsHandshakeTimeout = ProtoFlag(rawValue: 0x0400)
}

public enum ConnectionReuseType: Int, Sendable {
    case new = 0
    case keepAlive = 1
    case pooled = 2
}

public enum PushForwardStatus: Int, Sendable {
    case captureOnly = 0
    case forwarded = 1
    case failed = 2
}

/// Records HTTP session data via the new storage system (FlowDAO, PayloadWriter, TcpConnectionDAO).
/// The `session` property is retained temporarily as an in-memory data holder
/// because external handlers still read/write fields like `schemes`, `ignore`, `host`, etc.
/// TODO: Replace handler references to `recorder.session.xxx` with dedicated SessionRecorder API,
///       then remove the `session` property entirely.
public class SessionRecorder {

    // TODO: Remove once all handlers stop accessing recorder.session directly.
    public let session: ProxySession
    public let task: CaptureTask

    // New storage system
    private var httpRecorder: HTTPRecorder?
    private var _protocolRecorder: ProtocolRecorder?
    private var reqPayloadWriter: PayloadWriter?
    private var rspPayloadWriter: PayloadWriter?
    private var dbGroup: TaskDatabaseGroup?
    private var flowId: String?

    /// Exposes the underlying `TaskDatabaseGroup` so that protocol-specific
    /// recorders (GRPCRecorder, WebSocketRecorder, etc.) can write their own
    /// records directly to the same task databases.
    public var taskDatabaseGroup: TaskDatabaseGroup? { dbGroup }
    private var taskId: Int64 = 0
    private var tcpRecord: TcpConnectionRecord?

    // MARK: - Protocol Metadata State

    private var _connReuse: ConnectionReuseType = .new
    private var _protoFlags: ProtoFlag = []
    private var _pushStatus: PushForwardStatus? = nil
    private var _certChainRef: String? = nil
    private var _connReusePoolKey: String? = nil
    private var _keepAliveRequestIndex: Int = 0
    private var _h2StreamId: Int? = nil
    private var _bufferedCerts: [Any]? = nil
    private var _certChainSummary: [[String: String]]? = nil

    // MARK: - Protocol Metadata Public API

    public var connReuse: Int { _connReuse.rawValue }
    public var protoFlags: Int { _protoFlags.rawValue }
    public var pushStatus: Int? { _pushStatus?.rawValue }
    public var certChainRef: String? { _certChainRef }
    public var certChainSummary: [[String: String]]? { _certChainSummary }
    public var connReusePoolKey: String? { _connReusePoolKey }
    public var keepAliveRequestIndex: Int { _keepAliveRequestIndex }
    public var h2StreamId: Int? { _h2StreamId }

    public func markConnectionReuse(_ type: ConnectionReuseType, poolKey: String? = nil, requestIndex: Int = 0) {
        _connReuse = type
        _connReusePoolKey = poolKey
        _keepAliveRequestIndex = requestIndex
    }

    public func addProtoFlag(_ flag: ProtoFlag) {
        _protoFlags.insert(flag)
    }

    public func markPushStatus(_ status: PushForwardStatus) {
        _pushStatus = status
    }

    public func setH2StreamId(_ id: Int) {
        _h2StreamId = id
    }

    public func bufferCertificateChain(_ certs: [Any]) {
        _bufferedCerts = certs
    }

    // Local traffic counters (replaces session.uploadTraffic / session.downloadFlow)
    private var _uploadBytes: Int64 = 0
    private var _downloadBytes: Int64 = 0

    // Local timing (replaces session.startTime reads)
    private let _startTime: TimeInterval

    // Local address cache (replaces session.localAddress reads)
    private var _localAddress: String = ""

    public init(task: CaptureTask) {
        self.task = task
        self.session = ProxySession()
        self._startTime = Date().timeIntervalSince1970

        // Populate session in-memory fields that handlers still read
        session.inState = "open"
        session.startTime = _startTime

        // Initialize new storage system
        let tid = task.id
        self.taskId = tid
        NSLog("[SessionRecorder] init: task.id=\(tid)")
        if tid > 0, let group = try? DatabaseManager.shared.openTask(tid) {
            NSLog("[SessionRecorder] dbGroup opened for task \(tid)")
            self.dbGroup = group
            let fid = group.flowIdGenerator.next()
            self.flowId = fid

            // Create payload writers
            let rawDir = "\(PathManager.payloadsDirectory(tid, root: nil))/raw"
            self.reqPayloadWriter = try? PayloadWriter(directory: rawDir, fileName: "\(fid)_req.bin")
            self.rspPayloadWriter = try? PayloadWriter(directory: rawDir, fileName: "\(fid)_rsp.bin")
        }
    }

    // MARK: - Request Recording

    public func recordRequestHead(_ head: HTTPRequestHead, localAddress: SocketAddress?, isSSL: Bool) {
        // Populate session in-memory fields that handlers still read
        let localAddr = NetworkUtils.getIPAddress(socketAddress: localAddress)
        _localAddress = localAddr
        session.host = head.headers["Host"].first ?? ""
        session.localAddress = localAddr
        session.methods = "\(head.method)"
        session.uri = head.uri
        session.target = NetworkUtils.getUserAgent(target: head.headers["User-Agent"].first)
        session.reqLine = "\(head.method) \(head.uri) \(head.version)"
        session.reqHttpVersion = "\(head.version)"
        session.reqHeads = NetworkUtils.getHeadsJson(headers: head.headers)
        session.reqEncoding = head.headers["Content-Encoding"].first ?? ""
        session.reqType = head.headers["Content-Type"].first ?? ""

        // TODO: Rule matching will be rewritten (whitelist/blacklist/pattern modes).
        // For now, capture all traffic.
        if !isSSL {
            session.ignore = false
        }

        session.connectTime = Date().timeIntervalSince1970

        // Record request head to new storage
        if let fid = flowId, httpRecorder == nil {
            let host = head.headers["Host"].first ?? ""
            let port = isSSL ? 443 : 80
            httpRecorder = HTTPRecorder(
                flowId: fid, host: host, port: port,
                protocolOverride: isSSL ? "HTTPS" : nil,
                extraMetadata: isSSL ? ["encrypted": false, "decrypted": true] : [:]
            )
        }
        httpRecorder?.recordRequestHead(
            method: "\(head.method)",
            uri: head.uri,
            httpVersion: "\(head.version)",
            headers: head.headers.map { ($0.name, $0.value) }
        )
    }

    public func recordRequestBody(_ buffer: ByteBuffer) {
        guard !session.ignore else { return }

        // Write request body to new payload writer
        try? reqPayloadWriter?.append(buffer)
        httpRecorder?.addUpload(bytes: Int64(buffer.readableBytes))
    }

    public func recordRequestEnd() {
        guard !session.ignore else { return }

        // Finalize request payload and record timing
        try? reqPayloadWriter?.close()
        if reqPayloadWriter != nil, let fid = flowId {
            httpRecorder?.reqPayloadRef = "\(fid)_req.bin"
        }
        httpRecorder?.recordRequestEnd(at: Date().timeIntervalSince1970)
    }

    // MARK: - Connection Recording

    public func recordConnected(remoteAddress: SocketAddress?) {
        // Update session in-memory fields that handlers still read
        session.connectedTime = Date().timeIntervalSince1970
        session.outState = "open"
        session.remoteAddress = NetworkUtils.getIPAddress(socketAddress: remoteAddress)

        // Record connection timing in new storage
        let now = Date().timeIntervalSince1970
        httpRecorder?.recordConnected(at: now)

        // Create TCP connection record in connection.db
        if let fid = flowId, let group = dbGroup {
            let dstIp = NetworkUtils.getIPAddress(socketAddress: remoteAddress)
            let dstPort = remoteAddress?.port ?? 0
            var record = TcpConnectionRecord(
                flowId: fid,
                srcIp: _localAddress,
                srcPort: 0,
                dstIp: dstIp,
                dstPort: dstPort,
                startedAt: _startTime,
                state: "open",
                establishedAt: now
            )
            record.tlsSni = session.host
            self.tcpRecord = record
            group.connectionWriteQueue.async {
                try? TcpConnectionDAO.insertOrUpdate(db: group.connection, record: record)
            }
        }
    }

    public func recordHandshakeComplete() {
        session.handshakeEndTime = Date().timeIntervalSince1970

        // Record TLS timing
        httpRecorder?.recordTLSDone(at: Date().timeIntervalSince1970)

        // Update TCP connection with TLS info in connection.db
        if var record = tcpRecord, let group = dbGroup {
            record.state = "established"
            self.tcpRecord = record
            group.connectionWriteQueue.async {
                try? TcpConnectionDAO.insertOrUpdate(db: group.connection, record: record)
            }
        }
    }

    public func recordConnectionError(_ error: Error, host: String, port: Int) {
        session.outState = "failure"
        session.note = "error:connect \(host):\(port) failure:\(error)"

        // Record error in new storage
        httpRecorder?.recordError("connect \(host):\(port) failure: \(error)")
    }

    // MARK: - Response Recording

    public func recordResponseHead(_ head: HTTPResponseHead) {
        // Update session in-memory fields that handlers still read
        session.rspStartTime = Date().timeIntervalSince1970
        session.rspHttpVersion = "\(head.version)"
        session.state = "\(head.status.code)"
        session.rspMessage = head.status.reasonPhrase
        session.rspType = head.headers["Content-Type"].first ?? ""
        session.rspEncoding = head.headers["Content-Encoding"].first ?? ""
        session.rspHeads = NetworkUtils.getHeadsJson(headers: head.headers)
        session.rspDisposition = head.headers["Content-Disposition"].first ?? ""

        if let contentType = head.headers["Content-Type"].first?.components(separatedBy: ";").first {
            session.suffix = contentType.components(separatedBy: "/").last ?? ""
        }

        // Record response head to new storage
        httpRecorder?.recordResponseHead(
            statusCode: Int(head.status.code),
            headers: head.headers.map { ($0.name, $0.value) }
        )
        httpRecorder?.recordResponseStart(at: Date().timeIntervalSince1970)
    }

    public func recordResponseBody(_ buffer: ByteBuffer) {
        guard !session.ignore else { return }

        // Write response body to new payload writer
        try? rspPayloadWriter?.append(buffer)
        httpRecorder?.addDownload(bytes: Int64(buffer.readableBytes))
    }

    public func recordResponseEnd() {
        guard !session.ignore else { return }

        // Finalize response payload and record timing
        try? rspPayloadWriter?.close()
        if rspPayloadWriter != nil, let fid = flowId {
            httpRecorder?.rspPayloadRef = "\(fid)_rsp.bin"
        }
        httpRecorder?.recordResponseEnd(at: Date().timeIntervalSince1970)
    }

    // MARK: - Traffic Counting

    public func addUpload(_ bytes: Int) {
        let b = Int64(bytes)
        _uploadBytes += b
        // Forward to protocol recorder so FlowRecord.uploadBytes includes header estimates
        httpRecorder?.addUpload(bytes: b)
    }

    public func addDownload(_ bytes: Int) {
        let b = Int64(bytes)
        _downloadBytes += b
        // Forward to protocol recorder so FlowRecord.downloadBytes includes header estimates
        httpRecorder?.addDownload(bytes: b)
    }

    // MARK: - TLS Handshake Sniffing (for tunnel passthrough)

    /// Record TLS ClientHello metadata extracted by TLSClientSniffHandler.
    public func recordTLSClientInfo(version: String, recordVersion: String,
                                    cipherSuites: [UInt16], sni: String?, alpn: [String]?) {
        // Update host from SNI if available (more accurate than CONNECT host)
        if let sni = sni, !sni.isEmpty {
            session.host = sni
            httpRecorder?.updateHost(sni)
        }

        var tlsMeta: [String: Any] = [
            "tlsClientVersion": version,
            "tlsRecordVersion": recordVersion,
            "tlsCipherSuitesCount": cipherSuites.count,
            "tlsCipherSuites": cipherSuites.prefix(20).map { String(format: "0x%04X", $0) },
        ]
        if let sni = sni { tlsMeta["tlsSNI"] = sni }
        if let alpn = alpn { tlsMeta["tlsALPN"] = alpn }

        httpRecorder?.mergeMetadata(tlsMeta)
    }

    /// Record TLS ServerHello metadata extracted by TLSServerSniffHandler.
    public func recordTLSServerInfo(version: String, selectedCipher: UInt16) {
        httpRecorder?.mergeMetadata([
            "tlsServerVersion": version,
            "tlsSelectedCipher": String(format: "0x%04X", selectedCipher),
        ])
    }

    /// Record certificate chain subjects from ServerHello Certificate message.
    public func recordTLSCertificateChain(subjects: [String]) {
        guard !subjects.isEmpty else { return }
        httpRecorder?.mergeMetadata([
            "tlsCertChain": subjects,
            "tlsCertSubject": subjects.first ?? "",
        ])
    }

    // MARK: - Ensure Recorder for Non-HTTP Paths

    /// Ensure httpRecorder is initialized for connections that bypass normal HTTP decoding
    /// (e.g. HTTPS tunnel passthrough). This allows recordClosed() to write a FlowRecord.
    public func ensureHttpRecorder(host: String, port: Int, protocolOverride: String, method: String, uri: String, extraMetadata: [String: Any] = [:]) {
        guard let fid = flowId, httpRecorder == nil else { return }
        httpRecorder = HTTPRecorder(
            flowId: fid, host: host, port: port,
            protocolOverride: protocolOverride,
            extraMetadata: extraMetadata
        )
        httpRecorder?.recordRequestHead(
            method: method, uri: uri, httpVersion: "",
            headers: []
        )
    }

    /// Set the protocol-specific recorder. Called by leaf plugins.
    public func setProtocolRecorder(_ recorder: ProtocolRecorder) {
        self._protocolRecorder = recorder
        // Also set httpRecorder for backward compat
        if let httpRec = recorder as? HTTPRecorder {
            self.httpRecorder = httpRec
        }
    }

    // MARK: - Raw / Unknown Protocol Recording

    /// Record a connection with an unrecognized protocol. Creates a minimal FlowRecord
    /// so it appears in the capture UI even though we can't decode the content.
    public func recordRawConnection(peerAddress: String?, localAddress: String?, firstBytes: Data) {
        let peer = peerAddress ?? "unknown"
        _localAddress = localAddress ?? ""
        session.host = peer
        session.localAddress = _localAddress
        session.schemes = "RAW"
        session.methods = "RAW"
        session.uri = "/"
        session.reqLine = "Unknown protocol"
        session.connectTime = Date().timeIntervalSince1970

        // Initialize httpRecorder with minimal info so recordClosed() can write to DB
        let hexPreview = firstBytes.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
        if let fid = flowId, httpRecorder == nil {
            httpRecorder = HTTPRecorder(
                flowId: fid, host: peer, port: 0,
                protocolOverride: "RAW",
                extraMetadata: ["firstBytes": hexPreview]
            )
            httpRecorder?.recordRequestHead(
                method: "RAW", uri: "[\(firstBytes.count) bytes]", httpVersion: "",
                headers: []
            )
        }

        // Write first bytes as request payload
        if !firstBytes.isEmpty {
            var buf = ByteBufferAllocator().buffer(capacity: firstBytes.count)
            buf.writeBytes(firstBytes)
            recordRequestBody(buf)
            addUpload(firstBytes.count)
        }
    }

    // MARK: - Lifecycle

    public func recordClosed() {
        session.endTime = Date().timeIntervalSince1970
        NSLog("[SessionRecorder] recordClosed: taskId=\(taskId), dbGroup=\(dbGroup != nil), httpRecorder=\(httpRecorder != nil), flowId=\(flowId ?? "nil")")

        // Send real-time status to main app (uses session in-memory fields for URL construction)
        if !session.ignore {
            task.sendInfo(
                url: session.getFullUrl(),
                uploadTraffic: _uploadBytes,
                downloadFlow: _downloadBytes
            )
        }

        // Build FlowRecord and insert into protocol.db (off EventLoop via write queue).
        // Certificate chain export (file I/O) also runs on the write queue to avoid
        // blocking the NIO EventLoop.
        if let recorder = _protocolRecorder ?? httpRecorder, let group = dbGroup {
            let bufferedCerts = _bufferedCerts as? [NIOSSLCertificate]
            let fid = flowId
            let tid = taskId
            // Capture all state needed by the async block before it runs.
            // SessionRecorder fields are read here (on EventLoop), written in async.
            let certChainRef = _certChainRef
            let certChainSummary = _certChainSummary

            group.protoWriteQueue.async { [weak self] in
                // Write cert chain PEM if buffered certs exist and not already done
                if certChainRef == nil, let certs = bufferedCerts, let fid = fid, tid > 0 {
                    let taskDir = PathManager.taskDirectory(tid)
                    let certService = CertExportService(fileFolder: taskDir)
                    do {
                        let (ref, summary) = try certService.saveCertChain(flowId: fid, certificates: certs)
                        self?._certChainRef = ref
                        self?._certChainSummary = summary
                    } catch {
                        NSLog("[SessionRecorder] cert chain save failed: \(error)")
                    }
                }
                // Now build and insert the FlowRecord (picks up certChainRef/Summary)
                let flowRecord = recorder.buildFlowRecord(sessionRecorder: self)
                try? FlowDAO.insert(db: group.proto, record: flowRecord)
            }
        }

        // Update TCP connection state to closed in connection.db
        if var record = tcpRecord, let group = dbGroup {
            record.state = "closed"
            record.closedAt = Date().timeIntervalSince1970
            record.bytesOut = _uploadBytes
            record.bytesIn = _downloadBytes
            self.tcpRecord = record
            group.connectionWriteQueue.async {
                try? TcpConnectionDAO.insertOrUpdate(db: group.connection, record: record)
            }
        }

        // Release database group ref
        if taskId > 0 {
            DatabaseManager.shared.closeTask(taskId)
        }
    }

    public func recordError(_ message: String) {
        session.sstate = "failure"
        session.note = message

        // Record error in new storage
        httpRecorder?.recordError(message)
    }
}
