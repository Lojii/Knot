import Foundation
import NIOCore
import NIOHTTP1
import KnotStorage

enum FlowRoutes {

    static func list(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        let page = Int(queryParams["page"] ?? "1") ?? 1
        let size = min(Int(queryParams["size"] ?? "50") ?? 50, 500)
        let offset = (page - 1) * size
        let protocolFilter = queryParams["protocol"]
        let hostContains = queryParams["host"]
        let keyword = queryParams["keyword"]

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            let flows = try FlowDAO.query(
                db: group.proto,
                protocolFilter: protocolFilter,
                hostContains: hostContains,
                keyword: keyword,
                offset: offset,
                limit: size
            )
            let total = try FlowDAO.count(
                db: group.proto,
                protocolFilter: protocolFilter,
                hostContains: hostContains,
                keyword: keyword
            )

            let items: [[String: Any]] = flows.map { flowToDict($0) }
            let body: [String: Any] = [
                "items": items,
                "total": total,
                "page": page,
                "size": size,
            ]
            ResponseHelper.jsonResponse(context: context, body: body)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to list flows: \(error.localizedDescription)")
        }
    }

    static func search(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }
        guard let q = queryParams["q"], !q.isEmpty else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Missing search query parameter 'q'")
            return
        }
        let limit = min(Int(queryParams["limit"] ?? "50") ?? 50, 500)

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            let entries = try DecodedEntryDAO.searchFullText(db: group.decoded, query: q, limit: limit)
            // Collect unique flow IDs from results
            let flowIds = Array(Set(entries.map { $0.flowId }))

            // Fetch matching flows
            var flowDicts: [[String: Any]] = []
            for fid in flowIds {
                if let flow = try FlowDAO.find(db: group.proto, flowId: fid) {
                    flowDicts.append(flowToDict(flow))
                }
            }

            let body: [String: Any] = [
                "items": flowDicts,
                "total": flowDicts.count,
            ]
            ResponseHelper.jsonResponse(context: context, body: body)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Search failed: \(error.localizedDescription)")
        }
    }

    static func stats(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            let protocolCounts = try FlowDAO.countByProtocol(db: group.proto)
            let statusCounts = try FlowDAO.countByStatus(db: group.proto)
            let bytes = try FlowDAO.totalBytes(db: group.proto)

            // Convert status int keys to string keys for JSON compatibility
            var statusDict: [String: Int] = [:]
            for (k, v) in statusCounts {
                statusDict["\(k)"] = v
            }

            let body: [String: Any] = [
                "protocols": protocolCounts,
                "statuses": statusDict,
                "totalUploadBytes": bytes.upload,
                "totalDownloadBytes": bytes.download,
            ]
            ResponseHelper.jsonResponse(context: context, body: body)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to get stats: \(error.localizedDescription)")
        }
    }

    /// Returns domain (host) list with request counts.
    static func domains(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            let hostCounts = try FlowDAO.countByHost(db: group.proto)
            let items: [[String: Any]] = hostCounts.map { ["host": $0.key, "count": $0.value] }
                .sorted { ($0["count"] as! Int) > ($1["count"] as! Int) }

            ResponseHelper.jsonResponse(context: context, body: ["items": items])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to get domains: \(error.localizedDescription)")
        }
    }

    static func filters(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            let protocolCounts = try FlowDAO.countByProtocol(db: group.proto)
            let contentTypes = try FlowDAO.distinctContentTypes(db: group.proto)

            let body: [String: Any] = [
                "protocols": Array(protocolCounts.keys),
                "contentTypes": contentTypes,
            ]
            ResponseHelper.jsonResponse(context: context, body: body)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to get filters: \(error.localizedDescription)")
        }
    }

    static func detail(context: ChannelHandlerContext, taskId: String, flowId: String, queryParams: [String: String]) {
        guard let tid = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }

        do {
            let group = try DatabaseManager.shared.openTask(tid)
            defer { DatabaseManager.shared.closeTask(tid) }

            guard let flow = try FlowDAO.find(db: group.proto, flowId: flowId) else {
                ResponseHelper.errorResponse(context: context, status: .notFound, message: "Flow not found")
                return
            }

            var dict = flowToDict(flow)

            // Add connection info if available
            if let conn = try TcpConnectionDAO.find(db: group.connection, flowId: flowId) {
                dict["connection"] = [
                    "srcIp": conn.srcIp,
                    "srcPort": conn.srcPort,
                    "dstIp": conn.dstIp,
                    "dstPort": conn.dstPort,
                    "state": conn.state,
                    "startedAt": conn.startedAt,
                    "establishedAt": conn.establishedAt as Any,
                    "closedAt": conn.closedAt as Any,
                    "closeReason": conn.closeReason,
                    "tlsVersion": conn.tlsVersion,
                    "tlsCipher": conn.tlsCipher,
                    "tlsSni": conn.tlsSni,
                    "packetsIn": conn.packetsIn,
                    "packetsOut": conn.packetsOut,
                    "bytesIn": conn.bytesIn,
                    "bytesOut": conn.bytesOut,
                ] as [String: Any]
            }

            ResponseHelper.jsonResponse(context: context, body: dict)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to get flow detail: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func flowToDict(_ f: FlowRecord) -> [String: Any] {
        var dict: [String: Any] = [
            "flowId": f.flowId,
            "protocol": f.protocolName,
            "host": f.host,
            "port": f.port,
            "startedAt": f.startedAt,
            "uploadBytes": f.uploadBytes,
            "downloadBytes": f.downloadBytes,
            "status": f.status.rawValue,
            "errorMessage": f.errorMessage,
            "summary": f.summary,
            "searchKey1": f.searchKey1,
            "searchKey2": f.searchKey2,
            "searchKey3": f.searchKey3,
            "searchKey4": f.searchKey4,
            "reqPayloadRef": f.reqPayloadRef,
            "rspPayloadRef": f.rspPayloadRef,
            "isIntercepted": f.isIntercepted,
            "isModified": f.isModified,
            "tags": f.tags,
            "connReuse": f.connReuse,
            "protoFlags": f.protoFlags,
        ]

        if let v = f.endedAt { dict["endedAt"] = v }
        if let v = f.durationMs { dict["durationMs"] = v }
        if let v = f.connectAt { dict["connectAt"] = v }
        if let v = f.connectedAt { dict["connectedAt"] = v }
        if let v = f.tlsDoneAt { dict["tlsDoneAt"] = v }
        if let v = f.reqEndAt { dict["reqEndAt"] = v }
        if let v = f.rspStartAt { dict["rspStartAt"] = v }
        if let v = f.pushStatus { dict["pushStatus"] = v }
        if let v = f.certChainRef { dict["certChainRef"] = v }

        if !f.metadata.isEmpty { dict["metadata"] = f.metadata }

        return dict
    }
}
