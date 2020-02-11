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

/// A protocol that provides implementation for receiving HEADERS frames, for those states that
/// can validly accept headers.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol ReceivingHeadersState: HasFlowControlWindows {
    var role: HTTP2ConnectionStateMachine.ConnectionRole { get }

    var headerBlockValidation: HTTP2ConnectionStateMachine.ValidationState { get }

    var contentLengthValidation: HTTP2ConnectionStateMachine.ValidationState { get }

    var streamState: ConnectionStreamState { get set }

    var localInitialWindowSize: UInt32 { get }

    var remoteInitialWindowSize: UInt32 { get }
}

extension ReceivingHeadersState {
    /// Called when we receive a HEADERS frame in this state.
    mutating func receiveHeaders(streamID: HTTP2StreamID, headers: HPACKHeaders, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        let result: StateMachineResultWithStreamEffect
        let validateHeaderBlock = self.headerBlockValidation == .enabled
        let validateContentLength = self.contentLengthValidation == .enabled

        if self.role == .server && streamID.mayBeInitiatedBy(.client) {
            do {
                result = try self.streamState.modifyStreamStateCreateIfNeeded(streamID: streamID, localRole: .server, localInitialWindowSize: self.localInitialWindowSize, remoteInitialWindowSize: self.remoteInitialWindowSize) {
                    $0.receiveHeaders(headers: headers, validateHeaderBlock: validateHeaderBlock, validateContentLength: validateContentLength, isEndStreamSet: endStream)
                }
            } catch {
                return StateMachineResultWithEffect(result: .connectionError(underlyingError: error, type: .protocolError), effect: nil)
            }
        } else {
            // HEADERS cannot create streams for servers, so this must be for a stream we already know about.
            result = self.streamState.modifyStreamState(streamID: streamID, ignoreRecentlyReset: true) {
                $0.receiveHeaders(headers: headers, validateHeaderBlock: validateHeaderBlock, validateContentLength: validateContentLength, isEndStreamSet: endStream)
            }
        }

        return StateMachineResultWithEffect(result, connectionState: self)
    }
}


extension ReceivingHeadersState where Self: LocallyQuiescingState {
    /// Called when we receive a HEADERS frame in this state.
    ///
    /// If we've quiesced this connection, the remote peer is no longer allowed to create new streams.
    /// We ignore any frame that appears to be creating a new stream, and then prevent this from creating
    /// new streams.
    mutating func receiveHeaders(streamID: HTTP2StreamID, headers: HPACKHeaders, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        let validateHeaderBlock = self.headerBlockValidation == .enabled
        let validateContentLength = self.contentLengthValidation == .enabled

        if streamID.mayBeInitiatedBy(.client) && streamID > self.lastRemoteStreamID {
            return StateMachineResultWithEffect(result: .ignoreFrame, effect: nil)
        }

        // At this stage we've quiesced, so the remote peer is not allowed to create new streams.
        let result = self.streamState.modifyStreamState(streamID: streamID, ignoreRecentlyReset: true) {
            $0.receiveHeaders(headers: headers, validateHeaderBlock: validateHeaderBlock, validateContentLength: validateContentLength, isEndStreamSet: endStream)
        }
        return StateMachineResultWithEffect(result, connectionState: self)
    }
}
