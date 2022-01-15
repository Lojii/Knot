//
//  Task.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/1.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import AxLogger
import NIOSSL
import MMWormhole
import CocoaAsyncSocket
import SQLite

public let TaskDidChangedNotification = NSNotification.Name("TaskDidChangedNotification")
public let TaskValueDidChanged = "TaskValueDidChanged"
public let TaskConfigDidChanged = "TaskConfigDidChanged"

public class Task: ASModel {

    //
    var numberOfUse:NSNumber = 0  //使用次数，是否使用过
    //
    public var localIP:String = "127.0.0.1" // 本机地址
    public var localPort:NSNumber = 8034//本机端口
    public var localEnable:NSNumber = 1//本机开启 0:关闭 1:开启
    public var localState:NSNumber = 0   //本机状态 0:关闭、1:开启、-1异常
    
    public var wifiIP:String = ""//网卡地址
    public var wifiPort:NSNumber = 8034//网卡端口
    public var wifiEnable:NSNumber = 1//网卡开启 0:关闭 1:开启
    public var wifiState:NSNumber = 0//网卡状态
    
    //
    public var interceptCount:NSNumber = 0 //拦截数量
    public var uploadTraffic:NSNumber = 0 //上传流量
    public var downloadFlow:NSNumber = 0 //下载流量
    // wifi
    public var wifiInterceptCount:NSNumber = 0 //wifi 拦截数量
    public var wifiUploadTraffic:NSNumber = 0 //wifi 上传流量
    public var wifiDownloadFlow:NSNumber = 0 //wifi 下载流量
    // 配置信息
    public var ruleName:String = "" // 配置名称
    public var ruleId:NSNumber?
    //
    public var sslEnable:NSNumber = 1//证书配置 0:关闭 1:开启
    public var creatTime:NSNumber?//创建时间  = Int( Date().timeIntervalSince1970 * 1000)
    public var startTime:NSNumber?//开启时间  = Int( Date().timeIntervalSince1970 * 1000)
    public var stopTime:NSNumber? //关闭时间
    
    public var note:String = "" //备注信息
    public var extra:String = "" //额外信息
    
    public var saveCount:NSNumber = 0 // 保存次数
    
    public var fileFolder:String = ""  // 保存文件的文件夹  以Task.id命名的文件夹
    
    public var rule:Rule!
    public var cacert:NIOSSLCertificate!
    public var cakey:NIOSSLPrivateKey!
    public var rsakey:NIOSSLPrivateKey!
    public var certPool:NSMutableDictionary!//[String:NIOSSLCertificate]!
    public var wormhole:MMWormhole?
    public var udpSocket : GCDAsyncUdpSocket?
    
    override public func doubleTypes() -> [String]{
        return ["startTime","stopTime","uploadTraffic","downloadFlow","wifiUploadTraffic","wifiDownloadFlow"]
    }
    
    public static func newTask() -> Task{
        let task = Task()
        // 获取或创建rule
        var rule:Rule
        if let currentRuleId = UserDefaults.standard.string(forKey: CurrentRuleId),
            let currentRule = Rule.findAll(["id":NSNumber(value: Int(currentRuleId) ?? -1)]).first {
            currentRule.configParse()
            rule = currentRule
        }else{ //
            if let lastRule = Rule.findFirst(orders: ["id": false]) {
                rule = lastRule
                UserDefaults.standard.set("\(rule.id!)", forKey: CurrentRuleId)
                UserDefaults.standard.synchronize()
            }else{ // 创建一个
                let newDefaultRule = Rule.defaultRule()
                try? newDefaultRule.saveToDB()
                NSLog("New Default Rule:%d",newDefaultRule.id ?? -1)
                if let ruleid = newDefaultRule.id {
                    UserDefaults.standard.set("\(ruleid)", forKey: CurrentRuleId)
                    UserDefaults.standard.synchronize()
                }
                rule = newDefaultRule
            }
        }
        task.rule = rule
        task.ruleName = rule.name
        task.ruleId = rule.id
        //
        task.creatTime = NSNumber(value: Date().timeIntervalSince1970)
        let creatTimeStr = task.creatTime!.stringValue.components(separatedBy: ".")
        task.fileFolder = "\(creatTimeStr.first ?? "temp")\(creatTimeStr.last ?? "")"
        task.startTime = NSNumber(value: Date().timeIntervalSince1970)
        AxLogger.log("Task FileFolder:\(task.fileFolder)", level: .Info)
        // 获取网卡地址
        let wifiIP = NetworkInfo.LocalWifiIPv4()
        if wifiIP != "" {
            task.wifiIP = wifiIP
        }
//        task.loadCACert()
//        task.addSender()
        return task
    }
    
    public static func getSQL(pageSize:Int = 999999,pageIndex:Int = 0,orderBy:String = "id") -> String {
        let sql = "select t.id,t.startTime,t.stopTime,t.ruleName,t.ruleId,count(s.id) as sessionCount,sum(s.downloadFlow) as downloadFlowSum,sum(s.uploadTraffic) as uploadTrafficSum from task t left join session s on t.id = s.taskID group by t.id order by t.\(orderBy) desc limit \(pageSize) offset \(pageSize*pageIndex)"
        return sql
    }
    
    public static func deleteAll(taskIds:[Int]) -> Bool {
        if taskIds.count <= 0 { return true }
        let s = taskIds.map { (id) -> String in return "\(id)" }
        let sql = "delete from task where id in ( \(s.joined(separator: ",")) )"
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
    
    public static func findAll(taskIds:[Int]) -> [Session] {
        if taskIds.count <= 0 { return [] }
        let s = taskIds.map { (id) -> String in return "\(id)" }
        let sql = "select * from session where taskID in ( \(s.joined(separator: ",")) )"
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
    
    public static func getAllIds() -> [Int] {
        let sql = "select id from task"
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
    
    public static func findAll(pageSize:Int = 999999,pageIndex:Int = 0,orderBy:String?) -> [Task] {
        let sql = getSQL(pageSize: pageSize, pageIndex: pageIndex, orderBy: orderBy ?? "id")
//        print("sql:\(sql)")
        let db = try! ASConfigration.getDefaultDB()
        var tasks = [Task]()
        do {
//            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                if let task = getWith(columnNames: columnNames, row: row) {
                    tasks.append(task)
                }
            }
//            let endTime = CFAbsoluteTimeGetCurrent()
//            print("查询时长：\((endTime - startTime)*1000) 毫秒" )
        } catch  {
            print("getAll error:\(error)")
        }
        return tasks
    }
    
    static func getWith(columnNames:[String],row:Statement.Element) -> Task? {
        let task = Task()
        for i in 0..<columnNames.count {
            let columnName = columnNames[i]
            guard let value = row[i] else {
                continue
            }
            switch columnName {
            case "id":task.id =  value as? NSNumber
            case "ruleName":task.ruleName =  value as? String ?? ""
            case "ruleId":task.ruleId =  value as? NSNumber ?? -1
            case "sessionCount":task.interceptCount =  value as? NSNumber ?? 0
            case "downloadFlowSum":task.downloadFlow =  value as? NSNumber ?? 0
            case "uploadTrafficSum":task.uploadTraffic =  value as? NSNumber ?? 0
            case "startTime":task.startTime =  value as? NSNumber
            case "stopTime":task.stopTime =  value as? NSNumber
            default:
                break
            }
        }
        return task
    }
    
    public func setNumbers(){
        let sql = "select count(id) as sessionCount,sum(downloadFlow) as downloadFlowSum,sum(uploadTraffic) as uploadTrafficSum from session where taskID = \(id ?? -1)"
        let db = try! ASConfigration.getDefaultDB()
        do {
            let result = try db.prepare(sql)
            let columnNames:[String] = result.columnNames
            for row in result {
                for i in 0..<columnNames.count {
                    let columnName = columnNames[i]
                    let value = row[i]
                    switch columnName {
                    case "sessionCount":interceptCount =  value as? NSNumber ?? 0
                    case "downloadFlowSum":downloadFlow =  value as? NSNumber ?? 0
                    case "uploadTrafficSum":uploadTraffic =  value as? NSNumber ?? 0
                    default:
                        break
                    }
                }
                return
            }
        } catch  {
            print("setNumbers error:\(error)")
        }
    }
    
    public static func getLast(_ parseConfig:Bool = true) -> Task?{
        let task = Task.findFirst(nil, ["id":false])
        if task == nil { return nil }
        if !parseConfig {
            task?.setNumbers()
            return task
        }
        var rule:Rule
        if let ruleid = task?.ruleId,let currentRule = Rule.findAll(["id":ruleid]).first {
            if parseConfig {
                currentRule.configParse()
            }
            rule = currentRule
        }else{ //
            if let lastRule = Rule.findFirst(orders: ["id": false]) {
                rule = lastRule
                UserDefaults.standard.set("\(rule.id!)", forKey: CurrentRuleId)
                UserDefaults.standard.synchronize()
            }else{ // 创建一个
                let newDefaultRule = Rule.defaultRule()
                try? newDefaultRule.saveToDB()
                NSLog("New Default Rule:%d",newDefaultRule.id ?? -1)
                if let ruleid = newDefaultRule.id {
                    UserDefaults.standard.set("\(ruleid)", forKey: CurrentRuleId)
                    UserDefaults.standard.synchronize()
                }
                rule = newDefaultRule
            }
        }
        task?.rule = rule
        if parseConfig {
            task?.loadCACert()
            task?.addSender()
        }
        return task
    }
    
    func loadCACert(){
        // load cert
        certPool = NSMutableDictionary()//[String:NIOSSLCertificate]() as! NSMutableDictionary
        if let certDir = MitmService.getCertPath() {
            let cacertPath = certDir.appendingPathComponent("cacert.pem", isDirectory: false)
            let cakeyPath = certDir.appendingPathComponent("cakey.pem", isDirectory: false)
            let rsakeyPath = certDir.appendingPathComponent("rsakey.pem", isDirectory: false)
            if let cert = try? NIOSSLCertificate(file: cacertPath.absoluteString.replacingOccurrences(of: "file://", with: ""), format: .pem) {
                cacert = cert
            }else{
                AxLogger.log("Load CACert Failure !", level: .Error)
            }
            if let caPriKey = try? NIOSSLPrivateKey(file: cakeyPath.absoluteString.replacingOccurrences(of: "file://", with: ""), format: .pem) {
                cakey = caPriKey
            }else{
                AxLogger.log("Load CAKey Failure !", level: .Error)
            }
            if let carsaKey = try? NIOSSLPrivateKey(file: rsakeyPath.absoluteString.replacingOccurrences(of: "file://", with: ""), format: .pem) {
                rsakey = carsaKey
            }else{
                AxLogger.log("Load RSAKey Failure !", level: .Error)
            }
        }
    }
    
    func addSender(){
        if udpSocket == nil {
            udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.global())
        }
        if wormhole == nil {
            wormhole = MMWormhole.init(applicationGroupIdentifier: GROUPNAME, optionalDirectory: "wormhole")
            wormhole?.listenForMessage(withIdentifier: TaskConfigDidChanged, listener: { [weak self](jsonStr) in
                if let json = jsonStr as? String {
                    let dic = [String:String].fromJson(json)
                    if let wifi = dic["wifiEnable"],let value = Int(wifi) {
                        self?.wifiEnable = NSNumber(integerLiteral: value)
                    }
                    if let local = dic["localEnable"],let value = Int(local) {
                        self?.localEnable = NSNumber(integerLiteral: value)
                    }
                    try? self?.update()
                    AxLogger.log("TaskConfigDidChanged:\(json)", level: .Info)
                }
            })
        }
    }
    
    func sendInfo(data:Data) {
        udpSocket?.send(data, toHost: "127.0.0.1", port: 60001, withTimeout: -1, tag: 1)
    }

    func sendInfo(url:String,uploadTraffic:NSNumber,downloadFlow:NSNumber) {
        var infoDic = [String:String]()
        infoDic["url"] = url
        infoDic["uploadTraffic"] = "\(uploadTraffic)"
        infoDic["downloadFlow"] = "\(downloadFlow)"
        let info = infoDic.toJson()
        if let data = info.data(using: .utf8) {
            sendInfo(data: data)
        }
    }
    
    func getFullPath() -> String {
        var filePath = MitmService.getStoreFolder()
        filePath.append("\(fileFolder)")
        return filePath
    }
    
    func createFileFolder(){
        let filePath = getFullPath()
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        let isExits = fileManager.fileExists(atPath: filePath, isDirectory: &isDir)
        if isExits, isDir.boolValue {
            let errorStr = "Delete \(fileFolder)，Because it's not a folder !"
            NSLog(errorStr)
            try? fileManager.removeItem(atPath: filePath)
            try? fileManager.createDirectory(atPath: filePath, withIntermediateDirectories: true, attributes: nil)
        }
        if !isExits {
            try? fileManager.createDirectory(atPath: filePath, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
}

extension Task: GCDAsyncUdpSocketDelegate{
    
}
