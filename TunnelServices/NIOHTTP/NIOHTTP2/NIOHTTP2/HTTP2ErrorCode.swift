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

/// An HTTP/2 error code.
public struct HTTP2ErrorCode {
    /// The underlying network representation of the error code.
    public var networkCode: Int {
        get {
            return Int(self._networkCode)
        }
        set {
            self._networkCode = UInt32(newValue)
        }
    }

    /// The underlying network representation of the error code.
    fileprivate var _networkCode: UInt32

    /// Create a HTTP/2 error code from the given network value.
    public init(networkCode: Int) {
        self._networkCode = UInt32(networkCode)
    }

    /// Create a `HTTP2ErrorCode` from the 32-bit integer it corresponds to.
    internal init(_ networkInteger: UInt32) {
        self._networkCode = networkInteger
    }

    /// The associated condition is not a result of an error. For example,
    /// a GOAWAY might include this code to indicate graceful shutdown of
    /// a connection.
    public static let noError = HTTP2ErrorCode(networkCode: 0x0)

    /// The endpoint detected an unspecific protocol error. This error is
    /// for use when a more specific error code is not available.
    public static let protocolError = HTTP2ErrorCode(networkCode: 0x01)

    /// The endpoint encountered an unexpected internal error.
    public static let internalError = HTTP2ErrorCode(networkCode: 0x02)

    /// The endpoint detected that its peer violated the flow-control
    /// protocol.
    public static let flowControlError = HTTP2ErrorCode(networkCode: 0x03)

    /// The endpoint sent a SETTINGS frame but did not receive a
    /// response in a timely manner.
    public static let settingsTimeout = HTTP2ErrorCode(networkCode: 0x04)

    /// The endpoint received a frame after a stream was half-closed.
    public static let streamClosed = HTTP2ErrorCode(networkCode: 0x05)

    /// The endpoint received a frame with an invalid size.
    public static let frameSizeError = HTTP2ErrorCode(networkCode: 0x06)

    /// The endpoint refused the stream prior to performing any
    /// application processing.
    public static let refusedStream = HTTP2ErrorCode(networkCode: 0x07)

    /// Used by the endpoint to indicate that the stream is no
    /// longer needed.
    public static let cancel = HTTP2ErrorCode(networkCode: 0x08)

    /// The endpoint is unable to maintain the header compression
    /// context for the connection.
    public static let compressionError = HTTP2ErrorCode(networkCode: 0x09)

    /// The connection established in response to a CONNECT request
    /// was reset or abnormally closed.
    public static let connectError = HTTP2ErrorCode(networkCode: 0x0a)

    /// The endpoint detected that its peer is exhibiting a behavior
    /// that might be generating excessive load.
    public static let enhanceYourCalm = HTTP2ErrorCode(networkCode: 0x0b)

    /// The underlying transport has properties that do not meet
    /// minimum security requirements.
    public static let inadequateSecurity = HTTP2ErrorCode(networkCode: 0x0c)

    /// The endpoint requires that HTTP/1.1 be used instead of HTTP/2.
    public static let http11Required = HTTP2ErrorCode(networkCode: 0x0d)
}

extension HTTP2ErrorCode: Equatable { }

extension HTTP2ErrorCode: Hashable { }

extension HTTP2ErrorCode: CustomDebugStringConvertible {
    public var debugDescription: String {
        let errorCodeDescription: String
        switch self {
        case .noError:
            errorCodeDescription = "No Error"
        case .protocolError:
            errorCodeDescription = "ProtocolError"
        case .internalError:
            errorCodeDescription = "Internal Error"
        case .flowControlError:
            errorCodeDescription = "Flow Control Error"
        case .settingsTimeout:
            errorCodeDescription = "Settings Timeout"
        case .streamClosed:
            errorCodeDescription = "Stream Closed"
        case .frameSizeError:
            errorCodeDescription = "Frame Size Error"
        case .refusedStream:
            errorCodeDescription = "Refused Stream"
        case .cancel:
            errorCodeDescription = "Cancel"
        case .compressionError:
            errorCodeDescription = "Compression Error"
        case .connectError:
            errorCodeDescription = "Connect Error"
        case .enhanceYourCalm:
            errorCodeDescription = "Enhance Your Calm"
        case .inadequateSecurity:
            errorCodeDescription = "Inadequate Security"
        case .http11Required:
            errorCodeDescription = "HTTP/1.1 Required"
        default:
            errorCodeDescription = "Unknown Error"
        }

        return "HTTP2ErrorCode<0x\(String(self.networkCode, radix: 16)) \(errorCodeDescription)>"
    }
}

public extension UInt32 {
    /// Create a 32-bit integer corresponding to the given `HTTP2ErrorCode`.
    init(http2ErrorCode code: HTTP2ErrorCode) {
        self = code._networkCode
    }
}

public extension Int {
    /// Create an integer corresponding to the given `HTTP2ErrorCode`.
    init(http2ErrorCode code: HTTP2ErrorCode) {
        self = code.networkCode
    }
}

public extension ByteBuffer {
    /// Serializes a `HTTP2ErrorCode` into a `ByteBuffer` in the appropriate endianness
    /// for use in HTTP/2.
    ///
    /// - parameters:
    ///     - code: The `HTTP2ErrorCode` to serialize.
    /// - returns: The number of bytes written.
    mutating func write(http2ErrorCode code: HTTP2ErrorCode) -> Int {
        return self.writeInteger(UInt32(http2ErrorCode: code))
    }
}
