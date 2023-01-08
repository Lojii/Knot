//
//  NIOMan.swift
//  NIOMan
//
//  Created by LiuJie on 2022/3/20.
//

import Foundation
import UIKit
import ActiveSQLite
import CocoaAsyncSocket
import Reachability

public let DBDefaultName = "NIODB"
public let GROUPNAME = "group.lojii.nio.2022"
public let CURRENTTASKID = "CURRENTTASKID"
public let CURRENTRULEID = "CURRENTRULEID"

public let ConfigDidChangeAppMessage = "ConfigDidChangeAppMessage"

public class NIOMan: NSObject ,GCDAsyncUdpSocketDelegate {
    
    public var udpSocket : GCDAsyncUdpSocket?
    let reachability = try! Reachability()
    var reachabilityIsFirst = true
    
    public static let shared = NIOMan()
    
    override init() {
        super.init()
        setSender()
        setMonit()
    }
    
    func setSender(){
        if udpSocket == nil {
            udpSocket = GCDAsyncUdpSocket(delegate: nil, delegateQueue: DispatchQueue.global())
        }
    }
    
    func setMonit(){
        // 网络监控
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        do{
            try reachability.startNotifier()
        }catch{
            print("could not start reachability notifier")
        }
    }
    
    func sendInfo(data:Data) {
        udpSocket?.send(data, toHost: "127.0.0.1", port: 60001, withTimeout: -1, tag: 1)
    }
    
    // type: task
    // action: create\update
    // data:{task_id\count\in\out\time\}
    public static func sendInfo(type:String, action:String, data: [String:Any] ){
        var infoDic = [String:Any]()
        infoDic["type"] = type
        infoDic["action"] = action
        infoDic["data"] = data
        let info = infoDic.toJson()
//        print(infoDic)
        if let data = info.data(using: .utf8) {
            NIOMan.shared.sendInfo(data: data)
        }
    }
    
    @objc func reachabilityChanged(note: Notification) {
        let reachability = note.object as! Reachability
        switch reachability.connection {
        case .wifi:
            print("network wifi")
        case .cellular:
            print("network cellular")
        case .none:
            print("network none")
        default: break;
        }
        if reachabilityIsFirst {
            reachabilityIsFirst = false
            return
        }
        NIOMan.reopen()
    }
    
    public static func run(taskId: String) -> Int{
//        DatabaseInit()

        let manager = FileManager.default
        guard let certDir = NIOMan.CertPath() else {
            print("NIOMan error !")
            return 0
        }
        // 搜索cert与key,如果没有，则生成后再次尝试
        let crt = getCertAndKeyPath(certDir.path.components(separatedBy: "file://").last!)
        guard let certPath = crt.certPath,let keyPath = crt.keyPath else{
            print("no find cert ")
            return 0
        }
        if !manager.fileExists(atPath: certPath) {
            print("no cert ")
            return 0
        }
        if !manager.fileExists(atPath: keyPath) {
            print("no key ")
            return 0
        }
//        let rulePath = Bundle.main.url(forResource: "crt/rule", withExtension: "conf")
        let logsDir = NIOMan.LogsPath()
        
        var ipList:[String] = [NIOManConfig.host + ":" + NIOManConfig.port]
        if let wifiIP = NetworkInfo.LocalWifiIPv4() { ipList.append(wifiIP + ":" + NIOManConfig.port) }
        var cargs = ipList.map { strdup($0) }
        print("NIOMan run !")
        man_run(Int32(ipList.count), &cargs,
              strdup(certPath),
              strdup(keyPath),
              strdup(logsDir!.path.components(separatedBy: "file://").last),
              strdup(""),
              strdup(taskId)
        )
        print("NIOMan finised ！")
        return 1
    }
    
    public static func reopen(){
        var ipList:[String] = [NIOManConfig.host + ":" + NIOManConfig.port]
        if let wifiIP = NetworkInfo.LocalWifiIPv4() { ipList.append(wifiIP + ":" + NIOManConfig.port) }
        var cargs = ipList.map { strdup($0) }
        print("NIOMan reopen !")
        man_reopen(Int32(ipList.count), &cargs)
        // 通过UDP发送通知
        NIOMan.sendInfo(type: "IP", action: "change", data: ["iplist":ipList])
    }
    
    public static func stop(){
        man_stop()
    }
    
    // 初始化数据库，创建Task、Session表
    public static func DatabaseInit(_ defaultRuleName:String = "Default"){
        ASConfigration.setDefaultDB(path: NIOMan.DBPath(), name: DBDefaultName )
        try? Task.createTable()
        try? Session.createTable()
        try? Rule.createTable()
        Rule.setDefaultRule(defaultRuleName)
    }
    
    public static func CAGenerate(_ dirPath: String) -> Bool{
        let timeStr = Date().fullSting
        let commonName = "Knot SSL " + timeStr
        let countryCode = "US"
        let validDay = 3650
        // 会在指定文件夹下生成 ca20220326.cert.pem、ca20220326.key.pem
        let rv = cacert_generate(strdup(commonName), strdup(countryCode), Int32(validDay), strdup(dirPath))
        if rv == 0 {
            print("证书生成失败!")
            return false
        }
        return true
    }
    
    // 更新self_signed_cert，如果本地自签证书未过期，则不更新 // 2022.self.p12  123
    public static func updateSelfSignedCert(){
        // 读取证书 2022.self.p12
        if let p12Path = NIOMan.CertPath()?.appendingPathComponent("\(Date().yearSting).self.p12") {
            if FileManager.default.fileExists(atPath: p12Path.path.components(separatedBy: "file://").last!) {
//                print("p12文件已存在")
                return
            }
        }
//        print("重新创建p12文件")
        if let certDir = NIOMan.CertPath()?.path.components(separatedBy: "file://").last {
            init_self_signed_cert(strdup(certDir))
        }
    }
    
    //
    public static func DBPath() -> String{
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        let dbUrl = directory?.appendingPathComponent("nio.db").absoluteString ?? ""
        let file = dbUrl.components(separatedBy: "file://").last
        let isExits = fileManager.fileExists(atPath: file!, isDirectory:&isDir)
        if !isExits {
            fileManager.createFile(atPath: file!, contents: nil, attributes: nil)
        }
        return file!
    }


    public static func TestDBPath() -> String{
        let fileManager = FileManager.default
        let documentDirPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        var isDir : ObjCBool = false
        let isExits = fileManager.fileExists(atPath: documentDirPath, isDirectory:&isDir)
        
        if isExits && !isDir.boolValue{
            fatalError("The dir is file，can not create dir.")
        }
        if !isExits {
            try! FileManager.default.createDirectory(atPath: documentDirPath, withIntermediateDirectories: true, attributes: nil)
            print("Create db dir success-\(documentDirPath)")
        }
        let dbPath = documentDirPath + "/niox.db"
        if !FileManager.default.fileExists(atPath: dbPath) {
            FileManager.default.createFile(atPath: dbPath, contents: nil, attributes: nil)
            print("Create db file success-\(dbPath)")
        }
        return dbPath
    }

    public static func CertPath() -> URL? {
        let fileManager = FileManager.default
        var certDirectory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        certDirectory?.appendPathComponent("CA")
        let dir = certDirectory?.absoluteString.components(separatedBy: "file://").last
        let isExits = fileManager.fileExists(atPath: dir!, isDirectory:nil)
        if !isExits, certDirectory != nil {
            try? fileManager.createDirectory(at: certDirectory!, withIntermediateDirectories: false, attributes: nil)
        }
        return certDirectory
    }
    
    public static func LogsPath() -> URL? {
        let fileManager = FileManager.default
        var logsDirectory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        logsDirectory?.appendPathComponent("Logs")
        let dir = logsDirectory?.absoluteString.components(separatedBy: "file://").last
        let isExits = fileManager.fileExists(atPath: dir!, isDirectory:nil)
        if !isExits, logsDirectory != nil {
            try? fileManager.createDirectory(at: logsDirectory!, withIntermediateDirectories: false, attributes: nil)
        }
        return logsDirectory
    }
    
    
    static func getCertAndKeyPath(_ dirPath: String) -> (certPath:String?, keyPath:String?) {
        var certPath:String = ""
        var keyPath:String = ""
        var filePaths = [String]()
        do {
            let array = try FileManager.default.contentsOfDirectory(atPath: dirPath)
            for fileName in array {
                var isDir: ObjCBool = true
                let fullPath = "\(dirPath)/\(fileName)"
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    if !isDir.boolValue {
                        filePaths.append(fullPath)
                        if fileName.contains(".cert.pem") { certPath = fullPath }
                        if fileName.contains(".key.pem") { keyPath = fullPath }
                    }
                }
            }
        } catch let error as NSError {
            print("get cert path error: \(error)")
        }
        if certPath.isEmpty || keyPath.isEmpty {
            if NIOMan.CAGenerate(dirPath) {
                print("证书创建")
                return getCertAndKeyPath(dirPath)
            }else{
                return (nil, nil)
            }
        }
        return (certPath, keyPath)
    }
}

extension FileManager {
    public func fileExists(url:URL) -> Bool {
        let urlStr = url.absoluteString
        if let filePath = urlStr.components(separatedBy: "file://").last {
            return fileExists(atPath: filePath)
        }
        return false
    }
}

extension Date {
    ///获取当前时间字符串
    public var fullSting:String{
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
    
    ///获取当前时间字符串
    public var daySting:String{
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "YYYYMMdd"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
    
    ///获取当前时间字符串
    public var yearSting:String{
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "YYYY"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
}
