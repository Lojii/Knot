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

/// The event triggered by this state transition attempt.
///
/// All state transition attempts trigger one of three results. Firstly, they succeed, in which case
/// the frame may be passed on (either outwards, to the serializer, or inwards, to the user).
/// Alternatively, the frame itself may trigger an error.
///
/// Errors triggered by frames come in two types: connection errors, and stream errors. This refers
/// to the scope at which the error occurs. Stream errors occur at stream scope, and therefore should
/// lead to the teardown of only the affected stream (e.g. RST_STREAM frame emission). Connection errors
/// occur at connection scope: either there is no stream available to tear down, or the error is so
/// foundational that the connection can not be recovered. In either case, the mechanism for tolerating
/// that is to tear the entire connection down, via GOAWAY frame.
///
/// In both cases, there is an associated kind of error as represented by a `HTTP2ErrorCode`, that
/// should be reported to the remote peer. Additionally, there is an error fired by the internal state
/// machine that can be reported to the user. This enum ensures that both can be propagated out.
enum StateMachineResult {
    /// An error that transitions the stream into a fatal error state. This should cause emission of
    /// RST_STREAM frames.
    case streamError(streamID: HTTP2StreamID, underlyingError: Error, type: HTTP2ErrorCode)

    /// An error that transitions the entire connection into a fatal error state. This should cause
    /// emission of GOAWAY frames.
    case connectionError(underlyingError: Error, type: HTTP2ErrorCode)

    /// The frame itself was not valid, but it is also not an error. Drop the frame.
    case ignoreFrame

    /// The state transition succeeded, the frame may be passed on.
    case succeed
}


/// Operations that may need to be performed after receiving a frame.
enum PostFrameOperation {
    /// An appropriate ACK must be sent.
    case sendAck

    /// No operation is needed.
    case nothing
}


/// An encapsulation of a state machine result along with a possible triggered state change.
struct StateMachineResultWithEffect {
    var result: StateMachineResult

    var effect: NIOHTTP2ConnectionStateChange?

    init(result: StateMachineResult, effect: NIOHTTP2ConnectionStateChange?) {
        self.result = result
        self.effect = effect
    }

    init<ConnectionState: HasFlowControlWindows>(_ streamEffect: StateMachineResultWithStreamEffect, connectionState: ConnectionState) {
        self.result = streamEffect.result
        self.effect = streamEffect.effect.map { NIOHTTP2ConnectionStateChange($0, connectionState: connectionState) }
    }
}

/// An encapsulation of a state machine result along with a state change on a single stream.
struct StateMachineResultWithStreamEffect {
    var result: StateMachineResult

    var effect: StreamStateChange?
}
