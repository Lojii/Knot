//
//  TimeoutHandler.swift
//  TunnelServices
//
//  Fine-grained timeout control: read, write, and idle timeouts.
//
//  Netty reference: handler/timeout/ReadTimeoutHandler.java,
//                   WriteTimeoutHandler.java, IdleStateHandler.java
//

import Foundation
import NIO

// MARK: - Idle State Event

public enum IdleState {
    case read       // No data received for timeout period
    case write      // No data written for timeout period
    case all        // No read or write for timeout period
}

public struct IdleStateEvent {
    public let state: IdleState
    public let isFirst: Bool  // First occurrence since last activity
}

// MARK: - Idle State Handler

/// Fires IdleStateEvent when a channel has been idle for a configured duration.
/// Similar to Netty's IdleStateHandler.
public final class IdleStateHandler: ChannelDuplexHandler {
    public typealias InboundIn = NIOAny
    public typealias InboundOut = NIOAny
    public typealias OutboundIn = NIOAny
    public typealias OutboundOut = NIOAny

    private let readTimeout: TimeAmount?
    private let writeTimeout: TimeAmount?
    private let allIdleTimeout: TimeAmount?

    private var readTimer: Scheduled<Void>?
    private var writeTimer: Scheduled<Void>?
    private var allIdleTimer: Scheduled<Void>?
    private var readFired = false
    private var writeFired = false
    private var allFired = false

    /// - Parameters:
    ///   - readTimeout: Fire event if no read for this duration. nil = disabled.
    ///   - writeTimeout: Fire event if no write for this duration. nil = disabled.
    ///   - allIdleTimeout: Fire event if no read AND no write. nil = disabled.
    public init(readTimeout: TimeAmount? = nil,
                writeTimeout: TimeAmount? = nil,
                allIdleTimeout: TimeAmount? = nil) {
        self.readTimeout = readTimeout
        self.writeTimeout = writeTimeout
        self.allIdleTimeout = allIdleTimeout
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        scheduleAll(context: context)
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        cancelAll()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        readFired = false
        allFired = false
        resetReadTimer(context: context)
        resetAllIdleTimer(context: context)
        context.fireChannelRead(data)
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        writeFired = false
        allFired = false
        resetWriteTimer(context: context)
        resetAllIdleTimer(context: context)
        context.write(data, promise: promise)
    }

    // MARK: - Timer Management

    private func scheduleAll(context: ChannelHandlerContext) {
        resetReadTimer(context: context)
        resetWriteTimer(context: context)
        resetAllIdleTimer(context: context)
    }

    private func cancelAll() {
        readTimer?.cancel()
        writeTimer?.cancel()
        allIdleTimer?.cancel()
    }

    private func resetReadTimer(context: ChannelHandlerContext) {
        readTimer?.cancel()
        guard let timeout = readTimeout else { return }
        readTimer = context.eventLoop.scheduleTask(in: timeout) { [weak self] in
            guard let self = self else { return }
            let event = IdleStateEvent(state: .read, isFirst: !self.readFired)
            self.readFired = true
            context.fireUserInboundEventTriggered(event)
        }
    }

    private func resetWriteTimer(context: ChannelHandlerContext) {
        writeTimer?.cancel()
        guard let timeout = writeTimeout else { return }
        writeTimer = context.eventLoop.scheduleTask(in: timeout) { [weak self] in
            guard let self = self else { return }
            let event = IdleStateEvent(state: .write, isFirst: !self.writeFired)
            self.writeFired = true
            context.fireUserInboundEventTriggered(event)
        }
    }

    private func resetAllIdleTimer(context: ChannelHandlerContext) {
        allIdleTimer?.cancel()
        guard let timeout = allIdleTimeout else { return }
        allIdleTimer = context.eventLoop.scheduleTask(in: timeout) { [weak self] in
            guard let self = self else { return }
            let event = IdleStateEvent(state: .all, isFirst: !self.allFired)
            self.allFired = true
            context.fireUserInboundEventTriggered(event)
        }
    }
}

// MARK: - Read Timeout Handler

/// Closes the channel if no data is received within the timeout period.
public final class ReadTimeoutHandler: ChannelInboundHandler {
    public typealias InboundIn = NIOAny
    public typealias InboundOut = NIOAny

    private let timeout: TimeAmount
    private var timer: Scheduled<Void>?

    public init(timeout: TimeAmount) {
        self.timeout = timeout
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        resetTimer(context: context)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        resetTimer(context: context)
        context.fireChannelRead(data)
    }

    private func resetTimer(context: ChannelHandlerContext) {
        timer?.cancel()
        timer = context.eventLoop.scheduleTask(in: timeout) { [self] in
            context.fireErrorCaught(ChannelError.connectTimeout(self.timeout))
            context.close(promise: nil)
        }
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        timer?.cancel()
    }
}
