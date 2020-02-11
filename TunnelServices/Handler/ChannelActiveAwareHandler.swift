//
//  ChannelActiveAwareHandler.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/4.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOTLS
import NIO
import NIOSSL
import NIOHTTP1

class ChannelActiveAwareHandler: ChannelInboundHandler,RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    
    var promise:EventLoopPromise<Channel>
    
    init(promise:EventLoopPromise<Channel>){
        self.promise = promise
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        _ = context.pipeline.removeHandler(self)
        promise.succeed(context.channel)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
    }
}
