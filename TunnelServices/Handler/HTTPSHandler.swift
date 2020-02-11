//
//  HTTPSHandler.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOHTTP1
import NIO

class HTTPSHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart//IOData//
    
    enum ResponseState {
        case ready
        case parsingBody(HTTPRequestHead, ByteBuffer?)
    }
    
    var state: ResponseState
    var proxyContext:ProxyContext
    
    init(proxyContext:ProxyContext) {
        self.state = .ready
        self.proxyContext = proxyContext
    }
    
    // 原始消息报文
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        prepareProxyContext(context: context, data: data)
        let res = self.unwrapInboundIn(data)
        switch res {
        case .head(let head):
            switch self.state {
            case .ready: self.state = .parsingBody(head, nil)
            case .parsingBody: assert(false, "Unexpected HTTPServerRequestPart.head when body was being parsed.")
            }
        case .body(var body):
            switch self.state {
            case .ready: assert(false, "Unexpected HTTPServerRequestPart.body when awaiting request head.")
            case .parsingBody(let head, let existingData):
                let buffer: ByteBuffer
                if var existing = existingData {
                    existing.writeBuffer(&body)
                    buffer = existing
                } else {
                    buffer = body
                }
                self.state = .parsingBody(head, buffer)
            }
        case .end(let tailHeaders):
            assert(tailHeaders == nil, "Unexpected tail headers")
            switch self.state {
            case .ready: assert(false, "Unexpected HTTPServerRequestPart.end when awaiting request head.")
            case .parsingBody(var head, _):
                let netReq = NetRequest(head)
                // 移除代理相关头
                head.headers = NetRequest.removeProxyHead(heads: head.headers)
                // 填充数据到session
                proxyContext.session.reqLine = "\(head.method) \(head.uri) \(head.version)"
                proxyContext.session.host = netReq.host
                proxyContext.session.localAddress = Session.getIPAddress(socketAddress: context.channel.remoteAddress)
                proxyContext.session.methods = "\(head.method)"//
                proxyContext.session.uri = head.uri//
                proxyContext.session.reqHttpVersion = "\(head.version)"//
                proxyContext.session.target = Session.getUserAgent(target: head.headers["User-Agent"].first)
                proxyContext.session.reqHeads = Session.getHeadsJson(headers: head.headers)// //
                proxyContext.session.connectTime = NSNumber(value: Date().timeIntervalSince1970)  // 开始建立连接
                //TODO:判断是否匹配
                
                
                // 必须加个content-length:0 不然会自动添加transfer-encoding:chunked,导致部分设备无法识别，坑
                let rspHead = HTTPResponseHead(version: head.version,
                                               status: .custom(code: 200, reasonPhrase: "Connection Established"),
                                               headers: ["content-length":"0"])
//                let rspHead = HTTPResponseHead(version: head.version,
//                                               status: .custom(code: 200, reasonPhrase: "Connection Established"))
                context.channel.writeAndFlush(HTTPServerResponsePart.head(rspHead), promise: nil)
                context.channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                // 移除多余handler
                context.pipeline.removeHandler(name: "ProtocolDetector", promise: nil)
                context.pipeline.removeHandler(name: "HTTPResponseEncoder", promise: nil)
                context.pipeline.removeHandler(name: "ByteToMessageHandler", promise: nil)
                context.pipeline.removeHandler(name: "HTTPServerPipelineHandler", promise: nil)
                context.pipeline.removeHandler(name: "HTTPSHandler", promise: nil)
                // 添加ssl握手处理handler
                let cancelTask = context.channel.eventLoop.scheduleTask(in:  TimeAmount.seconds(10)) {
                    print( "error:can not get client hello from APP \(self.proxyContext.session.target ?? "") \(self.proxyContext.request?.host ?? "")")
                    self.proxyContext.session.note = "error:can not get client hello from APP \(self.proxyContext.session.target ?? "")"
                    self.proxyContext.session.sstate = "failure"
                    context.channel.close(mode: .all,promise: nil)
                }
                // 判断规则，是否拦截，copy等
                proxyContext.session.ignore = proxyContext.task.rule.matching(host: proxyContext.session.host ?? "",uri: head.uri, target: proxyContext.session.target ?? "")
//                print("HTTPSHandler匹配")
                if proxyContext.task.rule.defaultStrategy == .COPY {
                    proxyContext.session.ignore = !proxyContext.session.ignore
                }
                if proxyContext.task.sslEnable == 1, !proxyContext.session.ignore {
                    _ = context.pipeline.addHandler(SSLHandler(proxyContext: proxyContext,scheduled:cancelTask), name: "SSLHandler", position: .first)
                }else{
//                    _ = context.pipeline.addHandler(ChannelWatchHandler(proxyContext: self.proxyContext), name: "ChannelWatchHandler")
                    _ = context.pipeline.addHandler(TunnelProxyHandler(proxyContext: proxyContext, isOut: false,scheduled:cancelTask), name: "TunnelProxyHandler", position: .first)
                    proxyContext.session.note = "no cert config !"
                }
                return
            }
        }
    }
    
    func prepareProxyContext(context: ChannelHandlerContext, data: NIOAny) -> Void {
        if proxyContext.serverChannel == nil {
            proxyContext.serverChannel = context.channel
        }
        let res = self.unwrapInboundIn(data)
        switch res {
        case .head(let head):
            if proxyContext.request == nil {
                proxyContext.request = NetRequest(head)
                proxyContext.request?.ssl = true
            }
        case .body(_),.end(_):
            break
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
//        print("HTTPSHandler errorCaught:\(error.localizedDescription)")
//        _ = context.channel.close(mode: .all)
        proxyContext.serverChannel?.close(mode: .all, promise: nil)
        if let cc = proxyContext.clientChannel ,cc.isActive {
            _ = cc.close(mode: .all)
        }
    }
}
