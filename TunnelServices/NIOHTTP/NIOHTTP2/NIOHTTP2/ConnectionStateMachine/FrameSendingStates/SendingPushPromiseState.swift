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

/// A protocol that provides implementation for sending PUSH_PROMISE frames, for those states that
/// can validly send pushed streams.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol SendingPushPromiseState: HasFlowControlWindows {
    var headerBlockValidation: HTTP2ConnectionStateMachine.ValidationState { get }

    var streamState: ConnectionStreamState { get set }

    var localInitialWindowSize: UInt32 { get }

    var mayPush: Bool { get }
}

extension SendingPushPromiseState {
    mutating func sendPushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        return self._sendPushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
    }

    fileprivate mutating func _sendPushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        let validateHeaderBlock = self.headerBlockValidation == .enabled

        // While receivePushPromise has a two step process involving creating the child stream first, here we do it the other
        // way around. This is because we don't want to bother creating a child stream if the headers aren't valid, and because
        // we don't have to emit a frame to report the error (we just return it to the user), we don't have to have a stream
        // whose state we can modify.
        func parentStateModifier(stateMachine: inout HTTP2StreamStateMachine) -> StateMachineResultWithStreamEffect {
            return stateMachine.sendPushPromise(headers: headers, validateHeaderBlock: validateHeaderBlock)
        }

        // First, however, we need to check we can push at all!
        guard self.mayPush else {
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: NIOHTTP2Errors.PushInViolationOfSetting(), type: .protocolError), effect: nil)
        }

        do {
            let result = StateMachineResultWithEffect(self.streamState.modifyStreamState(streamID: originalStreamID, ignoreRecentlyReset: false, parentStateModifier), connectionState: self)
            guard case .succeed = result.result else {
                return result
            }

            try self.streamState.createLocallyPushedStream(streamID: childStreamID, localInitialWindowSize: self.localInitialWindowSize)
            return result
        } catch {
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: error, type: .protocolError), effect: nil)
        }
    }

    /// Whether we may push.
    var mayPush: Bool {
        // In the case where we don't have remote settings, we have to assume the default value, in which case we may push.
        return true
    }

}

extension SendingPushPromiseState where Self: RemotelyQuiescingState {
    mutating func sendPushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        // This call should never be used, but we do want to ensure that conforming types cannot enter the above method.
        // The state machine should return early in all cases where we might end up calling this function.
        preconditionFailure("Must not be called")
    }
}

extension SendingPushPromiseState where Self: HasRemoteSettings {
    var mayPush: Bool {
        return self.remoteSettings.enablePush == 1
    }
}
