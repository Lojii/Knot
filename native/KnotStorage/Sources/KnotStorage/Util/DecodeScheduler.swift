import Foundation
import SQLite

/// Background decode scheduler.
/// Two paths: async (background queue) and sync (with completion callback).
public class DecodeScheduler {
    private let dbGroup: TaskDatabaseGroup
    private let rootPath: String
    private let decodeQueue: DispatchQueue
    private var pendingFlowIds: [String] = []
    private var isProcessing = false

    public init(dbGroup: TaskDatabaseGroup, rootPath: String) {
        self.dbGroup = dbGroup
        self.rootPath = rootPath
        self.decodeQueue = DispatchQueue(label: "decode.\(dbGroup.taskId)", qos: .utility)
    }

    // MARK: - Async Path (background idle decode)

    /// Enqueue a flowId for background decoding. Non-blocking.
    public func enqueueAsync(flowId: String) {
        decodeQueue.async { [self] in
            pendingFlowIds.append(flowId)
            processNextIfIdle()
        }
    }

    private func processNextIfIdle() {
        guard !isProcessing, !pendingFlowIds.isEmpty else { return }
        isProcessing = true
        let flowId = pendingFlowIds.removeFirst()

        decodeAndStore(flowId: flowId) { [self] in
            isProcessing = false
            processNextIfIdle()
        }
    }

    // MARK: - Sync Path (intercept/breakpoint)

    /// Decode on background queue and call completion on the provided queue when done.
    public func decodeSynchronously(
        flowId: String,
        callbackQueue: DispatchQueue = .main,
        completion: @escaping (Swift.Result<DecodedPayload, Error>) -> Void
    ) {
        decodeQueue.async { [self] in
            do {
                let (result, _, _) = try decodeFlow(flowId: flowId)
                callbackQueue.async { completion(.success(result)) }
            } catch {
                callbackQueue.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Core Decode Logic (shared)

    private func decodeAndStore(flowId: String, completion: @escaping () -> Void) {
        do {
            let (result, reqEnc, rspEnc) = try decodeFlow(flowId: flowId)
            storeDecodedEntries(flowId: flowId, result: result, reqEncoding: reqEnc, rspEncoding: rspEnc)
            completion()
        } catch {
            completion()
        }
    }

    /// Decode a single flow (request + response payloads)
    private func decodeFlow(flowId: String) throws -> (DecodedPayload, String, String) {
        // Read flow metadata from protocol.db
        guard let flow = try FlowDAO.find(db: dbGroup.proto, flowId: flowId) else {
            return (DecodedPayload(), "", "")
        }

        var reqResult: DecodeResult?
        var rspResult: DecodeResult?

        // Extract encoding from metadata JSON
        let reqEncoding = extractEncoding(from: flow.metadata, key: "reqEncoding")
        let rspEncoding = extractEncoding(from: flow.metadata, key: "rspEncoding")

        // Decode request payload
        if !flow.reqPayloadRef.isEmpty {
            let rawPath = PathManager.rawPayloadPath(taskId: dbGroup.taskId, ref: flow.reqPayloadRef, root: rootPath)
            let decodedPath = PathManager.decodedPayloadPath(taskId: dbGroup.taskId, flowId: flowId, direction: .request, root: rootPath)
            if FileManager.default.fileExists(atPath: rawPath) {
                reqResult = try PayloadDecoder.decode(rawPath: rawPath, decodedPath: decodedPath, encoding: reqEncoding)
            }
        }

        // Decode response payload
        if !flow.rspPayloadRef.isEmpty {
            let rawPath = PathManager.rawPayloadPath(taskId: dbGroup.taskId, ref: flow.rspPayloadRef, root: rootPath)
            let decodedPath = PathManager.decodedPayloadPath(taskId: dbGroup.taskId, flowId: flowId, direction: .response, root: rootPath)
            if FileManager.default.fileExists(atPath: rawPath) {
                rspResult = try PayloadDecoder.decode(rawPath: rawPath, decodedPath: decodedPath, encoding: rspEncoding)
            }
        }

        return (DecodedPayload(request: reqResult, response: rspResult), reqEncoding, rspEncoding)
    }

    private func storeDecodedEntries(flowId: String, result: DecodedPayload, reqEncoding: String, rspEncoding: String) {
        dbGroup.decodedWriteQueue.async { [self] in
            if let req = result.request {
                let entry = DecodedEntry(
                    flowId: flowId,
                    direction: 0,
                    originalEncoding: reqEncoding,
                    decodedType: req.detectedType,
                    decodedSize: req.decodedSize,
                    payloadRef: req.payloadRef,
                    isInline: req.decodedSize <= 4096,
                    inlineData: req.decodedSize <= 4096 ? tryReadSmallFile(flowId: flowId, direction: .request) : nil,
                    searchText: req.searchText,
                    decodedAt: Date().timeIntervalSince1970
                )
                try? DecodedEntryDAO.insert(db: dbGroup.decoded, entry: entry)
            }
            if let rsp = result.response {
                let entry = DecodedEntry(
                    flowId: flowId,
                    direction: 1,
                    originalEncoding: rspEncoding,
                    decodedType: rsp.detectedType,
                    decodedSize: rsp.decodedSize,
                    payloadRef: rsp.payloadRef,
                    isInline: rsp.decodedSize <= 4096,
                    inlineData: rsp.decodedSize <= 4096 ? tryReadSmallFile(flowId: flowId, direction: .response) : nil,
                    searchText: rsp.searchText,
                    decodedAt: Date().timeIntervalSince1970
                )
                try? DecodedEntryDAO.insert(db: dbGroup.decoded, entry: entry)
            }
        }
    }

    private func tryReadSmallFile(flowId: String, direction: PayloadDirection) -> Data? {
        let path = PathManager.decodedPayloadPath(taskId: dbGroup.taskId, flowId: flowId, direction: direction, root: rootPath)
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func extractEncoding(from metadata: [String: Any], key: String) -> String {
        (metadata[key] as? String) ?? "identity"
    }
}
