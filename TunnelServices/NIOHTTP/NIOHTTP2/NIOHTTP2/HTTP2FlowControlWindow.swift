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
struct HTTP2FlowControlWindow {
    /// The maximum flow control window size allowed by RFC 7540.
    static let maxSize: Int32 = Int32.max

    /// The maximum increment to the flow control window size allowed by RFC 7540.
    private static let maxIncrement: Int32 = Int32.max

    /// The integer size of this flow control window.
    ///
    /// From RFC 7540 § 6.9.1:
    ///
    /// > A sender MUST NOT allow a flow-control window to exceed 2^31-1 octets.
    ///
    /// This means that we can store this safely in an Int32. This value is hidden, because we want
    /// to ensure that we have a nice safe wrapper that can report errors and ensure that the flow
    /// control window never exits the allowed range.
    ///
    /// The reason we use Int32 instead of UInt32 is that the flow control window may also go negative.
    /// From RFC 7540 § 6.9.2:
    ///
    /// > In addition to changing the flow-control window for streams that are not yet active, a
    /// > SETTINGS frame can alter the initial flow-control window size for streams with active
    /// > flow-control windows (that is, streams in the "open" or "half-closed (remote)" state).
    /// > When the value of SETTINGS_INITIAL_WINDOW_SIZE changes, a receiver MUST adjust the size of
    /// > all stream flow-control windows that it maintains by the difference between the new value
    /// > and the old value.
    /// >
    /// > A change to SETTINGS_INITIAL_WINDOW_SIZE can cause the available space in a flow-control
    /// > window to become negative.  A sender MUST track the negative flow-control window and MUST
    /// > NOT send new flow-controlled frames until it receives WINDOW_UPDATE frames that cause the
    /// > flow-control window to become positive.
    ///
    /// The most-negative a flow-control window can go occurs in the following case:
    ///
    /// - A stream was created with initial window size of 2 ** 31 - 1 (a.k.a. Int32.max)
    /// - Int32.max bytes were sent, leaving the window size at zero.
    /// - The value of SETTINGS_INITIAL_WINDOW_SIZE was set to 0, leading to a window size delta of
    ///     -(Int32.max), and setting the window size to -(Int32.max).
    ///
    /// As -(Int32.max) definitionally still fits into Int32, Int32 is the appropriate type to use here.
    fileprivate private(set) var windowSize: Int32

    init(initialValue: Int) {
        precondition(initialValue >= 0, "Flow control windows may not begin negative")
        precondition(initialValue <= HTTP2FlowControlWindow.maxSize,
                     "Flow control windows may not exceed \(HTTP2FlowControlWindow.maxSize) bytes")

        self.windowSize = Int32(initialValue)
    }

    init(initialValue: Int32) {
        precondition(initialValue >= 0, "Flow control windows may not begin negative")
        precondition(initialValue <= HTTP2FlowControlWindow.maxSize,
                     "Flow control windows may not exceed \(HTTP2FlowControlWindow.maxSize) bytes")

        self.windowSize = initialValue
    }

    init(initialValue: UInt32) {
        self.init(initialValue: Int32(initialValue))
    }

    /// Increment the flow control window as a result of a WINDOW_UPDATE frame.
    ///
    /// This method will asserts if `amount` is outside the allowed range, as the allowed range is enforced by
    /// the valid values of a WINDOW_UPDATE frame. It is assumed that the frame parser validates the values in
    /// WINDOW_UPDATE frames.
    ///
    /// - parameters:
    ///     - amount: The size of the increment.
    /// - throws: When `amount` is outside of RFC 7540's allowed range, or when it would move this value outside
    ///     of the allowed range.
    mutating func windowUpdate(by amount: UInt32) throws {
        assert(amount <= HTTP2FlowControlWindow.maxIncrement)

        guard amount >= 1 else {
            throw NIOHTTP2Errors.InvalidWindowIncrementSize()
        }

        // We now need to bounds check to confirm that our window size will remain in the valid range. We use
        // subtraction to avoid integer overflow. Note that if the current window size is negative then all window
        // update increments are valid.
        guard (self.windowSize < 0) || (HTTP2FlowControlWindow.maxSize - self.windowSize >= amount) else {
            throw NIOHTTP2Errors.InvalidFlowControlWindowSize(delta: Int(amount), currentWindowSize: Int(self.windowSize))
        }

        self.windowSize += Int32(amount)
    }

    /// Change the flow control window as a result of a change to SETTINGS_INITIAL_WINDOW_SIZE.
    ///
    /// This method will trap if `amount` is outside the allowed range, as the allowed range is implicitly enforced
    /// so long as the values of SETTINGS_INITIAL_WINDOW_SIZE are correctly policed. The allowed range here is fairly
    /// large, however.
    ///
    /// This method will throw if this change forces the flow control window size to become larger than the maximum flow
    /// control window size.
    ///
    /// - parameters:
    ///     - amount: The size of the increment/decrement.
    /// - throws: When `amount` would move the flow control window outside the allowed range.
    mutating func initialSizeChanged(by amount: Int32) throws {
        assert(amount >= -(Int32.max))

        guard (self.windowSize < 0) || (HTTP2FlowControlWindow.maxSize - self.windowSize >= amount) else {
            throw NIOHTTP2Errors.InvalidFlowControlWindowSize(delta: Int(amount), currentWindowSize: Int(self.windowSize))
        }

        self.windowSize += amount
    }

    /// Consume a portion of the flow control window.
    ///
    /// - parameters:
    ///     - flowControlledBytes: The number of flow controlled bytes to consume
    mutating func consume(flowControlledBytes size: Int) throws {
        assert(size >= 0)
        // TODO(cory): This is the max value of SETTINGS_MAX_FRAME_SIZE, we should name this thing.
        assert(size <= (1 << 24) - 1)

        let size = Int32(size)

        guard self.windowSize >= size else {
            throw NIOHTTP2Errors.FlowControlViolation()
        }

        self.windowSize -= size
    }
}

extension HTTP2FlowControlWindow: ExpressibleByIntegerLiteral {
    typealias IntegerLiteralType = Int32

    init(integerLiteral initialValue: Int32) {
        precondition(initialValue >= 0, "Flow control windows may not begin negative")
        precondition(initialValue <= HTTP2FlowControlWindow.maxSize,
                     "Flow control windows may not exceed \(HTTP2FlowControlWindow.maxSize) bytes")

        self.windowSize = initialValue
    }
}

extension HTTP2FlowControlWindow: CustomStringConvertible {
    var description: String {
        return self.windowSize.description
    }
}

extension HTTP2FlowControlWindow: Equatable { }

extension HTTP2FlowControlWindow: Hashable { }

extension HTTP2FlowControlWindow: Comparable {
    static func < (lhs: HTTP2FlowControlWindow, rhs: HTTP2FlowControlWindow) -> Bool {
        return lhs.windowSize < rhs.windowSize
    }

    static func > (lhs: HTTP2FlowControlWindow, rhs: HTTP2FlowControlWindow) -> Bool {
        return lhs.windowSize > rhs.windowSize
    }

    static func <= (lhs: HTTP2FlowControlWindow, rhs: HTTP2FlowControlWindow) -> Bool {
        return lhs.windowSize <= rhs.windowSize
    }

    static func >= (lhs: HTTP2FlowControlWindow, rhs: HTTP2FlowControlWindow) -> Bool {
        return lhs.windowSize >= rhs.windowSize
    }
}

extension Int {
    init(_ window: HTTP2FlowControlWindow) {
        self = Int(window.windowSize)
    }
}
