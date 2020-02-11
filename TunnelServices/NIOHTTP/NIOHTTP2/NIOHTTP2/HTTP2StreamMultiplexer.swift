//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO

/// A channel handler that creates a child channel for each HTTP/2 stream.
///
/// In general in NIO applications it is helpful to consider each HTTP/2 stream as an
/// independent stream of HTTP/2 frames. This multiplexer achieves this by creating a
/// number of in-memory `HTTP2StreamChannel` objects, one for each stream. These operate
/// on `HTTP2Frame` objects as their base communication atom, as opposed to the regular
/// NIO `SelectableChannel` objects which use `ByteBuffer` and `IOData`.
public final class HTTP2StreamMultiplexer: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = HTTP2Frame
    public typealias InboundOut = HTTP2Frame
    public typealias OutboundIn = HTTP2Frame
    public typealias OutboundOut = HTTP2Frame

    private var streams: [HTTP2StreamID: HTTP2StreamChannel] = [:]
    private let inboundStreamStateInitializer: ((Channel, HTTP2StreamID) -> EventLoopFuture<Void>)?
    private let channel: Channel
    private var context: ChannelHandlerContext!
    private var nextOutboundStreamID: HTTP2StreamID
    private var connectionFlowControlManager: InboundWindowManager
    private var flushState: FlushState = .notReading
    private var didReadChannels: StreamChannelList = StreamChannelList()
    private let streamChannelOutboundBytesHighWatermark: Int
    private let streamChannelOutboundBytesLowWatermark: Int

    public func handlerAdded(context: ChannelHandlerContext) {
        // We now need to check that we're on the same event loop as the one we were originally given.
        // If we weren't, this is a hard failure, as there is a thread-safety issue here.
        self.channel.eventLoop.preconditionInEventLoop()
        self.context = context
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.didReadChannels.removeAll()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        let streamID = frame.streamID

        self.flushState.startReading()

        guard streamID != .rootStream else {
            // For stream 0 we forward all frames on to the main channel.
            context.fireChannelRead(data)
            return
        }

        if case .priority = frame.payload {
            // Priority frames are special cases, and are always forwarded to the parent stream.
            context.fireChannelRead(data)
            return
        }

        if let channel = streams[streamID] {
            channel.receiveInboundFrame(frame)
            if !channel.inList {
                self.didReadChannels.append(channel)
            }
        } else if case .headers = frame.payload {
            let channel = HTTP2StreamChannel(allocator: self.channel.allocator,
                                             parent: self.channel,
                                             multiplexer: self,
                                             streamID: streamID,
                                             targetWindowSize: 65535,
                                             outboundBytesHighWatermark: self.streamChannelOutboundBytesHighWatermark,
                                             outboundBytesLowWatermark: self.streamChannelOutboundBytesLowWatermark)
            self.streams[streamID] = channel
            channel.configure(initializer: self.inboundStreamStateInitializer, userPromise: nil)
            channel.receiveInboundFrame(frame)

            if !channel.inList {
                self.didReadChannels.append(channel)
            }
        } else {
            // This frame is for a stream we know nothing about. We can't do much about it, so we
            // are going to fire an error and drop the frame.
            let error = NIOHTTP2Errors.NoSuchStream(streamID: streamID)
            context.fireErrorCaught(error)
        }
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        // Call channelReadComplete on the children until this has been propagated enough.
        while let channel = self.didReadChannels.removeFirst() {
            channel.receiveParentChannelReadComplete()
        }

        if case .flushPending = self.flushState {
            self.flushState = .notReading
            context.flush()
        } else {
            self.flushState = .notReading
        }

        context.fireChannelReadComplete()
    }

    public func flush(context: ChannelHandlerContext) {
        switch self.flushState {
        case .reading, .flushPending:
            self.flushState = .flushPending
        case .notReading:
            context.flush()
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        /* for now just forward */
        context.write(data, promise: promise)
    }

    public func channelActive(context: ChannelHandlerContext) {
        // We just got channelActive. Any previously existing channels may be marked active.
        for channel in self.streams.values {
            // We double-check the channel activity here, because it's possible action taken during
            // the activation of one of the child channels will cause the parent to close!
            if context.channel.isActive {
                channel.performActivation()
            }
        }
        context.fireChannelActive()
    }

    public func channelInactive(context: ChannelHandlerContext) {
        for channel in self.streams.values {
            channel.receiveStreamClosed(nil)
        }
        context.fireChannelInactive()
    }

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let evt as StreamClosedEvent:
            if let channel = self.streams[evt.streamID] {
                channel.receiveStreamClosed(evt.reason)
            }
        case let evt as NIOHTTP2WindowUpdatedEvent where evt.streamID == .rootStream:
            // This force-unwrap is safe: we always have a connection window.
            self.newConnectionWindowSize(newSize: evt.inboundWindowSize!, context: context)
        case let evt as NIOHTTP2WindowUpdatedEvent:
            if let channel = self.streams[evt.streamID], let windowSize = evt.inboundWindowSize {
                channel.receiveWindowUpdatedEvent(windowSize)
            }
        case let evt as NIOHTTP2BulkStreamWindowChangeEvent:
            // Here we need to pull the channels out so we aren't holding the streams dict mutably. This is because it
            // will trigger an overlapping access violation if we do.
            let channels = self.streams.values
            for channel in channels {
                channel.initialWindowSizeChanged(delta: evt.delta)
            }
        case let evt as NIOHTTP2StreamCreatedEvent:
            if let channel = self.streams[evt.streamID] {
                channel.networkActivationReceived()
            }
        default:
            break
        }

        context.fireUserInboundEventTriggered(event)
    }

    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        for channel in self.streams.values {
            channel.parentChannelWritabilityChanged(newValue: context.channel.isWritable)
        }

        context.fireChannelWritabilityChanged()
    }

    private func newConnectionWindowSize(newSize: Int, context: ChannelHandlerContext) {
        guard let increment = self.connectionFlowControlManager.newWindowSize(newSize) else {
            return
        }

        // This is too much flushing, but for now it'll have to do.
        let frame = HTTP2Frame(streamID: .rootStream, payload: .windowUpdate(windowSizeIncrement: increment))
        context.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)
    }

    /// Create a new `HTTP2StreamMultiplexer`.
    ///
    /// - parameters:
    ///     - mode: The mode of the HTTP/2 connection being used: server or client.
    ///     - channel: The Channel to which this `HTTP2StreamMultiplexer` belongs.
    ///     - targetWindowSize: The target inbound connection and stream window size. Defaults to 65535 bytes.
    ///     - inboundStreamStateInitializer: A block that will be invoked to configure each new child stream
    ///         channel that is created by the remote peer. For servers, these are channels created by
    ///         receiving a `HEADERS` frame from a client. For clients, these are channels created by
    ///         receiving a `PUSH_PROMISE` frame from a server. To initiate a new outbound channel, use
    ///         `createStreamChannel`.
    public convenience init(mode: NIOHTTP2Handler.ParserMode, channel: Channel, targetWindowSize: Int = 65535, inboundStreamStateInitializer: ((Channel, HTTP2StreamID) -> EventLoopFuture<Void>)? = nil) {
        // We default to an 8kB outbound buffer size: this is a good trade off for avoiding excessive buffering while ensuring that decent
        // throughput can be maintained. We use 4kB as the low water mark.
        self.init(mode: mode,
                  channel: channel,
                  targetWindowSize: targetWindowSize,
                  outboundBufferSizeHighWatermark: 8192,
                  outboundBufferSizeLowWatermark: 4096,
                  inboundStreamStateInitializer: inboundStreamStateInitializer)
    }

    /// Create a new `HTTP2StreamMultiplexer`.
    ///
    /// - parameters:
    ///     - mode: The mode of the HTTP/2 connection being used: server or client.
    ///     - channel: The Channel to which this `HTTP2StreamMultiplexer` belongs.
    ///     - targetWindowSize: The target inbound connection and stream window size. Defaults to 65535 bytes.
    ///     - outboundBufferSizeHighWatermark: The high watermark for the number of bytes of writes that are
    ///         allowed to be un-sent on any child stream. This is broadly analogous to a regular socket send buffer.
    ///     - outboundBufferSizeLowWatermark: The low watermark for the number of bytes of writes that are
    ///         allowed to be un-sent on any child stream. This is broadly analogous to a regular socket send buffer.
    ///     - inboundStreamStateInitializer: A block that will be invoked to configure each new child stream
    ///         channel that is created by the remote peer. For servers, these are channels created by
    ///         receiving a `HEADERS` frame from a client. For clients, these are channels created by
    ///         receiving a `PUSH_PROMISE` frame from a server. To initiate a new outbound channel, use
    ///         `createStreamChannel`.
    public init(mode: NIOHTTP2Handler.ParserMode,
                channel: Channel,
                targetWindowSize: Int = 65535,
                outboundBufferSizeHighWatermark: Int,
                outboundBufferSizeLowWatermark: Int,
                inboundStreamStateInitializer: ((Channel, HTTP2StreamID) -> EventLoopFuture<Void>)? = nil) {
        self.inboundStreamStateInitializer = inboundStreamStateInitializer
        self.channel = channel
        self.connectionFlowControlManager = InboundWindowManager(targetSize: Int32(targetWindowSize))
        self.streamChannelOutboundBytesHighWatermark = outboundBufferSizeHighWatermark
        self.streamChannelOutboundBytesLowWatermark = outboundBufferSizeLowWatermark

        switch mode {
        case .client:
            self.nextOutboundStreamID = 1
        case .server:
            self.nextOutboundStreamID = 2
        }
    }
}


extension HTTP2StreamMultiplexer {
    /// The state of the multiplexer for flush coalescing.
    ///
    /// The stream multiplexer aims to perform limited flush coalescing on the read side by delaying flushes from the child and
    /// parent channels until channelReadComplete is received. To do this we need to track what state we're in.
    enum FlushState {
        /// No channelReads have been fired since the last channelReadComplete, so we probably aren't reading. Let any
        /// flushes through.
        case notReading

        /// We've started reading, but don't have any pending flushes.
        case reading

        /// We're in the read loop, and have received a flush.
        case flushPending

        mutating func startReading() {
            if case .notReading = self {
                self = .reading
            }
        }
    }
}



extension HTTP2StreamMultiplexer {
    /// Create a new `Channel` for a new stream initiated by this peer.
    ///
    /// This method is intended for situations where the NIO application is initiating the stream. For clients,
    /// this is for all request streams. For servers, this is for pushed streams.
    ///
    /// - note:
    /// Resources for the stream will be freed after it has been closed.
    ///
    /// - parameters:
    ///     - promise: An `EventLoopPromise` that will be succeeded with the new activated channel, or
    ///         failed if an error occurs.
    ///     - streamStateInitializer: A callback that will be invoked to allow you to configure the
    ///         `ChannelPipeline` for the newly created channel.
    public func createStreamChannel(promise: EventLoopPromise<Channel>?, _ streamStateInitializer: @escaping (Channel, HTTP2StreamID) -> EventLoopFuture<Void>) {
        self.channel.eventLoop.execute {
            let streamID = self.nextOutboundStreamID
            self.nextOutboundStreamID = HTTP2StreamID(Int32(streamID) + 2)
            let channel = HTTP2StreamChannel(allocator: self.channel.allocator,
                                             parent: self.channel,
                                             multiplexer: self,
                                             streamID: streamID,
                                             targetWindowSize: 65535,  // TODO: make configurable
                                             outboundBytesHighWatermark: self.streamChannelOutboundBytesHighWatermark,
                                             outboundBytesLowWatermark: self.streamChannelOutboundBytesLowWatermark)
            self.streams[streamID] = channel
            channel.configure(initializer: streamStateInitializer, userPromise: promise)
        }
    }
}


// MARK:- Child to parent calls
extension HTTP2StreamMultiplexer {
    internal func childChannelClosed(streamID: HTTP2StreamID) {
        self.streams.removeValue(forKey: streamID)
    }

    internal func childChannelWrite(_ frame: HTTP2Frame, promise: EventLoopPromise<Void>?) {
        self.context.write(self.wrapOutboundOut(frame), promise: promise)
    }

    internal func childChannelFlush() {
        self.flush(context: context)
    }
}
