//
//  Session.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/24.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOHTTP1
import NIOFoundationCompat
import SQLite

enum FileType {
    case REQ
    case RSP
}

public let ImageTypes = ["png","jpeg","jpg","x-icon","gif","webp","jp2","tiff","tif","bmp","ico","icns"]
public let CompressTypes = ["gzip","br"]
public let JSTypes = ["javascript","x-javascript"]
public let CSSTypes = ["css"]
public let urlEncodedTypes = ["x-www-form-urlencoded"]

public class Session: ASModel {
                                        // https http
    public var taskID:NSNumber?         // *
    public var remoteAddress:String?    // 87.234.12.6
    public var localAddress:String?     // 127.0.0.1:8734 \ 192.168.1.43:8735  **
    public var host:String?             // xxx.xxx **
    public var schemes:String?          // Http\Https **
    // req head
    public var reqLine:String?          // 原始请求行
    public var methods:String?          // get\post...
    public var uri:String?              // /xxx/xx.xx?x=x&xxx=x
    public var suffix:String = ""       // 后缀
    
    public var reqHttpVersion:String?   // Http/1.1
    public var reqType:String = ""      // .gif\.js\.css * Content-Type
    public var reqEncoding:String = ""  // gzip x-gzip compress deflate identity br ...  Content-Encoding
    public var reqHeads:String?         // [{"key":"value"},{"key2":"value2"},...]
    public var reqBody:String = ""
    public var reqDisposition:String = ""
    public var target:String?           // Safari\qq
    // rsp head
    public var rspHttpVersion:String?   // Http/1.1 *
    public var state:String?            // 200\404\430 *
    public var rspMessage:String?       // ok   *
    public var rspType:String = ""      // .gif\.js\.css * Content-Type
    public var rspEncoding:String = ""  // gzip br ...  Content-Encoding
    public var rspDisposition:String = ""       // Content-Disposition
    public var rspHeads:String?         // [{"key":"value"},{"key2":"value2"},...] *
    public var rspBody:String = ""
    // session time
    public var startTime:NSNumber?      // 开始时间 *
    public var connectTime:NSNumber?    // 开始建立连接时间 *
    public var connectedTime:NSNumber?  // 连接建立成功时间 *
    public var handshakeEndTime:NSNumber? // 握手结束时间 *
    public var reqEndTime:NSNumber?     // 请求发送完毕时间 *
    public var rspStartTime:NSNumber?   // 开始接收响应时间 *
    public var rspEndTime:NSNumber?     // 接收完毕时间 *
    public var endTime:NSNumber?        // 最终结束时间 *
    // data
    public var uploadTraffic:NSNumber = 0  // 上传流量
    public var downloadFlow:NSNumber = 0   // 下载流量
    // state
    public var sstate:String?           // failure  success
    // note
    public var note:String?
    // count
    public var saveCount:NSNumber = 0 // 保存次数
    // close
    public var inState:String?  // open -> close
    public var outState:String?  // open -> close
    // 忽略即不保存
    public var ignore:Bool = false
    
//    public var master:NIOTSEventLoopGroup?
//    public var worker:NIOTSEventLoopGroup?
    
    public var reqBodyFD:FileHandle?
    public var rspBodyFD:FileHandle?
    
    public var fileName:String = ""
    public var fileFolder:String?
    
    public func getFullUrl() -> String {
        guard let u = uri, let s = schemes?.lowercased(), s != "", let h = host else {
            return ""
        }
        if u.first == "/" {
            return "\(s)://\(h)\(u)"
        }
        if u.contains("://") {
            return u
        }else{
            return "\(s)://\(u)"
        }
    }
    
    public func getRemoteIPAddress() -> String{
        if let ipAddress = remoteAddress {
            var count = 0
            for c in ipAddress {
                if c == ":" { count = count + 1 }
            }
            if count > 2 {  // ipv6
                let parts = ipAddress.components(separatedBy: "]:") // [CDCD:910A:2222:5498:8475:1111:3900:2020]:80
                if parts.count > 1 {
                    if let ipv6 = parts[0].components(separatedBy: "[").first {
                        return ipv6
                    }
                }
            }else{
                return ipAddress.components(separatedBy: ":").first ?? ""
            }
        }
        return ""
    }
    
    public var reqBodyFullPath:String {
        return "\(MitmService.getStoreFolder())\(fileFolder ?? "error")/\(rspBody)"
    }
    
    public func getBodyFullPath(_ isReq:Bool = false) -> String{
        return "\(MitmService.getStoreFolder())\(fileFolder ?? "error")/\(isReq ? reqBody :rspBody)"
    }
    
    public func hasBodyFile(_ isReq:Bool = false) -> Bool{
        let filePath = getBodyFullPath(isReq)
        let fn = FileManager.default
        return fn.fileExists(atPath: filePath)
    }
    
    public func getBodyData(_ isReq:Bool = false) -> Data?{
        if !hasBodyFile(isReq) { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: getBodyFullPath(isReq)))
    }
    
    public func getDecodedBody(_ isReq:Bool = false) -> Data?{
        guard let originalData = getBodyData(isReq) else { return nil }
        let encoding = isReq ? reqEncoding : rspEncoding
        if encoding.lowercased().contains("gzip") || encoding.lowercased().contains("deflate") || originalData.isGzipped {
            if let unzipData = try? originalData.gunzipped() {
                return unzipData
            }else{
                return originalData.unzip() ?? originalData
            }
        }
        return originalData
    }
    
    public func getBodySize(_ isReq:Bool = false) -> UInt64 {
        if !hasBodyFile(isReq) { return 0 }
        return Session.getSize(url: URL(fileURLWithPath: getBodyFullPath(isReq)))
    }
    
    public static func getSize(url: URL)->UInt64{
        var fileSize : UInt64 = 0
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = attr[FileAttributeKey.size] as! UInt64
            let dict = attr as NSDictionary
            fileSize = dict.fileSize()
        } catch {
            print("Error: \(error)")
            return 0
        }
        return fileSize
    }
    
    override public func doubleTypes() -> [String]{
        return ["startTime","connectTime","connectedTime","handshakeEndTime","reqEndTime","rspStartTime","rspEndTime","endTime","uploadTraffic","downloadFlow"]
    }
    
    
    
    // func
    public static func newSession(_ task:Task) -> Session {
        let  session = Session()
        session.taskID = task.id
        session.startTime = NSNumber(value: Date().timeIntervalSince1970)
        session.fileFolder = task.fileFolder
        return session
    }
    
    func writeBody(type:FileType,buffer:ByteBuffer?, realName:String = ""){
        if id == nil || fileFolder == nil { return }
        
//        if type == .RSP { return }
        
        if reqBody == "", type == .REQ {
            reqBody = "req_\(id!.stringValue)\(realName)"
        }
        if rspBody == "", type == .RSP {
            rspBody = "rsp_\(id!.stringValue)\(realName)"
        }
        guard let body = buffer else {
            return
        }
        
        var filePath = type == .REQ ? reqBody : rspBody
        filePath = "\(MitmService.getStoreFolder())\(fileFolder ?? "error")/\(filePath)"
        let fileManager = FileManager.default
        let exist = fileManager.fileExists(atPath: filePath)
        if !exist {
            fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
        }
        
        guard let data = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            print("no data !")
            return
        }
//        do {
//            try data.append(fileURL: URL(fileURLWithPath: filePath))
//        } catch  {
//            print("文件:\(filePath)写入出错：\(error)")
//        }
        
        let fileHandle = FileHandle(forWritingAtPath: filePath)
        if exist {
            fileHandle?.seekToEndOfFile()
        }
        fileHandle?.write(data)
        fileHandle?.closeFile()
    }
    
    func createBodyFiles() -> Bool{
        return createFiles(filePath: reqBody) && createFiles(filePath: rspBody)
    }
    
    private func createFiles(filePath:String) -> Bool{
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        let isExits = fileManager.fileExists(atPath: filePath, isDirectory: &isDir)
        if !isExits {
            return fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
        }else{
            return true
        }
    }
    
    static func getIPAddress(socketAddress: SocketAddress?) -> String {
        if let address = socketAddress?.description {
            let array = address.components(separatedBy: "/")
            return array.last ?? address
        }else{
            return "unknow"
        }
    }
    
    static func getUserAgent(target:String?) -> String {
        if target != nil {
            let firstTarget = target!.components(separatedBy: " ").first
            return firstTarget?.components(separatedBy: "/").first ?? target!
        }
        return ""
    }
    
    static func getHeadsJson(headers: HTTPHeaders) -> String {
        var reqHeads = [String:String]()
        for kv in headers {
            reqHeads[kv.name] = kv.value
        }
        return reqHeads.toJson()
    }
    
    public func saveToDB() throws{
        if ignore { return }
        saveCount = NSNumber(value: saveCount.intValue + 1)
        try save()
    }
    
    public static func groupBy(taskID:NSNumber?,type:String) -> [[String:String]]{
        let db = try! ASConfigration.getDefaultDB()
        var group = [[String:String]]()
        do {
//            let startTime = CFAbsoluteTimeGetCurrent()
            let sql = "SELECT \(type), count(\(type)) as count FROM Session WHERE \(taskID == nil ? "1 = 1" : "taskID = \(taskID!)") GROUP BY \(type)"
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
    
    public static func getSQL(taskID:String?,keyWord:String?,params:[String:[String]]?,pageSize:Int = 999999,pageIndex:Int = 0,orderBy:String?, timeInterval:Double = Date().timeIntervalSince1970, isCount:Bool = false) -> String {
        var sql = "select \(isCount ? "id" : "*") from Session where"
        // 精确匹配项
        let equals = ["taskID", "host", "schemes", "methods", "suffix", "reqHttpVersion", "target", "state", "rspType"]
        // 模糊匹配项
        //        let likes = ["remoteAddress", "localAddress", "uri", "reqHeads", "rspMessage", "rspEncoding", "rspHeads"]
        // 关键词搜索项
        let searchKeys = ["remoteAddress","localAddress","host","schemes","reqLine",
                          "reqHeads","target","state","rspMessage","rspHeads"]
        // "startTime", "uploadTraffic", "downloadFlow"
        var whereStr = ""
        if let tID = taskID, tID != ""{
            whereStr = "taskID = \(tID)"
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
        whereStr = whereStr + " and startTime < \(timeInterval)"
        // order by
        var orderByStr = ""
        if let oby = orderBy, oby != ""{
            orderByStr = "order by \(oby) desc"
        }else{
            orderByStr = "order by startTime desc"
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
    
    public static func findAll(taskID:String?,keyWord:String?,params:[String:[String]]?,pageSize:Int = 999999,pageIndex:Int = 0,orderBy:String?, timeInterval:Double = Date().timeIntervalSince1970) -> [Session] {
        let sql = getSQL(taskID: taskID, keyWord: keyWord, params: params, pageSize: pageSize, pageIndex: pageIndex, orderBy: orderBy, timeInterval: timeInterval, isCount: false)
//        print("sql:\(sql)")
        let db = try! ASConfigration.getDefaultDB()
        var sessions = [Session]()
        do {
//            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                let session = getWith(columnNames: columnNames, row: row)
                if session != nil {
                    sessions.append(session!)
                }
            }
//            let endTime = CFAbsoluteTimeGetCurrent()
//            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
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
            case "taskID":session.taskID =  value as? NSNumber
            case "remoteAddress":session.remoteAddress =  value as? String
            case "localAddress":session.localAddress =  value as? String
            case "host":session.host =  value as? String
            case "schemes":session.schemes =  value as? String
            case "reqLine":session.reqLine =  value as? String
            case "methods":session.methods =  value as? String
            case "uri":session.uri =  value as? String
            case "suffix":session.suffix =  value as? String ?? ""
            case "reqHttpVersion":session.reqHttpVersion =  value as? String
            case "reqType":session.reqType =  value as? String ?? ""
            case "reqEncoding":session.reqEncoding =  value as? String ?? ""
            case "reqHeads":session.reqHeads =  value as? String
            case "reqBody":session.reqBody =  value as? String ?? ""
            case "reqDisposition":session.reqDisposition =  value as? String ?? ""
            case "target":session.target =  value as? String
            case "rspHttpVersion":session.rspHttpVersion =  value as? String
            case "state":session.state =  value as? String
            case "rspMessage":session.rspMessage =  value as? String
            case "rspType":session.rspType =  value as? String ?? ""
            case "rspEncoding":session.rspEncoding =  value as? String ?? ""
            case "rspDisposition":session.rspDisposition =  value as? String ?? ""
            case "rspHeads":session.rspHeads =  value as? String
            case "rspBody":session.rspBody =  value as? String ?? ""
            case "startTime":session.startTime =  value as? NSNumber
            case "connectTime":session.connectTime =  value as? NSNumber
            case "connectedTime":session.connectedTime =  value as? NSNumber
            case "handshakeEndTime":session.handshakeEndTime =  value as? NSNumber
            case "reqEndTime":session.reqEndTime =  value as? NSNumber
            case "rspStartTime":session.rspStartTime =  value as? NSNumber
            case "rspEndTime":session.rspEndTime =  value as? NSNumber
            case "endTime":session.endTime =  value as? NSNumber
            case "uploadTraffic":session.uploadTraffic =  value as? NSNumber ?? 0
            case "downloadFlow":session.downloadFlow =  value as? NSNumber ?? 0
            case "sstate":session.sstate =  value as? String
            case "note":session.note =  value as? String
            case "saveCount":session.saveCount =  value as? NSNumber ?? 0
            case "inState":session.inState =  value as? String
            case "outState":session.outState =  value as? String
            case "fileName":session.fileName =  value as? String ?? ""
            case "fileFolder":session.fileFolder =  value as? String
            default:
                break
            }
        }
        return session
    }
}
