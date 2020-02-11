//
//  HttpsMatcher.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOHTTP1
import Foundation

class HttpsMatcher: ProtocolMatcher {
    
    public override init() {
        super.init()
        
    }
    
    override func match(buf: ByteBuffer) -> Int {
        
        if buf.readableBytes < 8 {
            return ProtocolMatcher.PENDING
        }
        
        guard let front8 = buf.getString(at: 0, length: 8) else {
            return ProtocolMatcher.MISMATCH
        }
        if "CONNECT " == front8 {
            return ProtocolMatcher.MATCH
        }
        return ProtocolMatcher.MISMATCH
    }
    
    override func handlePipeline(pipleline: ChannelPipeline, task:Task) {
        let pc = ProxyContext(isHttp:true, task:task)
        pc.session.schemes = "Https"
        _ = pipleline.addHandler(HTTPResponseEncoder(), name: "HTTPResponseEncoder", position: .last)
        let requestDecoder = HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)
        _ = pipleline.addHandler(ByteToMessageHandler(requestDecoder), name: "ByteToMessageHandler", position: .last)
        _ = pipleline.addHandler(HTTPServerPipelineHandler(), name: "HTTPServerPipelineHandler", position: .last)
        _ = pipleline.addHandler(HTTPSHandler(proxyContext: pc), name: "HTTPSHandler", position: .last)
    }
}
