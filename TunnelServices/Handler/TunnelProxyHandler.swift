//
//  TunnelProxyHandler.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/23.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import NIOTLS
import NIO

class TunnelProxyHandler: ChannelInboundHandler,RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    
    var proxyContext:ProxyContext
    
    var isOut:Bool
    var connected:Bool
    var requestDatas = [ByteBuffer]()
    var scheduled:Scheduled<Void>?
    var cf:EventLoopFuture<Channel>?
    
    init(proxyContext:ProxyContext, isOut: Bool,scheduled:Scheduled<Void>?){
        self.proxyContext = proxyContext
        self.connected = false
        self.isOut = isOut
        self.scheduled = scheduled
    }
    
    // 原始消息报文
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        print("TunnelProxyHandler: \(isOut ? "-->" : "<--")")
        scheduled?.cancel()
        let buf = unwrapInboundIn(data)
        if isOut {
            _ = proxyContext.serverChannel?.writeAndFlush(wrapInboundOut(buf))
        }else{
            // 连接服务器
            if cf == nil {
                connectToServer()
            }
            handleData(buf)
        }
        context.fireChannelRead(wrapInboundOut(buf))
        return
    }
    
    func connectToServer() -> Void {
        guard let request = proxyContext.request else {
            print("no request ! --> end")
            return
        }
        var channelInitializer: ((Channel) -> EventLoopFuture<Void>)?
        channelInitializer = { (outChannel) -> EventLoopFuture<Void> in
            self.proxyContext.clientChannel = outChannel
//                print("http.outChannel.pipeline:\(outChannel.pipeline)")
            return outChannel.pipeline.addHandler(TunnelProxyHandler(proxyContext: self.proxyContext, isOut: true, scheduled: nil), name: "TunnelProxyHandler")
        }
        
        let clientBootstrap = ClientBootstrap(group: proxyContext.serverChannel!.eventLoop.next())
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer(channelInitializer!)
        cf = clientBootstrap.connect(host: request.host, port: request.port)
        cf!.whenComplete { result in
            switch result {
            case .success( _):
                self.connected = true
                self.handleData(nil)
//                print("outChannel.pipeline:\(outChannel.pipeline)")
                break
            case .failure(let error):
                print("outChannel connect error:\(error)")
                self.proxyContext.session.sstate = "failure"
                self.proxyContext.session.note = "\(request.host) connect error:\(error)"
                _ = self.proxyContext.serverChannel?.close()
                break
            }
        }
    }
    
    func handleData(_ data:ByteBuffer?) -> Void {
//        let lock = ConditionLock(value: 0)
//        lock.lock()
        if connected {// 发送requestDatas，然后清空requestDatas
            for rd in requestDatas{
                _ = proxyContext.clientChannel!.writeAndFlush(rd)
            }
            if data != nil {
                _ = proxyContext.clientChannel!.writeAndFlush(data)
            }
            requestDatas.removeAll()
        }else{
            guard let msg = data else {return}
            requestDatas.append(msg)
        }
//        lock.unlock()
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        context.close(mode: .all, promise: nil)
    }
    
}
