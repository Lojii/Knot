import Foundation
import NIOCore
import NIOHTTP1
import NIOFoundationCompat
import KnotStorage

enum PayloadRoutes {

    static func request(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        streamPayload(context: context, taskId: taskId, flowId: flowId, direction: .request, queryParams: queryParams)
    }

    static func response(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        streamPayload(context: context, taskId: taskId, flowId: flowId, direction: .response, queryParams: queryParams)
    }

    static func decoded(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            let entries = try DecodedEntryDAO.findAll(db: group.decoded, flowId: flowId)
            let items: [[String: Any]] = entries.map { e in
                var dict: [String: Any] = [
                    "flowId": e.flowId,
                    "direction": e.direction,
                    "originalEncoding": e.originalEncoding,
                    "decodedType": e.decodedType,
                    "decodedSize": e.decodedSize,
                    "charset": e.charset,
                    "payloadRef": e.payloadRef,
                    "isInline": e.isInline,
                    "decodedAt": e.decodedAt,
                    "sequence": e.sequence,
                ]
                if let text = e.searchText {
                    dict["searchText"] = text
                }
                if e.isInline, let data = e.inlineData {
                    dict["inlineData"] = data.base64EncodedString()
                }
                return dict
            }
            ResponseHelper.jsonResponse(context: context, body: items)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to get decoded entries: \(error.localizedDescription)")
        }
    }

    /// Stream the decoded (decompressed) payload bytes for a given direction.
    /// Falls back to raw payload if decoded file doesn't exist.
    static func decodedPayload(context: ChannelHandlerContext, taskId: String, flowId: String, direction: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        let payloadDir: PayloadDirection
        switch direction {
        case "request": payloadDir = .request
        case "response": payloadDir = .response
        default:
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid direction")
            return
        }

        // Resolve the file path (DB access) up front, then release the DB group
        // before streaming so the group ref isn't held for the whole transfer.
        let filePath: String
        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            let decodedPath = PathManager.decodedPayloadPath(taskId: tid, flowId: flowId, direction: payloadDir)
            if FileManager.default.fileExists(atPath: decodedPath) {
                filePath = decodedPath
            } else {
                guard let flow = try FlowDAO.find(db: group.proto, flowId: flowId) else {
                    ResponseHelper.errorResponse(context: context, status: .notFound, message: "Flow not found")
                    return
                }
                let ref = payloadDir == .request ? flow.reqPayloadRef : flow.rspPayloadRef
                guard !ref.isEmpty else {
                    ResponseHelper.errorResponse(context: context, status: .notFound, message: "No payload available")
                    return
                }
                filePath = PathManager.rawPayloadPath(taskId: tid, ref: ref)
            }
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to read payload: \(error.localizedDescription)")
            return
        }

        streamFile(context: context, filePath: filePath)
    }

    // MARK: - Private

    private static func streamPayload(
        context: ChannelHandlerContext,
        taskId: String,
        flowId: String,
        direction: PayloadDirection,
        queryParams: [String: String]
    ) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        let preview = queryParams["preview"] == "true"

        // Resolve file path (DB access) then release the group before streaming.
        let filePath: String
        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            guard let flow = try FlowDAO.find(db: group.proto, flowId: flowId) else {
                ResponseHelper.errorResponse(context: context, status: .notFound, message: "Flow not found")
                return
            }

            let payloadRef: String
            switch direction {
            case .request: payloadRef = flow.reqPayloadRef
            case .response: payloadRef = flow.rspPayloadRef
            }

            guard !payloadRef.isEmpty else {
                ResponseHelper.errorResponse(context: context, status: .notFound, message: "No payload available")
                return
            }

            filePath = PathManager.rawPayloadPath(taskId: tid, ref: payloadRef)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to read payload: \(error.localizedDescription)")
            return
        }

        if preview {
            let reader: PayloadReader
            do {
                reader = try PayloadReader(filePath: filePath)
            } catch {
                ResponseHelper.errorResponse(context: context, status: .notFound, message: "Payload file not found")
                return
            }
            defer { reader.close() }
            let previewSize = min(4096, Int(reader.size))
            let data = reader.read(offset: 0, length: previewSize)
            ResponseHelper.sendHTTP(context: context, status: .ok,
                                    contentType: "application/octet-stream", body: data)
            return
        }

        streamFile(context: context, filePath: filePath)
    }

    /// Stream a file to the client with chunked transfer encoding, flushing each
    /// chunk and reading the next only after the previous write completes. This
    /// bounds outbound memory to a single chunk and applies natural backpressure,
    /// instead of queueing the whole file into the channel's write buffer.
    private static func streamFile(context: ChannelHandlerContext, filePath: String, chunkSize: Int = 64 * 1024) {
        guard FileManager.default.fileExists(atPath: filePath) else {
            ResponseHelper.errorResponse(context: context, status: .notFound, message: "Payload file not found")
            return
        }

        let reader: PayloadReader
        do {
            reader = try PayloadReader(filePath: filePath, chunkSize: chunkSize)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Cannot open payload: \(error.localizedDescription)")
            return
        }

        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "application/octet-stream")
        headers.add(name: "transfer-encoding", value: "chunked")
        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

        streamNextChunk(context: context, reader: reader, offset: 0, chunkSize: chunkSize)
    }

    private static func streamNextChunk(context: ChannelHandlerContext, reader: PayloadReader,
                                        offset: Int64, chunkSize: Int) {
        let chunk = reader.read(offset: offset, length: chunkSize)
        if chunk.isEmpty {
            context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
            reader.close()
            return
        }

        var buffer = context.channel.allocator.buffer(capacity: chunk.count)
        buffer.writeBytes(chunk)
        let promise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: promise)

        let nextOffset = offset + Int64(chunk.count)
        promise.futureResult.whenComplete { result in
            switch result {
            case .success:
                // whenComplete runs on the channel's event loop; safe to recurse
                // (scheduled, not stack-growing) and to reuse context/reader.
                streamNextChunk(context: context, reader: reader, offset: nextOffset, chunkSize: chunkSize)
            case .failure:
                // Client went away mid-transfer; stop reading and release the file.
                reader.close()
            }
        }
    }
}
