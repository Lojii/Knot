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

/// Records HTTP session data to the database and file system.
/// This is NOT a ChannelHandler - it's a plain helper used by handlers.
public class SessionRecorder {

    public let session: Session
    public let task: CaptureTask

    // New storage system (dual-write, Phase 1 migration)
    private var httpRecorder: HTTPRecorder?
    private var reqPayloadWriter: PayloadWriter?
    private var rspPayloadWriter: PayloadWriter?
    private var dbGroup: TaskDatabaseGroup?
    private var flowId: String?
    private var taskId: Int64 = 0

    public init(task: CaptureTask) {
        self.task = task
        self.session = Session.newSession(task)
        session.inState = "open"
        session.startTime = NSNumber(value: Date().timeIntervalSince1970)

        // Initialize new storage system (fail-safe — must not affect existing flow)
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
        session.reqLine = "\(head.method) \(head.uri) \(head.version)"
        session.host = head.headers["Host"].first
        session.localAddress = Session.getIPAddress(socketAddress: localAddress)
        session.methods = "\(head.method)"
        session.uri = head.uri
        session.reqHttpVersion = "\(head.version)"
        session.target = Session.getUserAgent(target: head.headers["User-Agent"].first)
        session.reqHeads = Session.getHeadsJson(headers: head.headers)
        session.reqEncoding = head.headers["Content-Encoding"].first ?? ""
        session.reqType = head.headers["Content-Type"].first ?? ""

        if !isSSL {
            session.ignore = task.rule.matching(
                host: session.host ?? "", uri: head.uri, target: session.target ?? ""
            )
            if task.rule.defaultStrategy == .COPY {
                session.ignore = !session.ignore
            }
        }

        session.connectTime = NSNumber(value: Date().timeIntervalSince1970)
        try? session.saveToDB()

        // Dual-write: record request head to new storage
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
        session.writeBody(type: .REQ, buffer: buffer)

        // Dual-write: write request body to new payload writer
        try? reqPayloadWriter?.append(buffer)
        httpRecorder?.addUpload(bytes: Int64(buffer.readableBytes))
    }

    public func recordRequestEnd() {
        guard !session.ignore else { return }
        session.writeBody(type: .REQ, buffer: nil)
        session.reqEndTime = NSNumber(value: Date().timeIntervalSince1970)
        try? session.saveToDB()

        // Dual-write: finalize request payload and record timing
        try? reqPayloadWriter?.close()
        if reqPayloadWriter != nil, let fid = flowId {
            httpRecorder?.reqPayloadRef = "\(fid)_req.bin"
        }
        httpRecorder?.recordRequestEnd(at: Date().timeIntervalSince1970)
    }

    // MARK: - Connection Recording

    public func recordConnected(remoteAddress: SocketAddress?) {
        session.connectedTime = NSNumber(value: Date().timeIntervalSince1970)
        session.outState = "open"
        session.remoteAddress = Session.getIPAddress(socketAddress: remoteAddress)
        try? session.saveToDB()

        // Dual-write: record connection timing
        httpRecorder?.recordConnected(at: Date().timeIntervalSince1970)
    }

    public func recordHandshakeComplete() {
        session.handshakeEndTime = NSNumber(value: Date().timeIntervalSince1970)

        // Dual-write: record TLS timing
        httpRecorder?.recordTLSDone(at: Date().timeIntervalSince1970)
    }

    public func recordConnectionError(_ error: Error, host: String, port: Int) {
        session.outState = "failure"
        session.note = "error:connect \(host):\(port) failure:\(error)"

        // Dual-write: record error
        httpRecorder?.recordError("connect \(host):\(port) failure: \(error)")
    }

    // MARK: - Response Recording

    public func recordResponseHead(_ head: HTTPResponseHead) {
        session.rspStartTime = NSNumber(value: Date().timeIntervalSince1970)
        session.rspHttpVersion = "\(head.version)"
        session.state = "\(head.status.code)"
        session.rspMessage = head.status.reasonPhrase
        session.rspType = head.headers["Content-Type"].first ?? ""
        session.rspEncoding = head.headers["Content-Encoding"].first ?? ""
        session.rspHeads = Session.getHeadsJson(headers: head.headers)
        session.rspDisposition = head.headers["Content-Disposition"].first ?? ""

        if let contentType = head.headers["Content-Type"].first?.components(separatedBy: ";").first {
            session.suffix = contentType.components(separatedBy: "/").last ?? ""
        }

        try? session.saveToDB()

        // Dual-write: record response head to new storage
        httpRecorder?.recordResponseHead(
            statusCode: Int(head.status.code),
            headers: head.headers.map { ($0.name, $0.value) }
        )
        httpRecorder?.recordResponseStart(at: Date().timeIntervalSince1970)
    }

    public func recordResponseBody(_ buffer: ByteBuffer) {
        guard !session.ignore else { return }
        if session.fileName == "" {
            if let fileName = session.uri?.getFileName() {
                session.fileName = fileName
                let nameParts = session.fileName.components(separatedBy: ".")
                if nameParts.count < 2 {
                    let type = session.rspType.getRealType()
                    if type != "" { session.fileName = "\(session.fileName).\(type)" }
                }
                try? session.saveToDB()
            }
        }
        session.writeBody(type: .RSP, buffer: buffer, realName: session.fileName)

        // Dual-write: write response body to new payload writer
        try? rspPayloadWriter?.append(buffer)
        httpRecorder?.addDownload(bytes: Int64(buffer.readableBytes))
    }

    public func recordResponseEnd() {
        guard !session.ignore else { return }
        session.writeBody(type: .RSP, buffer: nil, realName: session.fileName)
        session.rspEndTime = NSNumber(value: Date().timeIntervalSince1970)

        // Dual-write: finalize response payload and record timing
        try? rspPayloadWriter?.close()
        if rspPayloadWriter != nil, let fid = flowId {
            httpRecorder?.rspPayloadRef = "\(fid)_rsp.bin"
        }
        httpRecorder?.recordResponseEnd(at: Date().timeIntervalSince1970)
    }

    // MARK: - Traffic Counting

    public func addUpload(_ bytes: Int) {
        session.uploadTraffic = NSNumber(value: session.uploadTraffic.intValue + bytes)
    }

    public func addDownload(_ bytes: Int) {
        session.downloadFlow = NSNumber(value: session.downloadFlow.intValue + bytes)
    }

    // MARK: - Lifecycle

    public func recordClosed() {
        session.endTime = NSNumber(value: Date().timeIntervalSince1970)
        try? session.saveToDB()
        if !session.ignore {
            task.sendInfo(
                url: session.getFullUrl(),
                uploadTraffic: session.uploadTraffic,
                downloadFlow: session.downloadFlow
            )
        }

        // Dual-write: build FlowRecord and insert into protocol.db
        if let recorder = httpRecorder, let group = dbGroup {
            let flowRecord = recorder.buildFlowRecord()
            try? FlowDAO.insert(db: group.proto, record: flowRecord)
        }
        // Release database group ref
        if taskId > 0 {
            DatabaseManager.shared.closeTask(taskId)
        }
    }

    public func recordError(_ message: String) {
        session.sstate = "failure"
        session.note = message

        // Dual-write: record error
        httpRecorder?.recordError(message)
    }
}
