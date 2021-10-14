//
//  SSLHandler.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/17.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOTLS
import NIO
import NIOSSL
import NIOHTTP1
import AxLogger

class SSLHandler: ChannelInboundHandler,RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    
    var proxyContext:ProxyContext
    var scheduled:Scheduled<Void>
    
    init(proxyContext:ProxyContext,scheduled:Scheduled<Void>){
        self.proxyContext = proxyContext
        self.scheduled = scheduled
    }
    
    // 原始消息报文
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        scheduled.cancel()
        prepareProxyContext(context: context, data: data)
        //
        let buf = unwrapInboundIn(data)
        if buf.readableBytes < 3 {
            print("buf.readableBytes < 3")
            return
        }
        let first = buf.getBytes(at: buf.readerIndex, length: 1)
        let second = buf.getBytes(at: buf.readerIndex + 1, length: 1)
        let third = buf.getBytes(at: buf.readerIndex + 2, length: 1)
        let firstData = NSString(format: "%d", first?.first ?? 0).integerValue
        let secondData = NSString(format: "%d", second?.first ?? 0).integerValue
        let thirdData = NSString(format: "%d", third?.first ?? 0).integerValue
        if (firstData == 22 && secondData <= 3 && thirdData <= 3) {
            // is ClientHello
            proxyContext.isSSL = true
            // TODO:考虑做成全局变量，防止每次都从文件读取
            // load CA cert
//            let certPath = Bundle.main.path(forResource: "CA/cacert", ofType: "pem") ?? ""
//            guard let cert = try? NIOSSLCertificate(file: certPath, format: .pem) else{
//                proxyContext.session.sstate = "failure"
//                print("Load Certificate Error !")
//                proxyContext.session.note = "error:Load Certificate Error !"
//                _ = context.channel.close()
//                return
//            }
//            // ca private key
//            let caPriKeyPath = Bundle.main.path(forResource: "CA/cakey", ofType: "pem") ?? ""
//            guard let caPriKey = try? NIOSSLPrivateKey(file: caPriKeyPath, format: .pem) else {
//                proxyContext.session.sstate = "failure"
//                print("Load CA Key Error !")
//                proxyContext.session.note = "error:Load CA Key Error !"
//                _ = context.channel.close()
//                return
//            }
//            // rsa key
//            let rsaPriKeyPath = Bundle.main.path(forResource: "CA/rsakey", ofType: "pem") ?? ""
//            guard let rsaKey = try? NIOSSLPrivateKey(file: rsaPriKeyPath, format: .pem) else {
//                proxyContext.session.sstate = "failure"
//                print("Load RSA Key Error !")
//                proxyContext.session.note = "error:Load RSA Key Error !"
//                _ = context.channel.close()
//                return
//            }
            let cert = proxyContext.task.cacert
            let caPriKey = proxyContext.task.cakey
            let rsaKey = proxyContext.task.rsakey
            if cert == nil || caPriKey == nil || rsaKey == nil {
                AxLogger.log("证书为空！！！", level: .Error)
            }
            // 通过CA证书给域名动态签发证书
            let host = proxyContext.request!.host
            var dynamicCert = proxyContext.task.certPool[host]
            if dynamicCert == nil {
                dynamicCert = CertUtils.genreateCert(host: host,
                                                     rsaKeyPEM: CertDatas.rsakey.data(using: .utf8)!,
                                                     caKeyPEM: CertDatas.cakey.data(using: .utf8)!,
                                                     caCertPEM: CertDatas.cacert.data(using: .utf8)!)
//                proxyContext.task.certPool[host] = dynamicCert
                proxyContext.task.certPool.setValue(dynamicCert, forKey: host)
            }
            let tlsServerConfiguration = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(dynamicCert as! NIOSSLCertificate)],
                privateKey: .privateKey(rsaKey!))
            let sslServerContext = try! NIOSSLContext(configuration: tlsServerConfiguration)
            let sslServerHandler = NIOSSLServerHandler(context: sslServerContext)
            // issue:握手信息发出后，服务器验证未通过，失败未关闭channel
            // 添加ssl握手处理handler
            let cancelHandshakeTask = context.channel.eventLoop.scheduleTask(in:  TimeAmount.seconds(10)) {
                print("error:can not get server hello from MITM \(self.proxyContext.request?.host ?? "")")
                self.proxyContext.session.note = "error:can not get server hello from MITM"
                self.proxyContext.session.sstate = "failure"
                context.channel.close(mode: .all,promise: nil)
            }
            let aPNHandler = ApplicationProtocolNegotiationHandler(alpnCompleteHandler: { result -> EventLoopFuture<Void> in
                cancelHandshakeTask.cancel()
//                print("ServerHello MITM c->m:\(result) \(self.proxyContext.request?.host ?? "")")
                let requestDecoder = HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)
                return context.pipeline.addHandler(ByteToMessageHandler(requestDecoder), name: "ByteToMessageHandler").flatMap({
                    context.pipeline.addHandler(HTTPResponseEncoder(), name: "HTTPResponseEncoder").flatMap({                   // <--
                        context.pipeline.addHandler(HTTPServerPipelineHandler(), name: "HTTPServerPipelineHandler").flatMap({   // <-->
                            context.pipeline.addHandler(HTTPHandler(proxyContext: self.proxyContext), name: "HTTPHandler")      // -->
                        })
                    })
                })
            })
            
            _ = context.pipeline.addHandler(sslServerHandler, name: "NIOSSLServerHandler", position: .last)
            _ = context.pipeline.addHandler(aPNHandler, name: "ApplicationProtocolNegotiationHandler")
            context.fireChannelRead(self.wrapInboundOut(buf))
            _ = context.pipeline.removeHandler(name: "SSLHandler")
            return
        }else{
            print("+++++++++++++++ not ssl handshake ")
        }
    }
    
    func prepareProxyContext(context: ChannelHandlerContext, data: NIOAny) -> Void {
        if proxyContext.serverChannel == nil {
            proxyContext.serverChannel = context.channel
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("SSLHandler errorCaught:\(error.localizedDescription)")
        context.channel.close(mode: .all, promise: nil)
    }
}
