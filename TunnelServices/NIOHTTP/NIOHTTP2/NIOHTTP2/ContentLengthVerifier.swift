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
import NIOHPACK

/// An object that verifies that a content-length field on a HTTP request or
/// response is respected.
struct ContentLengthVerifier {
    private var expectedContentLength: Int?
}

extension ContentLengthVerifier {
    /// A chunk of data has been received from the network.
    mutating func receivedDataChunk(length: Int) throws {
        assert(length >= 0, "received data chunks must be positive")

        // If there was no content-length, don't keep track.
        guard let expectedContentLength = self.expectedContentLength else {
            return
        }

        let newContentLength = expectedContentLength - length
        if newContentLength < 0 {
            throw NIOHTTP2Errors.ContentLengthViolated()
        }
        self.expectedContentLength = newContentLength
    }

    /// Called when end of stream has been received. Validates that the complete body was received.
    func endOfStream() throws {
        switch self.expectedContentLength {
        case .none, .some(0):
            break
        default:
            throw NIOHTTP2Errors.ContentLengthViolated()
        }
    }
}

extension ContentLengthVerifier {
    internal init(_ headers: HPACKHeaders) {
        self.expectedContentLength = headers[canonicalForm: "content-length"].first.flatMap { Int($0, radix: 10) }
    }

    /// The verifier for use when content length verification is disabled.
    internal static var disabled: ContentLengthVerifier {
        return ContentLengthVerifier(expectedContentLength: nil)
    }
}

extension ContentLengthVerifier: CustomStringConvertible {
    var description: String {
        return "ContentLengthVerifier(length: \(String(describing: self.expectedContentLength)))"
    }
}
