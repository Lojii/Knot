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

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            // Try decoded file first
            let decodedPath = PathManager.decodedPayloadPath(taskId: tid, flowId: flowId, direction: payloadDir)
            var filePath = decodedPath

            if !FileManager.default.fileExists(atPath: filePath) {
                // Fall back to raw payload
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

            guard FileManager.default.fileExists(atPath: filePath) else {
                ResponseHelper.errorResponse(context: context, status: .notFound, message: "Payload file not found")
                return
            }

            let reader: PayloadReader
            do {
                reader = try PayloadReader(filePath: filePath)
            } catch {
                ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                             message: "Cannot open payload: \(error.localizedDescription)")
                return
            }
            defer { reader.close() }

            // Stream full file via chunked transfer
            var headers = HTTPHeaders()
            headers.add(name: "content-type", value: "application/octet-stream")
            headers.add(name: "transfer-encoding", value: "chunked")
            headers.add(name: "access-control-allow-origin", value: "*")

            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

            for chunk in reader.chunks() {
                var buffer = context.channel.allocator.buffer(capacity: chunk.count)
                buffer.writeBytes(chunk)
                context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            }

            context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to read payload: \(error.localizedDescription)")
        }
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

            let filePath = PathManager.rawPayloadPath(taskId: tid, ref: payloadRef)
            guard FileManager.default.fileExists(atPath: filePath) else {
                ResponseHelper.errorResponse(context: context, status: .notFound, message: "Payload file not found")
                return
            }

            let reader: PayloadReader
            do {
                reader = try PayloadReader(filePath: filePath)
            } catch {
                ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                             message: "Cannot open payload: \(error.localizedDescription)")
                return
            }
            defer { reader.close() }

            if preview {
                // Preview mode: return first 4KB as a single response
                let previewSize = min(4096, Int(reader.size))
                let data = reader.read(offset: 0, length: previewSize)
                ResponseHelper.sendHTTP(
                    context: context,
                    status: .ok,
                    contentType: "application/octet-stream",
                    body: data
                )
            } else {
                // Streaming mode: chunked transfer
                var headers = HTTPHeaders()
                headers.add(name: "content-type", value: "application/octet-stream")
                headers.add(name: "transfer-encoding", value: "chunked")
                headers.add(name: "access-control-allow-origin", value: "*")
                headers.add(name: "access-control-allow-methods", value: "GET, POST, OPTIONS")
                headers.add(name: "access-control-allow-headers", value: "Content-Type")

                let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
                context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

                for chunk in reader.chunks() {
                    var buffer = context.channel.allocator.buffer(capacity: chunk.count)
                    buffer.writeBytes(chunk)
                    context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                }

                context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
            }
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to read payload: \(error.localizedDescription)")
        }
    }
}
