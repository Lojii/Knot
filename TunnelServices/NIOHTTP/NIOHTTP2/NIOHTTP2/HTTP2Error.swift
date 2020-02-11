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
import NIOHPACK

public protocol NIOHTTP2Error: Equatable, Error { }

/// Errors that NIO raises when handling HTTP/2 connections.
public enum NIOHTTP2Errors {
    /// The outbound frame buffers have become filled, and it is not possible to buffer
    /// further outbound frames. This occurs when the remote peer is generating work
    /// faster than they are consuming the result. Additional buffering runs the risk of
    /// memory exhaustion.
    public struct ExcessiveOutboundFrameBuffering: NIOHTTP2Error {
        public init() { }
    }

    /// NIO's upgrade handler encountered a successful upgrade to a protocol that it
    /// does not recognise.
    public struct InvalidALPNToken: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to issue a write on a stream that does not exist.
    public struct NoSuchStream: NIOHTTP2Error {
        /// The stream ID that was used that does not exist.
        public var streamID: HTTP2StreamID

        public init(streamID: HTTP2StreamID) {
            self.streamID = streamID
        }
    }

    /// A stream was closed.
    public struct StreamClosed: NIOHTTP2Error {
        /// The stream ID that was closed.
        public var streamID: HTTP2StreamID

        /// The error code associated with the closure.
        public var errorCode: HTTP2ErrorCode

        public init(streamID: HTTP2StreamID, errorCode: HTTP2ErrorCode) {
            self.streamID = streamID
            self.errorCode = errorCode
        }
    }

    public struct BadClientMagic: NIOHTTP2Error {
        public init() {}
    }

    /// A stream state transition was attempted that was not valid.
    public struct BadStreamStateTransition: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to change the flow control window size, either via
    /// SETTINGS or WINDOW_UPDATE, but this change would move the flow control
    /// window size out of bounds.
    public struct InvalidFlowControlWindowSize: NIOHTTP2Error {
        /// The delta being applied to the flow control window.
        public var delta: Int

        /// The size of the flow control window before the delta was applied.
        public var currentWindowSize: Int

        public init(delta: Int, currentWindowSize: Int) {
            self.delta = delta
            self.currentWindowSize = currentWindowSize
        }
    }

    /// A frame was sent or received that violates HTTP/2 flow control rules.
    public struct FlowControlViolation: NIOHTTP2Error {
        public init() { }
    }

    /// A SETTINGS frame was sent or received with an invalid setting.
    public struct InvalidSetting: NIOHTTP2Error {
        /// The invalid setting.
        public var setting: HTTP2Setting

        public init(setting: HTTP2Setting) {
            self.setting = setting
        }
    }

    /// An attempt to perform I/O was made on a connection that is already closed.
    public struct IOOnClosedConnection: NIOHTTP2Error {
        public init() { }
    }

    /// A SETTINGS frame was received that is invalid.
    public struct ReceivedBadSettings: NIOHTTP2Error {
        public init() { }
    }

    /// A violation of SETTINGS_MAX_CONCURRENT_STREAMS occurred.
    public struct MaxStreamsViolation: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to use a stream ID that is too small.
    public struct StreamIDTooSmall: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to send a frame without having previously sent a connection preface!
    public struct MissingPreface: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to create a stream after a GOAWAY frame has forbidden further
    /// stream creation.
    public struct CreatedStreamAfterGoaway: NIOHTTP2Error {
        public init() { }
    }

    /// A peer has attempted to create a stream with a stream ID it is not permitted to use.
    public struct InvalidStreamIDForPeer: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to send a new GOAWAY frame whose lastStreamID is higher than the previous value.
    public struct RaisedGoawayLastStreamID: NIOHTTP2Error {
        public init() { }
    }

    /// The size of the window increment is invalid.
    public struct InvalidWindowIncrementSize: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to push a stream, even though the settings forbid it.
    public struct PushInViolationOfSetting: NIOHTTP2Error {
        public init() { }
    }

    /// An attempt was made to use a currently unsupported feature.
    public struct Unsupported: NIOHTTP2Error {
        public var info: String
        
        public init(info: String) {
            self.info = info
        }
    }

    public struct UnableToSerializeFrame: NIOHTTP2Error {
        public init() { }
    }

    public struct UnableToParseFrame: NIOHTTP2Error {
        public init() { }
    }

    /// A pseudo-header field is missing.
    public struct MissingPseudoHeader: NIOHTTP2Error {
        public var name: String

        public init(_ name: String) {
            self.name = name
        }
    }

    /// A pseudo-header field has been duplicated.
    public struct DuplicatePseudoHeader: NIOHTTP2Error {
        public var name: String

        public init(_ name: String) {
            self.name = name
        }
    }

    /// A header block contained a pseudo-header after a regular header.
    public struct PseudoHeaderAfterRegularHeader: NIOHTTP2Error {
        public var name: String

        public init(_ name: String) {
            self.name = name
        }
    }

    /// An unknown pseudo-header was received.
    public struct UnknownPseudoHeader: NIOHTTP2Error {
        public var name: String

        public init(_ name: String) {
            self.name = name
        }
    }

    /// A header block was received with an invalid set of pseudo-headers for the block type.
    public struct InvalidPseudoHeaders: NIOHTTP2Error {
        public var headerBlock: HPACKHeaders

        public init(_ block: HPACKHeaders) {
            self.headerBlock = block
        }
    }

    /// An outbound request was about to be sent, but does not contain a Host header.
    public struct MissingHostHeader: NIOHTTP2Error {
        public init() { }
    }

    /// An outbound request was about to be sent, but it contains a duplicated Host header.
    public struct DuplicateHostHeader: NIOHTTP2Error {
        public init() { }
    }

    /// A HTTP/2 header block was received with an empty :path header.
    public struct EmptyPathHeader: NIOHTTP2Error {
        public init() { }
    }

    /// A :status header was received with an invalid value.
    public struct InvalidStatusValue: NIOHTTP2Error {
        public var value: String

        public init(_ value: String) {
            self.value = value
        }
    }

    /// A priority update was received that would create a PRIORITY cycle.
    public struct PriorityCycle: NIOHTTP2Error {
        /// The affected stream ID.
        public var streamID: HTTP2StreamID

        public init(streamID: HTTP2StreamID) {
            self.streamID = streamID
        }
    }

    /// An attempt was made to send trailers without setting END_STREAM on them.
    public struct TrailersWithoutEndStream: NIOHTTP2Error {
        /// The affected stream ID.
        public var streamID: HTTP2StreamID

        public init(streamID: HTTP2StreamID) {
            self.streamID = streamID
        }
    }

    /// An attempt was made to send a header field with a field name that is not valid in HTTP/2.
    public struct InvalidHTTP2HeaderFieldName: NIOHTTP2Error {
        public var fieldName: String

        public init(_ fieldName: String) {
            self.fieldName = fieldName
        }
    }

    /// Connection-specific header fields are forbidden in HTTP/2: this error is raised when one is
    /// sent or received.
    public struct ForbiddenHeaderField: NIOHTTP2Error {
        public var name: String
        public var value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// A request or response has violated the expected content length, either exceeding or falling beneath it.
    public struct ContentLengthViolated: NIOHTTP2Error {
        public init() { }
    }

    /// The remote peer has sent an excessive number of empty DATA frames, which looks like a denial of service
    /// attempt, so the connection has been closed.
    public struct ExcessiveEmptyDataFrames: NIOHTTP2Error {
        public init() { }
    }

    /// The remote peer has sent a header block so large that NIO refuses to buffer any more data than that.
    public struct ExcessivelyLargeHeaderBlock: NIOHTTP2Error {
        public init() { }
    }
}


/// This enum covers errors that are thrown internally for messaging reasons. These should
/// not leak.
internal enum InternalError: Error {
    case attemptedToCreateStream

    case codecError(code: HTTP2ErrorCode)
}

extension InternalError: Hashable { }


