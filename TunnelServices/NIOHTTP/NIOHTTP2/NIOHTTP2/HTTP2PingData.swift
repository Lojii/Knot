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

/// The opaque data contained in a HTTP/2 ping frame.
///
/// A HTTP/2 ping frame must contain 8 bytes of opaque data that is controlled entirely by the sender.
/// This data type encapsulates those 8 bytes while providing a friendly interface for them.
public struct HTTP2PingData {
    /// The underlying bytes to be sent to the wire. These are in network byte order.
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    /// Exposes the `HTTP2PingData` as an unsigned 64-bit integer. This property will perform any
    /// endianness transition that is required, meaning that there is no need to byte swap the result
    /// or before setting this property.
    public var integer: UInt64 {
        // Note: this is the safest way to do this, because it automatically does the right thing
        // from a byte order perspective. It's not necessarily the fastest though, and it's definitely
        // not the prettiest.
        get {
            var rval = UInt64(bytes.0) << 56
            rval += UInt64(bytes.1) << 48
            rval += UInt64(bytes.2) << 40
            rval += UInt64(bytes.3) << 32
            rval += UInt64(bytes.4) << 24
            rval += UInt64(bytes.5) << 16
            rval += UInt64(bytes.6) << 8
            rval += UInt64(bytes.7)
            return rval
        }
        set {
            self.bytes = (
                UInt8(newValue >> 56), UInt8(truncatingIfNeeded: newValue >> 48),
                UInt8(truncatingIfNeeded: newValue >> 40), UInt8(truncatingIfNeeded: newValue >> 32),
                UInt8(truncatingIfNeeded: newValue >> 24), UInt8(truncatingIfNeeded: newValue >> 16),
                UInt8(truncatingIfNeeded: newValue >> 8), UInt8(truncatingIfNeeded: newValue)
            )
        }
    }

    /// Create a new, blank, `HTTP2PingData`.
    public init() {
        self.bytes = (0, 0, 0, 0, 0, 0, 0, 0)
    }

    /// Create a `HTTP2PingData` containing the 64-bit integer provided in network byte order.
    public init(withInteger integer: UInt64) {
        self.init()
        self.integer = integer
    }

    /// Create a `HTTP2PingData` from a tuple of bytes.
    public init(withTuple tuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) {
        self.bytes = tuple
    }
}

extension HTTP2PingData: RandomAccessCollection, MutableCollection {
    public typealias Index = Int
    public typealias Element =  UInt8

    public var startIndex: Index {
        return 0
    }

    public var endIndex: Index {
        return 7
    }

    public subscript(_ index: Index) -> Element {
        get {
            switch index {
            case 0:
                return self.bytes.0
            case 1:
                return self.bytes.1
            case 2:
                return self.bytes.2
            case 3:
                return self.bytes.3
            case 4:
                return self.bytes.4
            case 5:
                return self.bytes.5
            case 6:
                return self.bytes.6
            case 7:
                return self.bytes.7
            default:
                preconditionFailure("Invalid index into HTTP2PingData: \(index)")
            }
        }
        set {
            switch index {
            case 0:
                self.bytes.0 = newValue
            case 1:
                self.bytes.1 = newValue
            case 2:
                self.bytes.2 = newValue
            case 3:
                self.bytes.3 = newValue
            case 4:
                self.bytes.4 = newValue
            case 5:
                self.bytes.5 = newValue
            case 6:
                self.bytes.6 = newValue
            case 7:
                self.bytes.7 = newValue
            default:
                preconditionFailure("Invalid index into HTTP2PingData: \(index)")
            }
        }
    }
}

extension HTTP2PingData: Equatable {
    public static func ==(lhs: HTTP2PingData, rhs: HTTP2PingData) -> Bool {
        return lhs.bytes.0 == rhs.bytes.0 &&
            lhs.bytes.1 == rhs.bytes.1 &&
            lhs.bytes.2 == rhs.bytes.2 &&
            lhs.bytes.3 == rhs.bytes.3 &&
            lhs.bytes.4 == rhs.bytes.4 &&
            lhs.bytes.5 == rhs.bytes.5 &&
            lhs.bytes.6 == rhs.bytes.6 &&
            lhs.bytes.7 == rhs.bytes.7
    }
}

extension HTTP2PingData: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.integer)
    }
}
