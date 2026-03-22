import Foundation
import NIOCore
import NIOHTTP1

final class HTTPRouter: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var uri: String?
    private var method: HTTPMethod?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            self.uri = head.uri
            self.method = head.method

        case .body:
            break

        case .end:
            guard let uri = self.uri, let method = self.method else {
                send404(context: context)
                return
            }
            self.uri = nil
            self.method = nil
            route(context: context, method: method, uri: uri)
        }
    }

    // MARK: - Routing

    private func route(context: ChannelHandlerContext, method: HTTPMethod, uri: String) {
        let (path, queryParams) = parseURI(uri)
        let seg = pathSegments(path)
        let n = seg.count

        guard method == .GET else {
            send404(context: context)
            return
        }

        // GET /
        if n == 0 {
            serveDashboard(context: context)
            return
        }

        // All API routes start with /api/tasks
        guard n >= 2, seg[0] == "api", seg[1] == "tasks" else {
            send404(context: context)
            return
        }

        // GET /api/tasks
        if n == 2 {
            TaskRoutes.list(context: context, queryParams: queryParams)
            return
        }

        let taskId = seg[2]

        // GET /api/tasks/{id}
        if n == 3 {
            TaskRoutes.detail(context: context, taskId: taskId, queryParams: queryParams)
            return
        }

        guard n >= 4, seg[3] == "flows" else {
            send404(context: context)
            return
        }

        // GET /api/tasks/{id}/flows
        if n == 4 {
            FlowRoutes.list(context: context, taskId: taskId, queryParams: queryParams)
            return
        }

        let seg4 = seg[4]

        // GET /api/tasks/{id}/flows/search
        if n == 5 && seg4 == "search" {
            FlowRoutes.search(context: context, taskId: taskId, queryParams: queryParams)
            return
        }

        // GET /api/tasks/{id}/flows/stats
        if n == 5 && seg4 == "stats" {
            FlowRoutes.stats(context: context, taskId: taskId, queryParams: queryParams)
            return
        }

        // seg4 is flowId
        let flowId = seg4

        // GET /api/tasks/{id}/flows/{fid}
        if n == 5 {
            FlowRoutes.detail(context: context, taskId: taskId, flowId: flowId, queryParams: queryParams)
            return
        }

        guard n == 6 else {
            send404(context: context)
            return
        }

        let seg5 = seg[5]

        // GET /api/tasks/{id}/flows/{fid}/request
        if seg5 == "request" {
            PayloadRoutes.request(context: context, taskId: taskId, flowId: flowId, queryParams: queryParams)
            return
        }

        // GET /api/tasks/{id}/flows/{fid}/response
        if seg5 == "response" {
            PayloadRoutes.response(context: context, taskId: taskId, flowId: flowId, queryParams: queryParams)
            return
        }

        // GET /api/tasks/{id}/flows/{fid}/decoded
        if seg5 == "decoded" {
            PayloadRoutes.decoded(context: context, taskId: taskId, flowId: flowId, queryParams: queryParams)
            return
        }

        send404(context: context)
    }

    // MARK: - Dashboard

    private func serveDashboard(context: ChannelHandlerContext) {
        let body = Data(DashboardHTML.html.utf8)
        ResponseHelper.sendHTTP(context: context, status: .ok, contentType: "text/html; charset=utf-8", body: body)
    }

    // MARK: - 404

    private func send404(context: ChannelHandlerContext) {
        ResponseHelper.errorResponse(context: context, status: .notFound, message: "Not Found")
    }

    // MARK: - URI parsing

    private func parseURI(_ uri: String) -> (path: String, queryParams: [String: String]) {
        let parts = uri.split(separator: "?", maxSplits: 1)
        let path = String(parts[0])
        var queryParams: [String: String] = [:]

        if parts.count > 1 {
            let queryString = String(parts[1])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                    let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    queryParams[key] = value
                } else if kv.count == 1 {
                    let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                    queryParams[key] = ""
                }
            }
        }

        return (path, queryParams)
    }

    private func pathSegments(_ path: String) -> [String] {
        return path.split(separator: "/").map(String.init)
    }
}
