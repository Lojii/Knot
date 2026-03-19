//
//  ChannelWatchHandler.swift
//  Knot
//
//  Created by LiuJie on 2019/4/17.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
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

        self.proxyContext.session.uploadTraffic += Int64(outData.readableBytes)

        context.writeAndFlush(data, promise: promise)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let inData = unwrapInboundIn(data)

        self.proxyContext.session.downloadFlow += Int64(inData.readableBytes)

        context.fireChannelRead(data)
    }

}
