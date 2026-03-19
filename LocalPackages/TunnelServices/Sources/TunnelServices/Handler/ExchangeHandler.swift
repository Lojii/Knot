//
//  ExchangeHandler.swift
//  Knot
//
//  Created by LiuJie on 2019/4/20.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
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
            proxyContext.session.rspStartTime = Date().timeIntervalSince1970
            proxyContext.session.rspHttpVersion = "\(head.version)"     //
            proxyContext.session.state = "\(head.status.code)"          //
            proxyContext.session.rspMessage = head.status.reasonPhrase  //
            let contentType = head.headers["Content-Type"].first ?? ""
            proxyContext.session.rspType = contentType
            if let ss = contentType.components(separatedBy: ";").first {
                proxyContext.session.suffix = ss.components(separatedBy: "/").last ?? ""
            }
            proxyContext.session.rspEncoding = head.headers["Content-Encoding"].first ?? ""
            proxyContext.session.rspHeads = NetworkUtils.getHeadsJson(headers: head.headers)//
            proxyContext.session.rspDisposition = head.headers["Content-Disposition"].first ?? ""

            _ = proxyContext.serverChannel?.writeAndFlush(HTTPServerResponsePart.head(head))
        case .body(let body):
            // TODO:响应体修改
//            print("《======\(proxyContext)======》 响应体:\(body.readableBytes)")
            if proxyContext.session.fileName == "" {
                let fileName = proxyContext.session.uri.getFileName()
                if !fileName.isEmpty {
                    proxyContext.session.fileName = fileName
                }
                let nameParts = proxyContext.session.fileName.components(separatedBy: ".")
                if nameParts.count < 2 {
                    let type = proxyContext.session.rspType.getRealType()
                    if type != "" {
                        proxyContext.session.fileName = "\(proxyContext.session.fileName).\(type)"
                    }
                }
            }
            if body.readableBytes > 1024*1024 {
                print("超大：\(body.readableBytes)")
            }
            _ = proxyContext.serverChannel?.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(body)))

        case .end(let tailHeaders):
//            print("《======\(proxyContext)======》 响应尾")
            proxyContext.session.rspEndTime = Date().timeIntervalSince1970
            gotEnd = true
            let promise = proxyContext.serverChannel?.eventLoop.makePromise(of: Void.self)
            proxyContext.serverChannel?.writeAndFlush(HTTPServerResponsePart.end(tailHeaders), promise: promise)
            promise?.futureResult.whenComplete({ (_) in
//                print("关闭对内通道")
                if let serverChannel = self.proxyContext.serverChannel, serverChannel.isActive {
                    serverChannel.close(mode: .all, promise: nil)
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

        if let serverChannel = proxyContext.serverChannel, serverChannel.isActive {
            _ = serverChannel.close(mode: .all)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {

    }
}
