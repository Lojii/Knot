//
//  Task.swift
//  NIOMan
//
//  Created by LiuJie on 2022/3/24.
//

import Foundation
import ActiveSQLite
import SQLite

@_silgen_name("initInBytes")
public func initInBytes(task_id: UnsafePointer<CChar>) -> CUnsignedLongLong {
    var param:Dictionary<String, String> = Dictionary<String, String>()
    param["task_id"] = String(cString: task_id)
    if let lastTast = Task.findFirst(param) { return lastTast.in_bytes.uint64Value }
    return 0;
}

@_silgen_name("initOutBytes")
public func initOutBytes(task_id: UnsafePointer<CChar>) -> CUnsignedLongLong {
    var param:Dictionary<String, String> = Dictionary<String, String>()
    param["task_id"] = String(cString: task_id)
    if let lastTast = Task.findFirst(param) {
        return lastTast.out_bytes.uint64Value
    }
    return 0;
}

// 存入接口
@_silgen_name("saveTask")
public func saveTask( task_id: UnsafePointer<CChar>, conn_count: CUnsignedLong, out_bytes: CUnsignedLong, in_bytes: CUnsignedLong, start_time: CDouble, stop_time: CDouble) {
    let currentConfig = Rule.currentRule()
//        currentConfig.id
//        currentConfig.name
    
    var param:Dictionary<String, String> = Dictionary<String, String>()
    param["task_id"] = String(cString: task_id)
    if Session.findFirst(param) != nil { return }
    let t = Task()
    t.task_id = String(cString: task_id)
    t.conn_count = NSNumber(value:conn_count)
    t.out_bytes = NSNumber(value:out_bytes)
    t.in_bytes = NSNumber(value:in_bytes)
    t.start_time = NSNumber(value:start_time)
    t.rule_id = currentConfig.id ?? -1
    t.rule_name = currentConfig.name
    try! t.save()
    var data = [String:Any]()
    data["task_id"] = t.task_id
    data["conn_count"] = t.conn_count
    data["in_bytes"] = t.in_bytes
    data["out_bytes"] = t.out_bytes
    NIOMan.sendInfo(type: "task", action: "create", data: data)
}

@_silgen_name("updateTask")
public func updateTask( task_id: UnsafePointer<CChar>, conn_count: CUnsignedLong, out_bytes: CUnsignedLong, in_bytes: CUnsignedLong, start_time: CDouble, stop_time: CDouble,req_line: UnsafePointer<CChar>) {
    var params = Dictionary<String, Any?>()
    if NSNumber(value:conn_count).intValue > 0 { params["conn_count"] = NSNumber(value:conn_count) }
    if NSNumber(value:out_bytes).intValue > 0 { params["out_bytes"] = NSNumber(value:out_bytes) }
    if NSNumber(value:in_bytes).intValue > 0 { params["in_bytes"] = NSNumber(value:in_bytes) }
    if NSNumber(value:stop_time).intValue > 0 { params["stop_time"] = NSNumber(value:stop_time) }
    try? Task.update(params, where: ["task_id": String(cString: task_id)])
    
    var data = [String:Any]()
    data["task_id"] = String(cString: task_id)
    data["conn_count"] = NSNumber(value:conn_count)
    data["in_bytes"] = NSNumber(value:in_bytes)
    data["out_bytes"] = NSNumber(value:out_bytes)
    data["req_line"] = String(cString: req_line)
    NIOMan.sendInfo(type: "task", action: "update", data: data)
}

public class Task: ASModel {
    public var task_id: String = ""         // 任务id
    public var conn_count:NSNumber = 0      // 数量
    public var out_bytes:NSNumber = 0       // 上传流量
    public var in_bytes:NSNumber = 0        // 下载流量
    
    // 配置信息
    public var rule_name:String = "" // 配置名称
    public var rule_id:NSNumber = -1
    //
    public var start_time:NSNumber?// 开启时间  = Int( Date().timeIntervalSince1970 * 1000)
    public var stop_time:NSNumber? // 关闭时间
    
    public var wifi_ip:String = "" // 当前WiFi的IP地址，网络变化时更新。
    
    public var note:String = "" // 备注信息
    public var extra:String = "" // 额外信息
    
    public static func deleteAll(taskIds:[String]) -> Bool {
        if taskIds.count <= 0 { return true }
//        let s = taskIds.map { (id) -> String in return "\(id)" }
        let sql = "delete from task where task_id in ( \(taskIds.joined(separator: ",")) )"
        print("sql:\(sql)")
        let db = try! ASConfigration.getDefaultDB()
        do {
//            _ = try db.prepare(sql)
            try db.run(sql)
            return true
        } catch  {
            print("delete tasks error:\(error.localizedDescription)")
            return false
        }
    }
    public static func findAllTaskIds(ids:[Int]) -> [String] {
        var task_ids:[String] = []
        let s = ids.map { (id) -> String in return "\(id)" }
        let sql = "select task_id from task where id in ( \(s.joined(separator: ",")) )"
        print("sql:\(sql)")
        let db = try! ASConfigration.getDefaultDB()
//        var sessions = [Session]()
        do {
//            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                for i in 0..<columnNames.count {
                    let columnName = columnNames[i]
                    guard let value = row[i] else { continue }
                    if columnName == "task_id" {
                        task_ids.append(value as? String ?? "")
                    }
                }
            }
//            let endTime = CFAbsoluteTimeGetCurrent()
//            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getAll error:\(error)")
        }
        return task_ids
    }
    
    public static func findAll(taskIds:[String]) -> [Session] {
        if taskIds.count <= 0 { return [] }
//        let s = taskIds.map { (id) -> String in return "\(id)" }
        let sql = "select * from session where task_id in ( \(taskIds.joined(separator: ",")) )"
        print("sql:\(sql)")
        let db = try! ASConfigration.getDefaultDB()
        var sessions = [Session]()
        do {
//            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                let session = Session.getWith(columnNames: columnNames, row: row)
                if session != nil { sessions.append(session!) }
            }
//            let endTime = CFAbsoluteTimeGetCurrent()
//            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getAll error:\(error)")
        }
        return sessions
    }
    
    public static func findOne(_ task_id:String) -> Task? {
        let sql = findOneSQL(task_id)
        let db = try! ASConfigration.getDefaultDB()
        var tasks = [Task]()
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                if let task = tasktWith(columnNames: columnNames, row: row) {
                    tasks.append(task)
                }
            }
            let endTime = CFAbsoluteTimeGetCurrent()
            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getOne error:\(error)")
        }
        if tasks.count > 0 {
            return tasks.first
        }
        return nil
    }
    
    static func findOneSQL(_ task_id:String) -> String {
        let selectStr = "select t.id,t.task_id,t.conn_count,t.out_bytes,t.in_bytes,t.rule_name,t.rule_id,t.start_time,t.stop_time,t.wifi_ip,t.note,t.extra,"
        let calcStr = "count(s.id) as connCount,sum(s.in_bytes) as sumInBytes,sum(s.out_bytes) as sumOutBytes "
        let fromStr = "from task t left join session s on t.task_id = s.task_id "
        let whereStr = "where t.task_id = \(task_id) "
        let groupStr = "group by t.id "
//        let orderStr = "order by t.\(orderBy) desc "
//        let limitStr = "limit \(pageSize)"
        let sql = selectStr+calcStr+fromStr+whereStr+groupStr//+orderStr+limitStr
        return sql
    }
    
    public static func find(excludeTaskId:String? = nil,maxId:NSNumber = NSNumber(value: Int.max), orderBy:String = "id" , pageSize:Int = 20) -> [Task] {
        let sql = findSQL(excludeTaskId:excludeTaskId, maxId: maxId, orderBy: orderBy, pageSize: pageSize)
        let db = try! ASConfigration.getDefaultDB()
        var tasks = [Task]()
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                if let task = tasktWith(columnNames: columnNames, row: row) {
                    tasks.append(task)
                }
            }
            let endTime = CFAbsoluteTimeGetCurrent()
            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getAll error:\(error)")
        }
        return tasks
    }
    
    public static func getAllIds(excludeTaskId:String? = nil) -> [Int] {
        let sql = "select id from task where \(excludeTaskId == nil ? "1 = 1" : "task_id != \(excludeTaskId!)")"
        let db = try! ASConfigration.getDefaultDB()
        var results = [Int]()
        do {
            let result = try db.prepare(sql)
            for row in result {
                if let sessionId = row[0] as? NSNumber {
                    results.append(sessionId.intValue)
                }
            }
        } catch  {
            print("getAll error:\(error)")
        }
        return results
    }
    
    
    // list
    static func findSQL(excludeTaskId:String?, maxId:NSNumber, orderBy:String = "id" , pageSize:Int = 20) -> String {
        let selectStr = "select t.id,t.task_id,t.conn_count,t.out_bytes,t.in_bytes,t.rule_name,t.rule_id,t.start_time,t.stop_time,t.wifi_ip,t.note,t.extra,"
        let calcStr = "count(s.id) as connCount,sum(s.in_bytes) as sumInBytes,sum(s.out_bytes) as sumOutBytes "
        let fromStr = "from task t left join session s on t.task_id = s.task_id "
        let whereStr = "where t.id < \(maxId.doubleValue) \(excludeTaskId == nil ? "" : "and t.task_id != \(excludeTaskId!)") "
        let groupStr = "group by t.id "
        let orderStr = "order by t.\(orderBy) desc "
        let limitStr = "limit \(pageSize)"
        let sql = selectStr+calcStr+fromStr+whereStr+groupStr+orderStr+limitStr
        return sql
    }
    
    static func tasktWith(columnNames:[String],row:Statement.Element) -> Task? {
        let task = Task()
        for i in 0..<columnNames.count {
            let columnName = columnNames[i]
            guard let value = row[i] else {
                continue
            }
            switch columnName {
            case "id":task.id =  value as? NSNumber
            case "task_id":task.task_id =  value as? String ?? ""
//            case "conn_count":task.conn_count =  value as? NSNumber ?? -1
//            case "out_bytes":task.out_bytes =  value as? NSNumber ?? 0
//            case "in_bytes":task.in_bytes =  value as? NSNumber ?? 0
            case "rule_name":task.rule_name =  value as? String ?? "Default"
            case "rule_id":task.rule_id =  value as? NSNumber ?? 0
            case "start_time":task.start_time =  value as? NSNumber ?? 0
            case "stop_time":task.stop_time =  value as? NSNumber ?? 0
            case "wifi_ip":task.wifi_ip =  value as? String ?? ""
            case "note":task.note =  value as? String ?? ""
            case "extra":task.extra =  value as? String ?? ""
            case "connCount":task.conn_count =  value as? NSNumber ?? 0
            case "sumInBytes":task.in_bytes =  value as? NSNumber ?? 0
            case "sumOutBytes":task.out_bytes =  value as? NSNumber ?? 0
            default:
                break
            }
            if task.rule_name == "" {
                task.rule_name = "Default"
            }
        }
        return task
    }
    
    
}
