//
//  PipelineLogHandler.swift
//  TunnelServices
//
//  Debug logging handler for NIO pipelines.
//  Insert at any position to log data flow through that point.
//
//  Netty reference: handler/logging/LoggingHandler.java
//

import Foundation
import NIO

public final class PipelineLogHandler: ChannelDuplexHandler {
    public typealias InboundIn = NIOAny
    public typealias InboundOut = NIOAny
    public typealias OutboundIn = NIOAny
    public typealias OutboundOut = NIOAny

    public enum LogLevel { case debug, info, verbose }

    private let label: String
    private let level: LogLevel

    public init(label: String, level: LogLevel = .info) {
        self.label = label
        self.level = level
    }

    public func channelActive(context: ChannelHandlerContext) {
        log("ACTIVE \(context.channel.remoteAddress?.description ?? "?")")
        context.fireChannelActive()
    }

    public func channelInactive(context: ChannelHandlerContext) {
        log("INACTIVE")
        context.fireChannelInactive()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        log("READ \(describeData(data))")
        context.fireChannelRead(data)
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        if level == .verbose { log("READ_COMPLETE") }
        context.fireChannelReadComplete()
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        log("WRITE \(describeData(data))")
        context.write(data, promise: promise)
    }

    public func flush(context: ChannelHandlerContext) {
        if level == .verbose { log("FLUSH") }
        context.flush()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        log("ERROR \(error)")
        context.fireErrorCaught(error)
    }

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        log("EVENT \(event)")
        context.fireUserInboundEventTriggered(event)
    }

    private func describeData(_ data: NIOAny) -> String {
        // Try to get meaningful size info
        let mirror = Mirror(reflecting: data)
        if let child = mirror.children.first {
            return "\(type(of: child.value))"
        }
        return "\(type(of: data))"
    }

    private func log(_ message: String) {
        AxLogger.log("[\(label)] \(message)", level: .Info)
    }
}
