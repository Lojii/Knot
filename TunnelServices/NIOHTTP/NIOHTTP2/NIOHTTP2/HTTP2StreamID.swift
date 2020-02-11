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

/// A single HTTP/2 stream ID.
///
/// Every stream in HTTP/2 has a unique 31-bit stream ID. This stream ID monotonically
/// increases over the lifetime of the connection. While the stream ID is a 31-bit
/// integer on the wire, it does not meaningfully *behave* like a 31-bit integer: it is
/// not reasonable to perform mathematics on it, for example.
///
/// For this reason, SwiftNIO encapsulates the idea of this type into the HTTP2StreamID
/// structure.
public struct HTTP2StreamID {
    /// The stream ID as a 32 bit integer that will be sent on the network. This will
    /// always be positive.
    internal var networkStreamID: Int32

    /// The root stream on a HTTP/2 connection, stream 0.
    ///
    /// This can safely be used across all connections to identify stream 0.
    public static let rootStream: HTTP2StreamID = 0

    /// The largest possible stream ID on a HTTP/2 connection.
    ///
    /// This should not usually be used to manage a specific stream. Instead, it's a sentinel
    /// that can be used to "quiesce" a HTTP/2 connection on a GOAWAY frame.
    public static let maxID: HTTP2StreamID = HTTP2StreamID(Int32.max)

    /// Create a `HTTP2StreamID` for a specific integer value.
    public init(_ integerID: Int) {
        precondition(integerID >= 0 && integerID <= Int32.max, "\(integerID) is not a valid HTTP/2 stream ID value")
        self.networkStreamID = Int32(integerID)
    }

    /// Create a `HTTP2StreamID` for a specific integer value.
    public init(_ integerID: Int32) {
        precondition(integerID >= 0, "\(integerID) is not a valid HTTP/2 stream ID value")
        self.networkStreamID = integerID
    }
    
    /// Create a `HTTP2StreamID` from a 32-bit value received as part of a frame.
    ///
    /// This will ignore the most significant bit of the provided value.
    internal init(networkID: UInt32) {
        self.networkStreamID = Int32(networkID & ~0x8000_0000)
    }
}

// MARK:- Equatable conformance for HTTP2StreamID
extension HTTP2StreamID: Equatable { }


// MARK:- Hashable conformance for HTTP2StreamID
extension HTTP2StreamID: Hashable { }


// MARK:- Comparable conformance for HTTP2StreamID
extension HTTP2StreamID: Comparable {
    public static func <(lhs: HTTP2StreamID, rhs: HTTP2StreamID) -> Bool {
        return lhs.networkStreamID < rhs.networkStreamID
    }

    public static func >(lhs: HTTP2StreamID, rhs: HTTP2StreamID) -> Bool {
        return lhs.networkStreamID > rhs.networkStreamID
    }

    public static func <=(lhs: HTTP2StreamID, rhs: HTTP2StreamID) -> Bool {
        return lhs.networkStreamID <= rhs.networkStreamID
    }

    public static func >=(lhs: HTTP2StreamID, rhs: HTTP2StreamID) -> Bool {
        return lhs.networkStreamID >= rhs.networkStreamID
    }
}


// MARK:- CustomStringConvertible conformance for HTTP2StreamID
extension HTTP2StreamID: CustomStringConvertible {
    public var description: String {
        return "HTTP2StreamID(\(String(describing: self.networkStreamID)))"
    }
}


// MARK:- ExpressibleByIntegerLiteral conformance for HTTP2StreamID
extension HTTP2StreamID: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = Int32

    public init(integerLiteral value: IntegerLiteralType) {
        precondition(value >= 0 && value <= Int32.max, "\(value) is not a valid HTTP/2 stream ID value")
        self.networkStreamID = value
    }
}


// MARK:- Strideable conformance for HTTP2StreamID
extension HTTP2StreamID: Strideable {
    public typealias Stride = Int

    public func advanced(by n: Stride) -> HTTP2StreamID {
        return HTTP2StreamID(self.networkStreamID + Int32(n))
    }

    public func distance(to other: HTTP2StreamID) -> Stride {
        return Int(other.networkStreamID - self.networkStreamID)
    }
}


// MARK:- Helper initializers for integer conversion.
public extension Int {
    /// Create an Int holding the integer value of this streamID.
    init(_ http2StreamID: HTTP2StreamID) {
        self = Int(http2StreamID.networkStreamID)
    }
}


public extension Int32 {
    /// Create an Int32 holding the integer value of this streamID.
    init(_ http2StreamID: HTTP2StreamID) {
        self = http2StreamID.networkStreamID
    }
}


internal extension UInt32 {
    /// Create a UInt32 holding the integer value of this streamID.
    init(_ http2StreamID: HTTP2StreamID) {
        self = UInt32(http2StreamID.networkStreamID)
    }
}
