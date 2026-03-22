import NIOCore
import NIOHTTP1

enum TaskRoutes {

    static func list(context: ChannelHandlerContext, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "TaskRoutes.list not implemented")
    }

    static func detail(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "TaskRoutes.detail not implemented")
    }
}
