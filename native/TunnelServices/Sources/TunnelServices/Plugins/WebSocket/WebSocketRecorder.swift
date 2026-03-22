import Foundation
import KnotStorage

/// WebSocket protocol recorder. Captures WS/WSS frames in real-time and
/// produces a FlowRecord with WebSocket-specific search keys.
public class WebSocketRecorder: ProtocolRecorder {
    public static let protocolName = "WS"
    public static let searchKeyMapping = SearchKeyMapping(
        key1: "subprotocol", key2: "uri", key3: "totalFrames", key4: "closeCode"
    )

    private let flowId: String
    private let host: String
    private let port: Int
    private let isSecure: Bool
    private let startedAt: TimeInterval
    private let dbGroup: TaskDatabaseGroup

    // WebSocket metadata
    private var uri: String = ""
    private var subprotocol: String = ""
    private var reqHeaders: [(String, String)] = []
    private var rspHeaders: [(String, String)] = []

    // Frame tracking
    private var framesOut: Int = 0      // client → server
    private var framesIn: Int = 0       // server → client
    private var uploadBytes: Int64 = 0
    private var downloadBytes: Int64 = 0
    private var clientSeq: Int = 0
    private var serverSeq: Int = 0

    // Close
    private var closeCode: Int?
    private var endedAt: TimeInterval?

    // MARK: - Init

    /// Creates a WebSocketRecorder and immediately inserts a preliminary Flow
    /// with `status=inProgress` into protocol.db to prevent orphan decoded entries on crash.
    public init(flowId: String, host: String, port: Int, isSecure: Bool, uri: String = "",
                dbGroup: TaskDatabaseGroup) {
        self.flowId = flowId
        self.host = host
        self.port = port
        self.isSecure = isSecure
        self.uri = uri
        self.dbGroup = dbGroup
        self.startedAt = Date().timeIntervalSince1970

        // Insert preliminary flow record (fail-safe)
        let protocolName = isSecure ? "WSS" : "WS"
        var preliminary = FlowRecord(flowId: flowId, protocolName: protocolName, host: host,
                                     port: port, startedAt: self.startedAt)
        preliminary.status = .inProgress
        preliminary.summary = uri.isEmpty ? "\(protocolName) \(host)" : "\(protocolName) \(uri)"

        dbGroup.protoWriteQueue.async { [preliminary] in
            try? FlowDAO.insert(db: dbGroup.proto, record: preliminary)
        }
    }

    // MARK: - Recording Methods

    /// Records the HTTP Upgrade request/response headers.
    /// Extracts URI and Sec-WebSocket-Protocol from headers.
    public func recordUpgradeHeaders(reqHeaders: [(String, String)], rspHeaders: [(String, String)]) {
        self.reqHeaders = reqHeaders
        self.rspHeaders = rspHeaders

        // Extract subprotocol from response headers
        if let proto = rspHeaders.first(where: { $0.0.lowercased() == "sec-websocket-protocol" })?.1 {
            self.subprotocol = proto
        } else if let proto = reqHeaders.first(where: { $0.0.lowercased() == "sec-websocket-protocol" })?.1 {
            self.subprotocol = proto
        }
    }

    /// Sets the WebSocket URI (from the HTTP Upgrade request line).
    public func setURI(_ uri: String) {
        self.uri = uri
    }

    /// Records a WebSocket frame to decoded.db in real-time.
    ///
    /// - Parameters:
    ///   - direction: 0 = client→server, 1 = server→client
    ///   - opcode: WebSocket opcode name (e.g. "text", "binary", "ping", "pong", "close")
    ///   - payload: Frame payload data (nil for control frames without meaningful payload)
    ///   - timestamp: Frame arrival/departure timestamp
    public func recordFrame(direction: Int, opcode: String, payload: Data?, timestamp: TimeInterval) {
        let opcodeLC = opcode.lowercased()

        // Update traffic counters
        let payloadSize = Int64(payload?.count ?? 0)
        if direction == 0 {
            framesOut += 1
            uploadBytes += payloadSize
        } else {
            framesIn += 1
            downloadBytes += payloadSize
        }

        // Determine sequence number (per-direction counter)
        let seq: Int
        if direction == 0 {
            seq = clientSeq
            clientSeq += 1
        } else {
            seq = serverSeq
            serverSeq += 1
        }

        // Control frames (ping/pong/close): record type only, no payload storage
        let isControlFrame = opcodeLC == "ping" || opcodeLC == "pong" || opcodeLC == "close"

        var entry = DecodedEntry(
            flowId: flowId,
            direction: direction,
            originalEncoding: "",
            decodedType: opcodeLC,
            decodedSize: payloadSize,
            charset: "utf-8",
            payloadRef: "",
            isInline: false,
            inlineData: nil,
            searchText: nil,
            decodedAt: timestamp,
            sequence: seq
        )

        if !isControlFrame, let data = payload, !data.isEmpty {
            if opcodeLC == "text" {
                // TEXT frame: store inline; use as search_text
                let text = String(data: data, encoding: .utf8) ?? ""
                // Store inline for all text ≤ 64KB, otherwise just reference
                if data.count <= 65536 {
                    entry.isInline = true
                    entry.inlineData = data
                    // Truncate search_text to 4KB for FTS
                    entry.searchText = data.count <= 4096 ? text : String(text.prefix(4096))
                }
                // For larger text we just leave isInline=false and store no inline_data
            } else {
                // BINARY frame: store inline if ≤ 64KB
                if data.count <= 65536 {
                    entry.isInline = true
                    entry.inlineData = data
                }
            }
        }

        // Write to decoded.db via the serial write queue (fail-safe, non-blocking)
        let decodedDB = dbGroup.decoded
        dbGroup.decodedWriteQueue.async { [entry] in
            try? DecodedEntryDAO.insert(db: decodedDB, entry: entry)
        }
    }

    /// Called when the WebSocket connection is closed.
    /// Updates the Flow record in protocol.db with final state.
    public func recordClosed(closeCode: Int?) {
        self.closeCode = closeCode
        self.endedAt = Date().timeIntervalSince1970

        let record = buildFlowRecord()

        let protoDB = dbGroup.proto
        dbGroup.protoWriteQueue.async { [record] in
            try? FlowDAO.update(
                db: protoDB,
                flowId: record.flowId,
                endedAt: record.endedAt,
                status: .completed,
                summary: record.summary,
                downloadBytes: record.downloadBytes,
                uploadBytes: record.uploadBytes,
                durationMs: record.durationMs
            )
        }
    }

    // MARK: - ProtocolRecorder

    public func buildFlowRecord(context: FlowBuildContext) -> FlowRecord {
        let protocolName = isSecure ? "WSS" : "WS"
        var record = FlowRecord(flowId: flowId, protocolName: protocolName, host: host,
                                port: port, startedAt: startedAt)

        record.endedAt = endedAt
        if let ended = endedAt {
            record.durationMs = (ended - startedAt) * 1000
        }

        record.uploadBytes = uploadBytes
        record.downloadBytes = downloadBytes
        record.status = endedAt != nil ? .completed : .inProgress

        let totalFrames = framesIn + framesOut
        // Summary: "WSS chat.example.com — 42 frames (↑20 ↓22)"
        let uriPart = uri.isEmpty ? host : uri
        record.summary = "\(protocolName) \(uriPart) — \(totalFrames) frames (↑\(framesOut) ↓\(framesIn))"

        // Search keys
        record.searchKey1 = subprotocol
        record.searchKey2 = uri
        record.searchKey3 = String(totalFrames)
        record.searchKey4 = closeCode.map { String($0) } ?? ""

        // Metadata
        record.metadata = [
            "subprotocol": subprotocol,
            "reqHeaders": reqHeaders.map { ["\($0.0)": "\($0.1)"] },
            "rspHeaders": rspHeaders.map { ["\($0.0)": "\($0.1)"] },
            "framesOut": framesOut,
            "framesIn": framesIn,
        ]
        if let code = closeCode {
            record.metadata["closeCode"] = code
        }

        return record
    }
}
