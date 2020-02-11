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
#if compiler(>=5.1) && compiler(<5.2)
@_implementationOnly import CNIOBoringSSL
#else
import CNIOBoringSSL
#endif
import NIOTLS

/// The base class for all NIOSSL handlers. This class cannot actually be instantiated by
/// users directly: instead, users must select which mode they would like their handler to
/// operate in, client or server.
///
/// This class exists to deal with the reality that for almost the entirety of the lifetime
/// of a TLS connection there is no meaningful distinction between a server and a client.
/// For this reason almost the entirety of the implementation for the channel and server
/// handlers in NIOSSL is shared, in the form of this parent class.
public class NIOSSLHandler : ChannelInboundHandler, ChannelOutboundHandler, RemovableChannelHandler {
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private enum ConnectionState {
        case idle
        case handshaking
        case active
        case unwrapping
        case closing(Scheduled<Void>)
        case unwrapped
        case closed
    }

    private var state: ConnectionState = .idle
    private var connection: SSLConnection
    private var plaintextReadBuffer: ByteBuffer?
    private var bufferedWrites: MarkedCircularBuffer<BufferedWrite>
    private var closePromise: EventLoopPromise<Void>?
    private var shutdownPromise: EventLoopPromise<Void>?
    private var didDeliverData: Bool = false
    private var storedContext: ChannelHandlerContext? = nil
    private var shutdownTimeout: TimeAmount
    
    internal init(connection: SSLConnection, shutdownTimeout: TimeAmount) {
        self.connection = connection
        self.bufferedWrites = MarkedCircularBuffer(initialCapacity: 96)  // 96 brings the total size of the buffer to just shy of one page
        self.shutdownTimeout = shutdownTimeout
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        self.storedContext = context
        self.connection.setAllocator(context.channel.allocator)
        self.connection.parentHandler = self
        self.connection.eventLoop = context.eventLoop
        
        self.plaintextReadBuffer = context.channel.allocator.buffer(capacity: SSL_MAX_RECORD_SIZE)
        // If this channel is already active, immediately begin handshaking.
        if context.channel.isActive {
            doHandshakeStep(context: context)
        }
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        /// Get the connection to drop any state it might have. This state can cause reference cycles,
        /// so we need to break those when we know it's safe to do so. This is a good safe point, as no
        /// further I/O can possibly occur.
        self.connection.close()

        // We now want to drop the stored context.
        self.storedContext = nil
    }

    public func channelActive(context: ChannelHandlerContext) {
        // We fire this a bit early, entirely on purpose. This is because
        // in doHandshakeStep we may end up closing the channel again, and
        // if we do we want to make sure that the channelInactive message received
        // by later channel handlers makes sense.
        context.fireChannelActive()
        doHandshakeStep(context: context)
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        // This fires when the TCP connection goes away. Whatever happens, we end up in the closed
        // state here. This function calls out to a lot of user code, so we need to make sure we're
        // keeping track of the state we're in properly before we do anything else.
        let oldState = state
        state = .closed

        switch oldState {
        case .closed, .idle:
            // Nothing to do, but discard any buffered writes we still have.
            discardBufferedWrites(reason: ChannelError.ioOnClosedChannel)
        default:
            // This is a ragged EOF: we weren't sent a CLOSE_NOTIFY. We want to send a user
            // event to notify about this before we propagate channelInactive. We also want to fail all
            // these writes.
            let shutdownPromise = self.shutdownPromise
            self.shutdownPromise = nil
            let closePromise = self.closePromise
            self.closePromise = nil

            shutdownPromise?.fail(NIOSSLError.uncleanShutdown)
            closePromise?.fail(NIOSSLError.uncleanShutdown)
            context.fireErrorCaught(NIOSSLError.uncleanShutdown)
            discardBufferedWrites(reason: NIOSSLError.uncleanShutdown)
        }

        context.fireChannelInactive()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let binaryData = unwrapInboundIn(data)
        
        // The logic: feed the buffers, then take an action based on state.
        connection.consumeDataFromNetwork(binaryData)
        
        switch state {
        case .handshaking:
            doHandshakeStep(context: context)
        case .active:
            doDecodeData(context: context)
            doUnbufferWrites(context: context)
        case .closing:
            doShutdownStep(context: context)
        case .unwrapping:
            self.doShutdownStep(context: context)
        default:
            context.fireErrorCaught(NIOSSLError.readInInvalidTLSState)
            channelClose(context: context, reason: NIOSSLError.readInInvalidTLSState)
        }
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        guard let receiveBuffer = self.plaintextReadBuffer else {
            preconditionFailure("channelReadComplete called before handlerAdded")
        }

        self.doFlushReadData(context: context, receiveBuffer: receiveBuffer, readOnEmptyBuffer: true)
        self.writeDataToNetwork(context: context, promise: nil)
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        bufferWrite(data: unwrapOutboundIn(data), promise: promise)
    }

    public func flush(context: ChannelHandlerContext) {
        bufferFlush()
        doUnbufferWrites(context: context)
    }
    
    public func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        guard mode == .all else {
            // TODO: Support also other modes ?
            promise?.fail(ChannelError.operationUnsupported)
            return
        }
        
        switch state {
        case .closing:
            // We're in the process of TLS shutdown, so let's let that happen. However,
            // we want to cascade the result of the first request into this new one.
            if let promise = promise, let closePromise = self.closePromise {
                closePromise.futureResult.cascade(to: promise)
            } else if let promise = promise {
                self.closePromise = promise
            }
        case .unwrapping:
            // We've been asked to close the connection, but we were currently unwrapping.
            // We don't have to send any CLOSE_NOTIFY, but we now need to upgrade ourselves:
            // closing is a more extreme activity than unwrapping.
            self.state = .closing(self.scheduleTimedOutShutdown(context: context))
            if let promise = promise, let closePromise = self.closePromise {
                closePromise.futureResult.cascade(to: promise)
            } else if let promise = promise {
                self.closePromise = promise
            }
        case .idle:
            state = .closed
            fallthrough
        case .closed, .unwrapped:
            // For idle, closed, and unwrapped connections we immediately pass this on to the next
            // channel handler.
            context.close(promise: promise)
        case .active, .handshaking:
            // We need to begin processing shutdown now. We can't fire the promise for a
            // while though.
            self.state = .closing(self.scheduleTimedOutShutdown(context: context))
            closePromise = promise
            doShutdownStep(context: context)
        }
    }

    /// Attempt to perform another stage of the TLS handshake.
    ///
    /// A TLS connection has a multi-step handshake that requires at least two messages sent by each
    /// peer. As a result, a handshake will never complete in a single call to BoringSSL. This method
    /// will call `doHandshake`, and will then attempt to write whatever data this generated to the
    /// network. If we are waiting on data from the remote peer, this method will do nothing.
    ///
    /// This method must not be called once the connection is established.
    private func doHandshakeStep(context: ChannelHandlerContext) {
        let result = connection.doHandshake()
        
        switch result {
        case .incomplete:
            state = .handshaking
            writeDataToNetwork(context: context, promise: nil)
        case .complete:
            do {
                try validateHostname(context: context)
            } catch {
                // This counts as a failure.
                context.fireErrorCaught(error)
                channelClose(context: context, reason: error)
                return
            }

            state = .active
            writeDataToNetwork(context: context, promise: nil)

            // TODO(cory): This event should probably fire out of the BoringSSL info callback.
            let negotiatedProtocol = connection.getAlpnProtocol()
            context.fireUserInboundEventTriggered(TLSUserEvent.handshakeCompleted(negotiatedProtocol: negotiatedProtocol))
            
            // We need to unbuffer any pending writes and reads. We will have pending writes if the user attempted to
            // write before we completed the handshake. We may also have pending reads if the user sent data immediately
            // after their FINISHED record. We decode the reads first, as those reads may trigger writes.
            self.doDecodeData(context: context)
            self.doUnbufferWrites(context: context)
        case .failed(let err):
            writeDataToNetwork(context: context, promise: nil)
            
            // TODO(cory): This event should probably fire out of the BoringSSL info callback.
            context.fireErrorCaught(NIOSSLError.handshakeFailed(err))
            channelClose(context: context, reason: NIOSSLError.handshakeFailed(err))
        }
    }

    /// Attempt to perform a stage of orderly TLS shutdown.
    ///
    /// Orderly TLS shutdown requires each peer to send a TLS CloseNotify message.
    /// This message is a signal that the data being sent has been completely sent,
    /// without truncation. Where possible we attempt to perform an orderly shutdown,
    /// and so we will send a CloseNotify. We also try to wait for the remote peer to
    /// send a CloseNotify in response. This means we may call this multiple times,
    /// potentially writing our own CloseNotify each time.
    ///
    /// Once `state` has transitioned to `.closed`, further calls to this method will
    /// do nothing.
    private func doShutdownStep(context: ChannelHandlerContext) {
        if case .closed = self.state {
            return
        }

        let result = connection.doShutdown()

        var uncleanScheduledShutdown: Scheduled<Void>?
        let targetCompleteState: ConnectionState
        switch self.state {
        case .closing(let scheduledShutdown):
            uncleanScheduledShutdown = scheduledShutdown
            targetCompleteState = .closed
        case .unwrapping:
            targetCompleteState = .unwrapped
        default:
            preconditionFailure("Shutting down in a non-shutting-down state")
        }
        
        switch result {
        case .incomplete:
            writeDataToNetwork(context: context, promise: nil)
        case .complete:
            uncleanScheduledShutdown?.cancel()
            self.state = targetCompleteState
            writeDataToNetwork(context: context, promise: nil)

            // TODO(cory): This should probably fire out of the BoringSSL info callback.
            context.fireUserInboundEventTriggered(TLSUserEvent.shutdownCompleted)

            switch targetCompleteState {
            case .closed:
                self.channelClose(context: context, reason: NIOTLSUnwrappingError.closeRequestedDuringUnwrap)
            case .unwrapped:
                self.channelUnwrap(context: context)
            default:
                preconditionFailure("Cannot be in \(targetCompleteState) at this code point")
            }
        case .failed(let err):
            uncleanScheduledShutdown?.cancel()
            // TODO(cory): This should probably fire out of the BoringSSL info callback.
            context.fireErrorCaught(NIOSSLError.shutdownFailed(err))
            channelClose(context: context, reason: NIOSSLError.shutdownFailed(err))
        }
    }

    /// Creates a scheduled task to perform an unclean shutdown in event of a clean shutdown timing
    /// out. This task should be cancelled if the shutdown does not time out.
    private func scheduleTimedOutShutdown(context: ChannelHandlerContext) -> Scheduled<Void> {
        return context.eventLoop.scheduleTask(in: self.shutdownTimeout) {
            self.state = .closed
            self.channelClose(context: context, reason: NIOSSLCloseTimedOutError())
        }
    }

    /// Loops over the `SSL` object, decoding encrypted application data until there is
    /// no more available.
    private func doDecodeData(context: ChannelHandlerContext) {
        guard var receiveBuffer = self.plaintextReadBuffer else {
            preconditionFailure("didDecodeData called without handlerAdded firing.")
        }

        // We nil the read buffer here. This is done on purpose: we do it to ensure
        // that we don't have two references to the buffer, otherwise readDataFromNetwork
        // will trigger a CoW every time. We need to put this back on every exit from this
        // function, or before any call-out, to avoid re-entrancy issues. We validate the
        // requirement for this being non-nil on exit at the very least.
        self.plaintextReadBuffer = nil
        defer {
            assert(self.plaintextReadBuffer != nil)
        }

        readLoop: while true {
            let result = connection.readDataFromNetwork(outputBuffer: &receiveBuffer)
            
            switch result {
            case .complete:
                // Good read. Keep going
                continue readLoop

            case .incomplete:
                self.plaintextReadBuffer = receiveBuffer
                break readLoop

            case .failed(BoringSSLError.zeroReturn):
                switch self.state {
                case .idle, .closed, .unwrapped, .handshaking:
                    preconditionFailure("Should not get zeroReturn in \(self.state)")
                case .active:
                    self.state = .closing(self.scheduleTimedOutShutdown(context: context))
                case .unwrapping, .closing:
                    break
                }

                // This is a clean EOF: we can just start doing our own clean shutdown.
                self.doFlushReadData(context: context, receiveBuffer: receiveBuffer, readOnEmptyBuffer: false)
                doShutdownStep(context: context)
                writeDataToNetwork(context: context, promise: nil)
                break readLoop

            case .failed(let err):
                self.state = .closed
                self.plaintextReadBuffer = receiveBuffer
                context.fireErrorCaught(err)
                channelClose(context: context, reason: err)
                break readLoop
            }
        }
    }

    /// Flushes any pending read plaintext. This is called whenever we hit a flush
    /// point for reads: either channelReadComplete, or we receive a CLOSE_NOTIFY.
    ///
    /// This function will always set the empty buffer back to be the plaintext read buffer.
    /// Do not do this in your own code.
    private func doFlushReadData(context: ChannelHandlerContext, receiveBuffer: ByteBuffer, readOnEmptyBuffer: Bool) {
        defer {
            // All exits from this function must restore the plaintext read buffer.
            assert(self.plaintextReadBuffer != nil)
        }

        // We only want to fire channelReadComplete in a situation where we have actually sent the user some data, otherwise
        // we'll be confusing the hell out of them.
        if receiveBuffer.writerIndex > receiveBuffer.readerIndex {
            // We need to be very careful here: we must not call out before we fix up our local view of this buffer. In this
            // case, we're going to set the indices back to where they were. In this case we are deliberately *not* calling
            // clear(), as we don't want to trigger a CoW for our own local refs.
            var ourNewBuffer = receiveBuffer
            ourNewBuffer.moveReaderIndex(to: 0)
            ourNewBuffer.moveWriterIndex(to: 0)
            self.plaintextReadBuffer = ourNewBuffer

            // Ok, we can now pass the receive buffer on and fire channelReadComplete.
            context.fireChannelRead(self.wrapInboundOut(receiveBuffer))
            context.fireChannelReadComplete()
        } else if readOnEmptyBuffer {
            // We didn't deliver data, but the channel is still active. If this channel has got
            // autoread turned off then we should call read again, because otherwise the user
            // will never see any result from their read call.
            self.plaintextReadBuffer = receiveBuffer
            context.channel.getOption(ChannelOptions.autoRead).whenSuccess { autoRead in
                if !autoRead {
                    context.read()
                }
            }
        } else {
            // Regardless of what happens here, we need to put the plaintext read buffer back. Very important.
            self.plaintextReadBuffer = receiveBuffer
        }
    }

    /// Encrypts application data and writes it to the channel.
    ///
    /// This method always flushes. For this reason, it should only ever be called when a flush
    /// is intended.
    private func writeDataToNetwork(context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) {
        // There may be no data to write, in which case we can just exit early.
        guard let dataToWrite = connection.getDataForNetwork() else {
            if let promise = promise {
                // If we have a promise, we need to enforce ordering so we issue a zero-length write that
                // the event loop will have to handle.
                let buffer = context.channel.allocator.buffer(capacity: 0)
                context.writeAndFlush(wrapInboundOut(buffer), promise: promise)
            }
            return
        }

        context.writeAndFlush(self.wrapInboundOut(dataToWrite), promise: promise)
    }

    /// Close the underlying channel.
    ///
    /// This method does not perform any kind of I/O. Instead, it simply calls ChannelHandlerContext.close with
    /// any promise we may have already been given. It also transitions our state into closed. This should only be
    /// used to clean up after an error, or to perform the final call to close after a clean shutdown attempt.
    private func channelClose(context: ChannelHandlerContext, reason: Error) {
        state = .closed

        let shutdownPromise = self.shutdownPromise
        self.shutdownPromise = nil

        let closePromise = self.closePromise
        self.closePromise = nil

        shutdownPromise?.fail(reason)
        context.close(promise: closePromise)
    }

    private func channelUnwrap(context: ChannelHandlerContext) {
        assert(self.closePromise == nil)
        self.state = .unwrapped

        let shutdownPromise = self.shutdownPromise
        self.shutdownPromise = nil

        // We create a promise here to make sure we operate in the special magic state
        // where we are not in the pipeline any more, but we still have a valid context.
        let removalPromise: EventLoopPromise<Void> = context.eventLoop.makePromise()
        let removalFuture = removalPromise.futureResult.map {
            // Now drop the writes.
            self.discardBufferedWrites(reason: NIOTLSUnwrappingError.unflushedWriteOnUnwrap)

            if let unconsumedData = self.connection.extractUnconsumedData() {
                context.fireChannelRead(self.wrapInboundOut(unconsumedData))
            }
        }

        if let promise = shutdownPromise {
            removalFuture.cascade(to: promise)
        }

        // Ok, we've unwrapped. Let's get out of the channel.
        context.channel.pipeline.removeHandler(context: context, promise: removalPromise)
    }

    /// Validates the hostname from the certificate against the hostname provided by
    /// the user, assuming one has been provided at all.
    private func validateHostname(context: ChannelHandlerContext) throws {
        guard connection.validateHostnames else {
            return
        }

        // If there is no remote address, something weird is happening here. We can't
        // validate a certificate without it, so bail.
        guard let ipAddress = context.channel.remoteAddress else {
            throw NIOSSLError.cannotFindPeerIP
        }

        try connection.validateHostname(address: ipAddress)
    }
}


// MARK:- Extension APIs for users.
extension NIOSSLHandler {
    /// Called to instruct this handler to perform an orderly TLS shutdown and then remove itself
    /// from the pipeline. This will leave the connection established, but remove the TLS wrapper
    /// from it.
    ///
    /// This will send a CLOSE_NOTIFY and wait for the corresponding CLOSE_NOTIFY. When that next
    /// CLOSE_NOTIFY is received, this handler will pass on all pending writes and remove itself
    /// from the channel pipeline.
    ///
    /// This function **is not thread-safe**: you **must** call it from the correct event
    /// loop thread.
    ///
    /// - parameters:
    ///     - promise: (optional) An `EventLoopPromise` that will be completed when the unwrapping has
    ///         completed.
    public func stopTLS(promise: EventLoopPromise<Void>?) {
        switch self.state {
        case .unwrapping, .closing:
            // We're shutting down here. Nothing has to be done, but we should keep track of this promise.
            if let promise = promise, let shutdownPromise = self.shutdownPromise {
                shutdownPromise.futureResult.cascade(to: promise)
            } else if let promise = promise {
                self.shutdownPromise = promise
            }

        case .idle:
            // We've never activated, it's easy to remove TLS from a connection that never had it.
            guard let storedContext = self.storedContext else {
                promise?.fail(NIOTLSUnwrappingError.invalidInternalState)
                return
            }

            self.state = .unwrapping
            self.shutdownPromise = promise
            self.channelUnwrap(context: storedContext)

        case .handshaking, .active:
            // Time to try to strip TLS.
            guard let storedContext = self.storedContext else {
                promise?.fail(NIOTLSUnwrappingError.invalidInternalState)
                return
            }

            self.state = .unwrapping
            self.shutdownPromise = promise
            self.doShutdownStep(context: storedContext)

        case .unwrapped:
            // We are already unwrapped. Succeed the promise, do nothing.
            promise?.succeed(())

        case .closed:
            promise?.fail(NIOTLSUnwrappingError.alreadyClosed)
        }
    }
}


// MARK: Code that handles buffering/unbuffering writes.
extension NIOSSLHandler {
    private typealias BufferedWrite = (data: ByteBuffer, promise: EventLoopPromise<Void>?)

    private func bufferWrite(data: ByteBuffer, promise: EventLoopPromise<Void>?) {
        bufferedWrites.append((data: data, promise: promise))
    }

    private func bufferFlush() {
        bufferedWrites.mark()
    }

    private func discardBufferedWrites(reason: Error) {
        self.bufferedWrites.forEachRemoving {
            $0.promise?.fail(reason)
        }
    }

    private func doUnbufferWrites(context: ChannelHandlerContext) {
        // Return early if the user hasn't called flush.
        guard bufferedWrites.hasMark else {
            return
        }

        // These are some annoying variables we use to persist state across invocations of
        // our closures. A better version of this code might be able to simplify this somewhat.
        var promises: [EventLoopPromise<Void>] = []
        var didWrite = false

        /// Given a byte buffer to encode, passes it to BoringSSL and handles the result.
        func encodeWrite(buf: inout ByteBuffer, promise: EventLoopPromise<Void>?) throws -> Bool {
            let result = connection.writeDataToNetwork(&buf)

            switch result {
            case .complete:
                didWrite = true
                if let promise = promise { promises.append(promise) }
                return true
            case .incomplete:
                // Ok, we can't write. Let's stop.
                return false
            case .failed(let err):
                // Once a write fails, all writes must fail. This includes prior writes
                // that successfully made it through BoringSSL.
                throw err
            }
        }

        func flushWrites() {
            let ourPromise: EventLoopPromise<Void> = context.eventLoop.makePromise()
            promises.forEach { ourPromise.futureResult.cascade(to: $0) }
            writeDataToNetwork(context: context, promise: ourPromise)
            promises = []
        }

        do {
            try bufferedWrites.forEachElementUntilMark { element in
                var data = element.data
                return try encodeWrite(buf: &data, promise: element.promise)
            }

            // If we got this far and did a write, we should shove the data out to the
            // network.
            if didWrite {
                flushWrites()
            }
        } catch {
            // We encountered an error, it's cleanup time. Close ourselves down.
            channelClose(context: context, reason: error)
            // Fail any writes we've previously encoded but not flushed.
            promises.forEach { $0.fail(error) }
            // Fail everything else.
            self.discardBufferedWrites(reason: error)
        }
    }
}

fileprivate extension MarkedCircularBuffer {
    mutating func forEachElementUntilMark(callback: (Element) throws -> Bool) rethrows {
        while try self.hasMark && callback(self.first!) {
            _ = self.removeFirst()
        }
    }

    mutating func forEachRemoving(callback: (Element) -> Void) {
        while self.count > 0 {
            callback(self.removeFirst())
        }
    }
}


// MARK:- Code for handling asynchronous handshake resumption.
extension NIOSSLHandler {
    internal func asynchronousCertificateVerificationComplete() {
        guard let storedContext = self.storedContext else {
            // Oh well, the connection is dead. Do nothing.
            return
        }

        self.doHandshakeStep(context: storedContext)
    }
}
