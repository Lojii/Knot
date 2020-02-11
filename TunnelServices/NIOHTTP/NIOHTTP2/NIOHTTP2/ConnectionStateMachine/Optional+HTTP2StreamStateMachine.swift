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

internal extension Optional where Wrapped == HTTP2StreamStateMachine {
    // This function exists as a performance optimisation: by mutating the optional returned from Dictionary directly
    // inline, we can avoid the dictionary needing to hash the key twice, which it would have to do if we removed the
    // value, mutated it, and then re-inserted it.
    //
    // However, we need to be a bit careful here, as the performance gain from doing this would be completely swamped
    // if the Swift compiler failed to inline this method into its caller. This would force the closure to have its
    // context heap-allocated, and the cost of doing that is vastly higher than the cost of hashing the key a second
    // time. So for this reason we make it clear to the compiler that this method *must* be inlined at the call-site.
    // Sorry about doing this!
    //
    /// Transform the value of an optional HTTP2StreamStateMachine, setting it to nil
    /// if the result of the transformation is to close the stream.
    ///
    /// - parameters:
    ///     - modifier: A block that will modify the contained value in the
    ///         optional, if there is one present.
    /// - returns: The return value of the block or `nil` if the optional was `nil`.
    @inline(__always)
    mutating func autoClosingTransform<T>(_ modifier: (inout Wrapped) -> T) -> T? {
        if self == nil { return nil }

        var unwrapped = self!
        let result = modifier(&unwrapped)
        let closed = unwrapped.closed

        if closed == .notClosed {
            self = unwrapped
        } else {
            self = nil
        }

        return result
    }


    // This function exists as a performance optimisation: by mutating the optional returned from Dictionary directly
    // inline, we can avoid the dictionary needing to hash the key twice, which it would have to do if we removed the
    // value, mutated it, and then re-inserted it.
    //
    // However, we need to be a bit careful here, as the performance gain from doing this would be completely swamped
    // if the Swift compiler failed to inline this method into its caller. This would force these closures to have their
    // contexts heap-allocated, and the cost of doing that is vastly higher than the cost of hashing the key a second
    // time. So for this reason we make it clear to the compiler that this method *must* be inlined at the call-site.
    // Sorry about doing this!
    @inline(__always)
    mutating func transformOrCreateAutoClose<T>(_ creator: () throws -> Wrapped, _ transformer: (inout Wrapped) -> T) rethrows -> T? {
        var unwrapped: Wrapped
        if self == nil {
            unwrapped = try creator()
        } else {
            unwrapped = self!
        }

        let result = transformer(&unwrapped)
        let closed = unwrapped.closed
        if closed == .notClosed {
            self = unwrapped
        } else {
            self = nil
        }

        return result
    }
}
