import Foundation
import NIOCore
import NIOHTTP1
import KnotStorage

public enum RuleRoutes {

    /// Static callback for resuming breakpoints — wired by ProxyServer when LiveBridge is attached.
    public static var onBreakpointResume: ((String, String, [String: Any]?) -> Void)?

    /// Static callback for toggling No Caching — wired by ProxyServer to set on active CaptureTask.
    public static var onNoCachingChanged: ((Bool) -> Void)?

    // MARK: - Map Local

    static func listMapLocal(context: ChannelHandlerContext) {
        do {
            let db = DatabaseManager.shared.catalogDB
            let rules = try RuleDAO.findAllMapLocal(db: db)
            let items: [[String: Any]] = rules.map { r in
                var d: [String: Any] = [
                    "id": r.id,
                    "enabled": r.enabled,
                    "urlPattern": r.urlPattern,
                    "statusCode": r.statusCode,
                    "responseHeaders": r.responseHeaders,
                    "responseFile": r.responseFile,
                    "comment": r.comment,
                    "createdAt": r.createdAt,
                ]
                if let m = r.method { d["method"] = m }
                return d
            }
            ResponseHelper.jsonResponse(context: context, body: items)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to list map-local rules: \(error.localizedDescription)")
        }
    }

    static func createMapLocal(context: ChannelHandlerContext, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid JSON body")
            return
        }
        do {
            var rule = MapLocalRule()
            rule.urlPattern = json["urlPattern"] as? String ?? ""
            rule.method = json["method"] as? String
            rule.statusCode = json["statusCode"] as? Int ?? 200
            rule.responseHeaders = json["responseHeaders"] as? String ?? ""
            rule.responseFile = json["responseFile"] as? String ?? ""
            rule.comment = json["comment"] as? String ?? ""
            if let enabled = json["enabled"] as? Bool { rule.enabled = enabled }

            let db = DatabaseManager.shared.catalogDB
            let id = try RuleDAO.insertMapLocal(db: db, rule: rule)
            ResponseHelper.jsonResponse(context: context, body: ["id": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to create map-local rule: \(error.localizedDescription)")
        }
    }

    static func updateMapLocal(context: ChannelHandlerContext, id: Int64, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid JSON body")
            return
        }
        do {
            var rule = MapLocalRule()
            rule.id = id
            rule.urlPattern = json["urlPattern"] as? String ?? ""
            rule.method = json["method"] as? String
            rule.statusCode = json["statusCode"] as? Int ?? 200
            rule.responseHeaders = json["responseHeaders"] as? String ?? ""
            rule.responseFile = json["responseFile"] as? String ?? ""
            rule.comment = json["comment"] as? String ?? ""
            if let enabled = json["enabled"] as? Bool { rule.enabled = enabled }

            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.updateMapLocal(db: db, rule: rule)
            ResponseHelper.jsonResponse(context: context, body: ["updated": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to update map-local rule: \(error.localizedDescription)")
        }
    }

    static func deleteMapLocal(context: ChannelHandlerContext, id: Int64) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.deleteMapLocal(db: db, id: id)
            ResponseHelper.jsonResponse(context: context, body: ["deleted": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to delete map-local rule: \(error.localizedDescription)")
        }
    }

    static func toggleMapLocal(context: ChannelHandlerContext, id: Int64) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.toggleMapLocal(db: db, id: id)
            ResponseHelper.jsonResponse(context: context, body: ["toggled": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to toggle map-local rule: \(error.localizedDescription)")
        }
    }

    // MARK: - Breakpoint

    static func listBreakpoint(context: ChannelHandlerContext) {
        do {
            let db = DatabaseManager.shared.catalogDB
            let rules = try RuleDAO.findAllBreakpoint(db: db)
            let items: [[String: Any]] = rules.map { r in
                var d: [String: Any] = [
                    "id": r.id,
                    "enabled": r.enabled,
                    "urlPattern": r.urlPattern,
                    "breakOn": r.breakOn,
                    "comment": r.comment,
                    "createdAt": r.createdAt,
                ]
                if let m = r.method { d["method"] = m }
                return d
            }
            ResponseHelper.jsonResponse(context: context, body: items)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to list breakpoint rules: \(error.localizedDescription)")
        }
    }

    static func createBreakpoint(context: ChannelHandlerContext, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid JSON body")
            return
        }
        do {
            var rule = BreakpointRule()
            rule.urlPattern = json["urlPattern"] as? String ?? ""
            rule.method = json["method"] as? String
            rule.breakOn = json["breakOn"] as? String ?? "both"
            rule.comment = json["comment"] as? String ?? ""
            if let enabled = json["enabled"] as? Bool { rule.enabled = enabled }

            let db = DatabaseManager.shared.catalogDB
            let id = try RuleDAO.insertBreakpoint(db: db, rule: rule)
            ResponseHelper.jsonResponse(context: context, body: ["id": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to create breakpoint rule: \(error.localizedDescription)")
        }
    }

    static func updateBreakpoint(context: ChannelHandlerContext, id: Int64, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid JSON body")
            return
        }
        do {
            var rule = BreakpointRule()
            rule.id = id
            rule.urlPattern = json["urlPattern"] as? String ?? ""
            rule.method = json["method"] as? String
            rule.breakOn = json["breakOn"] as? String ?? "both"
            rule.comment = json["comment"] as? String ?? ""
            if let enabled = json["enabled"] as? Bool { rule.enabled = enabled }

            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.updateBreakpoint(db: db, rule: rule)
            ResponseHelper.jsonResponse(context: context, body: ["updated": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to update breakpoint rule: \(error.localizedDescription)")
        }
    }

    static func deleteBreakpoint(context: ChannelHandlerContext, id: Int64) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.deleteBreakpoint(db: db, id: id)
            ResponseHelper.jsonResponse(context: context, body: ["deleted": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to delete breakpoint rule: \(error.localizedDescription)")
        }
    }

    static func toggleBreakpoint(context: ChannelHandlerContext, id: Int64) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.toggleBreakpoint(db: db, id: id)
            ResponseHelper.jsonResponse(context: context, body: ["toggled": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to toggle breakpoint rule: \(error.localizedDescription)")
        }
    }

    // MARK: - Map Remote

    static func listMapRemote(context: ChannelHandlerContext) {
        do {
            let db = DatabaseManager.shared.catalogDB
            let rules = try RuleDAO.findAllMapRemote(db: db)
            let items: [[String: Any]] = rules.map { r in
                var d: [String: Any] = [
                    "id": r.id,
                    "enabled": r.enabled,
                    "urlPattern": r.urlPattern,
                    "comment": r.comment,
                    "createdAt": r.createdAt,
                ]
                if let m = r.method { d["method"] = m }
                if let v = r.replaceScheme { d["replaceScheme"] = v }
                if let v = r.replaceHost { d["replaceHost"] = v }
                if let v = r.replacePort { d["replacePort"] = v }
                if let v = r.replacePath { d["replacePath"] = v }
                return d
            }
            ResponseHelper.jsonResponse(context: context, body: items)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to list map-remote rules: \(error.localizedDescription)")
        }
    }

    static func createMapRemote(context: ChannelHandlerContext, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid JSON body")
            return
        }
        do {
            var rule = MapRemoteRule()
            rule.urlPattern = json["urlPattern"] as? String ?? ""
            rule.method = json["method"] as? String
            rule.replaceScheme = json["replaceScheme"] as? String
            rule.replaceHost = json["replaceHost"] as? String
            rule.replacePort = json["replacePort"] as? Int
            rule.replacePath = json["replacePath"] as? String
            rule.comment = json["comment"] as? String ?? ""
            if let enabled = json["enabled"] as? Bool { rule.enabled = enabled }

            let db = DatabaseManager.shared.catalogDB
            let id = try RuleDAO.insertMapRemote(db: db, rule: rule)
            ResponseHelper.jsonResponse(context: context, body: ["id": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to create map-remote rule: \(error.localizedDescription)")
        }
    }

    static func updateMapRemote(context: ChannelHandlerContext, id: Int64, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid JSON body")
            return
        }
        do {
            var rule = MapRemoteRule()
            rule.id = id
            rule.urlPattern = json["urlPattern"] as? String ?? ""
            rule.method = json["method"] as? String
            rule.replaceScheme = json["replaceScheme"] as? String
            rule.replaceHost = json["replaceHost"] as? String
            rule.replacePort = json["replacePort"] as? Int
            rule.replacePath = json["replacePath"] as? String
            rule.comment = json["comment"] as? String ?? ""
            if let enabled = json["enabled"] as? Bool { rule.enabled = enabled }

            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.updateMapRemote(db: db, rule: rule)
            ResponseHelper.jsonResponse(context: context, body: ["updated": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to update map-remote rule: \(error.localizedDescription)")
        }
    }

    static func deleteMapRemote(context: ChannelHandlerContext, id: Int64) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.deleteMapRemote(db: db, id: id)
            ResponseHelper.jsonResponse(context: context, body: ["deleted": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to delete map-remote rule: \(error.localizedDescription)")
        }
    }

    static func toggleMapRemote(context: ChannelHandlerContext, id: Int64) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.toggleMapRemote(db: db, id: id)
            ResponseHelper.jsonResponse(context: context, body: ["toggled": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to toggle map-remote rule: \(error.localizedDescription)")
        }
    }

    // MARK: - Allow List

    static func listAllowList(context: ChannelHandlerContext) {
        do {
            let db = DatabaseManager.shared.catalogDB
            let patterns = try RuleDAO.findAllAllowList(db: db)
            ResponseHelper.jsonResponse(context: context, body: patterns)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to list allow-list: \(error.localizedDescription)")
        }
    }

    static func addToAllowList(context: ChannelHandlerContext, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pattern = json["pattern"] as? String else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Expected {\"pattern\": \"...\"}")
            return
        }
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.addToAllowList(db: db, pattern: pattern)
            ResponseHelper.jsonResponse(context: context, body: ["added": pattern])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to add to allow-list: \(error.localizedDescription)")
        }
    }

    static func removeFromAllowList(context: ChannelHandlerContext, pattern: String) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.removeFromAllowList(db: db, pattern: pattern)
            ResponseHelper.jsonResponse(context: context, body: ["removed": pattern])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to remove from allow-list: \(error.localizedDescription)")
        }
    }

    // MARK: - Block List

    static func listBlockList(context: ChannelHandlerContext) {
        do {
            let db = DatabaseManager.shared.catalogDB
            let patterns = try RuleDAO.findAllBlockList(db: db)
            ResponseHelper.jsonResponse(context: context, body: patterns)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to list block-list: \(error.localizedDescription)")
        }
    }

    static func addToBlockList(context: ChannelHandlerContext, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pattern = json["pattern"] as? String else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Expected {\"pattern\": \"...\"}")
            return
        }
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.addToBlockList(db: db, pattern: pattern)
            ResponseHelper.jsonResponse(context: context, body: ["added": pattern])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to add to block-list: \(error.localizedDescription)")
        }
    }

    static func removeFromBlockList(context: ChannelHandlerContext, pattern: String) {
        do {
            let db = DatabaseManager.shared.catalogDB
            try RuleDAO.removeFromBlockList(db: db, pattern: pattern)
            ResponseHelper.jsonResponse(context: context, body: ["removed": pattern])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to remove from block-list: \(error.localizedDescription)")
        }
    }

    // MARK: - No Caching

    /// Runtime-only noCaching flag. Stored on the active CaptureTask, not persisted.
    static var noCachingEnabled: Bool = false

    static func getNoCaching(context: ChannelHandlerContext) {
        ResponseHelper.jsonResponse(context: context, body: ["enabled": noCachingEnabled])
    }

    static func setNoCaching(context: ChannelHandlerContext, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = json["enabled"] as? Bool else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Expected {\"enabled\": true/false}")
            return
        }
        noCachingEnabled = enabled
        onNoCachingChanged?(enabled)
        ResponseHelper.jsonResponse(context: context, body: ["enabled": enabled])
    }

    // MARK: - Breakpoint Resume

    /// PATCH /api/breakpoint/{flowId}/resume
    /// Body: {"action": "execute"|"cancel"|"abort", "modifiedRequest": {...}}
    static func resumeBreakpoint(context: ChannelHandlerContext, flowId: String, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            ResponseHelper.errorResponse(context: context, status: .badRequest,
                                         message: "Expected {\"action\": \"execute\"|\"cancel\"|\"abort\"}")
            return
        }
        let modified = json["modifiedRequest"] as? [String: Any]
        if let handler = onBreakpointResume {
            handler(flowId, action, modified)
            ResponseHelper.jsonResponse(context: context, body: ["resumed": flowId])
        } else {
            ResponseHelper.errorResponse(context: context, status: .serviceUnavailable,
                                         message: "No breakpoint resume handler registered")
        }
    }
}
