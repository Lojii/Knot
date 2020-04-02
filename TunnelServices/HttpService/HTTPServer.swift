//
//  HTTPServer.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/6/19.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOHTTP1
import Reachability

fileprivate let isDebug = false
public let LocalHTTPServerChanged: NSNotification.Name = NSNotification.Name(rawValue: "LocalHTTPServerChanged")

public class LocalHTTPServer {
    
    let reachability = try! Reachability()
    
    public static let httpRootPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)?.appendingPathComponent("Root")
    
    let defaultHost = "::1"
    let defaultPort = 80
    let htdocs: String = LocalHTTPServer.httpRootPath?.absoluteString.components(separatedBy: "file://").last ?? ""
    
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    var threadPool:NIOThreadPool?
    
    var channel:Channel?
    var wifiChannel:Channel?
    
    public init() {
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        
    }
    
    @objc func reachabilityChanged(note: Notification) {
        let reachability = note.object as! Reachability
        switch reachability.connection {
        case .wifi:
            runWifiAgain()
        case .cellular,.none:
            closeWifi()
        default:
            break;
        }
    }
    
    deinit {
        if isDebug { print("LocalHTTPServer Deinit !") }
        reachability.stopNotifier()
        NotificationCenter.default.removeObserver(self, name: .reachabilityChanged, object: reachability)
    }
    
    func newBootstrap() -> ServerBootstrap {
        let fileIO = NonBlockingFileIO(threadPool: threadPool!)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPServerHandler(fileIO: fileIO, htdocsPath: self.htdocs))
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        return bootstrap
    }
    
    func runWifi(){
        let bootstrap = newBootstrap()
        
        let wifiIP = NetworkInfo.LocalWifiIPv4()
        if wifiIP != "" {
            DispatchQueue.global().async {
                do {
                    self.wifiChannel = try bootstrap.bind(host: wifiIP, port: self.defaultPort).wait()
                    guard let localAddress = self.wifiChannel?.localAddress else {
                        fatalError("HTTPServer(Wifi):Address was unable to bind:\(wifiIP):\(self.defaultPort)")
                    }
                    self.wifiChannel?.closeFuture.whenComplete({ (r) in
                        if isDebug { print("HTTPServer(Wifi):Server Channel Closed !") }
                        DispatchQueue.main.async { NotificationCenter.default.post(name: LocalHTTPServerChanged, object: ["wifi":false])}
                    })
                    if isDebug { print("HTTPServer(Wifi):Server started and listening on \(localAddress)") }
                    DispatchQueue.main.async { NotificationCenter.default.post(name: LocalHTTPServerChanged, object: ["wifi":true]) }
                    try self.wifiChannel?.closeFuture.wait()
                } catch  {
                    if isDebug { print("HTTPServer(Wifi):Server started failure:\(error.localizedDescription)") }
                }
                if isDebug { print("HTTPServer(Wifi):Server closed") }
            }
        }
    }
    
    func runLocal(){
        let bootstrap =  newBootstrap()
        DispatchQueue.global().async {
            do {
                self.channel = try bootstrap.bind(host: self.defaultHost, port: self.defaultPort).wait()
                guard let localAddress = self.channel?.localAddress else {
                    fatalError("HTTPServer(Local):Address was unable to bind:\(self.defaultHost):\(self.defaultPort)")
                }
                self.channel?.closeFuture.whenComplete({ (r) in
                    if isDebug { print("HTTPServer(Local):Server Channel Closed !") }
                    DispatchQueue.main.async { NotificationCenter.default.post(name: LocalHTTPServerChanged, object: ["local":false])}
                })
                if isDebug { print("HTTPServer(Local):Server started and listening on \(localAddress)") }
                DispatchQueue.main.async { NotificationCenter.default.post(name: LocalHTTPServerChanged, object: ["local":true]) }
                try self.channel?.closeFuture.wait()
            } catch  {
                if isDebug { print("HTTPServer(Local):Server started failure:\(error.localizedDescription)") }
            }
            if isDebug { print("HTTPServer(Local):Server closed") }
        }
    }
    
    public func run(){
        // TODO:监听网络变化
        threadPool = NIOThreadPool(numberOfThreads: 6)
        threadPool?.start()
        if threadPool == nil {
            if isDebug { print("LocalHTTPServer run failured !") }
            return
        }
        if isDebug { print("LocalHTTPServer root :\(htdocs)") }
        do{
            try reachability.startNotifier()
        }catch{
            print("could not start reachability notifier")
        }
        
        runLocal()
    }
    
    func closeWifi(){
        if wifiChannel != nil {
            try? wifiChannel?.close().wait()
            wifiChannel = nil
        }
    }
    
    func runWifiAgain(){
        closeWifi()
        runWifi()
    }
    
    public func close(){
        channel?.close(mode: .all, promise: nil)
        wifiChannel?.close(mode: .all, promise: nil)
        do {
            try group.syncShutdownGracefully()
            try threadPool?.syncShutdownGracefully()
        } catch {
            if isDebug { print("Resources release failure !\(error.localizedDescription)") }
        }
    }
}
