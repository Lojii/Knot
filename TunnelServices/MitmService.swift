//
//  MitmService.swift
//  SwiftNIO
//
//  Created by Lojii on 2018/8/15.
//  Copyright © 2018年 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOHTTP1
import AxLogger


public let StartInExtension = true
public let GROUPNAME = "group.Lojii.NIO1901"
public let CurrentRuleId = "CurrentRuleId"

/// 定义一个结构体类型的错误类型
public struct ServerChannelError: Error {
    var errCode: Int = 0
    /// 实现Error协议的localizedDescription只读实例属性
    var localizedDescription: String = ""
    init(errCode:Int,localizedDescription:String) {
        self.errCode = errCode
        self.localizedDescription = localizedDescription
    }
}

public class MitmService: NSObject {
    
    
    public static var storeFolder = ""
    var wifiIsOpen = false
    
    enum ServerState {
        case none       // 初始状态
        case running    // 已启动
        case closed     // 已关闭
        case failure    // 失败
    }

    var task:Task!
    let master = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let worker = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount*3)
    
    var localBootstrap:ServerBootstrap!
    var localChannel:Channel!
    var localBindIP = ""
    var localBindPort = -1
    var localStarted = ServerState.none
    
    var wifiBootstrap:ServerBootstrap!
    var wifiChannel:Channel!
    var wifiBindIP = ""
    var wifiBindPort = -1
    var wifiStarted = ServerState.none
    // 是否启用局域网监听
    var enableWifiServer = true
    var enableLocalServer = true
    
    var compelete:((Result<Int, Error>) -> Void)?
    var closed:(() -> Void)?
    
    public init(task:Task) {
        super.init()
        
        self.task = task
        
        let protocolDetector = ProtocolDetector(task: task ,matchers: [HttpMatcher(),HttpsMatcher(),SSLMatcher()])
        
        localBootstrap = ServerBootstrap(group: master, childGroup: worker)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(protocolDetector, name: "ProtocolDetector", position: .first)
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: false)
            .childChannelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(10))
        //
        wifiBootstrap = ServerBootstrap(group: master, childGroup: worker)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(protocolDetector, name: "ProtocolDetector", position: .first)
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: false)
            .childChannelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(10))
    }
    
    public static func prepare() -> MitmService? {
        // 数据库设置
        ASConfigration.setDefaultDB(path: MitmService.getDBPath(), name: "Session")
        ASConfigration.logLevel = .error
        // 日志记录
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        if let tunnelDir = directory?.appendingPathComponent("Tunnel") {
            AxLogger.openLogging(tunnelDir, date: Date(),debug: true)
        }
        // 启动
        // 判断是否有最新的，如果有，则通过，如果没有，则新建一个task
        /*
         1、读取配置Rule
            1.1、通过CurrentRuleId获取数据库中的Rule
                存在：直接使用
                不存在：使用最新的Rule
                    存在：直接使用
                    不存在：创建一个默认的Rule，保存到数据库、设置CurrentRuleId、并使用
         2、使用配置，获取一个任务Task
            2.1、读取数据库中最新的Task
            2.2、判断该Task是否已经使用
                否：直接使用
                是：创建一个新的Task、保存到数据库、并使用
            2.3、设置Task的Rule
         3、使用Task启动服务
         */
        // 获取Rule
        
        // 获取Task
        let task:Task
        if let lastTask = Task.getLast(), lastTask.numberOfUse <= 0 { // 最新的未使用过的Task
            task = lastTask
            task.addSender()
            task.loadCACert()
            AxLogger.log("********* 使用的是最新的未使用过的！", level: .Info)
        }else{
            task = Task.newTask()
            try? task.save()
            task.addSender()
            task.loadCACert()
            AxLogger.log("********* 新建一个Task保存！", level: .Info)
        }
        let server = MitmService(task: task)
        return server
    }
    
    public func restart() -> MitmService? {
        NSLog("重启服务！")
        closeLocalServer()
        closeWifiServer()
        try? master.syncShutdownGracefully()
        try? worker.syncShutdownGracefully()
        
        task.wifiIP = NetworkInfo.LocalWifiIPv4()
        task.wifiEnable = 1
        let newServer = MitmService(task: task)
        return newServer
    }
    
    public func run(_ callback: @escaping ((Result<Int, Error>) -> Void)) -> Void {
        compelete = callback
        task.startTime = NSNumber(value: Date().timeIntervalSince1970)
        task.createFileFolder()
        task.numberOfUse = NSNumber(value: task.numberOfUse.intValue + 1)
        
        try? task.update()
        
        if task.localEnable == 1 {
            DispatchQueue.global().async {
                self.openLocalServer(ip: self.task.localIP, port: Int(truncating: self.task.localPort), { (r) in
                    self.runcallback()
                })
            }
        }
        if task.wifiIP != "" {
            wifiIsOpen = true
        }
        if task.wifiEnable == 1, task.wifiIP != "" {
            DispatchQueue.global().async {
                self.openWifiServer(ip: self.task.wifiIP, port: Int(truncating: self.task.wifiPort), { (r) in
                    self.runcallback()
                })
            }
        }
        
    }
    
    public func openWifiServer(ip: String, port: Int,_ callback: ((Result<Int, Error>) -> Void)?){
        enableWifiServer = true
        
        wifiChannel = try? wifiBootstrap.bind(host: ip, port: port).wait()
        if wifiChannel == nil {
            let errorStr = "Wifi Address was unable to bind.\(ip):\(port)"
            AxLogger.log(errorStr, level: .Error)
            wifiStarted = .failure
            task.wifiState = -1
            try? task.update()
//            callback?(.failure(ServerChannelError(errCode: -1, localizedDescription: errorStr)))
            return
        }
        guard let localAddress = wifiChannel.localAddress else {
            let errorStr = "Wifi Address was unable to bind. Please check that the socket was not closed or that the address family was understood."
            AxLogger.log(errorStr, level: .Error)
            wifiStarted = .failure
            task.wifiState = -1
            try? task.update()
//            callback?(.failure(ServerChannelError(errCode: -1, localizedDescription: errorStr)))
            return
        }
        
        let infoStr = "Wifi Server started and listening on \(localAddress)"
        AxLogger.log(infoStr, level: .Info)
        wifiStarted = .running
        task.wifiState = 1
        try? task.update()
//        callback?(.success(0))
        try? wifiChannel.closeFuture.wait()
        AxLogger.log("Wifi Server closed", level: .Info)
        wifiStarted = .closed
        task.wifiState = 0
        try? task.update()
    }
    
    public func openLocalServer(ip: String, port: Int,_ callback: ((Result<Int, Error>) -> Void)?){
        enableLocalServer = true
        localChannel = try? localBootstrap.bind(host: ip, port: port).wait()
        if localChannel == nil {
            let errorStr = "Local Address was unable to bind.\(ip):\(port)"
            AxLogger.log(errorStr, level: .Error)
            localStarted = .failure
            task.localState = -1
            task.note = task.note + errorStr
            try? task.update()
            callback?(.failure(ServerChannelError(errCode: -1, localizedDescription: errorStr)))
            return
        }
        guard let localAddress = localChannel.localAddress else {
            let errorStr = "Local Address was unable to bind. Please check that the socket was not closed or that the address family was understood."
            AxLogger.log(errorStr, level: .Error)
            localStarted = .failure
            task.localState = -1
            task.note = task.note + errorStr
            try? task.update()
            callback?(.failure(ServerChannelError(errCode: -1, localizedDescription: errorStr)))
            return
        }
        AxLogger.log("Local Server started and listening on \(localAddress)", level: .Info)
        localStarted = .running
        task.localState = 1
        try? task.update()
        callback?(.success(0))
        try? localChannel.closeFuture.wait()
        AxLogger.log("Local Server closed", level: .Info)
        localStarted = .closed
        task.localState = 0
        try? task.update()
    }
    
    func runcallback(){
        guard let callback = compelete else {
            return
        }
        if localStarted == .running {
            NSLog("***************** runcallback success:wifiStarted:\(wifiStarted)-localStarted:\(localStarted) !")
            callback(.success(0))
        }else{
            if localStarted != .none {
                NSLog("***************** runcallback failure:wifiStarted:\(wifiStarted)-localStarted:\(localStarted) !")
                callback(.failure(ServerChannelError(errCode: 1, localizedDescription: "Local Failure")))
            }
        }
        
//        if wifiStarted != .none , localStarted != .none {
//            // done
//            if wifiStarted == .failure || localStarted == .failure {
//                if wifiStarted == .failure && localStarted == .failure {
//                    callback(.failure(ServerChannelError(errCode: 2, localizedDescription: "All Failure")))
//                }else if wifiStarted == .failure && localStarted != .failure {
//                    callback(.failure(ServerChannelError(errCode: 1, localizedDescription: "Wifi Failure")))
//                }else{
//                    callback(.failure(ServerChannelError(errCode: 1, localizedDescription: "Local Failure")))
//                }
//            }else{
//                NSLog("***************** runcallback:wifiStarted\(wifiStarted)-localStarted\(localStarted) !")
//                callback(.success(0))
//            }
//        }
    }
    
    public func wifiNetWorkChanged(isOpen:Bool){  // 以后用
        if isOpen {
            if wifiIsOpen { return }
            if wifiChannel != nil {
                wifiChannel.close(mode: .all, promise: nil)
                wifiChannel = nil
            }
            let wifiIP = NetworkInfo.LocalWifiIPv4()
            if wifiIP == "" { return }
            task.wifiIP = wifiIP
            task.wifiEnable = 1
            // 重新启动wifiServer
            DispatchQueue.global().async {
                self.openWifiServer(ip: wifiIP, port: Int(truncating: self.task?.wifiPort ?? 8034)) { (r) in
                    try? self.task.update()
                    // TODO:发送更新信息
                    NSLog("网络切换，重新启动成功")
                }
            }
            
        }else{
            // 关闭wifiServer
            closeWifiServer()
            wifiChannel = nil
            task.wifiIP = ""
            task.wifiEnable = 0
            try? task.update()
            // TODO:发送更新信息
            NSLog("网络切换，关闭成功")
        }
    }
    
    public func close(_ completionHandler: (() -> Void)?) -> Void {
        closed = completionHandler
        task.stopTime = NSNumber(value: Date().timeIntervalSince1970)
        
        var infoDic = [String:String]()
        infoDic["state"] = "close"
        let info = infoDic.toJson()
        if let data = info.data(using: .utf8) {
            task?.sendInfo(data: data)
        }
        
        try? task.update()
        
        if let callback = completionHandler {
            callback()
        }
        
        closeLocalServer()
        closeWifiServer()
        
        master.shutdownGracefully { (error) in
            if let e = error {
                AxLogger.log("master thread of eventloop close error:\(e.localizedDescription)", level: .Error)
            }
        }
        worker.shutdownGracefully { (error) in
            if let e = error {
                AxLogger.log("worker thread of eventloop close error:\(e.localizedDescription)", level: .Error)
            }
        }
    }
    
    public func closeWifiServer(){
        if wifiChannel == nil {
            return
        }
        wifiChannel.close(mode: .input).whenComplete { (r) in
            self.enableWifiServer = false
            self.wifiStarted = .closed
            switch r{
            case .success:
                self.wifiChannel = nil
                break
            case .failure(_):
                break
            }
        }
    }
    
    public func closeLocalServer(){
        if localChannel == nil {
            return
        }
        localChannel.close(mode: .input).whenComplete { (r) in
            self.enableLocalServer = false
            self.localStarted = .closed
            switch r{
            case .success:
                self.localChannel = nil
                break
            case .failure(_):
                break
            }
        }
    }
    
    public static func getStoreFolder() -> String {
        if storeFolder != "" {
            return storeFolder
        }
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME) else {
            return ""
        }
        let storeURL = groupURL.appendingPathComponent("Task")
        var isDir : ObjCBool = false
        let isExits = fileManager.fileExists(atPath: storeURL.absoluteString, isDirectory: &isDir)
        if isExits {
            if isDir.boolValue {
                return storeURL.absoluteString
            }else{
                try? fileManager.removeItem(at: storeURL)
            }
        }
        try? fileManager.createDirectory(at: storeURL, withIntermediateDirectories: true, attributes: nil)
        let fullPath = storeURL.absoluteString
        
        storeFolder = fullPath.replacingOccurrences(of: "file://", with: "")
        //fullPath.components(separatedBy: "file://").last ?? ""
        if storeFolder.last != "/"{
            storeFolder = "\(storeFolder)/"
        }
        print("storeFolder:\(storeFolder)")
        AxLogger.log("Store Folder:\(storeFolder)", level: .Info)
        return storeFolder
    }
    
    public static func getCertPath() -> URL? {
        let fileManager = FileManager.default
        var certDirectory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        certDirectory?.appendPathComponent("Cert")
        let dir = certDirectory?.absoluteString.components(separatedBy: "file://").last
        let isExits = fileManager.fileExists(atPath: dir!, isDirectory:nil)
        if !isExits, certDirectory != nil {
            try? fileManager.createDirectory(at: certDirectory!, withIntermediateDirectories: false, attributes: nil)
        }
        AxLogger.log("Cert Directory path:\(certDirectory?.absoluteString ?? "null")", level: .Info)
        return certDirectory
    }
    
    public static func getDBPath() -> String{
        
//        return getTestDBPath()
        
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        let dbUrl = directory?.appendingPathComponent("nio.db").absoluteString ?? ""
        //directory?.appendingPathExtension("nio.db").absoluteString ?? ""
        //"\(directory?.absoluteString ?? "")nio.db"
        let file = dbUrl.components(separatedBy: "file://").last
        let isExits = fileManager.fileExists(atPath: file!, isDirectory:&isDir)
        if !isExits {
            fileManager.createFile(atPath: file!, contents: nil, attributes: nil)
        }
        AxLogger.log("DB file path:\(file ?? "null")", level: .Info)
        return file!
    }
    
    public static func getTestDBPath() -> String{
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
    
}
