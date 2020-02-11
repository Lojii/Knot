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
import NIOConcurrencyHelpers


/// The various channel options specific to `HTTP2StreamChannel`s.
///
/// Please note that some of NIO's regular `ChannelOptions` are valid on `HTTP2StreamChannel`s.
public struct HTTP2StreamChannelOptions {
    /// - seealso: `StreamIDOption`.
    public static let streamID: HTTP2StreamChannelOptions.Types.StreamIDOption = .init()
}

extension HTTP2StreamChannelOptions {
    public enum Types {}
}

@available(*, deprecated, renamed: "HTTP2StreamChannelOptions.Types.StreamIDOption")
public typealias StreamIDOption = HTTP2StreamChannelOptions.Types.StreamIDOption

extension HTTP2StreamChannelOptions.Types {
    /// `StreamIDOption` allows users to query the stream ID for a given `HTTP2StreamChannel`.
    ///
    /// On active `HTTP2StreamChannel`s, it is possible that a channel handler or user may need to know which
    /// stream ID the channel owns. This channel option allows that query. Please note that this channel option
    /// is *get-only*: that is, it cannot be used with `setOption`. The stream ID for a given `HTTP2StreamChannel`
    /// is immutable.
    public struct StreamIDOption: ChannelOption {
        public typealias Value = HTTP2StreamID

        public init() { }
    }
}

/// The current state of a stream channel.
private enum StreamChannelState {
    /// The stream has been created, but not configured.
    case idle

    /// The is "active": we haven't sent channelActive yet, but it exists on the network and any shutdown must cause a frame to be emitted.
    case remoteActive

    /// This is also "active", but different to the above: we've sent channelActive, but the NIOHTTP2Handler hasn't seen the frame yet,
    /// and so we can close this channel without action if needed.
    case localActive

    /// This is actually active: channelActive has been fired and the HTTP2Handler believes this stream exists.
    case active

    /// We are closing from a state where channelActive had been fired. In practice this is only ever active, as
    /// in localActive we transition directly to closed.
    case closing

    /// We're closing from a state where we have never fired channel active, but where the channel was on the network.
    /// This means we need to send frames and wait for their side effects.
    case closingNeverActivated

    /// We're fully closed.
    case closed

    mutating func activate() {
        switch self {
        case .idle:
            self = .localActive
        case .remoteActive:
            self = .active
        case .localActive, .active, .closing, .closingNeverActivated, .closed:
            preconditionFailure("Became active from state \(self)")
        }
    }

    mutating func networkActive() {
        switch self {
        case .idle:
            self = .remoteActive
        case .localActive:
            self = .active
        case .closed:
            preconditionFailure("Stream must be reset on network activation when closed")
        case .remoteActive, .active, .closing, .closingNeverActivated:
            preconditionFailure("Cannot become network active twice, in state \(self)")
        }
    }

    mutating func beginClosing() {
        switch self {
        case .active, .closing:
            self = .closing
        case .closingNeverActivated, .remoteActive:
            self = .closingNeverActivated
        case .idle, .localActive:
            preconditionFailure("Idle streams immediately close")
        case .closed:
            preconditionFailure("Cannot begin closing while closed")
        }
    }

    mutating func completeClosing() {
        switch self {
        case .idle, .remoteActive, .closing, .closingNeverActivated, .active, .localActive:
            self = .closed
        case .closed:
            preconditionFailure("Complete closing from \(self)")
        }
    }
}


final class HTTP2StreamChannel: Channel, ChannelCore {
    internal init(allocator: ByteBufferAllocator,
                  parent: Channel,
                  multiplexer: HTTP2StreamMultiplexer,
                  streamID: HTTP2StreamID,
                  targetWindowSize: Int32,
                  outboundBytesHighWatermark: Int,
                  outboundBytesLowWatermark: Int) {
        self.allocator = allocator
        self.closePromise = parent.eventLoop.makePromise()
        self.localAddress = parent.localAddress
        self.remoteAddress = parent.remoteAddress
        self.parent = parent
        self.eventLoop = parent.eventLoop
        self.streamID = streamID
        self.multiplexer = multiplexer
        self.windowManager = InboundWindowManager(targetSize: Int32(targetWindowSize))
        self._isWritable = Atomic(value: true)
        self.state = .idle
        self.writabilityManager = StreamChannelFlowController(highWatermark: outboundBytesHighWatermark,
                                                              lowWatermark: outboundBytesLowWatermark,
                                                              parentIsWritable: parent.isWritable)

        // To begin with we initialize autoRead to false, but we are going to fetch it from our parent before we
        // go much further.
        self.autoRead = false
        self._pipeline = ChannelPipeline(channel: self)
    }

    internal func configure(initializer: ((Channel, HTTP2StreamID) -> EventLoopFuture<Void>)?, userPromise promise: EventLoopPromise<Channel>?){
        // We need to configure this channel. This involves doing four things:
        // 1. Setting our autoRead state from the parent
        // 2. Calling the initializer, if provided.
        // 3. Activating when complete.
        // 4. Catching errors if they occur.
        let f = self.parent!.getOption(ChannelOptions.autoRead).flatMap { autoRead -> EventLoopFuture<Void> in
            self.autoRead = autoRead
            return initializer?(self, self.streamID) ?? self.eventLoop.makeSucceededFuture(())
        }.map {
            // This force unwrap is safe as parent is assigned in the initializer, and never unassigned.
            // If parent is not active, we expect to receive a channelActive later.
            if self.parent!.isActive {
                self.performActivation()
            }

            // We aren't using cascade here to avoid the allocations it causes.
            promise?.succeed(self)
        }

        f.whenFailure { (error: Error) in
            if self.state != .idle {
                self.closedWhileOpen()
            } else {
                self.errorEncountered(error: error)
            }

            promise?.fail(error)
        }
    }

    /// Activates this channel.
    internal func performActivation() {
        precondition(self.parent?.isActive ?? false, "Parent must be active to activate the child")

        if self.state == .closed || self.state == .closingNeverActivated {
            // We're already closed, or we've been asked to close and are waiting for the network.
            // No need to activate in either case
            return
        }

        self.state.activate()
        self.pipeline.fireChannelActive()
        if self.autoRead {
            self.read0()
        }
        self.deliverPendingWrites()
    }

    internal func networkActivationReceived() {
        if self.state == .closed {
            // Uh-oh: we got an activation but we think we're closed! We need to send a RST_STREAM frame.
            let resetFrame = HTTP2Frame(streamID: self.streamID, payload: .rstStream(.cancel))
            self.parent?.writeAndFlush(resetFrame, promise: nil)
            return
        }
        self.state.networkActive()

        if self.writabilityManager.isWritable != self._isWritable.load() {
            // We have probably delayed telling the user that this channel isn't writable, but we should do
            // it now.
            self._isWritable.store(self.writabilityManager.isWritable)
            self.pipeline.fireChannelWritabilityChanged()
        }

        // If we got here, we may need to flush some pending reads. Notably we don't call read0 here as
        // we don't actually want to start reading before activation, which tryToRead will refuse to do.
        if self.pendingReads.count > 0 {
            self.tryToRead()
        }
    }

    private var _pipeline: ChannelPipeline!

    public let allocator: ByteBufferAllocator

    private let closePromise: EventLoopPromise<()>

    private let multiplexer: HTTP2StreamMultiplexer

    public var closeFuture: EventLoopFuture<Void> {
        return self.closePromise.futureResult
    }

    public var pipeline: ChannelPipeline {
        return self._pipeline
    }

    public let localAddress: SocketAddress?

    public let remoteAddress: SocketAddress?

    public let parent: Channel?

    func localAddress0() throws -> SocketAddress {
        fatalError()
    }

    func remoteAddress0() throws -> SocketAddress {
        fatalError()
    }

    func setOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> EventLoopFuture<Void> {
        if eventLoop.inEventLoop {
            do {
                return eventLoop.makeSucceededFuture(try setOption0(option, value: value))
            } catch {
                return eventLoop.makeFailedFuture(error)
            }
        } else {
            return eventLoop.submit { try self.setOption0(option, value: value) }
        }
    }

    public func getOption<Option: ChannelOption>(_ option: Option) -> EventLoopFuture<Option.Value> {
        if eventLoop.inEventLoop {
            do {
                return eventLoop.makeSucceededFuture(try getOption0(option))
            } catch {
                return eventLoop.makeFailedFuture(error)
            }
        } else {
            return eventLoop.submit { try self.getOption0(option) }
        }
    }

    private func setOption0<Option: ChannelOption>(_ option: Option, value: Option.Value) throws {
        assert(eventLoop.inEventLoop)

        switch option {
        case _ as ChannelOptions.Types.AutoReadOption:
            self.autoRead = value as! Bool
        default:
            fatalError("setting option \(option) on HTTP2StreamChannel not supported")
        }
    }

    private func getOption0<Option: ChannelOption>(_ option: Option) throws -> Option.Value {
        assert(eventLoop.inEventLoop)

        switch option {
        case _ as HTTP2StreamChannelOptions.Types.StreamIDOption:
            return self.streamID as! Option.Value
        case _ as ChannelOptions.Types.AutoReadOption:
            return self.autoRead as! Option.Value
        default:
            fatalError("option \(option) not supported on HTTP2StreamChannel")
        }
    }

    public var isWritable: Bool {
        return self._isWritable.load()
    }

    private let _isWritable: Atomic<Bool>

    public var isActive: Bool {
        return self.state == .active || self.state == .closing || self.state == .localActive
    }

    public var _channelCore: ChannelCore {
        return self
    }

    public let eventLoop: EventLoop

    private let streamID: HTTP2StreamID

    private var state: StreamChannelState

    private var windowManager: InboundWindowManager

    /// If close0 was called but the stream could not synchronously close (because it's currently
    /// active), the promise is stored here until it can be fulfilled.
    private var pendingClosePromise: EventLoopPromise<Void>?

    /// A buffer of pending inbound reads delivered from the parent channel.
    ///
    /// In the future this buffer will be used to manage interactions with read() and even, one day,
    /// with flow control. For now, though, all this does is hold frames until we have set the
    /// channel up.
    private var pendingReads: CircularBuffer<HTTP2Frame> = CircularBuffer(initialCapacity: 8)

    /// Whether `autoRead` is enabled. By default, all `HTTP2StreamChannel` objects inherit their `autoRead`
    /// state from their parent.
    private var autoRead: Bool

    /// Whether a call to `read` has happened without any frames available to read (that is, whether newly
    /// received frames should be immediately delivered to the pipeline).
    private var unsatisfiedRead: Bool = false

    /// A buffer of pending outbound writes to deliver to the parent channel.
    ///
    /// To correctly respect flushes, we deliberately withold frames from the parent channel until this
    /// stream is flushed, at which time we deliver them all. This buffer holds the pending ones.
    private var pendingWrites: MarkedCircularBuffer<(HTTP2Frame, EventLoopPromise<Void>?)> = MarkedCircularBuffer(initialCapacity: 8)

    /// A list node used to hold stream channels.
    internal var streamChannelListNode: StreamChannelListNode = StreamChannelListNode()

    /// An object that controls whether this channel should be writable.
    private var writabilityManager: StreamChannelFlowController

    public func register0(promise: EventLoopPromise<Void>?) {
        fatalError("not implemented \(#function)")
    }

    public func bind0(to: SocketAddress, promise: EventLoopPromise<Void>?) {
        fatalError("not implemented \(#function)")
    }

    public func connect0(to: SocketAddress, promise: EventLoopPromise<Void>?) {
        fatalError("not implemented \(#function)")
    }

    public func write0(_ data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard self.state != .closed else {
            promise?.fail(ChannelError.ioOnClosedChannel)
            return
        }

        let frame = self.unwrapData(data, as: HTTP2Frame.self)

        // We need a promise to attach our flow control callback to.
        // Regardless of whether the write succeeded or failed, we don't count
        // the bytes any longer.
        let promise = promise ?? self.eventLoop.makePromise()
        let writeSize = frame.bufferBytes

        // Right now we deal with this math by just attaching a callback to all promises. This is going
        // to be annoyingly expensive, but for now it's the most straightforward approach.
        promise.futureResult.hop(to: self.eventLoop).whenComplete { (_: Result<Void, Error>) in
            if case .changed(newValue: let value) = self.writabilityManager.wroteBytes(writeSize) {
                self.changeWritability(to: value)
            }
        }
        self.pendingWrites.append((frame, promise))

        // Ok, we can make an outcall now, which means we can safely deal with the flow control.
        if case .changed(newValue: let value) = self.writabilityManager.bufferedBytes(writeSize) {
            self.changeWritability(to: value)
        }
    }

    public func flush0() {
        self.pendingWrites.mark()

        if self.isActive {
            self.deliverPendingWrites()
        }
    }

    public func read0() {
        if self.unsatisfiedRead {
            // We already have an unsatisfied read, let's do nothing.
            return
        }

        // At this stage, we have an unsatisfied read. If there is no pending data to read,
        // we're going to call read() on the parent channel. Otherwise, we're going to
        // succeed the read out of our pending data.
        self.unsatisfiedRead = true
        if self.pendingReads.count > 0 {
            self.tryToRead()
        } else {
            self.parent?.read()
        }
    }

    public func close0(error: Error, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        // If the stream is already closed, we can fail this early and abort processing. If it's not, we need to emit a
        // RST_STREAM frame.
        guard self.state != .closed else {
            promise?.fail(ChannelError.alreadyClosed)
            return
        }

        // Store the pending close promise: it'll be succeeded later.
        if let promise = promise {
            if let pendingPromise = self.pendingClosePromise {
                pendingPromise.futureResult.cascade(to: promise)
            } else {
                self.pendingClosePromise = promise
            }
        }

        switch self.state {
        case .idle, .localActive, .closed:
            // The stream isn't open on the network, just go straight to closed cleanly.
            self.closedCleanly()
        case .remoteActive, .active, .closing, .closingNeverActivated:
            // In all of these states the stream is still on the network and we need to wait.
            self.closedWhileOpen()
        }
    }

    public func triggerUserOutboundEvent0(_ event: Any, promise: EventLoopPromise<Void>?) {
        // do nothing
    }

    public func channelRead0(_ data: NIOAny) {
        // do nothing
    }

    public func errorCaught0(error: Error) {
        // do nothing
    }

    /// Called when the channel was closed from the pipeline while the stream is still open.
    ///
    /// Will emit a RST_STREAM frame in order to close the stream. Note that this function does not
    /// directly close the stream: it waits until the stream closed notification is fired.
    private func closedWhileOpen() {
        precondition(self.state != .closed)
        guard self.state != .closing else {
            // If we're already closing, nothing to do here.
            return
        }

        self.state.beginClosing()
        let resetFrame = HTTP2Frame(streamID: self.streamID, payload: .rstStream(.cancel))
        self.receiveOutboundFrame(resetFrame, promise: nil)
        self.multiplexer.childChannelFlush()
    }

    private func closedCleanly() {
        guard self.state != .closed else {
            return
        }
        self.state.completeClosing()
        self.dropPendingReads()
        self.failPendingWrites(error: ChannelError.eof)
        if let promise = self.pendingClosePromise {
            self.pendingClosePromise = nil
            promise.succeed(())
        }
        self.pipeline.fireChannelInactive()

        self.eventLoop.execute {
            self.removeHandlers(channel: self)
            self.closePromise.succeed(())
            self.multiplexer.childChannelClosed(streamID: self.streamID)
        }
    }

    fileprivate func errorEncountered(error: Error) {
        guard self.state != .closed else {
            return
        }
        self.state.completeClosing()
        self.dropPendingReads()
        self.failPendingWrites(error: error)
        if let promise = self.pendingClosePromise {
            self.pendingClosePromise = nil
            promise.fail(error)
        }
        self.pipeline.fireErrorCaught(error)
        self.pipeline.fireChannelInactive()

        self.eventLoop.execute {
            self.removeHandlers(channel: self)
            self.closePromise.fail(error)
            self.multiplexer.childChannelClosed(streamID: self.streamID)
        }
    }

    private func tryToRead() {
        // If there's no read to satisfy, no worries about it.
        guard self.unsatisfiedRead else {
            return
        }

        // If we're not active, we will hold on to these reads.
        guard self.isActive else {
            return
        }

        // Ok, we're satisfying a read here.
        self.unsatisfiedRead = false
        self.deliverPendingReads()

        // If auto-read is turned on, recurse into read0.
        // This cannot recurse indefinitely unless frames are being delivered
        // by the read stacks, which is generally fairly unlikely to continue unbounded.
        if self.autoRead {
            self.read0()
        }
    }

    private func changeWritability(to newWritability: Bool) {
        self._isWritable.store(newWritability)
        self.pipeline.fireChannelWritabilityChanged()
    }
}

// MARK:- Functions used to manage pending reads and writes.
private extension HTTP2StreamChannel {
    /// Drop all pending reads.
    private func dropPendingReads() {
        /// To drop all the reads, as we don't need to report it, we just allocate a new buffer of 0 size.
        self.pendingReads = CircularBuffer(initialCapacity: 0)
    }

    /// DinitialCapacityreads to the channel.
    private func deliverPendingReads() {
        assert(self.isActive)
        while self.pendingReads.count > 0 {
            self.pipeline.fireChannelRead(NIOAny(self.pendingReads.removeFirst()))
        }
        self.pipeline.fireChannelReadComplete()
    }

    /// Delivers all pending flushed writes to the parent channel.
    private func deliverPendingWrites() {
        // If there are no pending writes, don't bother with the processing.
        guard self.pendingWrites.hasMark else {
            return
        }

        while self.pendingWrites.hasMark {
            let write = self.pendingWrites.removeFirst()
            self.receiveOutboundFrame(write.0, promise: write.1)
        }
        self.multiplexer.childChannelFlush()
    }

    /// Fails all pending writes with the given error.
    private func failPendingWrites(error: Error) {
        assert(self.state == .closed)
        while self.pendingWrites.count > 0 {
            self.pendingWrites.removeFirst().1?.fail(error)
        }
    }
}

// MARK:- Functions used to communicate between the `HTTP2StreamMultiplexer` and the `HTTP2StreamChannel`.
internal extension HTTP2StreamChannel {
    /// Called when a frame is received from the network.
    ///
    /// - parameters:
    ///     - frame: The `HTTP2Frame` received from the network.
    func receiveInboundFrame(_ frame: HTTP2Frame) {
        guard self.state != .closed else {
            // Do nothing
            return
        }

        if self.unsatisfiedRead {
            self.pipeline.fireChannelRead(NIOAny(frame))
        } else {
            self.pendingReads.append(frame)
        }
    }


    /// Called when a frame is sent to the network.
    ///
    /// - parameters:
    ///     - frame: The `HTTP2Frame` to send to the network.
    ///     - promise: The promise associated with the frame write.
    private func receiveOutboundFrame(_ frame: HTTP2Frame, promise: EventLoopPromise<Void>?) {
        guard self.state != .closed else {
            let error = ChannelError.alreadyClosed
            promise?.fail(error)
            self.errorEncountered(error: error)
            return
        }
        self.multiplexer.childChannelWrite(frame, promise: promise)
    }

    /// Called when a stream closure is received from the network.
    ///
    /// - parameters:
    ///     - reason: The reason received from the network, if any.
    func receiveStreamClosed(_ reason: HTTP2ErrorCode?) {
        // The stream is closed, we should aim to deliver any read frames we have for it.
        self.tryToRead()

        if let reason = reason {
            let err = NIOHTTP2Errors.StreamClosed(streamID: self.streamID, errorCode: reason)
            self.errorEncountered(error: err)
        } else {
            self.closedCleanly()
        }
    }

    func receiveWindowUpdatedEvent(_ windowSize: Int) {
        if let increment = self.windowManager.newWindowSize(windowSize) {
            let frame = HTTP2Frame(streamID: self.streamID, payload: .windowUpdate(windowSizeIncrement: increment))
            self.receiveOutboundFrame(frame, promise: nil)
            // This flush should really go away, but we need it for now until we sort out window management.
            self.multiplexer.childChannelFlush()
        }
    }

    func initialWindowSizeChanged(delta: Int) {
        if let increment = self.windowManager.initialWindowSizeChanged(delta: delta) {
            let frame = HTTP2Frame(streamID: self.streamID, payload: .windowUpdate(windowSizeIncrement: increment))
            self.receiveOutboundFrame(frame, promise: nil)
            // This flush should really go away, but we need it for now until we sort out window management.
            self.multiplexer.childChannelFlush()
        }
    }

    func receiveParentChannelReadComplete() {
        self.tryToRead()
    }

    func parentChannelWritabilityChanged(newValue: Bool) {
        // There's a trick here that's worth noting: if the child channel hasn't either sent a frame
        // or been activated on the network, we don't actually want to change the observable writability.
        // This is because in this case we really want user code to send a frame as soon as possible to avoid
        // issues with their stream ID becoming out of date. Once the state transitions we can update
        // the writability if needed.
        guard case .changed(newValue: let localValue) = self.writabilityManager.parentWritabilityChanged(newValue) else {
            return
        }

        // Ok, the writability changed.
        switch self.state {
        case .idle, .localActive:
            // Do nothing here.
            return
        case .remoteActive, .active, .closing, .closingNeverActivated, .closed:
            self._isWritable.store(localValue)
            self.pipeline.fireChannelWritabilityChanged()
        }
    }
}

extension HTTP2Frame {
    /// A shorthand heuristic for how many bytes we assume a frame consumes on the wire.
    ///
    /// Here we concern ourselves only with per-stream frames: that is, `HEADERS`, `DATA`,
    /// `WINDOW_UDPATE`, `RST_STREAM`, and I guess `PRIORITY`. As a simple heuristic we
    /// hard code fixed lengths for fixed length frames, use a calculated length for
    /// variable length frames, and just ignore encoded headers because it's not worth doing a better
    /// job.
    fileprivate var bufferBytes: Int {
        let frameHeaderSize = 9

        switch self.payload {
        case .data(let d):
            let paddingBytes = d.paddingBytes.map { $0 + 1 } ?? 0
            return d.data.readableBytes + paddingBytes + frameHeaderSize
        case .headers(let h):
            let paddingBytes = h.paddingBytes.map { $0 + 1 } ?? 0
            return paddingBytes + frameHeaderSize
        case .priority:
            return frameHeaderSize + 5
        case .pushPromise(let p):
            // Like headers, this is variably size, and we just ignore the encoded headers because
            // it's not worth having a heuristic.
            let paddingBytes = p.paddingBytes.map { $0 + 1 } ?? 0
            return paddingBytes + frameHeaderSize
        case .rstStream:
            return frameHeaderSize + 4
        case .windowUpdate:
            return frameHeaderSize + 4
        default:
            // Unknown or unexpected control frame: say 9 bytes.
            return frameHeaderSize
        }
    }
}
