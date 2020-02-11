//
//  ChannelWatchHandler.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/17.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO

class ChannelWatchHandler: ChannelDuplexHandler, RemovableChannelHandler {
    
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    
    
    var proxyContext:ProxyContext
    
    init(proxyContext:ProxyContext) {
        self.proxyContext = proxyContext
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let outData = unwrapInboundIn(data)
        
        let sum = self.proxyContext.session.uploadTraffic
        self.proxyContext.session.uploadTraffic = NSNumber(value: (sum.intValue + outData.readableBytes))
        
//        let taskdownloadFlow = self.proxyContext.task.uploadTraffic
//        self.proxyContext.task.uploadTraffic = NSNumber(value: (taskdownloadFlow.intValue + outData.readableBytes))
        
        context.writeAndFlush(data, promise: promise)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let inData = unwrapInboundIn(data)
        
        let sum = self.proxyContext.session.downloadFlow
        self.proxyContext.session.downloadFlow = NSNumber(value: (sum.intValue + inData.readableBytes))
        
//        let taskdownloadFlow = self.proxyContext.task.downloadFlow
//        self.proxyContext.task.downloadFlow = NSNumber(value: (taskdownloadFlow.intValue + inData.readableBytes))
        
        context.fireChannelRead(data)
    }
    
}
