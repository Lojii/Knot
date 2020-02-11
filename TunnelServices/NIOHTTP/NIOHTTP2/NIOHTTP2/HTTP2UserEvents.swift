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

/// A `StreamClosedEvent` is fired whenever a stream is closed.
///
/// This event is fired whether the stream is closed normally, or via RST_STREAM,
/// or via GOAWAY. Normal closure is indicated by having `reason` be `nil`. In the
/// case of closure by GOAWAY the `reason` is always `.refusedStream`, indicating that
/// the remote peer has not processed this stream. In the case of RST_STREAM,
/// the `reason` contains the error code sent by the peer in the RST_STREAM frame.
public struct StreamClosedEvent {
    /// The stream ID of the stream that is closed.
    public let streamID: HTTP2StreamID

    /// The reason for the stream closure. `nil` if the stream was closed without
    /// error. Otherwise, the error code indicating why the stream was closed.
    public let reason: HTTP2ErrorCode?

    public init(streamID: HTTP2StreamID, reason: HTTP2ErrorCode?) {
        self.streamID = streamID
        self.reason = reason
    }
}

extension StreamClosedEvent: Hashable { }


/// A `NIOHTTP2WindowUpdatedEvent` is fired whenever a flow control window is changed.
/// This includes changes on the connection flow control window, which is signalled by
/// this event having `streamID` set to `.rootStream`.
public struct NIOHTTP2WindowUpdatedEvent {
    /// The stream ID of the window that has been changed. May be .rootStream, in which
    /// case the connection window has changed.
    public let streamID: HTTP2StreamID

    /// The new inbound window size for this stream, if any. May be nil if this stream is half-closed.
    public let inboundWindowSize: Int?

    /// The new outbound window size for this stream, if any. May be nil if this stream is half-closed.
    public let outboundWindowSize: Int?

    public init(streamID: HTTP2StreamID, inboundWindowSize: Int?, outboundWindowSize: Int?) {
        // We use Int here instead of Int32. Nonetheless, the value must fit in the Int32 range.
        precondition(inboundWindowSize == nil || inboundWindowSize! <= Int(HTTP2FlowControlWindow.maxSize))
        precondition(outboundWindowSize == nil || outboundWindowSize! <= Int(HTTP2FlowControlWindow.maxSize))
        precondition(inboundWindowSize == nil || inboundWindowSize! >= Int(Int32.min))
        precondition(outboundWindowSize == nil || outboundWindowSize! >= Int(Int32.min))

        self.streamID = streamID
        self.inboundWindowSize = inboundWindowSize
        self.outboundWindowSize = outboundWindowSize
    }
}

extension NIOHTTP2WindowUpdatedEvent: Hashable { }


/// A `NIOHTTP2StreamCreatedEvent` is fired whenever a HTTP/2 stream is created.
public struct NIOHTTP2StreamCreatedEvent {
    public let streamID: HTTP2StreamID

    /// The initial local stream window size. May be nil if this stream may never have data sent on it.
    public let localInitialWindowSize: UInt32?

    /// The initial remote stream window size. May be nil if this stream may never have data received on it.
    public let remoteInitialWidowSize: UInt32?

    public init(streamID: HTTP2StreamID, localInitialWindowSize: UInt32?, remoteInitialWindowSize: UInt32?) {
        self.streamID = streamID
        self.localInitialWindowSize = localInitialWindowSize
        self.remoteInitialWidowSize = remoteInitialWindowSize
    }
}

extension NIOHTTP2StreamCreatedEvent: Hashable { }

/// A `NIOHTTP2BulkStreamWindowChangeEvent` is fired whenever all of the remote flow control windows for a given stream have been changed.
///
/// This occurs when an ACK to a SETTINGS frame is received that changes the value of SETTINGS_INITIAL_WINDOW_SIZE. This is only fired
/// when the local peer has changed its settings.
public struct NIOHTTP2BulkStreamWindowChangeEvent {
    /// The change in the remote stream window sizes.
    public let delta: Int

    public init(delta: Int) {
        self.delta = delta
    }
}

extension NIOHTTP2BulkStreamWindowChangeEvent: Hashable  { }
