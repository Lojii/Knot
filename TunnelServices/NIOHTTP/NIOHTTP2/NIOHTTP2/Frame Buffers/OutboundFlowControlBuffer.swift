//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIO

/// A structure that manages buffering outbound frames for active streams to ensure that those streams do not violate flow control rules.
internal struct OutboundFlowControlBuffer {
    /// A buffer of the data sent on the stream that has not yet been passed to the the connection state machine.
    private var streamDataBuffers: [HTTP2StreamID: StreamFlowControlState]

    // TODO(cory): This will eventually need to grow into a priority implementation. For now, it's sufficient to just
    // use a set and worry about the data structure costs later.
    /// The streams with pending data to output.
    private var flushableStreams: Set<HTTP2StreamID> = Set()

    /// The current size of the connection flow control window. May be negative.
    internal var connectionWindowSize: Int

    /// The current value of SETTINGS_MAX_FRAME_SIZE set by the peer.
    internal var maxFrameSize: Int

    internal init(initialConnectionWindowSize: Int = 65535, initialMaxFrameSize: Int = 1<<14) {
        /// By and large there won't be that many concurrent streams floating around, so we pre-allocate a decent-ish
        /// size.
        // TODO(cory): HEAP! This should be a heap, sorted off the number of pending bytes!
        self.streamDataBuffers = Dictionary(minimumCapacity: 16)
        self.connectionWindowSize = initialConnectionWindowSize
        self.maxFrameSize = initialMaxFrameSize
    }

    internal mutating func processOutboundFrame(_ frame: HTTP2Frame, promise: EventLoopPromise<Void>?) throws -> OutboundFrameAction {
        // A side note: there is no special handling for RST_STREAM frames here, unlike in the concurrent streams buffer. This is because
        // RST_STREAM frames will cause stream closure notifications, which will force us to drop our buffers. For this reason we can
        // simplify our code here, which helps a lot.
        switch frame.payload {
        case .data(let body):
            // We buffer DATA frames.
            if !self.streamDataBuffers[frame.streamID].apply({ $0.dataBuffer.bufferWrite((.data(body), promise)) }) {
                // We don't have this stream ID. This is an internal error, but we won't precondition on it as
                // it can happen due to channel handler misconfiguration or other weirdness. We'll just complain.
                throw NIOHTTP2Errors.NoSuchStream(streamID: frame.streamID)
            }
            return .nothing
        case .headers(let headerContent):
            // Headers are special. If we have a data frame buffered, we buffer behind it to avoid frames
            // being reordered. However, if we don't have a data frame buffered we pass the headers frame on
            // immediately, as there is no risk of violating ordering guarantees.
            let bufferResult = self.streamDataBuffers[frame.streamID].modify { (state: inout StreamFlowControlState) -> Bool in
                if state.dataBuffer.haveBufferedDataFrame {
                    state.dataBuffer.bufferWrite((.headers(headerContent), promise))
                    return true
                } else {
                    return false
                }
            }

            switch bufferResult {
            case .some(true):
                // Buffered, do nothing.
                return .nothing
            case .some(false), .none:
                // We don't need to buffer this, pass it on.
                return .forward
            }
        default:
            // For all other frame types, we don't care about them, pass them on.
            return .forward
        }
    }

    internal mutating func flushReceived() {
        // Mark the flush points on all the streams we have.
        self.streamDataBuffers.mutatingForEachValue {
            let hadData = $0.hasPendingData
            $0.dataBuffer.markFlushPoint()
            if $0.hasPendingData && !hadData {
                assert(!self.flushableStreams.contains($0.streamID))
                self.flushableStreams.insert($0.streamID)
            }
        }
    }

    private func nextStreamToSend() -> HTTP2StreamID? {
        return self.flushableStreams.first
    }

    internal mutating func updateWindowOfStream(_ streamID: HTTP2StreamID, newSize: Int32) {
        assert(streamID != .rootStream)

        self.streamDataBuffers[streamID].apply {
            let hadData = $0.hasPendingData
            $0.currentWindowSize = Int(newSize)
            if $0.hasPendingData && !hadData {
                assert(!self.flushableStreams.contains($0.streamID))
                self.flushableStreams.insert($0.streamID)
            } else if !$0.hasPendingData && hadData {
                assert(self.flushableStreams.contains($0.streamID))
                self.flushableStreams.remove($0.streamID)
            }
        }
    }

    internal func invalidateBuffer(reason: ChannelError) {
        for buffer in self.streamDataBuffers.values {
            buffer.dataBuffer.failAllWrites(error: reason)
        }
    }

    internal mutating func streamCreated(_ streamID: HTTP2StreamID, initialWindowSize: UInt32) {
        assert(streamID != .rootStream)

        let streamState = StreamFlowControlState(streamID: streamID, initialWindowSize: Int(initialWindowSize))
        self.streamDataBuffers[streamID] = streamState
    }

    // We received a stream closed event. Drop any stream state we're holding.
    //
    // - returns: Any buffered stream state we may have been holding so their promises can be failed.
    internal mutating func streamClosed(_ streamID: HTTP2StreamID) -> MarkedCircularBuffer<(HTTP2Frame.FramePayload, EventLoopPromise<Void>?)>? {
        self.flushableStreams.remove(streamID)
        guard var streamData = self.streamDataBuffers.removeValue(forKey: streamID) else {
            // Huh, we didn't have any data for this stream. Oh well. That was easy.
            return nil
        }

        // To avoid too much work higher up the stack, we only return writes from here if there actually are any.
        let writes = streamData.dataBuffer.evacuatePendingWrites()
        if writes.count > 0 {
            return writes
        } else {
            return nil
        }
    }

    internal mutating func nextFlushedWritableFrame() -> (HTTP2Frame, EventLoopPromise<Void>?)? {
        // If the channel isn't writable, we don't want to send anything.
        guard let nextStreamID = self.nextStreamToSend(), self.connectionWindowSize > 0 else {
            return nil
        }

        let nextWrite = self.streamDataBuffers[nextStreamID].modify { (state: inout StreamFlowControlState) -> DataBuffer.BufferElement in
            let nextWrite = state.nextWrite(maxSize: min(self.connectionWindowSize, self.maxFrameSize))
            if !state.hasPendingData {
                self.flushableStreams.remove(nextStreamID)
            }
            return nextWrite
        }
        guard let (payload, promise) = nextWrite else {
            // The stream was not present. This is weird, it shouldn't ever happen, but we tolerate it, and recurse.
            self.flushableStreams.remove(nextStreamID)
            return self.nextFlushedWritableFrame()
        }

        let frame = HTTP2Frame(streamID: nextStreamID, payload: payload)
        return (frame, promise)
    }

    internal mutating func initialWindowSizeChanged(_ delta: Int) {
        self.streamDataBuffers.mutatingForEachValue {
            let hadPendingData = $0.hasPendingData
            $0.currentWindowSize += delta
            let hasPendingData = $0.hasPendingData

            if !hadPendingData && hasPendingData {
                assert(!self.flushableStreams.contains($0.streamID))
                self.flushableStreams.insert($0.streamID)
            } else if hadPendingData && !hasPendingData {
                assert(self.flushableStreams.contains($0.streamID))
                self.flushableStreams.remove($0.streamID)
            }
        }
    }
}


// MARK: Priority API
extension OutboundFlowControlBuffer {
    /// A frame with new priority data has been received that affects prioritisation of outbound frames.
    internal mutating func priorityUpdate(streamID: HTTP2StreamID, priorityData: HTTP2Frame.StreamPriorityData) throws {
        // Right now we don't actually do anything with priority information. However, we do want to police some parts of
        // RFC 7540 § 5.3, where we can, so this hook is already in place for us to extend later.
        if streamID == priorityData.dependency {
            // Streams may not depend on themselves!
            throw NIOHTTP2Errors.PriorityCycle(streamID: streamID)
        }
    }
}


private struct StreamFlowControlState {
    let streamID: HTTP2StreamID
    var currentWindowSize: Int
    var dataBuffer: DataBuffer

    var hasPendingData: Bool {
        return self.dataBuffer.hasMark && (self.currentWindowSize > 0 || self.dataBuffer.nextWriteIsHeaders)
    }

    init(streamID: HTTP2StreamID, initialWindowSize: Int) {
        self.streamID = streamID
        self.currentWindowSize = initialWindowSize
        self.dataBuffer = DataBuffer()
    }

    mutating func nextWrite(maxSize: Int) -> DataBuffer.BufferElement {
        assert(maxSize > 0)
        let writeSize = min(maxSize, currentWindowSize)
        let nextWrite = self.dataBuffer.nextWrite(maxSize: writeSize)

        if case .data(let payload) = nextWrite.0 {
            self.currentWindowSize -= payload.data.readableBytes
        }

        assert(self.currentWindowSize >= 0)
        return nextWrite
    }
}


private struct DataBuffer {
    typealias BufferElement = (HTTP2Frame.FramePayload, EventLoopPromise<Void>?)

    private var bufferedChunks: MarkedCircularBuffer<BufferElement>

    internal private(set) var flushedBufferedBytes: UInt

    var haveBufferedDataFrame: Bool {
        return self.bufferedChunks.count > 0
    }

    var nextWriteIsHeaders: Bool {
        if case .some(.headers) = self.bufferedChunks.first?.0 {
            return true
        } else {
            return false
        }
    }

    var hasMark: Bool {
        return self.bufferedChunks.hasMark
    }

    init() {
        self.bufferedChunks = MarkedCircularBuffer(initialCapacity: 8)
        self.flushedBufferedBytes = 0
    }

    mutating func bufferWrite(_ write: BufferElement) {
        self.bufferedChunks.append(write)
    }

    /// Marks the current point in the buffer as the place up to which we have flushed.
    mutating func markFlushPoint() {
        if let markIndex = self.bufferedChunks.markedElementIndex {
            for element in self.bufferedChunks.suffix(from: markIndex) {
                if case .data(let contents) = element.0 {
                    self.flushedBufferedBytes += UInt(contents.data.readableBytes)
                }
            }
            self.bufferedChunks.mark()
        } else if self.bufferedChunks.count > 0 {
            for element in self.bufferedChunks {
                if case .data(let contents) = element.0 {
                    self.flushedBufferedBytes += UInt(contents.data.readableBytes)
                }
            }
            self.bufferedChunks.mark()
        }
    }

    mutating func nextWrite(maxSize: Int) -> BufferElement {
        assert(maxSize >= 0)
        precondition(self.bufferedChunks.count > 0)

        let firstElementIndex = self.bufferedChunks.startIndex

        // First check that the next write is DATA. If it's not, just pass it on.
        guard case .data(var contents) = self.bufferedChunks[firstElementIndex].0 else {
            return self.bufferedChunks.removeFirst()
        }

        // Now check if we have enough space to return the next DATA frame wholesale.
        let firstElementReadableBytes = contents.data.readableBytes
        if firstElementReadableBytes <= maxSize {
            // Return the whole element.
            self.flushedBufferedBytes -= UInt(firstElementReadableBytes)
            return self.bufferedChunks.removeFirst()
        }

        // Here we have too many bytes. So we need to slice out a copy of the data we need
        // and leave the rest.
        let dataSlice = contents.data.slicePrefix(maxSize)
        self.flushedBufferedBytes -= UInt(maxSize)
        self.bufferedChunks[self.bufferedChunks.startIndex].0 = .data(contents)
        return (.data(.init(data: dataSlice)), nil)
    }

    /// Removes all pending writes, invalidating this structure as it does so.
    mutating func evacuatePendingWrites() -> MarkedCircularBuffer<BufferElement> {
        var buffer = MarkedCircularBuffer<BufferElement>(initialCapacity: 0)
        swap(&buffer, &self.bufferedChunks)
        return buffer
    }

    func failAllWrites(error: ChannelError) {
        for chunk in self.bufferedChunks {
            chunk.1?.fail(error)
        }
    }
}


private extension IOData {
    mutating func slicePrefix(_ length: Int) -> IOData {
        assert(length < self.readableBytes)

        switch self {
        case .byteBuffer(var buf):
            // This force-unwrap is safe, as we only invoke this when we have already checked the length.
            let newBuf = buf.readSlice(length: length)!
            self = .byteBuffer(buf)
            return .byteBuffer(newBuf)

        case .fileRegion(var region):
            let newRegion = FileRegion(fileHandle: region.fileHandle, readerIndex: region.readerIndex, endIndex: region.readerIndex + length)
            region.moveReaderIndex(forwardBy: length)
            self = .fileRegion(region)
            return .fileRegion(newRegion)
        }
    }
}


private extension Optional where Wrapped == StreamFlowControlState {
    // This function exists as a performance optimisation: by mutating the optional returned from Dictionary directly
    // inline, we can avoid the dictionary needing to hash the key twice, which it would have to do if we removed the
    // value, mutated it, and then re-inserted it.
    //
    // However, we need to be a bit careful here, as the performance gain from doing this would be completely swamped
    // if the Swift compiler failed to inline this method into its caller. This would force the closure to have its
    // context heap-allocated, and the cost of doing that is vastly higher than the cost of hashing the key a second
    // time. So for this reason we make it clear to the compiler that this method *must* be inlined at the call-site.
    // Sorry about doing this!
    //
    /// Apply a transform to a wrapped DataBuffer.
    ///
    /// - parameters:
    ///     - body: A block that will modify the contained value in the
    ///         optional, if there is one present.
    /// - returns: Whether the value was present or not.
    @inline(__always)
    @discardableResult
    mutating func apply(_ body: (inout Wrapped) -> Void) -> Bool {
        if self == nil {
            return false
        }

        var unwrapped = self!
        self = nil
        body(&unwrapped)
        self = unwrapped
        return true
    }

    // This function exists as a performance optimisation: by mutating the optional returned from Dictionary directly
    // inline, we can avoid the dictionary needing to hash the key twice, which it would have to do if we removed the
    // value, mutated it, and then re-inserted it.
    //
    // However, we need to be a bit careful here, as the performance gain from doing this would be completely swamped
    // if the Swift compiler failed to inline this method into its caller. This would force the closure to have its
    // context heap-allocated, and the cost of doing that is vastly higher than the cost of hashing the key a second
    // time. So for this reason we make it clear to the compiler that this method *must* be inlined at the call-site.
    // Sorry about doing this!
    //
    /// Apply a transform to a wrapped DataBuffer and return the result.
    ///
    /// - parameters:
    ///     - body: A block that will modify the contained value in the
    ///         optional, if there is one present.
    /// - returns: The return value of the modification, or nil if there was no object to modify.
    mutating func modify<T>(_ body: (inout Wrapped) -> T) -> T? {
        if self == nil {
            return nil
        }

        var unwrapped = self!
        self = nil
        let r = body(&unwrapped)
        self = unwrapped
        return r
    }
}
