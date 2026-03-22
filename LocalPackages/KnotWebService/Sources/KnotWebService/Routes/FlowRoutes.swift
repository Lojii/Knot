import NIOCore
import NIOHTTP1

enum FlowRoutes {

    static func list(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "FlowRoutes.list not implemented")
    }

    static func search(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "FlowRoutes.search not implemented")
    }

    static func stats(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "FlowRoutes.stats not implemented")
    }

    static func detail(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        ResponseHelper.errorResponse(context: context, status: .notImplemented, message: "FlowRoutes.detail not implemented")
    }
}
