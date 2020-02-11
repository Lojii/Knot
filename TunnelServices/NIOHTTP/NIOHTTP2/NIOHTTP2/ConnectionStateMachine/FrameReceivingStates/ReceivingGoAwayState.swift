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

/// A protocol that provides implementation for receiving GOAWAY frames, for those states that
/// can validly be quiesced.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol ReceivingGoawayState {
    var role: HTTP2ConnectionStateMachine.ConnectionRole { get }

    var streamState: ConnectionStreamState { get set }
}

extension ReceivingGoawayState {
    mutating func receiveGoAwayFrame(lastStreamID: HTTP2StreamID) -> StateMachineResultWithEffect {
        guard lastStreamID.mayBeInitiatedBy(self.role) || lastStreamID == .rootStream || lastStreamID == .maxID else {
            // The remote peer has sent a GOAWAY with an invalid stream ID.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.InvalidStreamIDForPeer(), type: .protocolError), effect: nil)
        }

        let droppedStreams = self.streamState.dropAllStreamsWithIDHigherThan(lastStreamID, droppedLocally: false, initiatedBy: self.role)
        let effect: NIOHTTP2ConnectionStateChange? = droppedStreams.map { .bulkStreamClosure(.init(closedStreams: $0)) }
        return .init(result: .succeed, effect: effect)
    }
}

extension ReceivingGoawayState where Self: RemotelyQuiescingState {
    mutating func receiveGoAwayFrame(lastStreamID: HTTP2StreamID) -> StateMachineResultWithEffect {
        guard lastStreamID.mayBeInitiatedBy(self.role) || lastStreamID == .rootStream || lastStreamID == .maxID else {
            // The remote peer has sent a GOAWAY with an invalid stream ID.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.InvalidStreamIDForPeer(), type: .protocolError), effect: nil)
        }

        if lastStreamID > self.lastLocalStreamID {
            // The remote peer has attempted to raise the lastStreamID.
            return .init(result: .connectionError(underlyingError: NIOHTTP2Errors.RaisedGoawayLastStreamID(), type: .protocolError), effect: nil)
        }

        let droppedStreams = self.streamState.dropAllStreamsWithIDHigherThan(lastStreamID, droppedLocally: false, initiatedBy: self.role)
        let effect: NIOHTTP2ConnectionStateChange? = droppedStreams.map { .bulkStreamClosure(.init(closedStreams: $0)) }
        self.lastLocalStreamID = lastStreamID
        return .init(result: .succeed, effect: effect)
    }
}

