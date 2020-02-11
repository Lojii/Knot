//
//  HTTPServerHandler.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/6/21.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOHTTP1

extension String {
    func chopPrefix(_ prefix: String) -> String? {
        if self.unicodeScalars.starts(with: prefix.unicodeScalars) {
            return String(self[self.index(self.startIndex, offsetBy: prefix.count)...])
        } else {
            return nil
        }
    }
    
    func containsDotDot() -> Bool {
        for idx in self.indices {
            if self[idx] == "." && idx < self.index(before: self.endIndex) && self[self.index(after: idx)] == "." {
                return true
            }
        }
        return false
    }
}

private func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
    var head = HTTPResponseHead(version: request.version, status: status, headers: headers)
    let connectionHeaders: [String] = head.headers[canonicalForm: "connection"].map { $0.lowercased() }
    
    if !connectionHeaders.contains("keep-alive") && !connectionHeaders.contains("close") {
        // the user hasn't pre-set either 'keep-alive' or 'close', so we might need to add headers
        
        switch (request.isKeepAlive, request.version.major, request.version.minor) {
        case (true, 1, 0):
            // HTTP/1.0 and the request has 'Connection: keep-alive', we should mirror that
            head.headers.add(name: "Connection", value: "keep-alive")
        case (false, 1, let n) where n >= 1:
            // HTTP/1.1 (or treated as such) and the request has 'Connection: close', we should mirror that
            head.headers.add(name: "Connection", value: "close")
        default:
            // we should match the default or are dealing with some HTTP that we don't support, let's leave as is
            ()
        }
    }
    return head
}

class HTTPServerHandler: ChannelInboundHandler {
    private enum FileIOMethod {
        case sendfile
        case nonblockingFileIO
    }
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    
    private enum State {
        case idle
        case waitingForRequestBody
        case sendingResponse
        
        mutating func requestReceived() {
            precondition(self == .idle, "Invalid state for request received: \(self)")
            self = .waitingForRequestBody
        }
        
        mutating func requestComplete() {
            precondition(self == .waitingForRequestBody, "Invalid state for request complete: \(self)")
            self = .sendingResponse
        }
        
        mutating func responseComplete() {
            precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
            self = .idle
        }
    }
    
    private var buffer: ByteBuffer! = nil
    private var keepAlive = false
    private var state = State.idle
    private let htdocsPath: String
    
    private var infoSavedRequestHead: HTTPRequestHead?
    private var infoSavedBodyBytes: Int = 0
    
    private var continuousCount: Int = 0
    
    private var handler: ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)?
    private var handlerFuture: EventLoopFuture<Void>?
    private let fileIO: NonBlockingFileIO
    private let defaultResponse = "Hello NIO\r\n"
    
    public init(fileIO: NonBlockingFileIO, htdocsPath: String) {
        self.htdocsPath = htdocsPath
        self.fileIO = fileIO
    }
    
    private func handleFile(context: ChannelHandlerContext, request: HTTPServerRequestPart, ioMethod: FileIOMethod, path: String) {
        self.buffer.clear()
        func sendErrorResponse(request: HTTPRequestHead, _ error: Error) {
            var body = context.channel.allocator.buffer(capacity: 128)
            let response = { () -> HTTPResponseHead in
                switch error {
                case let e as IOError where e.errnoCode == ENOENT:
                    body.writeStaticString("404 not found \r\n")
                    return httpResponseHead(request: request, status: .notFound)
                case let e as IOError:
                    body.writeStaticString("Error (other)\r\n")
                    body.writeString(e.description)
                    body.writeStaticString("\r\n")
                    return httpResponseHead(request: request, status: .notFound)
                default:
                    body.writeString("\(type(of: error)) error\r\n")
                    return httpResponseHead(request: request, status: .internalServerError)
                }
            }()
            body.writeString("\(error)")
            body.writeStaticString("\r\n")
            context.write(self.wrapOutboundOut(.head(response)), promise: nil)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.channel.close(promise: nil)
        }
        
        func responseHead(request: HTTPRequestHead, fileRegion region: FileRegion, path:String) -> HTTPResponseHead {
            var response = httpResponseHead(request: request, status: .ok)
            response.headers.add(name: "Content-Length", value: "\(region.endIndex)")
            if path.lowercased().contains(".pem") {
                response.headers.add(name: "Content-Type", value: "application/x-x509-ca-cert")
                response.headers.add(name: "Content-Disposition", value: "filename=nio-ca-certificate-\(Date().fullSting).pem")
            }else if path.lowercased().contains(".html") {
                response.headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
            }else{
                response.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
            }
            return response
        }
        
        switch request {
        case .head(let request):
            self.keepAlive = request.isKeepAlive
            self.state.requestReceived()
            guard !request.uri.containsDotDot() else {
                let response = httpResponseHead(request: request, status: .forbidden)
                context.write(self.wrapOutboundOut(.head(response)), promise: nil)
                self.completeResponse(context, trailers: nil, promise: nil)
                return
            }
            let path = self.htdocsPath + "/" + (path == "/" ? "/index.html" : path)
            let fileHandleAndRegion = self.fileIO.openFile(path: path, eventLoop: context.eventLoop)
            fileHandleAndRegion.whenFailure {
                sendErrorResponse(request: request, $0)
            }
            fileHandleAndRegion.whenSuccess { (file, region) in
                switch ioMethod {
                case .nonblockingFileIO:
                    var responseStarted = false
                    let response = responseHead(request: request, fileRegion: region, path: path)
                    if region.readableBytes == 0 {
                        responseStarted = true
                        context.write(self.wrapOutboundOut(.head(response)), promise: nil)
                    }
                    return self.fileIO.readChunked(fileRegion: region,
                                                   chunkSize: 32 * 1024,
                                                   allocator: context.channel.allocator,
                                                   eventLoop: context.eventLoop) { buffer in
                                                    if !responseStarted {
                                                        responseStarted = true
                                                        context.write(self.wrapOutboundOut(.head(response)), promise: nil)
                                                    }
                                                    return context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))))
                        }.flatMap { () -> EventLoopFuture<Void> in
                            let p = context.eventLoop.makePromise(of: Void.self)
                            self.completeResponse(context, trailers: nil, promise: p)
                            return p.futureResult
                        }.flatMapError { error in
                            if !responseStarted {
                                let response = httpResponseHead(request: request, status: .ok)
                                context.write(self.wrapOutboundOut(.head(response)), promise: nil)
                                var buffer = context.channel.allocator.buffer(capacity: 100)
                                buffer.writeString("fail: \(error)")
                                context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                                self.state.responseComplete()
                                return context.writeAndFlush(self.wrapOutboundOut(.end(nil)))
                            } else {
                                return context.close()
                            }
                        }.whenComplete { (_: Result<Void, Error>) in
                            _ = try? file.close()
                    }
                case .sendfile:
                    let response = responseHead(request: request, fileRegion: region, path: path)
                    context.write(self.wrapOutboundOut(.head(response)), promise: nil)
                    context.writeAndFlush(self.wrapOutboundOut(.body(.fileRegion(region)))).flatMap {
                        let p = context.eventLoop.makePromise(of: Void.self)
                        self.completeResponse(context, trailers: nil, promise: p)
                        return p.futureResult
                        }.flatMapError { (_: Error) in
                            context.close()
                        }.whenComplete { (_: Result<Void, Error>) in
                            _ = try? file.close()
                    }
                }
            }
        case .end:
            self.state.requestComplete()
        default:
            fatalError("oh noes: \(request)")
        }
    }
    
    private func completeResponse(_ context: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
        self.state.responseComplete()
        
        let promise = self.keepAlive ? promise : (promise ?? context.eventLoop.makePromise())
        if !self.keepAlive {
            promise!.futureResult.whenComplete { (_: Result<Void, Error>) in context.close(promise: nil) }
        }
        self.handler = nil
        
        context.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        if let handler = self.handler {
            handler(context, reqPart)
            return
        }
        
        switch reqPart {
        case .head(let request):
            self.handler = { self.handleFile(context: $0, request: $1, ioMethod: .nonblockingFileIO, path: request.uri) }
            self.handler!(context, reqPart)
            return
        case .body:
            break
        case .end:
            self.state.requestComplete()
            let content = HTTPServerResponsePart.body(.byteBuffer(buffer!.slice()))
            context.write(self.wrapOutboundOut(content), promise: nil)
            self.completeResponse(context, trailers: nil, promise: nil)
        }
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        self.buffer = context.channel.allocator.buffer(capacity: 0)
    }
    
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let evt as ChannelEvent where evt == ChannelEvent.inputClosed:
            switch self.state {
            case .idle, .waitingForRequestBody:
                context.close(promise: nil)
            case .sendingResponse:
                self.keepAlive = false
            }
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }
}

