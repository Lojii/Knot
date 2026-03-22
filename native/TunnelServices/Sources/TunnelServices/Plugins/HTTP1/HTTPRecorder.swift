import Foundation
import KnotStorage

/// HTTP protocol recorder. Captures HTTP/1.x request/response metadata
/// and produces a FlowRecord with HTTP-specific search keys.
public class HTTPRecorder: ProtocolRecorder {
    public static let protocolName = "HTTP"
    public static let searchKeyMapping = SearchKeyMapping(
        key1: "method", key2: "uri", key3: "statusCode", key4: "contentType"
    )

    private let flowId: String
    private let host: String
    private let port: Int
    private let startedAt: TimeInterval
    private var protocolOverride: String?
    private var extraMetadata: [String: Any]

    // Request
    private var method: String = ""
    private var uri: String = ""
    private var httpVersion: String = ""
    private var reqHeaders: [(String, String)] = []

    // Response
    private var statusCode: Int = 0
    private var rspHeaders: [(String, String)] = []
    private var contentType: String = ""
    private var contentEncoding: String = ""

    // Timing
    private var connectAt: TimeInterval?
    private var connectedAt: TimeInterval?
    private var tlsDoneAt: TimeInterval?
    private var reqEndAt: TimeInterval?
    private var rspStartAt: TimeInterval?
    private var endedAt: TimeInterval?

    // Traffic
    private var uploadBytes: Int64 = 0
    private var downloadBytes: Int64 = 0

    // Payload refs (set externally)
    public var reqPayloadRef: String = ""
    public var rspPayloadRef: String = ""

    // Error
    private var error: String?

    public init(flowId: String, host: String, port: Int, protocolOverride: String? = nil, extraMetadata: [String: Any] = [:]) {
        self.flowId = flowId
        self.host = host
        self.port = port
        self.protocolOverride = protocolOverride
        self.extraMetadata = extraMetadata
        self.startedAt = Date().timeIntervalSince1970
    }

    // MARK: - Mutable Helpers

    /// Update host after initial creation (e.g. when SNI is extracted from TLS handshake).
    public func updateHost(_ newHost: String) {
        // host is let — use a mutable override
        _hostOverride = newHost
    }
    private var _hostOverride: String?

    /// Merge additional metadata (e.g. TLS handshake info).
    public func mergeMetadata(_ meta: [String: Any]) {
        extraMetadata.merge(meta) { _, new in new }
    }

    // MARK: - Recording Methods

    public func recordRequestHead(method: String, uri: String, httpVersion: String, headers: [(String, String)]) {
        self.method = method
        self.uri = uri
        self.httpVersion = httpVersion
        self.reqHeaders = headers
    }

    public func recordResponseHead(statusCode: Int, headers: [(String, String)]) {
        self.statusCode = statusCode
        self.rspHeaders = headers
        self.contentType = headers.first { $0.0.lowercased() == "content-type" }?.1 ?? ""
        self.contentEncoding = headers.first { $0.0.lowercased() == "content-encoding" }?.1 ?? ""
    }

    public func recordConnected(at time: TimeInterval) { connectedAt = time }
    public func recordTLSDone(at time: TimeInterval) { tlsDoneAt = time }
    public func recordRequestEnd(at time: TimeInterval) { reqEndAt = time }
    public func recordResponseStart(at time: TimeInterval) { rspStartAt = time }
    public func recordResponseEnd(at time: TimeInterval) { endedAt = time }

    public func addUpload(bytes: Int64) { uploadBytes += bytes }
    public func addDownload(bytes: Int64) { downloadBytes += bytes }

    public func recordError(_ message: String) { error = message }

    // MARK: - ProtocolRecorder

    public func buildFlowRecord(context: FlowBuildContext) -> FlowRecord {
        let effectiveHost = _hostOverride ?? host
        var record = FlowRecord(flowId: flowId, protocolName: protocolOverride ?? Self.protocolName, host: effectiveHost, port: port, startedAt: startedAt)

        record.endedAt = endedAt
        if let ended = endedAt {
            record.durationMs = (ended - startedAt) * 1000
        }

        record.uploadBytes = uploadBytes
        record.downloadBytes = downloadBytes

        record.status = error != nil ? .failed : (endedAt != nil ? .completed : .inProgress)
        record.errorMessage = error ?? ""

        // Summary: "GET /api/users → 200"
        if statusCode > 0 {
            record.summary = "\(method) \(uri) → \(statusCode)"
        } else {
            record.summary = "\(method) \(uri)"
        }

        // Search keys
        record.searchKey1 = method
        record.searchKey2 = uri
        record.searchKey3 = statusCode > 0 ? String(statusCode) : ""
        record.searchKey4 = contentType

        // Timeline
        record.connectAt = connectAt
        record.connectedAt = connectedAt
        record.tlsDoneAt = tlsDoneAt
        record.reqEndAt = reqEndAt
        record.rspStartAt = rspStartAt

        // Metadata
        record.metadata = [
            "httpVersion": httpVersion,
            "reqHeaders": reqHeaders.map { ["\($0.0)": "\($0.1)"] },
            "rspHeaders": rspHeaders.map { ["\($0.0)": "\($0.1)"] },
            "contentEncoding": contentEncoding,
        ]
        record.metadata.merge(extraMetadata) { _, new in new }

        // Payload refs
        record.reqPayloadRef = reqPayloadRef
        record.rspPayloadRef = rspPayloadRef

        // Merge protocol metadata from FlowBuildContext
        record.connReuse = context.connReuse
        record.protoFlags = context.protoFlags
        record.certChainRef = context.certChainRef

        return record
    }

    /// Backward-compatible overload for callers that don't have a FlowBuildContext.
    public func buildFlowRecordLegacy(sessionRecorder: SessionRecorder?) -> FlowRecord {
        var ctx = FlowBuildContext(
            flowId: flowId,
            reqPayloadRef: reqPayloadRef,
            rspPayloadRef: rspPayloadRef,
            uploadBytes: uploadBytes,
            downloadBytes: downloadBytes
        )
        if let sr = sessionRecorder {
            ctx = FlowBuildContext(
                flowId: flowId,
                reqPayloadRef: reqPayloadRef,
                rspPayloadRef: rspPayloadRef,
                uploadBytes: uploadBytes,
                downloadBytes: downloadBytes,
                protoFlags: sr.protoFlags,
                connReuse: sr.connReuse,
                certChainRef: sr.certChainRef
            )
        }
        var record = buildFlowRecord(context: ctx)

        // Merge extra SessionRecorder metadata that FlowBuildContext doesn't carry
        if let sr = sessionRecorder {
            record.pushStatus = sr.pushStatus
            if let poolKey = sr.connReusePoolKey {
                record.metadata["connReusePoolKey"] = poolKey
            }
            if sr.keepAliveRequestIndex > 0 {
                record.metadata["keepAliveRequestIndex"] = sr.keepAliveRequestIndex
            }
            if let streamId = sr.h2StreamId {
                record.metadata["h2StreamId"] = streamId
            }
            if let summary = sr.certChainSummary {
                record.metadata["certChainSummary"] = summary
            }
        }

        return record
    }
}
