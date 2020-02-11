//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIO


/// A buffer that stores outbound control frames.
///
/// In general it is preferential to buffer outbound frames instead of passing them into the channel.
/// This is because once the frame has left the HTTP2 handler and moved into the Channel it is no longer
/// easy for us to tell how much data has been buffered. The larger the buffer grows, the more likely it
/// is that the peer is consuming resources of ours that we need for other use-cases, and in some cases
/// this may amount to an actual denial of service attack.
///
/// We have a number of buffers that handle data frames, but a similar concern applies to control frames
/// too. Control frames need to be emitted with relatively high priority, but they should only be emitted
/// when it will be reasonably possible to write them to the network. As long as it is not possible, we
/// want to store them where we can see them, and use the buffer size to make choices about the connection.
struct ControlFrameBuffer {
    /// Any control frame writes that may need to be emitted.
    private var pendingControlFrames: MarkedCircularBuffer<PendingControlFrame>

    /// The maximum size of the buffer. If we have to buffer more frames than this,
    /// we'll kill the connection.
    internal var maximumBufferSize: Int
}


// MARK:- ControlFrameBuffer initializers
extension ControlFrameBuffer {
    internal init(maximumBufferSize: Int) {
        // We allocate a circular buffer of reasonable size to ensure that if we ever do have to
        // buffer control frames that we won't need to resize this too aggressively.
        self.pendingControlFrames = MarkedCircularBuffer(initialCapacity: 16)
        self.maximumBufferSize = maximumBufferSize
    }
}


// MARK:- ControlFrameBuffer frame processing
extension ControlFrameBuffer {
    internal mutating func processOutboundFrame(_ frame: HTTP2Frame, promise: EventLoopPromise<Void>?, channelWritable: Bool) throws -> OutboundFrameAction {
        switch frame.payload {
        case .data:
            // These frames are not buffered here. If it reached us, it's because we believe the channel is writable,
            // and we must have no control frames buffered.
            assert(channelWritable, "Received flushed data frame without writable channel")
            assert(self.pendingControlFrames.count == 0, "Received flush data frames while buffering control frames")
            return .forward
        default:
            // Control frames. These are what we buffer. We buffer them in two cases: either we have something else
            // already buffered (to ensure ordering stays correct), or the channel isn't writable.
            if !channelWritable || self.pendingControlFrames.count > 0 {
                try self.bufferFrame(frame, promise: promise)
                return .nothing
            } else {
                return .forward
            }
        }
    }

    internal mutating func flushReceived() {
        self.pendingControlFrames.mark()
    }

    internal mutating func nextFlushedWritableFrame() -> PendingControlFrame? {
        if self.pendingControlFrames.hasMark && self.pendingControlFrames.count > 0 {
            return self.pendingControlFrames.removeFirst()
        } else {
            return nil
        }
    }

    internal func invalidateBuffer(reason: ChannelError) {
        for write in self.pendingControlFrames {
            write.promise?.fail(reason)
        }
    }

    private mutating func bufferFrame(_ frame: HTTP2Frame, promise: EventLoopPromise<Void>?) throws {
        guard self.pendingControlFrames.count < self.maximumBufferSize else {
            // Appending another frame would violate the maximum buffer size. We're storing too many frames here,
            // we gotta move on.
            throw NIOHTTP2Errors.ExcessiveOutboundFrameBuffering()
        }
        self.pendingControlFrames.append(PendingControlFrame(frame: frame, promise: promise))
    }
}


// MARK:- ControlFrameBuffer.PendingControlFrame definition
extension ControlFrameBuffer {
    /// A buffered control frame write and its associated promise.
    struct PendingControlFrame {
        var frame: HTTP2Frame
        var promise: EventLoopPromise<Void>?
    }
}
