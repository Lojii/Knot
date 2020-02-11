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

/// A protocol that provides implementation for receiving RST_STREAM frames, for those states that
/// can validly receive such frames.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol ReceivingRstStreamState: HasFlowControlWindows {
    var streamState: ConnectionStreamState { get set }
}

extension ReceivingRstStreamState {
    /// Called to receive a RST_STREAM frame.
    mutating func receiveRstStream(streamID: HTTP2StreamID, reason: HTTP2ErrorCode) -> StateMachineResultWithEffect {
        // RFC 7540 § 6.4 <https://httpwg.org/specs/rfc7540.html#RST_STREAM> does not explicitly forbid a peer sending
        // multiple RST_STREAMs for the same stream which means we should ignore subsequent RST_STREAMs.
        let result = self.streamState.modifyStreamState(streamID: streamID, ignoreRecentlyReset: true, ignoreClosed: true) {
            $0.receiveRstStream(reason: reason)
        }
        return StateMachineResultWithEffect(result, connectionState: self)
    }
}
