//
//  Session.swift
//  NIO2022
//
//  Created by LiuJie on 2022/3/18.
//

import Foundation
import ActiveSQLite
import SQLite

public let ImageTypes = ["3dm","3ds","max","bmp","dds","gif","jpg","jpeg","png","psd","xcf","tga","thm","tif","tiff","yuv","ai","eps","ps","svg","dwg","dxf","gpx","kml","kmz","webp","heif"]
public let CompressTypes = ["gzip","br"]
public let JSTypes = ["javascript","x-javascript"]
public let CSSTypes = ["css"]
public let urlEncodedTypes = ["x-www-form-urlencoded"]
// https://github.com/dyne/file-extension-list/blob/master/pub/categories.json
public let FileTypes = [
    "archive": ["7z","a","apk","ar","bz2","cab","cpio","deb","dmg","egg","gz","iso","jar","lha","mar","pea","rar","rpm","s7z","shar","tar","tbz2","tgz","tlz","war","whl","xpi","zip","zipx","xz","pak"],
    "audio": ["aac","aiff","ape","au","flac","gsm","it","m3u","m4a","mid","mod","mp3","mpa","pls","ra","s3m","sid","wav","wma","xm"],
    "book": ["mobi","epub","azw1","azw3","azw4","azw6","azw","cbr","cbz"],
    "exec": ["exe","msi","bin","command","sh","bat","crx","bash","csh","fish","ksh","zsh"],
    "font": ["eot","otf","ttf","woff","woff2"],
    "image": ["3dm","3ds","max","bmp","dds","gif","jpg","jpeg","png","psd","xcf","tga","thm","tif","tiff","yuv","ai","eps","ps","svg","dwg","dxf","gpx","kml","kmz","webp","heif"],
    "sheet": ["ods","xls","xlsx","csv","ics","vcf"],
    "slide": ["ppt","odp"],
    "text": ["doc","docx","ebook","log","md","msg","odt","org","pages","pdf","rtf","rst","tex","txt","wpd","wps"],
    "video": ["3g2","3gp","aaf","asf","avchd","avi","drc","flv","m2v","m4p","m4v","mkv","mng","mov","mp2","mp4","mpe","mpeg","mpg","mpv","mxf","nsv","ogg","ogv","ogm","qt","rm","rmvb","roq","srt","svi","vob","webm","wmv","yuv"],
    "web": ["html","htm","css","js","jsx","less","scss","wasm","php"]
]

// 获取最大conn数
@_silgen_name("maxConnNum")
public func maxConnNum(task_id: UnsafePointer<CChar>) -> CUnsignedLongLong {
    var param:Dictionary<String, String> = Dictionary<String, String>()
    param["task_id"] = String(cString: task_id)
    if let lastSession = Session.findFirst(param, ["conn_id":false]) {
        return lastSession.conn_id.uint64Value
    }
    return 0;
}

// 存入接口
@_silgen_name("saveToDB")
public func saveToDB(schemes: UnsafePointer<CChar>,             // http / https / ...
                     task_id: UnsafePointer<CChar>,             // 任务id
                     conn_id: CUnsignedLong,                    // 连接序号
                     
                     srchost_str: UnsafePointer<CChar>,         // 源地址
                     srcport_str: UnsafePointer<CChar>,         // 源端口
                     dsthost_str: UnsafePointer<CChar>,         // 目标地址
                     dstport_str: UnsafePointer<CChar>,         // 目标端口
                     
                     in_bytes: CUnsignedLong,                   // 接收数据量
                     out_bytes: CUnsignedLong,                  // 发送数据量
                     
                     dns_time_s:CDouble,                        // DNS开始时间
                     connect_s:CDouble,                         // 开始建立连接
                     send_s:CDouble,                            // 开始发送数据
                     send_e:CDouble,                            // 发送结束
                     receive_s:CDouble,                         // 开始接受数据
                     receive_e:CDouble,                         // 接受结束
                     method: UnsafePointer<CChar>,              // 方法
                     uri: UnsafePointer<CChar>,                 // uri
                     host: UnsafePointer<CChar>,                // host
                     req_line: UnsafePointer<CChar>,            // 请求行
                     req_content_type: UnsafePointer<CChar>,    //
                     req_encode: UnsafePointer<CChar>,          //
                     req_body_size: UnsafePointer<CChar>,       //
                     req_target: UnsafePointer<CChar>,          //
                     rsp_line: UnsafePointer<CChar>,            //
                     rsp_state: UnsafePointer<CChar>,           //
                     rsp_message: UnsafePointer<CChar>,         //
                     rsp_content_type: UnsafePointer<CChar>,    //
                     rsp_encode: UnsafePointer<CChar>,          //
                     rsp_body_size: UnsafePointer<CChar>        //
) {
    let s = Session()
//    // id
    s.task_id = String(cString: task_id)
    s.conn_id = NSNumber(value: conn_id)
    // data
    s.in_bytes = NSNumber(value:in_bytes)
    s.out_bytes = NSNumber(value:out_bytes)
    // time
    s.dns_time_s = NSNumber(value:dns_time_s)
    s.connect_s = NSNumber(value:connect_s)
    s.send_s = NSNumber(value:send_s)
    s.send_e = NSNumber(value:send_e)
    s.receive_s = NSNumber(value:receive_s)
    s.receive_e = NSNumber(value:receive_e)
    // req rsp
    s.schemes = String(cString: schemes)
    s.srchost_str = String(cString: srchost_str)
    s.srcport_str = String(cString: srcport_str)
    s.dsthost_str = String(cString: dsthost_str)
    s.dstport_str = String(cString: dstport_str)
    s.method = String(cString: method)
    s.uri = String(cString: uri)
    s.host = String(cString: host)
    s.req_line = String(cString: req_line)
    s.req_content_type = String(cString: req_content_type)
    s.req_encode = String(cString: req_encode)
    s.req_body_size = String(cString: req_body_size)
    s.req_target = String(cString: req_target)
    s.rsp_line = String(cString: rsp_line)
    s.rsp_state = String(cString: rsp_state)
    s.rsp_message = String(cString: rsp_message)
    s.rsp_content_type = String(cString: rsp_content_type)
    s.rsp_encode = String(cString: rsp_encode)
    s.rsp_body_size = String(cString: rsp_body_size)
    try! s.saveToDB()
    
}

public class Session: ASModel {
    
    public var task_id: String = ""             // 任务id
    public var conn_id: NSNumber = 0            // 连接序号

    public var in_bytes: NSNumber = 0           // 接收数据量
    public var out_bytes: NSNumber = 0          // 发送数据量

    public var dns_time_s: NSNumber = 0         // DNS开始时间
    public var connect_s: NSNumber = 0          // 开始建立连接
    public var send_s: NSNumber = 0             // 开始发送数据
    public var send_e: NSNumber = 0             // 发送结束
    public var receive_s: NSNumber = 0          // 开始接受数据
    public var receive_e: NSNumber = 0          // 接受结束

    public var schemes: String = ""             // http / https / ...
    public var srchost_str: String = ""         // 源地址
    public var srcport_str: String = ""         // 源端口
    public var dsthost_str: String = ""         // 目标地址
    public var dstport_str: String = ""         // 目标端口
    public var method: String = ""              // 方法
    public var uri: String = ""                 // uri
    public var host: String = ""                // host
    public var req_line: String = ""            // 请求行
    public var req_content_type: String = ""    // req数据类型
    public var req_encode: String = ""          // req编码
    public var req_body_size: String = ""       // req body 大小
    public var req_target: String = ""          // 标志
    public var rsp_line: String = ""            // 响应行
    public var rsp_state: String = ""           // 状态码
    public var rsp_message: String = ""         // 消息
    public var rsp_content_type: String = ""    // rsp类型
    public var rsp_encode: String = ""          // rsp编码
    public var rsp_body_size: String = ""       // rsp body 大小
    // 需要额外计算得出
    public var suffix: String = ""              // 后缀
    public var version: String = ""             // 版本
    public var req_path: String = ""            // req文件路径
    public var rsp_path: String = ""            // rsp文件路径
    
    public var file_type: String = ""            // 文件类型
    
    override public func doubleTypes() -> [String]{
        return ["dns_time_s","connect_s","send_s","send_e","receive_s","receive_e"]
    }
    
    // 计算后缀、版本、req rsp 路径以及crt路径
    func preSave(){
        req_target = Session.getUserAgent(target: req_target)
        // suffix
        if let ss = rsp_content_type.components(separatedBy: ";").first {
            suffix = ss.components(separatedBy: "/").last ?? ""
        }
        if let lastComponent = uri.components(separatedBy: "/").last {
            if let path = lastComponent.components(separatedBy: "?").first {
                let coms = path.components(separatedBy: ".")
                if coms.count > 1 {
                    if let tmp = coms.last {
                        if tmp.lengthOfBytes(using: .utf8) <= 4 {
                            for type in FileTypes.keys {
                                if let v = FileTypes[type] {
                                    if v.contains(tmp) {
                                        suffix = tmp
                                        file_type = type
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // version
        version = rsp_line.components(separatedBy: " ").first ?? ""
        // path
        req_path = task_id + "/" + conn_id.stringValue + ".req"
        rsp_path = task_id + "/" + conn_id.stringValue + ".rsp"
    }
    
    public func saveToDB() throws{
        preSave()
        try save()
    }
    
    static func getUserAgent(target:String?) -> String {
        if target != nil {
            let firstTarget = target!.components(separatedBy: " ").first
            return firstTarget?.components(separatedBy: "/").first ?? target!
        }
        return ""
    }
    
    public static func groupBy(task_id:String?,type:String) -> [[String:String]]{
        let db = try! ASConfigration.getDefaultDB()
        var group = [[String:String]]()
        do {
//            let startTime = CFAbsoluteTimeGetCurrent()
            let sql = "SELECT \(type), count(\(type)) as count FROM Session WHERE \(task_id == nil ? "1 = 1" : "task_id = \(task_id!)") GROUP BY \(type)"
//            let result = try db.run(sql)
            let result = try db.prepare(sql)
            for r in result {
                if let type = r[0],let count = r[1]{
                    if "\(type)" != ""{
                        group.append(["\(type)":"\(count)"])
                    }
                }
            }
//            let endTime = CFAbsoluteTimeGetCurrent()
//            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getAll error:\(error)")
            return group
        }
        return group
    }
    // keyword 模糊搜索   params 精确搜索
    public static func getSQL(taskID:String?,keyWord:String?,params:[String:[String]]?,pageSize:Int = 999999,pageIndex:Int = 0,orderBy:String?, timeInterval:Double = Date().timeIntervalSince1970, isCount:Bool = false) -> String {
        var sql = "select \(isCount ? "id" : "*") from Session where"
        // 精确匹配项
        let equals = ["task_id", "host", "schemes", "method", "suffix", "req_target", "rsp_state", "rsp_content_type"]
        // 模糊匹配项
        //        let likes = ["remoteAddress", "localAddress", "uri", "reqHeads", "rspMessage", "rspEncoding", "rspHeads"]
        // 关键词搜索项
        let searchKeys = ["dsthost_str","srchost_str","host","suffix","req_line", "req_content_type", "rsp_content_type", "req_target","rsp_state","rsp_message","rsp_line","schemes"]
        // "startTime", "uploadTraffic", "downloadFlow"
        var whereStr = ""
        if let tID = taskID, tID != ""{
            whereStr = "task_id = \(tID)"
        }
        // params
        var count = 0
        for kv in params ?? [String:[String]]() {
            var orStr = ""
            let isEqual = equals.contains(kv.key)
            for i in 0..<kv.value.count {
                let v = kv.value[i]
                if isEqual {
                    orStr = "\(orStr) lower(\(kv.key)) = '\(v.lowercased())' \(i == kv.value.count - 1 ? "" : "or")"
                }else{
                    orStr = "\(orStr) lower(\(kv.key)) like '%\(v.lowercased())%' \(i == kv.value.count - 1 ? "" : "or")"
                }
            }
            orStr = "(\(orStr))"
            count = count + 1
            if whereStr != "", count == 1{
                whereStr = " \(whereStr) and \(orStr) \(count == params?.count ? "" : "and")"
            }else{
                whereStr = "\(whereStr) \(orStr) \(count == params?.count ? "" : "and")"
            }
        }
        // keyWord
        if let key = keyWord, key != "" {
            var orStr = ""
            for i in 0..<searchKeys.count {
                let item = searchKeys[i]
                orStr = "\(orStr) lower(\(item)) like '%\(key.lowercased())%' \(i == searchKeys.count - 1 ? "" : "or")"
            }
            orStr = "(\(orStr))"
            if whereStr != ""{
                whereStr = "\(whereStr) and \(orStr)"
            }else{
                whereStr = "\(orStr)"
            }
        }
        if whereStr == "" { whereStr = "1 = 1" }
        whereStr = whereStr + " and dns_time_s < \(timeInterval)"
        // order by
        var orderByStr = ""
        if let oby = orderBy, oby != ""{
            orderByStr = "order by \(oby) desc"
        }else{
            orderByStr = "order by dns_time_s desc"
        }
        // limit offset
        let limitStr = "limit \(pageSize) offset \(pageIndex*pageSize)"
        sql = "\(sql) \(whereStr) \(orderByStr) \(limitStr)"
        return sql
    }
    
    public static func countWith(taskID:String?,keyWord:String?,params:[String:[String]]?,pageSize:Int = 999999,pageIndex:Int = 0,orderBy:String?, timeInterval:Double = Date().timeIntervalSince1970) -> [Int] {
        let sql = getSQL(taskID: taskID, keyWord: keyWord, params: params, pageSize: pageSize, pageIndex: pageIndex, orderBy: "id", timeInterval: timeInterval, isCount: true)
        //        print("sql:\(sql)")
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
    
    public static func calculate(excludeTaskId:String?) -> (i:Float,o:Float, c:Int){
        let sql = "select count(id) as connCount,sum(in_bytes) as sumInBytes,sum(out_bytes) as sumOutBytes from Session where \(excludeTaskId == nil ? "1 = 1" : "task_id != \(excludeTaskId!)")"
        let db = try! ASConfigration.getDefaultDB()
//        var results:(i:Float,o:Float, c:Int) = (0,0,0)
        var connCount:Int = 0
        var sumInBytes:Float = 0
        var sumOutBytes:Float = 0
        do {
            let result = try db.prepare(sql)
            for row in result {
                if let c = row[0] as? NSNumber {
                    connCount = c.intValue
                }
                if let i = row[1] as? NSNumber {
                    sumInBytes = i.floatValue
                }
                if let o = row[2] as? NSNumber {
                    sumOutBytes = o.floatValue
                }
                break
            }
        } catch  {
            print("calculate error:\(error)")
        }
        return (sumInBytes, sumOutBytes, connCount)
    }
    
    public static func findReqLines(task_id:String) -> [String] {
        var reqLines:[String] = []
        let sql = "select req_line from Session where task_id = '\(task_id)' order by dns_time_s desc limit 30"
        do {
            let db = try! ASConfigration.getDefaultDB()
            let result = try db.prepare(sql)
            for r in result {
                if let line = r[0]{
                    if "\(line)" != ""{
                        reqLines.append("\(line)")
                    }
                }
            }
        } catch  {
            print("findAllHost error:\(error)")
        }
        return reqLines
    }
    
    public static func findAllHost(keyWord:String = "") -> [String] {
        var hosts:[String] = []
        var sql = "select host from Session where host like '%\(keyWord)%' group by host"
        if keyWord == "" {
            sql = "select host from Session group by host"
        }
        do {
            let db = try! ASConfigration.getDefaultDB()
//            let result = try db.run(sql)
            let result = try db.prepare(sql)
            for r in result {
                if let host = r[0]{
                    if "\(host)" != ""{
                        hosts.append("\(host)")
                    }
                }
            }
//            let endTime = CFAbsoluteTimeGetCurrent()
//            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("findAllHost error:\(error)")
        }
        
        return hosts
    }
    
    public static func findAll(taskID:String?,keyWord:String?,params:[String:[String]]?,pageSize:Int = 999999,pageIndex:Int = 0,orderBy:String?, timeInterval:Double = Date().timeIntervalSince1970) -> [Session] {
        let sql = getSQL(taskID: taskID, keyWord: keyWord, params: params, pageSize: pageSize, pageIndex: pageIndex, orderBy: orderBy, timeInterval: timeInterval, isCount: false)
        print("sql:\(sql)")
        let db = try! ASConfigration.getDefaultDB()
        var sessions = [Session]()
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                let session = getWith(columnNames: columnNames, row: row)
                if session != nil {
                    sessions.append(session!)
                }
            }
            let endTime = CFAbsoluteTimeGetCurrent()
            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getAll error:\(error)")
        }
        return sessions
    }
    
    public static func findAll(ids:[Int]) -> [Session] {
        if ids.count <= 0 { return [] }
        let s = ids.map { (id) -> String in return "\(id)" }
        let sql = "select * from session where id in ( \(s.joined(separator: ",")) )"
        print("sql:\(sql)")
        let db = try! ASConfigration.getDefaultDB()
        var sessions = [Session]()
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                let session = getWith(columnNames: columnNames, row: row)
                if session != nil {
                    sessions.append(session!)
                }
            }
            let endTime = CFAbsoluteTimeGetCurrent()
            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getAll error:\(error)")
        }
        return sessions
    }
    
    static func getWith(columnNames:[String],row:Statement.Element) -> Session? {
        let session = Session()
        for i in 0..<columnNames.count {
            let columnName = columnNames[i]
            guard let value = row[i] else {
                continue
            }
            switch columnName {
            case "id":session.id =  value as? NSNumber
            case "task_id": session.task_id = value as? String ?? ""            // 任务id
            case "conn_id": session.conn_id = value as? NSNumber ?? 0            // 连接序号
            case "in_bytes": session.in_bytes = value as? NSNumber ?? 0           // 接收数据量
            case "out_bytes": session.out_bytes = value as? NSNumber ?? 0          // 发送数据量
            case "dns_time_s": session.dns_time_s = value as? NSNumber ?? 0         // DNS开始时间
            case "connect_s": session.connect_s = value as? NSNumber ?? 0          // 开始建立连接
            case "send_s": session.send_s = value as? NSNumber ?? 0             // 开始发送数据
            case "send_e": session.send_e = value as? NSNumber ?? 0             // 发送结束
            case "receive_s": session.receive_s = value as? NSNumber ?? 0          // 开始接受数据
            case "receive_e": session.receive_e = value as? NSNumber ?? 0          // 接受结束
            case "schemes": session.schemes = value as? String ?? ""            // http / https / ...
            case "srchost_str": session.srchost_str = value as? String ?? ""        // 源地址
            case "srcport_str": session.srcport_str = value as? String ?? ""        // 源端口
            case "dsthost_str": session.dsthost_str = value as? String ?? ""        // 目标地址
            case "dstport_str": session.dstport_str = value as? String ?? ""        // 目标端口
            case "method": session.method = value as? String ?? ""             // 方法
            case "uri": session.uri = value as? String ?? ""                // uri
            case "host": session.host = value as? String ?? ""               // host
            case "req_line": session.req_line = value as? String ?? ""           // 请求行
            case "req_content_type": session.req_content_type = value as? String ?? ""   // req数据类型
            case "req_encode": session.req_encode = value as? String ?? ""         // req编码
            case "req_body_size": session.req_body_size = value as? String ?? ""      // req body 大小
            case "req_target": session.req_target = value as? String ?? ""         // 标志
            case "rsp_line": session.rsp_line = value as? String ?? ""           // 响应行
            case "rsp_state": session.rsp_state = value as? String ?? ""          // 状态码
            case "rsp_message": session.rsp_message = value as? String ?? ""        // 消息
            case "rsp_content_type": session.rsp_content_type = value as? String ?? ""   // rsp类型
            case "rsp_encode": session.rsp_encode = value as? String ?? ""         // rsp编码
            case "rsp_body_size": session.rsp_body_size = value as? String ?? ""      // rsp body 大小
            case "suffix": session.suffix = value as? String ?? ""             // 后缀
            case "version": session.version = value as? String ?? ""            // 版本
            case "req_path": session.req_path = value as? String ?? ""           // req文件路径
            case "rsp_path": session.rsp_path = value as? String ?? ""           // rsp文件路径
            default:
                break
            }
        }
        return session
    }
    
    public func parse(finished: @escaping (_ reqLinePath:String?, _ reqHeadPath:String?, _ reqBodyPath:String?,_ rspLinePath:String?, _ rspHeadPath:String?, _ rspBodyPath:String?) ->()){
        // 1.req.line / 1.req.head / 1.req.body / 1.rsp.line / 1.rsp.head / 1.rsp.body
        DispatchQueue.global().async {
            let res = self.syncParse()
            DispatchQueue.main.async {
                finished(res.reqLinePath, res.reqHeadPath, res.reqBodyPath, res.rspLinePath, res.rspHeadPath, res.rspBodyPath)
            }
        }
    }
    
    public func syncParse() -> (reqLinePath:String?, reqHeadPath:String?, reqBodyPath:String?,rspLinePath:String?, rspHeadPath:String?, rspBodyPath:String?){
        let reqPath = NIOMan.LogsPath()!.appendingPathComponent(req_path).path.components(separatedBy: "file://").last ?? ""
        let rspPath = NIOMan.LogsPath()!.appendingPathComponent(rsp_path).path.components(separatedBy: "file://").last ?? ""
        
        var reqLinePath:String? = nil
        var reqHeadPath:String? = nil
        var reqBodyPath:String? = nil
        
        var rspLinePath:String? = nil
        var rspHeadPath:String? = nil
        var rspBodyPath:String? = nil

        let fileM = FileManager.default
        if fileM.fileExists(atPath: reqPath) {
            reqLinePath = reqPath + ".line"
            reqHeadPath = reqPath + ".head"
            reqBodyPath = reqPath + ".body"
            if !fileM.fileExists(atPath: reqHeadPath!) || !fileM.fileExists(atPath: reqBodyPath!) || !fileM.fileExists(atPath: reqLinePath!) {
                parse_http(strdup(reqPath))
            }
        }
        if fileM.fileExists(atPath: rspPath) {
            rspLinePath = reqPath + ".line"
            rspHeadPath = rspPath + ".head"
            rspBodyPath = rspPath + ".body"
            if !fileM.fileExists(atPath: rspHeadPath!) || !fileM.fileExists(atPath: rspBodyPath!) || !fileM.fileExists(atPath: rspLinePath!) {
                parse_http(strdup(rspPath))
            }
        }
        return (reqLinePath, reqHeadPath, reqBodyPath, rspLinePath, rspHeadPath, rspBodyPath)
    }
    
    public func fullUrl() -> String {
//        guard let u = uri, let s = schemes.lowercased(), s != "", let h = host else {
//            return ""
//        }
        if host == "" { return "" }
        if uri.first == "/" {
            return "\(schemes.lowercased())://\(host)\(uri)"
        }
        if uri.contains("://") {
            return uri
        }else{
            return "\(schemes.lowercased())://\(host)"
        }
    }
    
    public func shortUrl() -> String {
        if uri.first == "/" || uri.first == ":" {
            return uri
        }
        if uri.contains("://") {
            return uri.components(separatedBy: host).last ?? uri
        }else{
            return uri
        }
    }
    // 返回请求体路径
    public func body(_ isReq:Bool = true) -> String?{ // xxx.req.body
        if req_path == "" && isReq { return nil }
        if rsp_path == "" && !isReq { return nil }
        let bodyPath = (NIOMan.LogsPath()?.path.components(separatedBy: "file://").last ?? "") + "/" + (isReq ? req_path : rsp_path) + ".body"
        let fileM = FileManager.default
        if fileM.fileExists(atPath: bodyPath) {
            if let attributes = try? fileM.attributesOfItem(atPath: bodyPath), let fileSize = attributes[FileAttributeKey.size] as? NSNumber {
                if fileSize.intValue > 0 {
                    return bodyPath
                }
            }
        }
        return nil
    }
    
    public func bodySize(_ isReq:Bool = true) -> UInt?{ // xxx.req.body
//        if req_path == "" && isReq { return nil }
//        if rsp_path == "" && !isReq { return nil }
//        let bodyPath = (NIOMan.LogsPath()?.path.components(separatedBy: "file://").last ?? "") + "/" + (isReq ? req_path : rsp_path) + ".body"
//        let fileM = FileManager.default
//        if fileM.fileExists(atPath: bodyPath) {
//            if let attributes = try? fileM.attributesOfItem(atPath: bodyPath), let fileSize = attributes[FileAttributeKey.size] as? NSNumber {
//                if fileSize.intValue > 0 {
//                    return bodyPath
//                }
//            }
//        }
        return nil
    }

    public func head(_ isReq:Bool = true) -> [String:String]?{
        if req_path == "" && isReq { return nil }
        if rsp_path == "" && !isReq { return nil }
        let headPath = (NIOMan.LogsPath()?.path.components(separatedBy: "file://").last ?? "") + "/" + (isReq ? req_path : rsp_path) + ".head"
        let fileM = FileManager.default
        if fileM.fileExists(atPath: headPath) {
            if let fullStr = try? String(contentsOfFile: headPath) {
                let strParts = fullStr.components(separatedBy:"\r\n")
                var dic = [String:String]()
                for part in strParts {
                    let lineParts = part.components(separatedBy: ":")
                    if lineParts.count == 2 {
                        dic[lineParts[0]] = lineParts[1]
                    }
                }
                return dic
            }
        }
        return nil
    }
    
    public func line(_ isReq:Bool = true) -> String? {
        if req_path == "" && isReq { return nil }
        if rsp_path == "" && !isReq { return nil }
        let linePath = (NIOMan.LogsPath()?.path.components(separatedBy: "file://").last ?? "") + "/" + (isReq ? req_path : rsp_path) + ".line"
        let fileM = FileManager.default
        if fileM.fileExists(atPath: linePath) {
            if let fullStr = try? String(contentsOfFile: linePath) {
                return fullStr.replacingOccurrences(of: "\r\n", with: "")
            }
        }
        return nil
    }
}
