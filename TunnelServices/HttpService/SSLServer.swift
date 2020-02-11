//
//  SSLServer.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/6/22.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOSSL

import NIOTLS
import NIOConcurrencyHelpers

fileprivate let isDebug = false
fileprivate let SSLHost = "www.localhost.com"

private final class EchoHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.write(data, promise: nil)
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
}

public class LocalSSLServer {
    
    var host: String
    var port: Int
    
    var group:MultiThreadedEventLoopGroup?
    var channel:Channel?
    
    var sslContext:NIOSSLContext!
    public var cacert:NIOSSLCertificate!
    public var cakey:NIOSSLPrivateKey!
    public var rsakey:NIOSSLPrivateKey!
    
    public init(host:String,port:Int) {
        self.host = host
        self.port = port
    }
    
    deinit {
        if isDebug { print("LocalSSLServer deinit !") }
    }
    
    public func run(_ callBack:@escaping (Bool) -> Void) -> Void {
        if !loadCACert() {
            callBack(false)
            return
        }
        // 通过CA证书给域名动态签发证书
        let dynamicCert = CertUtils.generateCert(host: SSLHost,rsaKey: rsakey, caKey: cakey, caCert: cacert)
        let tlsServerConfiguration = TLSConfiguration.forServer(certificateChain: [.certificate(dynamicCert)], privateKey: .privateKey(rsakey))
        sslContext = try! NIOSSLContext(configuration: tlsServerConfiguration)
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group!)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                return channel.pipeline.addHandler(try! NIOSSLServerHandler(context: self.sslContext)).flatMap {
                    channel.pipeline.addHandler(EchoHandler())
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        
        DispatchQueue.global().async {
            do{
                self.channel = try bootstrap.bind(host: self.host, port: self.port).wait()
                if isDebug { print("SSL Server started and listening on \(self.channel?.localAddress?.description ?? "unknow")") }
                callBack(true)
                try self.channel?.closeFuture.wait()
            }catch {
                if isDebug { print("SSL Server started Failure :\(error.localizedDescription)") }
                callBack(false)
            }
        }
    }
    
    public func close(){
        channel?.close(mode: .all).whenSuccess({ () in
            if isDebug { print("SSL Server Channel Close Success !") }
        })
        try? group?.syncShutdownGracefully()
        if isDebug { print("SSL Server close !") }
    }
    
    func loadCACert() -> Bool{
        // load cert
        if let certDir = MitmService.getCertPath() {
            let cacertPath = certDir.appendingPathComponent("cacert.pem", isDirectory: false)
            let cakeyPath = certDir.appendingPathComponent("cakey.pem", isDirectory: false)
            let rsakeyPath = certDir.appendingPathComponent("rsakey.pem", isDirectory: false)
            if let cert = try? NIOSSLCertificate(file: cacertPath.absoluteString.replacingOccurrences(of: "file://", with: ""), format: .pem) {
                cacert = cert
            }else{
                print("Load CACert Failure !")
                return false
            }
            if let caPriKey = try? NIOSSLPrivateKey(file: cakeyPath.absoluteString.replacingOccurrences(of: "file://", with: ""), format: .pem) {
                cakey = caPriKey
            }else{
                print("Load CAKey Failure !")
                return false
            }
            if let carsaKey = try? NIOSSLPrivateKey(file: rsakeyPath.absoluteString.replacingOccurrences(of: "file://", with: ""), format: .pem) {
                rsakey = carsaKey
            }else{
                print("Load RSAKey Failure !")
                return false
            }
        }
        return true
    }
}

public enum TrustResultType:String {
    case none = "none"
    case installed = "installed"
    case trusted = "trusted"
}

public class CheckCert {
    
    var checkCallBack:((TrustResultType) -> Void)!
    var sslServer:LocalSSLServer?
    var isEnd = false
    let host: String = "::1"
    let port: Int = 4433
    
    public init() {
        
    }
    
    deinit {
        // 释放资源
        if isDebug { print("CheckCert deinit !") }
    }
    
    public static func checkPermissions(_ callBack:@escaping (TrustResultType) -> Void){
        let check = CheckCert()
        check.isTrust(callBack)
    }
    
    public func isTrust(_ callBack:@escaping (TrustResultType) -> Void){
        checkCallBack = callBack
        // 先检查是否安装证书
        if let certPath = MitmService.getCertPath()?.appendingPathComponent("cacert.der"),
            let certData = try? Data(contentsOf: certPath) {
            guard let cert = SecCertificateCreateWithData(nil, certData as CFData) else {
                if isDebug { print("no cert file !") }
                isEnd = true
                checkCallBack(.none)
                return
            }
            let policy = SecPolicyCreateBasicX509()
            var trust:SecTrust?
            _ = SecTrustCreateWithCertificates([cert] as CFTypeRef, policy, &trust)
            if trust != nil {
                var trustResult: SecTrustResultType = .invalid
                _ = SecTrustEvaluate(trust!, &trustResult)
                if trustResult != .proceed && trustResult != .unspecified {
                    if isDebug { print("no install cert !") }
                    isEnd = true
                    checkCallBack(.none)
                    return
                }
            }
        }else{
            if isDebug { print("no cert file !") }
            isEnd = true
            checkCallBack(.none)
            return
        }
        // 启动ssl服务，检查是否信任证书
        sslServer = LocalSSLServer(host: host, port: port)
        sslServer?.run({ (success) in
            if !success {
                self.isEnd = true
                self.checkCallBack(.installed)
                return
            }
            self.check()
        })
    }
    
    func check(){
        let channelInitializer: ((Channel) -> EventLoopFuture<Void>) = { (channel) -> EventLoopFuture<Void> in
            let tlsClientConfiguration = TLSConfiguration.forClient(applicationProtocols: ["http/1.1"])
            let sslClientContext = try! NIOSSLContext(configuration: tlsClientConfiguration)
            let sslClientHandler = try! NIOSSLClientHandler(context: sslClientContext, serverHostname: SSLHost)
            let applicationProtocolNegotiationHandler = ApplicationProtocolNegotiationHandler { (result) -> EventLoopFuture<Void> in
                // ssl握手成功
                self.isEnd = true
                self.checkCallBack(.trusted)
                return channel.close(mode: .all)
            }
            return channel.pipeline.addHandler(sslClientHandler, name: "NIOSSLClientHandler").flatMap({
                channel.pipeline.addHandler(applicationProtocolNegotiationHandler, name: "ApplicationProtocolNegotiationHandler")
            })
        }
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientBootstrap = ClientBootstrap(group: group).channelInitializer(channelInitializer)
        let cf = clientBootstrap.connect(host: host, port: port)
        cf.whenComplete { result in
            switch result {
            case .success(let channel):
                channel.closeFuture.whenComplete({ (R) in
                    switch R{
                    case .failure(let error):
                        if isDebug { print("SSL Client Channel Close Error ! \(error.localizedDescription)") }
                    case .success(_):
                        if isDebug { print("SSL Client Channel Close Success !") }
                        break
                    }
                    if !self.isEnd {
                        self.isEnd = true
                        self.checkCallBack(.installed)
                    }
                    if isDebug { print("SSL Client Close !") }
                    self.sslServer?.close()
                    try? group.syncShutdownGracefully()
                })
                if isDebug { print("SSL Client Connect Success ! \(channel.remoteAddress?.description ?? "")") }
                break
            case .failure(let error):
                self.isEnd = true
                self.checkCallBack(.installed)
                if isDebug { print("SSL Client Connect failure:\(error)") }
                break
            }
        }
    }
}
