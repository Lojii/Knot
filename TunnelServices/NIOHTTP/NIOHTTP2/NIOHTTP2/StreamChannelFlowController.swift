//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// The outbound flow control manager for `HTTP2StreamChannel` objects.
///
/// `HTTP2StreamChannel` objects need a separate piece of outbound flow control
/// management from the one used in HTTP/2. This is because we don't want the
/// size of the remote peer's HTTP/2 flow control window to in any meaningful way affect
/// the resources we allow ourselves to consume locally.
///
/// Our flow control strategy here is in two parts. The first is a watermarked
/// pending-byte-based flow control strategy that uses the number of writes that have been
/// issued by the channel but not written to the network. If these writes move past a certain
/// threshold, the channel writability state will change.
///
/// The second is a parent-channel based observation. If the parent channel is not writable,
/// there is no reason to tell the stream channels that they can write either, as those writes
/// will simply back up in the parent.
///
/// The observed effect is that the `HTTP2StreamChannel` is writable only if both of the above
/// strategies are writable: if either is not writable, neither is the `HTTP2StreamChannel`.
struct StreamChannelFlowController {
    private var watermarkedController: WatermarkedFlowController

    private var parentIsWritable: Bool

    internal init(highWatermark: Int, lowWatermark: Int, parentIsWritable: Bool) {
        self.watermarkedController = WatermarkedFlowController(highWatermark: highWatermark, lowWatermark: lowWatermark)
        self.parentIsWritable = parentIsWritable
    }
}


extension StreamChannelFlowController {
    /// Whether the `HTTP2StreamChannel` should be writable.
    var isWritable: Bool {
        return self.watermarkedController.isWritable && self.parentIsWritable
    }
}


extension StreamChannelFlowController {
    /// A value representing a change in writability.
    enum WritabilityChange: Hashable {
        /// No writability change occurred
        case noChange

        /// Writability changed to a new value.
        case changed(newValue: Bool)
    }
}


extension StreamChannelFlowController {
    /// Notifies the flow controller that we have queued some bytes for writing to the network.
    mutating func bufferedBytes(_ bufferedBytes: Int) -> WritabilityChange {
        return self.mayChangeWritability {
            $0.watermarkedController.bufferedBytes(bufferedBytes)
        }
    }

    /// Notifies the flow controller that we have successfully written some bytes to the network.
    mutating func wroteBytes(_ writtenBytes: Int) -> WritabilityChange {
        return self.mayChangeWritability {
            $0.watermarkedController.wroteBytes(writtenBytes)
        }
    }

    mutating func parentWritabilityChanged(_ newWritability: Bool) -> WritabilityChange {
        return self.mayChangeWritability {
            $0.parentIsWritable = newWritability
        }
    }

    private mutating func mayChangeWritability(_ body: (inout StreamChannelFlowController) -> Void) -> WritabilityChange {
        let wasWritable = self.isWritable
        body(&self)
        let isWritable = self.isWritable

        if wasWritable != isWritable {
            return .changed(newValue: isWritable)
        } else {
            return .noChange
        }
    }
}


extension StreamChannelFlowController: Equatable { }


extension StreamChannelFlowController: CustomDebugStringConvertible {
    var debugDescription: String {
        return "StreamChannelFlowController(parentIsWritable: \(self.parentIsWritable), watermarkedController: \(self.watermarkedController.debugDescription))"
    }
}
