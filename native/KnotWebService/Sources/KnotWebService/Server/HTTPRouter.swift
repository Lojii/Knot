import Foundation
import NIOCore
import NIOHTTP1

final class HTTPRouter: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var uri: String?
    private var method: HTTPMethod?
    private var body: ByteBuffer?
    private var headers: HTTPHeaders?

    private let authToken: String

    /// Reject request bodies larger than this to prevent unbounded memory growth.
    private static let maxBodyBytes = 8 * 1024 * 1024

    init(authToken: String) {
        self.authToken = authToken
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            self.uri = head.uri
            self.method = head.method
            self.headers = head.headers
            self.body = nil

        case .body(let buf):
            if self.body == nil {
                self.body = buf
            } else {
                var b = buf
                self.body?.writeBuffer(&b)
            }
            if let count = self.body?.readableBytes, count > Self.maxBodyBytes {
                self.body = nil
                self.uri = nil
                ResponseHelper.errorResponse(context: context, status: .payloadTooLarge, message: "Request body too large")
            }

        case .end:
            guard let uri = self.uri, let method = self.method else {
                send404(context: context)
                return
            }
            let reqHeaders = self.headers ?? HTTPHeaders()
            let bodyData = body.flatMap { $0.getData(at: $0.readerIndex, length: $0.readableBytes) }
            self.uri = nil
            self.method = nil
            self.headers = nil
            self.body = nil
            route(context: context, method: method, uri: uri, headers: reqHeaders, bodyData: bodyData)
        }
    }

    // MARK: - Routing

    private func route(context: ChannelHandlerContext, method: HTTPMethod, uri: String, headers: HTTPHeaders = HTTPHeaders(), bodyData: Data? = nil) {
        let (path, queryParams) = parseURI(uri)
        let seg = pathSegments(path)
        let n = seg.count

        // CORS preflight — answer before auth (no body is exposed).
        if method == .OPTIONS {
            ResponseHelper.sendPreflight(context: context)
            return
        }

        // GET / — dashboard is served same-origin and needs no token.
        if method == .GET && n == 0 {
            serveDashboard(context: context)
            return
        }

        // Everything under /api requires the session token.
        if n >= 1 && seg[0] == "api" {
            guard RequestAuth.isAuthorized(headers: headers, uri: uri, expected: authToken) else {
                ResponseHelper.errorResponse(context: context, status: .unauthorized, message: "Unauthorized")
                return
            }
        }

        // /api/rules/...
        if n >= 2 && seg[0] == "api" && seg[1] == "rules" {
            routeRules(context: context, method: method, segments: Array(seg.dropFirst(2)), bodyData: bodyData)
            return
        }

        // /api/breakpoint/{flowId}/resume
        if n == 4 && seg[0] == "api" && seg[1] == "breakpoint" && seg[3] == "resume" && method == .PATCH {
            RuleRoutes.resumeBreakpoint(context: context, flowId: seg[2], bodyData: bodyData)
            return
        }

        // All remaining API routes start with /api/tasks
        guard n >= 2, seg[0] == "api", seg[1] == "tasks" else {
            send404(context: context)
            return
        }

        // POST /api/tasks/batch-delete
        if method == .POST && n == 3 && seg[2] == "batch-delete" {
            TaskRoutes.batchDelete(context: context, bodyData: bodyData)
            return
        }

        // GET /api/tasks
        if method == .GET && n == 2 {
            TaskRoutes.list(context: context, queryParams: queryParams)
            return
        }

        let taskId = seg[2]

        // DELETE /api/tasks/{id}
        if method == .DELETE && n == 3 {
            TaskRoutes.delete(context: context, taskId: taskId)
            return
        }

        // PATCH /api/tasks/{id} — rename / update
        if method == .PATCH && n == 3 {
            TaskRoutes.update(context: context, taskId: taskId, bodyData: bodyData)
            return
        }

        // GET /api/tasks/{id}
        if method == .GET && n == 3 {
            TaskRoutes.detail(context: context, taskId: taskId, queryParams: queryParams)
            return
        }

        guard method == .GET else {
            send404(context: context)
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

        // GET /api/tasks/{id}/flows/filters
        if n == 5 && seg4 == "filters" {
            FlowRoutes.filters(context: context, taskId: taskId, queryParams: queryParams)
            return
        }

        // GET /api/tasks/{id}/flows/domains
        if n == 5 && seg4 == "domains" {
            FlowRoutes.domains(context: context, taskId: taskId, queryParams: queryParams)
            return
        }

        // seg4 is flowId
        let flowId = seg4

        // GET /api/tasks/{id}/flows/{fid}
        if n == 5 {
            FlowRoutes.detail(context: context, taskId: taskId, flowId: flowId, queryParams: queryParams)
            return
        }

        if n == 6 {
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

            // GET /api/tasks/{id}/flows/{fid}/decoded (metadata)
            if seg5 == "decoded" {
                PayloadRoutes.decoded(context: context, taskId: taskId, flowId: flowId, queryParams: queryParams)
                return
            }
        }

        // GET /api/tasks/{id}/flows/{fid}/decoded/{direction} (streamed decoded bytes)
        if n == 7 && seg[5] == "decoded" {
            let direction = seg[6]
            PayloadRoutes.decodedPayload(context: context, taskId: taskId, flowId: flowId, direction: direction, queryParams: queryParams)
            return
        }

        send404(context: context)
    }

    // MARK: - Rule routing

    private func routeRules(context: ChannelHandlerContext, method: HTTPMethod,
                            segments: [String], bodyData: Data?) {
        let n = segments.count

        // /api/rules/map-local
        if n >= 1 && segments[0] == "map-local" {
            if method == .GET && n == 1 {
                RuleRoutes.listMapLocal(context: context)
                return
            }
            if method == .POST && n == 1 {
                RuleRoutes.createMapLocal(context: context, bodyData: bodyData)
                return
            }
            if n == 2, let id = Int64(segments[1]) {
                if method == .PUT {
                    RuleRoutes.updateMapLocal(context: context, id: id, bodyData: bodyData)
                    return
                }
                if method == .DELETE {
                    RuleRoutes.deleteMapLocal(context: context, id: id)
                    return
                }
            }
            if n == 3 && segments[2] == "toggle", let id = Int64(segments[1]), method == .PATCH {
                RuleRoutes.toggleMapLocal(context: context, id: id)
                return
            }
        }

        // /api/rules/map-remote
        if n >= 1 && segments[0] == "map-remote" {
            if method == .GET && n == 1 {
                RuleRoutes.listMapRemote(context: context)
                return
            }
            if method == .POST && n == 1 {
                RuleRoutes.createMapRemote(context: context, bodyData: bodyData)
                return
            }
            if n == 2, let id = Int64(segments[1]) {
                if method == .PUT {
                    RuleRoutes.updateMapRemote(context: context, id: id, bodyData: bodyData)
                    return
                }
                if method == .DELETE {
                    RuleRoutes.deleteMapRemote(context: context, id: id)
                    return
                }
            }
            if n == 3 && segments[2] == "toggle", let id = Int64(segments[1]), method == .PATCH {
                RuleRoutes.toggleMapRemote(context: context, id: id)
                return
            }
        }

        // /api/rules/allow-list
        if n >= 1 && segments[0] == "allow-list" {
            if method == .GET && n == 1 {
                RuleRoutes.listAllowList(context: context)
                return
            }
            if method == .POST && n == 1 {
                RuleRoutes.addToAllowList(context: context, bodyData: bodyData)
                return
            }
            if method == .DELETE && n == 2 {
                let pattern = segments[1].removingPercentEncoding ?? segments[1]
                RuleRoutes.removeFromAllowList(context: context, pattern: pattern)
                return
            }
        }

        // /api/rules/block-list
        if n >= 1 && segments[0] == "block-list" {
            if method == .GET && n == 1 {
                RuleRoutes.listBlockList(context: context)
                return
            }
            if method == .POST && n == 1 {
                RuleRoutes.addToBlockList(context: context, bodyData: bodyData)
                return
            }
            if method == .DELETE && n == 2 {
                let pattern = segments[1].removingPercentEncoding ?? segments[1]
                RuleRoutes.removeFromBlockList(context: context, pattern: pattern)
                return
            }
        }

        // /api/rules/no-caching
        if n >= 1 && segments[0] == "no-caching" {
            if method == .GET && n == 1 {
                RuleRoutes.getNoCaching(context: context)
                return
            }
            if method == .POST && n == 1 {
                RuleRoutes.setNoCaching(context: context, bodyData: bodyData)
                return
            }
        }

        // /api/rules/breakpoint
        if n >= 1 && segments[0] == "breakpoint" {
            if method == .GET && n == 1 {
                RuleRoutes.listBreakpoint(context: context)
                return
            }
            if method == .POST && n == 1 {
                RuleRoutes.createBreakpoint(context: context, bodyData: bodyData)
                return
            }
            if n == 2, let id = Int64(segments[1]) {
                if method == .PUT {
                    RuleRoutes.updateBreakpoint(context: context, id: id, bodyData: bodyData)
                    return
                }
                if method == .DELETE {
                    RuleRoutes.deleteBreakpoint(context: context, id: id)
                    return
                }
            }
            if n == 3 && segments[2] == "toggle", let id = Int64(segments[1]), method == .PATCH {
                RuleRoutes.toggleBreakpoint(context: context, id: id)
                return
            }
        }

        send404(context: context)
    }

    // MARK: - Dashboard

    private func serveDashboard(context: ChannelHandlerContext) {
        let html = DashboardHTML.html.replacingOccurrences(of: "__KNOT_TOKEN__", with: authToken)
        let body = Data(html.utf8)
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
