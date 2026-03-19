//
//  SSLHandler.swift
//  Knot
//
//  Created by LiuJie on 2019/4/17.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import NIOTLS
import NIO
import NIOSSL
import NIOHTTP1

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
            guard let certMgr = proxyContext.task.certManager,
                  let rsaKey = certMgr.rsakey,
                  let x509CACert = certMgr.x509CACert,
                  let rsaSigningKey = certMgr.rsaSigningKey else {
                AxLogger.log("证书为空！！！", level: .Error)
                proxyContext.session.sstate = "failure"
                proxyContext.session.note = "error:Certificate or key is nil"
                _ = context.channel.close()
                return
            }
            guard let request = proxyContext.request else {
                AxLogger.log("request is nil in SSLHandler", level: .Error)
                _ = context.channel.close()
                return
            }
            let host = request.host
            // 通过 CA 证书给域名动态签发证书 (pure Swift)
            var niosslCert = certMgr.certPool[host]
            if niosslCert == nil {
                do {
                    let x509Cert = try CertGenerator.generateCert(
                        host: host, rsaKey: rsaSigningKey, caKey: rsaSigningKey, caCert: x509CACert
                    )
                    niosslCert = try CertGenerator.toNIOSSL(x509Cert)
                    if let c = niosslCert {
                        certMgr.certPool.set(c, forKey: host)
                    }
                } catch {
                    AxLogger.log("Failed to generate cert for \(host): \(error)", level: .Error)
                }
            }
            guard let finalCert = niosslCert else {
                AxLogger.log("Failed to generate dynamic cert for \(host)", level: .Error)
                proxyContext.session.sstate = "failure"
                proxyContext.session.note = "error:Failed to generate certificate for \(host)"
                _ = context.channel.close()
                return
            }
            let tlsServerConfiguration = TLSConfiguration.forServer(certificateChain: [.certificate(finalCert)], privateKey: .privateKey(rsaKey))
            guard let sslServerContext = try? NIOSSLContext(configuration: tlsServerConfiguration) else {
                AxLogger.log("Failed to create NIOSSLContext for \(host)", level: .Error)
                proxyContext.session.sstate = "failure"
                proxyContext.session.note = "error:Failed to create SSL context for \(host)"
                _ = context.channel.close()
                return
            }
            guard let sslServerHandler = try? NIOSSLServerHandler(context: sslServerContext) else {
                AxLogger.log("Failed to create NIOSSLServerHandler for \(host)", level: .Error)
                proxyContext.session.sstate = "failure"
                proxyContext.session.note = "error:Failed to create SSL handler for \(host)"
                _ = context.channel.close()
                return
            }
            // issue:握手信息发出后，服务器验证未通过，失败未关闭channel
            // 添加ssl握手处理handler
            let cancelHandshakeTask = context.channel.eventLoop.scheduleTask(in:  TimeAmount.seconds(ProxyConfig.SSL.handshakeTimeout)) {
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
