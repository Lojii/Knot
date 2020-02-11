//
//  CloseTimeoutChannelHandler.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/4.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO

class CloseTimeoutChannelHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        print("CloseTimeoutChannelHandler event :\(event)")
        switch event {
        case is ChannelShouldQuiesceEvent:
            break
        case ChannelEvent.inputClosed:
            break
        case ChannelError.connectTimeout(TimeAmount.seconds(10)):
            break
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }
}
