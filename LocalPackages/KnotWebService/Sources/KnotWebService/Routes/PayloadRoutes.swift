import NIOCore
import NIOHTTP1

enum PayloadRoutes {

    static func request(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "PayloadRoutes.request not implemented")
    }

    static func response(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "PayloadRoutes.response not implemented")
    }

    static func decoded(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "PayloadRoutes.decoded not implemented")
    }
}
