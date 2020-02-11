//
//  ExchangeHandler.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/20.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOHTTP1
import NIOFoundationCompat

class ExchangeHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPServerResponsePart
    
    var proxyContext:ProxyContext
    var gotEnd:Bool = false
    init(proxyContext:ProxyContext) {
        self.proxyContext = proxyContext
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let res = self.unwrapInboundIn(data)
        switch res {
        case .head(let head):
            // TODO:响应头修改
//            print("《======\(proxyContext)======》 响应头:\(head.description)")
            // 保存响应数据
            proxyContext.session.rspStartTime = NSNumber(value: Date().timeIntervalSince1970) // 开始接收响应
            proxyContext.session.rspHttpVersion = "\(head.version)"     //
            proxyContext.session.state = "\(head.status.code)"          //
            proxyContext.session.rspMessage = head.status.reasonPhrase  //
            let contentType = head.headers["Content-Type"].first ?? ""
            proxyContext.session.rspType = contentType
//            if let uri = proxyContext.session.uri, let ss = uri.components(separatedBy: "?").first, let urilast = ss.components(separatedBy: "/").last {
//                let lastss = urilast.components(separatedBy: ".")
//                if lastss.count == 2 {
//                    proxyContext.session.suffix = lastss[1]
//                }
//            }
//            if proxyContext.session.suffix == ""{
//                if let ss = contentType.components(separatedBy: ";").first {
//                    proxyContext.session.suffix = ss.components(separatedBy: "/").last ?? ""
//                }
//            }
            if let ss = contentType.components(separatedBy: ";").first {
                proxyContext.session.suffix = ss.components(separatedBy: "/").last ?? ""
            }
            proxyContext.session.rspEncoding = head.headers["Content-Encoding"].first ?? ""
            proxyContext.session.rspHeads = Session.getHeadsJson(headers: head.headers)//
            proxyContext.session.rspDisposition = head.headers["Content-Disposition"].first ?? ""
            try? proxyContext.session.saveToDB()
            
            _ = proxyContext.serverChannel?.writeAndFlush(HTTPServerResponsePart.head(head))
        case .body(let body):
            // TODO:响应体修改
//            print("《======\(proxyContext)======》 响应体:\(body.readableBytes)")
            // TODO:写入到rspbody文件
            if proxyContext.session.fileName == "" {
                if let fileName = proxyContext.session.uri?.getFileName() {
                    proxyContext.session.fileName = fileName
                    try? proxyContext.session.saveToDB()
                }
                let nameParts = proxyContext.session.fileName.components(separatedBy: ".")
                if nameParts.count < 2 {
                    let type = proxyContext.session.rspType.getRealType()
                    if type != "" {
                        proxyContext.session.fileName = "\(proxyContext.session.fileName).\(type)"
                        try? proxyContext.session.saveToDB()
                    }
                }
            }
            if body.readableBytes > 1024*1024 {
                print("超大：\(body.readableBytes)")
            }
            if !proxyContext.session.ignore {
                proxyContext.session.writeBody(type: .RSP, buffer: body, realName: proxyContext.session.fileName)
            }
            _ = proxyContext.serverChannel?.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(body)))
            
        case .end(let tailHeaders):
//            print("《======\(proxyContext)======》 响应尾")
            proxyContext.session.rspEndTime = NSNumber(value: Date().timeIntervalSince1970) // 接收完毕响应
            gotEnd = true
            // TODO:关闭写文件
            if !proxyContext.session.ignore {
                proxyContext.session.writeBody(type: .RSP, buffer: nil, realName: proxyContext.session.fileName )
            }
            let promise = proxyContext.serverChannel?.eventLoop.makePromise(of: Void.self)
            proxyContext.serverChannel?.writeAndFlush(HTTPServerResponsePart.end(tailHeaders), promise: promise)
            promise?.futureResult.whenComplete({ (_) in
//                print("关闭对内通道")
                if self.proxyContext.serverChannel!.isActive {
                    self.proxyContext.serverChannel!.close(mode: .all, promise: nil)
                }
            })
//             读完数据后关闭对外channel
            let outPromise = context.eventLoop.makePromise(of: Void.self)
            context.channel.close(mode: .all, promise: outPromise)
            outPromise.futureResult.whenComplete { (_) in
//                print("对外关闭")
            }
            return
        }
        context.fireChannelRead(data)
        
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        context.close(mode: .all, promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {

        context.channel.close(mode: .all,promise: nil)

        if proxyContext.serverChannel!.isActive {
            _ = self.proxyContext.serverChannel!.close(mode: .all)
        }
    }
    
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {

    }
}
