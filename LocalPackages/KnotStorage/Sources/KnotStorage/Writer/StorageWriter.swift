import Foundation
import os

/// Facade for writing capture data to storage (PayloadWriter + DAOs).
/// Created per flow by SessionRecorder in TunnelServices.
public class StorageWriter {
    private static let logger = Logger(subsystem: "KnotStorage", category: "StorageWriter")

    public let taskId: Int64
    public let flowId: String

    private let dbGroup: TaskDatabaseGroup
    private var reqPayloadWriter: PayloadWriter?
    private var rspPayloadWriter: PayloadWriter?
    private var closed = false

    /// File reference for the request payload (empty string if no data written).
    public var reqPayloadRef: String { reqPayloadWriter?.filePath ?? "" }

    /// File reference for the response payload (empty string if no data written).
    public var rspPayloadRef: String { rspPayloadWriter?.filePath ?? "" }

    /// Root path used for payload directory resolution.
    private let rootPath: String

    /// Creates a StorageWriter for a single flow.
    /// - Parameters:
    ///   - dbGroup: The per-task database group to write into.
    ///   - rootPath: Storage root path (defaults to DatabaseManager.rootPath).
    public init(dbGroup: TaskDatabaseGroup, rootPath: String? = nil) {
        self.taskId = dbGroup.taskId
        self.flowId = dbGroup.flowIdGenerator.next()
        self.dbGroup = dbGroup
        self.rootPath = rootPath ?? DatabaseManager.rootPath
    }

    // MARK: - Payload Writes

    /// Append data to the request payload file. Creates the file on first call.
    public func writeRequestBody(_ data: Data) {
        guard !closed, !data.isEmpty else { return }
        if reqPayloadWriter == nil {
            let dir = PathManager.payloadsDirectory(taskId, root: rootPath) + "/raw"
            reqPayloadWriter = try? PayloadWriter(directory: dir, fileName: "\(flowId)_req.bin")
        }
        try? reqPayloadWriter?.append(data)
    }

    /// Append data to the response payload file. Creates the file on first call.
    public func writeResponseBody(_ data: Data) {
        guard !closed, !data.isEmpty else { return }
        if rspPayloadWriter == nil {
            let dir = PathManager.payloadsDirectory(taskId, root: rootPath) + "/raw"
            rspPayloadWriter = try? PayloadWriter(directory: dir, fileName: "\(flowId)_rsp.bin")
        }
        try? rspPayloadWriter?.append(data)
    }

    // MARK: - DB Writes

    /// Insert a FlowRecord into protocol.db (async on the proto write queue).
    public func insertFlow(_ record: FlowRecord) {
        dbGroup.protoWriteQueue.async { [dbGroup] in
            try? FlowDAO.insert(db: dbGroup.proto, record: record)
        }
    }

    /// Update fields of an existing flow record (async on the proto write queue).
    public func updateFlow(_ flowId: String, status: FlowStatus? = nil,
                           endedAt: TimeInterval? = nil, errorMessage: String? = nil) {
        dbGroup.protoWriteQueue.async { [dbGroup] in
            try? FlowDAO.update(db: dbGroup.proto, flowId: flowId,
                                endedAt: endedAt, status: status, errorMessage: errorMessage)
        }
    }

    /// Insert a PacketRow into transport.db (async on the transport write queue).
    public func insertPacket(_ row: PacketRow) {
        dbGroup.transportWriteQueue.async { [dbGroup] in
            try? PacketDAO.insert(db: dbGroup.transport, row: row)
        }
    }

    /// Insert a DecodedEntry into decoded.db (async on the decoded write queue).
    public func insertDecodedEntry(_ entry: DecodedEntry) {
        dbGroup.decodedWriteQueue.async { [dbGroup] in
            try? DecodedEntryDAO.insert(db: dbGroup.decoded, entry: entry)
        }
    }

    /// Insert or update a TcpConnectionRecord in connection.db (async on the connection write queue).
    public func insertOrUpdateConnection(_ record: TcpConnectionRecord) {
        dbGroup.connectionWriteQueue.async { [dbGroup] in
            try? TcpConnectionDAO.insertOrUpdate(db: dbGroup.connection, record: record)
        }
    }

    // MARK: - Lifecycle

    /// Flush and close all open payload writers. Idempotent.
    public func close() {
        guard !closed else { return }
        closed = true
        try? reqPayloadWriter?.flush()
        try? reqPayloadWriter?.close()
        try? rspPayloadWriter?.flush()
        try? rspPayloadWriter?.close()
    }

    deinit {
        if !closed { close() }
    }
}
