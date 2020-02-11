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
import NIO

/// A buffer of pending user events.
///
/// This buffer is used to ensure that we deliver user events and frames correctly from
/// the `NIOHTTP2Handler` in the face of reentrancy. Specifically, it is possible that
/// a re-entrant call will lead to `NIOHTTP2Handler.channelRead` being on the stack twice.
/// In this case, we do not want to deliver frames or user events out of order. Rather than
/// force the stack to unwind, we have this temporary storage location where all user events go.
/// This will be drained both before and after any frame read operation, to ensure that we
/// have always delivered all pending user events before we deliver a frame.
class InboundEventBuffer {
    fileprivate var buffer: CircularBuffer<Any> = CircularBuffer(initialCapacity: 8)

    func pendingUserEvent(_ event: Any) {
        self.buffer.append(event)
    }
}


// MARK:- Sequence conformance
extension InboundEventBuffer: Sequence {
    typealias Element = Any

    func makeIterator() -> InboundEventBufferIterator {
        return InboundEventBufferIterator(self)
    }

    struct InboundEventBufferIterator: IteratorProtocol {
        typealias Element = InboundEventBuffer.Element

        let inboundBuffer: InboundEventBuffer

        fileprivate init(_ buffer: InboundEventBuffer) {
            self.inboundBuffer = buffer
        }

        func next() -> Element? {
            if self.inboundBuffer.buffer.count > 0 {
                return self.inboundBuffer.buffer.removeFirst()
            } else {
                return nil
            }
        }
    }
}


// MARK:- CustomStringConvertible conformance
extension InboundEventBuffer: CustomStringConvertible {
    var description: String {
        return "InboundEventBuffer { \(self.buffer) }"
    }
}
