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

/// A protocol that provides implementation for sending RST_STREAM frames, for those states that
/// can validly send such frames.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol SendingRstStreamState: HasFlowControlWindows {
    var streamState: ConnectionStreamState { get set }
}

extension SendingRstStreamState {
    /// Called to send a RST_STREAM frame.
    mutating func sendRstStream(streamID: HTTP2StreamID, reason: HTTP2ErrorCode) -> StateMachineResultWithEffect {
        let result = self.streamState.locallyResetStreamState(streamID: streamID) {
            $0.sendRstStream(reason: reason)
        }
        return StateMachineResultWithEffect(result, connectionState: self)
    }
}
