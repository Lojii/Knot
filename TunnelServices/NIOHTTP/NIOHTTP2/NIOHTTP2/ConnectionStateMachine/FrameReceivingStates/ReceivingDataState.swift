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

/// A protocol that provides implementation for receiving DATA frames, for those states that
/// can validly receive data.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol ReceivingDataState: HasFlowControlWindows {
    var streamState: ConnectionStreamState { get set }

    var inboundFlowControlWindow: HTTP2FlowControlWindow { get set }
}

extension ReceivingDataState {
    /// Called to receive a DATA frame.
    mutating func receiveData(streamID: HTTP2StreamID, contentLength: Int, flowControlledBytes: Int, isEndStreamSet endStream: Bool) -> StateMachineResultWithEffect {
        do {
            try self.inboundFlowControlWindow.consume(flowControlledBytes: flowControlledBytes)
        } catch let error where error is NIOHTTP2Errors.FlowControlViolation {
            return StateMachineResultWithEffect(result: .connectionError(underlyingError: error, type: .flowControlError), effect: nil)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }

        let result = self.streamState.modifyStreamState(streamID: streamID, ignoreRecentlyReset: true) {
            $0.receiveData(contentLength: contentLength, flowControlledBytes: flowControlledBytes, isEndStreamSet: endStream)
        }

        // We need to be a bit careful here. The backing code may have triggered either an ignoreFrame or streamError. While both of these
        // need to be honored, in those cases we also need to make sure the user knows that the frame did consume some flow control window!
        return StateMachineResultWithEffect.withGuaranteedFlowControlEffect(result, connectionState: self)
    }
}


private extension StateMachineResultWithEffect {
    static func withGuaranteedFlowControlEffect<ConnectionState: ReceivingDataState>(_ result: StateMachineResultWithStreamEffect, connectionState: ConnectionState) -> StateMachineResultWithEffect {
        // In most cases, this will update the underlying effect with the new flow control window info.
        var newResult = StateMachineResultWithEffect(result, connectionState: connectionState)
        if newResult.effect == nil {
            // But if we aren't noting it anywhere else, we note it here.
            newResult.effect = .flowControlChange(.init(localConnectionWindowSize: Int(connectionState.outboundFlowControlWindow), remoteConnectionWindowSize: Int(connectionState.inboundFlowControlWindow), localStreamWindowSize: nil))
        }

        return newResult
    }
}
