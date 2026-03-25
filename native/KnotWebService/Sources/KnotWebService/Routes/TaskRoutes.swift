import Foundation
import NIOCore
import NIOHTTP1
import KnotStorage

enum TaskRoutes {

    /// Whether stats repair has been run this session
    private static var statsRepaired = false

    static func list(context: ChannelHandlerContext, queryParams: [String: String]) {
        do {
            let db = DatabaseManager.shared.catalogDB

            // Auto-repair stats on first load (backfills historical tasks)
            if !statsRepaired {
                statsRepaired = true
                DispatchQueue.global().async {
                    CatalogDAO.repairAllStats(catalogDB: db, rootPath: DatabaseManager.rootPath)
                }
            }

            let tasks = try CatalogDAO.findAllTasks(db: db)
            let items: [[String: Any]] = tasks.map { t in
                var d: [String: Any] = [
                    "id": t.id,
                    "name": t.name,
                    "createdAt": t.createdAt,
                    "status": t.status,
                    "flowCount": t.flowCount,
                    "uploadBytes": t.uploadBytes,
                    "downloadBytes": t.downloadBytes,
                ]
                if let v = t.startedAt { d["startedAt"] = v }
                if let v = t.stoppedAt { d["stoppedAt"] = v }
                return d
            }
            ResponseHelper.jsonResponse(context: context, body: items)
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to list tasks: \(error.localizedDescription)")
        }
    }

    static func detail(context: ChannelHandlerContext, taskId: String, queryParams: [String: String]) {
        guard let id = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }
        do {
            let db = DatabaseManager.shared.catalogDB
            let stmt = try db.prepare(
                """
                SELECT id, name, created_at, started_at, stopped_at, status, rule_id,
                       local_ip, local_port, local_enabled,
                       wifi_ip, wifi_port, wifi_enabled,
                       flow_count, upload_bytes, download_bytes, note, extra
                FROM capture_task WHERE id = ?
                """, id
            )
            var found = false
            for row in stmt {
                found = true
                let dict: [String: Any] = [
                    "id": row[0] as? Int64 ?? 0,
                    "name": row[1] as? String ?? "",
                    "createdAt": row[2] as? Double ?? 0,
                    "startedAt": row[3] as? Double as Any,
                    "stoppedAt": row[4] as? Double as Any,
                    "status": Int(row[5] as? Int64 ?? 0),
                    "ruleId": row[6] as? Int64 as Any,
                    "localIp": row[7] as? String ?? "",
                    "localPort": Int(row[8] as? Int64 ?? 0),
                    "localEnabled": Int(row[9] as? Int64 ?? 1),
                    "wifiIp": row[10] as? String ?? "",
                    "wifiPort": Int(row[11] as? Int64 ?? 0),
                    "wifiEnabled": Int(row[12] as? Int64 ?? 1),
                    "flowCount": row[13] as? Int64 ?? 0,
                    "uploadBytes": row[14] as? Int64 ?? 0,
                    "downloadBytes": row[15] as? Int64 ?? 0,
                    "note": row[16] as? String ?? "",
                    "extra": row[17] as? String ?? "",
                ]
                ResponseHelper.jsonResponse(context: context, body: dict)
                return
            }
            if !found {
                ResponseHelper.errorResponse(context: context, status: .notFound, message: "Task not found")
            }
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to get task: \(error.localizedDescription)")
        }
    }

    // MARK: - Rename

    /// PATCH /api/tasks/{id} — update task properties (name)
    /// Body: {"name": "new name"}
    static func update(context: ChannelHandlerContext, taskId: String, bodyData: Data?) {
        guard let id = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Expected JSON body")
            return
        }
        do {
            let db = DatabaseManager.shared.catalogDB
            if let name = json["name"] as? String {
                try CatalogDAO.renameTask(db: db, taskId: id, name: name)
            }
            ResponseHelper.jsonResponse(context: context, body: ["updated": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to update task: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    /// DELETE /api/tasks/{id} — delete a single task and all its data
    static func delete(context: ChannelHandlerContext, taskId: String) {
        guard let id = Int64(taskId) else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Invalid task id")
            return
        }
        do {
            let db = DatabaseManager.shared.catalogDB
            try DatabaseManager.shared.deleteTask(id)
            try CatalogDAO.deleteTask(db: db, taskId: id)
            ResponseHelper.jsonResponse(context: context, body: ["deleted": id])
        } catch {
            ResponseHelper.errorResponse(context: context, status: .internalServerError,
                                         message: "Failed to delete task: \(error.localizedDescription)")
        }
    }

    /// POST /api/tasks/batch-delete — delete multiple tasks
    /// Body: {"ids": [1, 2, 3]}
    static func batchDelete(context: ChannelHandlerContext, bodyData: Data?) {
        guard let data = bodyData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = json["ids"] as? [Int] else {
            ResponseHelper.errorResponse(context: context, status: .badRequest, message: "Expected {\"ids\": [...]}")
            return
        }

        let db = DatabaseManager.shared.catalogDB
        var deleted: [Int] = []
        var failed: [Int] = []

        for id in ids {
            let taskId = Int64(id)
            do {
                try DatabaseManager.shared.deleteTask(taskId)
                try CatalogDAO.deleteTask(db: db, taskId: taskId)
                deleted.append(id)
            } catch {
                failed.append(id)
            }
        }

        ResponseHelper.jsonResponse(context: context, body: [
            "deleted": deleted,
            "failed": failed,
        ])
    }
}
