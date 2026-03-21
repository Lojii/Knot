import Foundation

/// gRPC protocol recorder. Captures gRPC messages (unary and streaming) in real-time
/// and produces a FlowRecord with gRPC-specific search keys.
public class GRPCRecorder: ProtocolRecorder {
    public static let protocolName = "gRPC"
    public static let searchKeyMapping = SearchKeyMapping(
        key1: "method", key2: "service", key3: "grpcStatus", key4: "grpcMessage"
    )

    private let flowId: String
    private let host: String
    private let port: Int
    private let service: String
    private let method: String
    private let startedAt: TimeInterval
    private let dbGroup: TaskDatabaseGroup

    // Headers
    private var reqHeaders: [(String, String)] = []
    private var rspHeaders: [(String, String)] = []

    // Traffic tracking
    private var uploadBytes: Int64 = 0
    private var downloadBytes: Int64 = 0

    // Closure state
    private var grpcStatus: Int?
    private var grpcMessage: String = ""
    private var trailers: [(String, String)] = []
    private var endedAt: TimeInterval?

    // MARK: - Init

    /// Creates a GRPCRecorder and immediately inserts a preliminary Flow
    /// with `status=inProgress` into protocol.db to prevent orphan decoded entries on crash.
    ///
    /// - Parameters:
    ///   - flowId: Unique flow identifier
    ///   - host: Target host
    ///   - port: Target port
    ///   - path: gRPC path, e.g. `/UserService/GetUser` or `/com.example.MyService/DoThing`
    ///   - dbGroup: TaskDatabaseGroup to write into
    public init(flowId: String, host: String, port: Int, path: String, dbGroup: TaskDatabaseGroup) {
        self.flowId = flowId
        self.host = host
        self.port = port
        self.dbGroup = dbGroup
        self.startedAt = Date().timeIntervalSince1970

        // Parse path: strip leading slash, split on last '/'
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if let slashRange = trimmed.range(of: "/", options: .backwards) {
            self.service = String(trimmed[trimmed.startIndex..<slashRange.lowerBound])
            self.method = String(trimmed[slashRange.upperBound...])
        } else if !trimmed.isEmpty {
            // Single component: treat as method, no service
            self.service = trimmed
            self.method = ""
        } else {
            self.service = ""
            self.method = ""
        }

        // Insert preliminary flow record (fail-safe)
        var preliminary = FlowRecord(flowId: flowId, protocolName: Self.protocolName,
                                     host: host, port: port, startedAt: self.startedAt)
        preliminary.status = .inProgress
        preliminary.summary = "\(self.service)/\(self.method)"

        dbGroup.protoWriteQueue.async { [preliminary] in
            try? FlowDAO.insert(db: dbGroup.proto, record: preliminary)
        }
    }

    // MARK: - Recording Methods

    /// Records a gRPC request message (client → server) to decoded.db.
    ///
    /// - Parameters:
    ///   - data: Serialized message data (typically protobuf)
    ///   - sequence: Message sequence number within this stream
    public func recordRequestMessage(data: Data, sequence: Int) {
        uploadBytes += Int64(data.count)
        writeMessage(data: data, direction: 0, sequence: sequence)
    }

    /// Records a gRPC response message (server → client) to decoded.db.
    ///
    /// - Parameters:
    ///   - data: Serialized message data (typically protobuf)
    ///   - sequence: Message sequence number within this stream
    public func recordResponseMessage(data: Data, sequence: Int) {
        downloadBytes += Int64(data.count)
        writeMessage(data: data, direction: 1, sequence: sequence)
    }

    /// Records HTTP/2 request and response headers.
    public func recordHeaders(reqHeaders: [(String, String)], rspHeaders: [(String, String)]) {
        self.reqHeaders = reqHeaders
        self.rspHeaders = rspHeaders
    }

    /// Called when the gRPC stream is closed.
    /// Updates the Flow record in protocol.db with final state.
    ///
    /// - Parameters:
    ///   - grpcStatus: gRPC status code (0 = OK)
    ///   - grpcMessage: Human-readable status message
    ///   - trailers: Trailing metadata key-value pairs
    public func recordClosed(grpcStatus: Int, grpcMessage: String, trailers: [(String, String)]) {
        self.grpcStatus = grpcStatus
        self.grpcMessage = grpcMessage
        self.trailers = trailers
        self.endedAt = Date().timeIntervalSince1970

        let record = buildFlowRecord()
        let protoDB = dbGroup.proto
        dbGroup.protoWriteQueue.async { [record] in
            try? FlowDAO.update(
                db: protoDB,
                flowId: record.flowId,
                endedAt: record.endedAt,
                status: record.status,
                summary: record.summary,
                downloadBytes: record.downloadBytes,
                uploadBytes: record.uploadBytes,
                durationMs: record.durationMs
            )
        }
    }

    // MARK: - ProtocolRecorder

    public func buildFlowRecord(sessionRecorder: SessionRecorder? = nil) -> FlowRecord {
        var record = FlowRecord(flowId: flowId, protocolName: Self.protocolName,
                                host: host, port: port, startedAt: startedAt)

        record.endedAt = endedAt
        if let ended = endedAt {
            record.durationMs = (ended - startedAt) * 1000
        }

        record.uploadBytes = uploadBytes
        record.downloadBytes = downloadBytes

        // Determine status: failed if gRPC status is non-zero, completed if closed, otherwise inProgress
        if let status = grpcStatus {
            record.status = status == 0 ? .completed : .failed
        } else {
            record.status = .inProgress
        }

        // Summary: "UserService/GetUser → OK"
        record.summary = "\(service)/\(method) → \(grpcMessage)"

        // Search keys
        record.searchKey1 = method
        record.searchKey2 = service
        record.searchKey3 = grpcStatus.map { String($0) } ?? ""
        record.searchKey4 = grpcMessage

        // Metadata
        record.metadata = [
            "service": service,
            "method": method,
            "reqHeaders": reqHeaders.map { ["\($0.0)": "\($0.1)"] },
            "rspHeaders": rspHeaders.map { ["\($0.0)": "\($0.1)"] },
            "trailers": trailers.map { ["\($0.0)": "\($0.1)"] },
        ]
        if let status = grpcStatus {
            record.metadata["grpcStatus"] = status
        }

        return record
    }

    // MARK: - Private

    private func writeMessage(data: Data, direction: Int, sequence: Int) {
        var entry = DecodedEntry(
            flowId: flowId,
            direction: direction,
            originalEncoding: "protobuf",
            decodedType: "grpc-message",
            decodedSize: Int64(data.count),
            charset: "utf-8",
            payloadRef: "",
            isInline: false,
            inlineData: nil,
            searchText: nil,
            decodedAt: Date().timeIntervalSince1970,
            sequence: sequence
        )

        if !data.isEmpty && data.count <= 65536 {
            entry.isInline = true
            entry.inlineData = data

            // Attempt UTF-8 decode for search_text (JSON or text-based payloads)
            if let text = String(data: data, encoding: .utf8) {
                // Truncate search_text to 4KB for FTS
                entry.searchText = data.count <= 4096 ? text : String(text.prefix(4096))
            }
        }

        let decodedDB = dbGroup.decoded
        dbGroup.decodedWriteQueue.async { [entry] in
            try? DecodedEntryDAO.insert(db: decodedDB, entry: entry)
        }
    }
}
