import Foundation
import SQLite

/// PRAGMA configuration profiles for different execution environments
public enum PragmaProfile {
    case mainApp
    case packetTunnel
}

/// Bundles the 4 per-task databases with their serial write queues.
/// One instance per active CaptureTask.
public class TaskDatabaseGroup {
    public let taskId: Int64

    // Database connections
    public let transport: Connection
    public let proto: Connection
    public let decoded: Connection
    public let state: Connection
    public let connection: Connection

    // Serial write queues (one per database)
    public let transportWriteQueue: DispatchQueue
    public let protoWriteQueue: DispatchQueue
    public let decodedWriteQueue: DispatchQueue
    public let stateWriteQueue: DispatchQueue
    public let connectionWriteQueue: DispatchQueue

    // FlowId generator (one per task)
    public let flowIdGenerator: FlowIdGenerator

    // Reference count (managed by DatabaseManager)
    var refCount: Int = 1

    public init(taskId: Int64, rootPath: String, profile: PragmaProfile = .mainApp) throws {
        self.taskId = taskId
        self.flowIdGenerator = FlowIdGenerator()

        // Create directories
        try PathManager.ensureTaskDirectories(taskId, root: rootPath)

        // Open connections
        transport = try Connection(PathManager.transportDBPath(taskId, root: rootPath))
        proto = try Connection(PathManager.protocolDBPath(taskId, root: rootPath))
        decoded = try Connection(PathManager.decodedDBPath(taskId, root: rootPath))
        state = try Connection(PathManager.stateDBPath(taskId, root: rootPath))
        connection = try Connection(PathManager.connectionDBPath(taskId, root: rootPath))

        // Configure PRAGMAs
        for db in [transport, proto, decoded, state, connection] {
            try Self.configurePragmas(db, profile: profile)
        }

        // Create schemas
        try TransportSchema.create(transport)
        try ProtocolSchema.create(proto)
        try ProtocolSchema.migrateIfNeeded(proto)
        try DecodedSchema.create(decoded)
        try StateSchema.create(state)
        try ConnectionSchema.create(connection)

        // Create write queues
        transportWriteQueue = DispatchQueue(label: "db.transport.\(taskId)")
        protoWriteQueue = DispatchQueue(label: "db.proto.\(taskId)")
        decodedWriteQueue = DispatchQueue(label: "db.decoded.\(taskId)")
        stateWriteQueue = DispatchQueue(label: "db.state.\(taskId)")
        connectionWriteQueue = DispatchQueue(label: "db.connection.\(taskId)")
    }

    static func configurePragmas(_ db: Connection, profile: PragmaProfile) throws {
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA synchronous = NORMAL")
        try db.execute("PRAGMA busy_timeout = 3000")

        switch profile {
        case .mainApp:
            try db.execute("PRAGMA cache_size = -2000")      // 2MB
            try db.execute("PRAGMA mmap_size = 134217728")    // 128MB
        case .packetTunnel:
            try db.execute("PRAGMA cache_size = -512")        // 512KB
            try db.execute("PRAGMA mmap_size = 16777216")     // 16MB
        }
    }
}
