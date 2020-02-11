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

/* private but tests */
/// Encodes an integer value into a provided memory location.
///
/// - Parameters:
///   - value: The integer value to encode.
///   - buffer: The location at which to begin encoding.
///   - prefix: The number of bits available for use in the first byte at `buffer`.
///   - prefixBits: Existing bits to place in that first byte of `buffer` before encoding `value`.
/// - Returns: Returns the number of bytes used to encode the integer.
@discardableResult
func encodeInteger(_ value: UInt, to buffer: inout ByteBuffer,
                   prefix: Int, prefixBits: UInt8 = 0) -> Int {
    assert(prefix <= 8)
    assert(prefix >= 1)
    
    let start = buffer.writerIndex
    
    let k = (1 << prefix) - 1
    var initialByte = prefixBits
    
    if value < k {
        // it fits already!
        initialByte |= UInt8(truncatingIfNeeded: value)
        buffer.writeInteger(initialByte)
        return 1
    }
    
    // if it won't fit in this byte altogether, fill in all the remaining bits and move
    // to the next byte.
    initialByte |= UInt8(truncatingIfNeeded: k)
    buffer.writeInteger(initialByte)
    
    // deduct the initial [prefix] bits from the value, then encode it seven bits at a time into
    // the remaining bytes.
    var n = value - UInt(k)
    while n >= 128 {
        let nextByte = (1 << 7) | UInt8(n & 0x7f)
        buffer.writeInteger(nextByte)
        n >>= 7
    }
    
    buffer.writeInteger(UInt8(n))
    return buffer.writerIndex - start
}

/* private but tests */
func decodeInteger(from bytes: ByteBufferView, prefix: Int) throws -> (UInt, Int) {
    assert(prefix <= 8)
    assert(prefix >= 1)
    
    let k = (1 << prefix) - 1
    var n: UInt = 0
    var i = bytes.startIndex
    
    if n == 0 {
        // if the available bits aren't all set, the entire value consists of those bits
        if bytes[i] & UInt8(k) != k {
            return (UInt(bytes[i] & UInt8(k)), 1)
        }
        
        n = UInt(k)
        i = bytes.index(after: i)
        if i == bytes.endIndex {
            return (n, bytes.distance(from: bytes.startIndex, to: i))
        }
    }
    
    // for the remaining bytes, as long as the top bit is set, consume the low seven bits.
    var m: UInt = 0
    var b: UInt8 = 0
    repeat {
        if i == bytes.endIndex {
            throw NIOHPACKErrors.InsufficientInput()
        }
        
        b = bytes[i]
        n += UInt(b & 127) * (1 << m)
        m += 7
        i = bytes.index(after: i)
    } while b & 128 == 128
    
    return (n, bytes.distance(from: bytes.startIndex, to: i))
}

extension ByteBuffer {
    mutating func readEncodedInteger(withPrefix prefix: Int = 0) throws -> Int {
        let (result, nread) = try decodeInteger(from: self.readableBytesView, prefix: prefix)
        self.moveReaderIndex(forwardBy: nread)
        return Int(result)
    }
    
    mutating func write(encodedInteger value: UInt, prefix: Int = 0, prefixBits: UInt8 = 0) {
        encodeInteger(value, to: &self, prefix: prefix, prefixBits: prefixBits)
    }
}
