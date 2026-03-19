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
    private var reqPayloadWriter: PayloadWriter?
    private var rspPayloadWriter: PayloadWriter?
    private var dbGroup: TaskDatabaseGroup?
    private var flowId: String?
    private var taskId: Int64 = 0
    private var tcpRecord: TcpConnectionRecord?

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
        let tid = task.id?.int64Value ?? 0
        self.taskId = tid
        if tid > 0, let group = try? DatabaseManager.shared.openTask(tid) {
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

        if !isSSL {
            session.ignore = task.rule.matching(
                host: session.host, uri: head.uri, target: session.target
            )
            if task.rule.defaultStrategy == .COPY {
                session.ignore = !session.ignore
            }
        }

        session.connectTime = Date().timeIntervalSince1970

        // Record request head to new storage
        if let fid = flowId, httpRecorder == nil {
            let host = head.headers["Host"].first ?? ""
            let port = isSSL ? 443 : 80
            httpRecorder = HTTPRecorder(flowId: fid, host: host, port: port)
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
        _uploadBytes += Int64(bytes)
    }

    public func addDownload(_ bytes: Int) {
        _downloadBytes += Int64(bytes)
    }

    // MARK: - Lifecycle

    public func recordClosed() {
        session.endTime = Date().timeIntervalSince1970

        // Send real-time status to main app (uses session in-memory fields for URL construction)
        if !session.ignore {
            task.sendInfo(
                url: session.getFullUrl(),
                uploadTraffic: NSNumber(value: _uploadBytes),
                downloadFlow: NSNumber(value: _downloadBytes)
            )
        }

        // Build FlowRecord and insert into protocol.db
        if let recorder = httpRecorder, let group = dbGroup {
            let flowRecord = recorder.buildFlowRecord()
            try? FlowDAO.insert(db: group.proto, record: flowRecord)
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
