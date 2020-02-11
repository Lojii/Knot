//
//  SSLMatcher.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOHTTP1

class SSLMatcher: ProtocolMatcher {
    
    private let methods:Set<String> = ["GET", "POST", "PUT", "HEAD", "OPTIONS", "PATCH", "DELETE","TRACE"]
    
    public override init() {
        super.init()
        
    }
    
    //根据第一个单词是否为方法名来判断
    override func match(buf: ByteBuffer) -> Int {
        
        // SSL的每一条消息都会包含有ContentType,Version,HandshakeType等信息
        /*
             1、第一个字节为ContentType,有以下值，如果为22，则是握手阶段
             0x14 20 ChangeCipherSpec    开始加密传输
             0x15 21 Alert
             0x16 22 Handshake           握手   *
             0x17 23 Application         正常通信
             2、第二和三个字节为Version是TLS的版本，有以下值
             Major Version | Minor Version | Version Type
             3               0               SSLv3  *
             3               1               TLS 1.0
             3               2               TLS 1.1
             3               3               TLS 1.2
             3、第三个字节为Handshake Type是在handshanke阶段中的具体哪一步
             0   HelloRequest
             1   ClientHello  *
             2   ServerHello
             11  Certificate
             12  ServerKeyExchange
             13  CertificateRequest
             14  ServerHelloDone
             15  CertificateVerify
             16  ClientKeyExchange
             20  Finished
         */
//        Consumer
        if buf.readableBytes < 3 {
            return ProtocolMatcher.PENDING
        }
        
        let first = buf.getBytes(at: buf.readerIndex, length: 1)
        let second = buf.getBytes(at: buf.readerIndex + 1, length: 1)
        let third = buf.getBytes(at: buf.readerIndex + 2, length: 1)
        
        let firstData = NSString(format: "%d", first?.first ?? 0).integerValue
        let secondData = NSString(format: "%d", second?.first ?? 0).integerValue
        let thirdData = NSString(format: "%d", third?.first ?? 0).integerValue
//        print("SSL:\(firstData),\(secondData),\(thirdData)")
        if (firstData == 22 && secondData <= 3 && thirdData <= 3) {
            return ProtocolMatcher.MATCH
        }
        return ProtocolMatcher.MISMATCH
    }
    
    override func handlePipeline(pipleline: ChannelPipeline, task:Task) {
        let ppp = ProxyContext(isHttp: false, task: task)
        _ = pipleline.addHandler(ChannelWatchHandler(proxyContext: ppp), name: "ChannelWatchHandler", position: .first)
//        _ = pipleline.addHandler(SSLHandler(proxyContext: ppp), name: "SSLDetector", position: .last)
    }
    
}
