//
//  ProtocolMatcher.swift
//  SwiftNIO
//
//  Created by Lojii on 2018/8/16.
//  Copyright © 2018年 Lojii. All rights reserved.
//

import UIKit
import NIO

//Matcher for protocol.
class ProtocolMatcher {
    
    static let MATCH = 1
    static let MISMATCH = -1
    static let PENDING = 0
    
    // overwrite
    //If match the protocol.
    public func match(buf:ByteBuffer) -> Int {return -1}
    
    //Deal with the pipeline when matched
    public func handlePipeline(pipleline:ChannelPipeline, task:Task) -> Void {}
    
}
