//
//  ProtocolDetector.swift
//  SwiftNIO
//
//  Created by Lojii on 2018/8/16.
//  Copyright © 2018年 Lojii. All rights reserved.
//
// 协议探测器
import UIKit
import NIO
import NIOHTTP1
//import NIOTransportServices

public final class ProtocolDetector: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn =  ByteBuffer
    public typealias InboundOut = ByteBuffer
    
    private var buf:ByteBuffer?
    
    private var index:Int = 0 //

    private let matcherList: [ProtocolMatcher]
    public var task:Task
    
    init(task:Task ,matchers:[ProtocolMatcher]) {
        self.matcherList = matchers
        self.task = task
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if let local = context.channel.localAddress?.description {
            let isLocal = local.contains("127.0.0.1")
            if (isLocal && task.localEnable == 0) || (!isLocal && task.wifiEnable == 0) {
                context.flush()
                context.close(promise: nil)
//                print("channel:\(context.channel.localAddress?.description ?? "") close !")
                return
            }
        }
//        print("channel:\(context.channel.localAddress?.description ?? "") open !")
//        print("channelRead")
//        print("******监听管道：",context.channel)
        let buffer = unwrapInboundIn(data)
        //TODO: 需要处理粘包情况以及数据不完整情况
        for i in index..<matcherList.count {
            let matcher = matcherList[i]
            let match = matcher.match(buf: buffer)
            if match == ProtocolMatcher.MATCH {
                matcher.handlePipeline(pipleline: context.pipeline, task: task)
                context.fireChannelRead(data)
                context.pipeline.removeHandler(self, promise: nil)
                return
            }
            if match == ProtocolMatcher.PENDING {
                index = i
                return
            }
        }
        // all miss
        context.flush()
        context.close(promise: nil)
        print("unsupported protocol")
    }
    
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        print("userInboundEventTriggered:\(event)")
//        context.channel.
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("ProtocolDetector error: \(error.localizedDescription)")
        context.close(promise: nil)
    }
    
    private func startReading(context: ChannelHandlerContext) {
        print("startReading")
    }
    
    private func deliverPendingRequests(context: ChannelHandlerContext) {
        print("deliverPendingRequests")
    }
    
}
