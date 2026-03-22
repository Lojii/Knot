import Foundation
import NIOCore
import NIOHTTP1
import NIOFoundationCompat

enum ResponseHelper {

    // MARK: - JSON envelope

    static func jsonResponse(
        context: ChannelHandlerContext,
        body: Any
    ) {
        let envelope: [String: Any] = ["code": 0, "data": body]
        sendJSON(context: context, status: .ok, object: envelope)
    }

    static func errorResponse(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        message: String
    ) {
        let envelope: [String: Any] = ["code": Int(status.code), "error": message]
        sendJSON(context: context, status: status, object: envelope)
    }

    // MARK: - Low-level

    static func sendHTTP(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        contentType: String,
        body: Data
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: contentType)
        headers.add(name: "content-length", value: "\(body.count)")
        headers.add(name: "access-control-allow-origin", value: "*")
        headers.add(name: "access-control-allow-methods", value: "GET, POST, OPTIONS")
        headers.add(name: "access-control-allow-headers", value: "Content-Type")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
    }

    // MARK: - Private

    private static func sendJSON(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        object: [String: Any]
    ) {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            data = Data("{\"code\":500,\"error\":\"JSON serialization failed\"}".utf8)
        }
        sendHTTP(context: context, status: status, contentType: "application/json", body: data)
    }
}
