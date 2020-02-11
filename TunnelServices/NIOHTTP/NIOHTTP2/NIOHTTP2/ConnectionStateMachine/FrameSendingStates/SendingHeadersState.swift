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


/// A protocol that provides implementation for sending HEADERS frames, for those states that
/// can validly send headers.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol SendingHeadersState: HasFlowControlWindows {
    var role: HTTP2ConnectionStateMachine.ConnectionRole { get }

    var headerBlockValidation: HTTP2ConnectionStateMachine.ValidationState { get }

    var contentLengthValidation: HTTP2ConnectionStateMachine.ValidationState { get }

    var streamState: ConnectionStreamState { get set }

    var localInitialWindowSize: UInt32 { get }

    var remoteInitialWindowSize: UInt32 { get }
}

extension SendingHeadersState {
    /// Called when we send a HEADERS frame in this state.
    mutating func sendHeaders(streamID: HTTP2StreamID, headers: HPACKHeaders, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        let result: StateMachineResultWithStreamEffect
        let validateHeaderBlock = self.headerBlockValidation == .enabled
        let validateContentLength = self.contentLengthValidation == .enabled

        if self.role == .client && streamID.mayBeInitiatedBy(.client) {
            do {
                result = try self.streamState.modifyStreamStateCreateIfNeeded(streamID: streamID,
                                                                              localRole: .client,
                                                                              localInitialWindowSize: self.localInitialWindowSize,
                                                                              remoteInitialWindowSize: self.remoteInitialWindowSize) {
                    $0.sendHeaders(headers: headers, validateHeaderBlock: validateHeaderBlock, validateContentLength: validateContentLength, isEndStreamSet: endStream)
                }
            } catch {
                return StateMachineResultWithEffect(result: .connectionError(underlyingError: error, type: .protocolError), effect: nil)
            }
        } else {
            // HEADERS cannot create streams for servers, so this must be for a stream we already know about.
            result = self.streamState.modifyStreamState(streamID: streamID, ignoreRecentlyReset: false) {
                $0.sendHeaders(headers: headers, validateHeaderBlock: validateHeaderBlock, validateContentLength: validateContentLength, isEndStreamSet: endStream)
            }
        }

        return StateMachineResultWithEffect(result, connectionState: self)
    }
}


extension SendingHeadersState where Self: RemotelyQuiescingState {
    /// If we've been remotely quiesced, we're forbidden from creating new streams. So we can only possibly
    /// be modifying an existing one.
    mutating func sendHeaders(streamID: HTTP2StreamID, headers: HPACKHeaders, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        let validateHeaderBlock = self.headerBlockValidation == .enabled
        let validateContentLength = self.contentLengthValidation == .enabled
        
        let result = self.streamState.modifyStreamState(streamID: streamID, ignoreRecentlyReset: false) {
            $0.sendHeaders(headers: headers, validateHeaderBlock: validateHeaderBlock, validateContentLength: validateContentLength, isEndStreamSet: endStream)
        }
        return StateMachineResultWithEffect(result, connectionState: self)
    }
}
