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

/// A protocol that provides implementation for receiving PUSH_PROMISE frames, for those states that
/// can validly accept pushed streams.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol ReceivingPushPromiseState: HasFlowControlWindows {
    var role: HTTP2ConnectionStateMachine.ConnectionRole { get }

    var headerBlockValidation: HTTP2ConnectionStateMachine.ValidationState { get }

    var streamState: ConnectionStreamState { get set }

    var remoteInitialWindowSize: UInt32 { get }

    var peerMayPush: Bool { get }
}

extension ReceivingPushPromiseState {
    mutating func receivePushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        return self._receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
    }

    fileprivate mutating func _receivePushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        // In states that support a push promise we have two steps. Firstly, we want to create the child stream; then we want to
        // pass the PUSH_PROMISE frame through the stream state machine for the parent stream.
        //
        // The reason we do things in this order is that if for any reason the PUSH_PROMISE frame is invalid on the parent stream,
        // we want to take out both the child stream and the parent stream. We can only do that if we have a child stream state to
        // modify. For this reason, we unconditionally allow the remote peer to consume the stream. The only case where this is *not*
        // true is when the child stream itself cannot be validly created, because the stream ID used by the remote peer is invalid.
        // In this case this is a connection error, anyway, so we don't worry too much about it.
        //
        // Before any of this, though, we need to check whether the remote peer is even allowed to push!
        guard self.peerMayPush else {
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: NIOHTTP2Errors.PushInViolationOfSetting(), type: .protocolError), effect: nil)
        }

        let validateHeaderBlock = self.headerBlockValidation == .enabled

        do {
            try self.streamState.createRemotelyPushedStream(streamID: childStreamID,
                                                            remoteInitialWindowSize: self.remoteInitialWindowSize)

            let result = self.streamState.modifyStreamState(streamID: originalStreamID, ignoreRecentlyReset: true) {
                $0.receivePushPromise(headers: headers, validateHeaderBlock: validateHeaderBlock)
            }
            return StateMachineResultWithEffect(result, connectionState: self)
        } catch {
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: error, type: .protocolError), effect: nil)
        }
    }

    /// Whether the remote peer may push.
    var peerMayPush: Bool {
        // In the case where we don't have local settings, we have to assume the default value, in which the peer may push.
        return true
    }
}

extension ReceivingPushPromiseState where Self: LocallyQuiescingState {
    mutating func receivePushPromise(originalStreamID: HTTP2StreamID, childStreamID: HTTP2StreamID, headers: HPACKHeaders) -> StateMachineResultWithEffect {
        // This check is duplicated here, because the protocol error of violating this setting is more important than ignoring the frame.
        guard self.peerMayPush else {
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: NIOHTTP2Errors.PushInViolationOfSetting(), type: .protocolError), effect: nil)
        }

        // If we're a client, the server is forbidden from initiating new streams, as we quiesced. However, RFC 7540 wants us to ignore this.
        if self.role == .client {
            return StateMachineResultWithEffect(result: .ignoreFrame, effect: nil)
        }

        // We're a server, so the remote peer can't initiate a stream with a PUSH_PROMISE, but that's ok, the stream state machine
        // will forbid this as it normally does.
        return self._receivePushPromise(originalStreamID: originalStreamID, childStreamID: childStreamID, headers: headers)
    }
}

extension ReceivingPushPromiseState where Self: HasLocalSettings {
    var peerMayPush: Bool {
        return self.localSettings.enablePush == 1
    }
}
