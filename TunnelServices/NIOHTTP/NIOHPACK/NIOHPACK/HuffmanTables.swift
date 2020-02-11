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

typealias HuffmanTableEntry = (bits: UInt32, nbits: Int)

/// Base-64 decoding has been jovially purloined from swift-corelibs-foundation/.../NSData.swift.
/// The ranges of ASCII characters that are used to encode data in Base64.
private let base64ByteMappings: [Range<UInt8>] = [
    65 ..< 91,      // A-Z
    97 ..< 123,     // a-z
    48 ..< 58,      // 0-9
    43 ..< 44,      // +
    47 ..< 48,      // /
]
/**
 Padding character used when the number of bytes to encode is not divisible by 3
 */
private let base64Padding : UInt8 = 61 // =

/**
 This method takes a byte with a character from Base64-encoded string
 and gets the binary value that the character corresponds to.
 
 - parameter byte:       The byte with the Base64 character.
 - returns:              Base64DecodedByte value containing the result (Valid , Invalid, Padding)
 */
private enum Base64DecodedByte {
    case valid(UInt8)
    case invalid
    case padding
}

private func base64DecodeByte(_ byte: UInt8) -> Base64DecodedByte {
    guard byte != base64Padding else {return .padding}
    var decodedStart: UInt8 = 0
    for range in base64ByteMappings {
        if range.contains(byte) {
            let result = decodedStart + (byte - range.lowerBound)
            return .valid(result)
        }
        decodedStart += range.upperBound - range.lowerBound
    }
    return .invalid
}

/**
 This method decodes Base64-encoded data.
 
 If the input contains any bytes that are not valid Base64 characters,
 this will return nil.
 
 - parameter bytes:      The Base64 bytes
 - parameter options:    Options for handling invalid input
 - returns:              The decoded bytes.
 */
private func base64DecodeBytes<C: Collection>(_ bytes: C, ignoreUnknownCharacters: Bool = false) -> [UInt8]? where C.Element == UInt8 {
    var decodedBytes = [UInt8]()
    decodedBytes.reserveCapacity((bytes.count/3)*2)
    
    var currentByte : UInt8 = 0
    var validCharacterCount = 0
    var paddingCount = 0
    var index = 0
    
    
    for base64Char in bytes {
        
        let value : UInt8
        
        switch base64DecodeByte(base64Char) {
        case .valid(let v):
            value = v
            validCharacterCount += 1
        case .invalid:
            if ignoreUnknownCharacters {
                continue
            } else {
                return nil
            }
        case .padding:
            paddingCount += 1
            continue
        }
        
        //padding found in the middle of the sequence is invalid
        if paddingCount > 0 {
            return nil
        }
        
        switch index%4 {
        case 0:
            currentByte = (value << 2)
        case 1:
            currentByte |= (value >> 4)
            decodedBytes.append(currentByte)
            currentByte = (value << 4)
        case 2:
            currentByte |= (value >> 2)
            decodedBytes.append(currentByte)
            currentByte = (value << 6)
        case 3:
            currentByte |= value
            decodedBytes.append(currentByte)
        default:
            fatalError()
        }
        
        index += 1
    }
    
    guard (validCharacterCount + paddingCount)%4 == 0 else {
        //invalid character count
        return nil
    }
    return decodedBytes
}

internal let StaticHuffmanTable: [HuffmanTableEntry] = [
    (0x1ff8, 13), (0x7fffd8, 23), (0xfffffe2, 28), (0xfffffe3, 28), (0xfffffe4, 28), (0xfffffe5, 28),
    (0xfffffe6, 28), (0xfffffe7, 28), (0xfffffe8, 28), (0xffffea, 24), (0x3ffffffc, 30), (0xfffffe9, 28),
    (0xfffffea, 28), (0x3ffffffd, 30), (0xfffffeb, 28), (0xfffffec, 28), (0xfffffed, 28), (0xfffffee, 28),
    (0xfffffef, 28), (0xffffff0, 28), (0xffffff1, 28), (0xffffff2, 28), (0x3ffffffe, 30), (0xffffff3, 28),
    (0xffffff4, 28), (0xffffff5, 28), (0xffffff6, 28), (0xffffff7, 28), (0xffffff8, 28), (0xffffff9, 28),
    (0xffffffa, 28), (0xffffffb, 28), (0x14, 6), (0x3f8, 10), (0x3f9, 10), (0xffa, 12),
    (0x1ff9, 13), (0x15, 6), (0xf8, 8), (0x7fa, 11), (0x3fa, 10), (0x3fb, 10),
    (0xf9, 8), (0x7fb, 11), (0xfa, 8), (0x16, 6), (0x17, 6), (0x18, 6),
    (0x0, 5), (0x1, 5), (0x2, 5), (0x19, 6), (0x1a, 6), (0x1b, 6),
    (0x1c, 6), (0x1d, 6), (0x1e, 6), (0x1f, 6), (0x5c, 7), (0xfb, 8),
    (0x7ffc, 15), (0x20, 6), (0xffb, 12), (0x3fc, 10), (0x1ffa, 13), (0x21, 6),
    (0x5d, 7), (0x5e, 7), (0x5f, 7), (0x60, 7), (0x61, 7), (0x62, 7),
    (0x63, 7), (0x64, 7), (0x65, 7), (0x66, 7), (0x67, 7), (0x68, 7),
    (0x69, 7), (0x6a, 7), (0x6b, 7), (0x6c, 7), (0x6d, 7), (0x6e, 7),
    (0x6f, 7), (0x70, 7), (0x71, 7), (0x72, 7), (0xfc, 8), (0x73, 7),
    (0xfd, 8), (0x1ffb, 13), (0x7fff0, 19), (0x1ffc, 13), (0x3ffc, 14), (0x22, 6),
    (0x7ffd, 15), (0x3, 5), (0x23, 6), (0x4, 5), (0x24, 6), (0x5, 5),
    (0x25, 6), (0x26, 6), (0x27, 6), (0x6, 5), (0x74, 7), (0x75, 7),
    (0x28, 6), (0x29, 6), (0x2a, 6), (0x7, 5), (0x2b, 6), (0x76, 7),
    (0x2c, 6), (0x8, 5), (0x9, 5), (0x2d, 6), (0x77, 7), (0x78, 7),
    (0x79, 7), (0x7a, 7), (0x7b, 7), (0x7ffe, 15), (0x7fc, 11), (0x3ffd, 14),
    (0x1ffd, 13), (0xffffffc, 28), (0xfffe6, 20), (0x3fffd2, 22), (0xfffe7, 20), (0xfffe8, 20),
    (0x3fffd3, 22), (0x3fffd4, 22), (0x3fffd5, 22), (0x7fffd9, 23), (0x3fffd6, 22), (0x7fffda, 23),
    (0x7fffdb, 23), (0x7fffdc, 23), (0x7fffdd, 23), (0x7fffde, 23), (0xffffeb, 24), (0x7fffdf, 23),
    (0xffffec, 24), (0xffffed, 24), (0x3fffd7, 22), (0x7fffe0, 23), (0xffffee, 24), (0x7fffe1, 23),
    (0x7fffe2, 23), (0x7fffe3, 23), (0x7fffe4, 23), (0x1fffdc, 21), (0x3fffd8, 22), (0x7fffe5, 23),
    (0x3fffd9, 22), (0x7fffe6, 23), (0x7fffe7, 23), (0xffffef, 24), (0x3fffda, 22), (0x1fffdd, 21),
    (0xfffe9, 20), (0x3fffdb, 22), (0x3fffdc, 22), (0x7fffe8, 23), (0x7fffe9, 23), (0x1fffde, 21),
    (0x7fffea, 23), (0x3fffdd, 22), (0x3fffde, 22), (0xfffff0, 24), (0x1fffdf, 21), (0x3fffdf, 22),
    (0x7fffeb, 23), (0x7fffec, 23), (0x1fffe0, 21), (0x1fffe1, 21), (0x3fffe0, 22), (0x1fffe2, 21),
    (0x7fffed, 23), (0x3fffe1, 22), (0x7fffee, 23), (0x7fffef, 23), (0xfffea, 20), (0x3fffe2, 22),
    (0x3fffe3, 22), (0x3fffe4, 22), (0x7ffff0, 23), (0x3fffe5, 22), (0x3fffe6, 22), (0x7ffff1, 23),
    (0x3ffffe0, 26), (0x3ffffe1, 26), (0xfffeb, 20), (0x7fff1, 19), (0x3fffe7, 22), (0x7ffff2, 23),
    (0x3fffe8, 22), (0x1ffffec, 25), (0x3ffffe2, 26), (0x3ffffe3, 26), (0x3ffffe4, 26), (0x7ffffde, 27),
    (0x7ffffdf, 27), (0x3ffffe5, 26), (0xfffff1, 24), (0x1ffffed, 25), (0x7fff2, 19), (0x1fffe3, 21),
    (0x3ffffe6, 26), (0x7ffffe0, 27), (0x7ffffe1, 27), (0x3ffffe7, 26), (0x7ffffe2, 27), (0xfffff2, 24),
    (0x1fffe4, 21), (0x1fffe5, 21), (0x3ffffe8, 26), (0x3ffffe9, 26), (0xffffffd, 28), (0x7ffffe3, 27),
    (0x7ffffe4, 27), (0x7ffffe5, 27), (0xfffec, 20), (0xfffff3, 24), (0xfffed, 20), (0x1fffe6, 21),
    (0x3fffe9, 22), (0x1fffe7, 21), (0x1fffe8, 21), (0x7ffff3, 23), (0x3fffea, 22), (0x3fffeb, 22),
    (0x1ffffee, 25), (0x1ffffef, 25), (0xfffff4, 24), (0xfffff5, 24), (0x3ffffea, 26), (0x7ffff4, 23),
    (0x3ffffeb, 26), (0x7ffffe6, 27), (0x3ffffec, 26), (0x3ffffed, 26), (0x7ffffe7, 27), (0x7ffffe8, 27),
    (0x7ffffe9, 27), (0x7ffffea, 27), (0x7ffffeb, 27), (0xffffffe, 28), (0x7ffffec, 27), (0x7ffffed, 27),
    (0x7ffffee, 27), (0x7ffffef, 27), (0x7fffff0, 27), (0x3ffffee, 26), (0x3fffffff, 30)
]

// Great googly-moogly that's a large array! This comes from the nice folks at nghttp.

/*
 This implementation of a Huffman decoding table for HTTP/2 is essentially a
 Swift port of the C tables from nghttp2's Huffman decoding implementation,
 and is thus clearly a derivative work of the nghttp2 file
 ``nghttp2_hd_huffman_data.c``, obtained from https://github.com/tatsuhiro-t/nghttp2/.
 That work is also available under the Apache 2.0 license under the following terms:
 
 Copyright (c) 2013 Tatsuhiro Tsujikawa
 
 Permission is hereby granted, free of charge, to any person obtaining
 a copy of this software and associated documentation files (the
 "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
 the following conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

typealias HuffmanDecodeEntry = (state: UInt8, flags: HuffmanDecoderFlags, sym: UInt8)

internal struct HuffmanDecoderFlags : OptionSet
{
    var rawValue: UInt8
    
    static let none     = HuffmanDecoderFlags(rawValue: 0b000)
    static let accepted = HuffmanDecoderFlags(rawValue: 0b001)
    static let symbol   = HuffmanDecoderFlags(rawValue: 0b010)
    static let failure  = HuffmanDecoderFlags(rawValue: 0b100)
}

/**
 This was described nicely by `@Lukasa` in his Python implementation:
 
 The essence of this approach is that it builds a finite state machine out of
 4-bit nybbles of Huffman coded data. The input function passes 4 bits worth of
 data to the state machine each time, which uses those 4 bits of data along with
 the current accumulated state data to process the data given.

 For the sake of efficiency, the in-memory representation of the states,
 transitions, and result values of the state machine are represented as a long
 list containing three-tuples. This list is enormously long, and viewing it as
 an in-memory representation is not very clear, but it is laid out here in a way
 that is intended to be *somewhat* more clear.

 Essentially, the list is structured as 256 collections of 16 entries (one for
 each nybble) of three-tuples. Each collection is called a "node", and the
 zeroth collection is called the "root node". The state machine tracks one
 value: the "state" byte.

 For each nybble passed to the state machine, it first multiplies the "state"
 byte by 16 and adds the numerical value of the nybble. This number is the index
 into the large flat list.

 The three-tuple that is found by looking up that index consists of three
 values:

 - a new state value, used for subsequent decoding
 - a collection of flags, used to determine whether data is emitted or whether
 the state machine is complete.
 - the byte value to emit, assuming that emitting a byte is required.

 The flags are consulted, if necessary a byte is emitted, and then the next
 nybble is used. This continues until the state machine believes it has
 completely Huffman-decoded the data.

 This approach has relatively little indirection, and therefore performs
 relatively well. The total number of loop
 iterations is 4x the number of bytes passed to the decoder.
 */
internal struct HuffmanDecoderTable {
    subscript(state state: UInt8, nybble nybble: UInt8) -> HuffmanDecodeEntry {
        assert(nybble < 16)
        let index = (Int(state) * 16) + Int(nybble)
        return HuffmanDecoderTable.rawTable[index]
    }
    
    // You would not *believe* how much faster this compiles now.
    // TODO(jim): decide if it's worth dropping the un-encoded raw bytes into
    // a segment of the binary, i.e. __DATA,__huffman_decode_table. I don't know
    // how to do that (automatically) via SwiftPM though, only via Xcode.
    private static let rawTable: [HuffmanDecodeEntry] = {
        let base64_table_bytes: StaticString = """
                BAAABQAABwAACAAACwAADAAAEAAAEwAAGQAAHAAAIAAAIwAAKgAAMQAAOQAAQAEA
                AAMwAAMxAAMyAANhAANjAANlAANpAANvAANzAAN0DQAADgAAEQAAEgAAFAAAFQAA
                AQIwFgMwAQIxFgMxAQIyFgMyAQJhFgNhAQJjFgNjAQJlFgNlAQJpFgNpAQJvFgNv
                AgIwCQIwFwIwKAMwAgIxCQIxFwIxKAMxAgIyCQIyFwIyKAMyAgJhCQJhFwJhKANh
                AwIwBgIwCgIwDwIwGAIwHwIwKQIwOAMwAwIxBgIxCgIxDwIxGAIxHwIxKQIxOAMx
                AwIyBgIyCgIyDwIyGAIyHwIyKQIyOAMyAwJhBgJhCgJhDwJhGAJhHwJhKQJhOANh
                AgJjCQJjFwJjKANjAgJlCQJlFwJlKANlAgJpCQJpFwJpKANpAgJvCQJvFwJvKANv
                AwJjBgJjCgJjDwJjGAJjHwJjKQJjOANjAwJlBgJlCgJlDwJlGAJlHwJlKQJlOANl
                AwJpBgJpCgJpDwJpGAJpHwJpKQJpOANpAwJvBgJvCgJvDwJvGAJvHwJvKQJvOANv
                AQJzFgNzAQJ0FgN0AAMgAAMlAAMtAAMuAAMvAAMzAAM0AAM1AAM2AAM3AAM4AAM5
                AgJzCQJzFwJzKANzAgJ0CQJ0FwJ0KAN0AQIgFgMgAQIlFgMlAQItFgMtAQIuFgMu
                AwJzBgJzCgJzDwJzGAJzHwJzKQJzOANzAwJ0BgJ0CgJ0DwJ0GAJ0HwJ0KQJ0OAN0
                AgIgCQIgFwIgKAMgAgIlCQIlFwIlKAMlAgItCQItFwItKAMtAgIuCQIuFwIuKAMu
                AwIgBgIgCgIgDwIgGAIgHwIgKQIgOAMgAwIlBgIlCgIlDwIlGAIlHwIlKQIlOAMl
                AwItBgItCgItDwItGAItHwItKQItOAMtAwIuBgIuCgIuDwIuGAIuHwIuKQIuOAMu
                AQIvFgMvAQIzFgMzAQI0FgM0AQI1FgM1AQI2FgM2AQI3FgM3AQI4FgM4AQI5FgM5
                AgIvCQIvFwIvKAMvAgIzCQIzFwIzKAMzAgI0CQI0FwI0KAM0AgI1CQI1FwI1KAM1
                AwIvBgIvCgIvDwIvGAIvHwIvKQIvOAMvAwIzBgIzCgIzDwIzGAIzHwIzKQIzOAMz
                AwI0BgI0CgI0DwI0GAI0HwI0KQI0OAM0AwI1BgI1CgI1DwI1GAI1HwI1KQI1OAM1
                AgI2CQI2FwI2KAM2AgI3CQI3FwI3KAM3AgI4CQI4FwI4KAM4AgI5CQI5FwI5KAM5
                AwI2BgI2CgI2DwI2GAI2HwI2KQI2OAM2AwI3BgI3CgI3DwI3GAI3HwI3KQI3OAM3
                AwI4BgI4CgI4DwI4GAI4HwI4KQI4OAM4AwI5BgI5CgI5DwI5GAI5HwI5KQI5OAM5
                GgAAGwAAHQAAHgAAIQAAIgAAJAAAJQAAKwAALgAAMgAANQAAOgAAPQAAQQAARAEA
                AAM9AANBAANfAANiAANkAANmAANnAANoAANsAANtAANuAANwAANyAAN1JgAAJwAA
                AQI9FgM9AQJBFgNBAQJfFgNfAQJiFgNiAQJkFgNkAQJmFgNmAQJnFgNnAQJoFgNo
                AgI9CQI9FwI9KAM9AgJBCQJBFwJBKANBAgJfCQJfFwJfKANfAgJiCQJiFwJiKANi
                AwI9BgI9CgI9DwI9GAI9HwI9KQI9OAM9AwJBBgJBCgJBDwJBGAJBHwJBKQJBOANB
                AwJfBgJfCgJfDwJfGAJfHwJfKQJfOANfAwJiBgJiCgJiDwJiGAJiHwJiKQJiOANi
                AgJkCQJkFwJkKANkAgJmCQJmFwJmKANmAgJnCQJnFwJnKANnAgJoCQJoFwJoKANo
                AwJkBgJkCgJkDwJkGAJkHwJkKQJkOANkAwJmBgJmCgJmDwJmGAJmHwJmKQJmOANm
                AwJnBgJnCgJnDwJnGAJnHwJnKQJnOANnAwJoBgJoCgJoDwJoGAJoHwJoKQJoOANo
                AQJsFgNsAQJtFgNtAQJuFgNuAQJwFgNwAQJyFgNyAQJ1FgN1AAM6AANCAANDAANE
                AgJsCQJsFwJsKANsAgJtCQJtFwJtKANtAgJuCQJuFwJuKANuAgJwCQJwFwJwKANw
                AwJsBgJsCgJsDwJsGAJsHwJsKQJsOANsAwJtBgJtCgJtDwJtGAJtHwJtKQJtOANt
                AwJuBgJuCgJuDwJuGAJuHwJuKQJuOANuAwJwBgJwCgJwDwJwGAJwHwJwKQJwOANw
                AgJyCQJyFwJyKANyAgJ1CQJ1FwJ1KAN1AQI6FgM6AQJCFgNCAQJDFgNDAQJEFgNE
                AwJyBgJyCgJyDwJyGAJyHwJyKQJyOANyAwJ1BgJ1CgJ1DwJ1GAJ1HwJ1KQJ1OAN1
                AgI6CQI6FwI6KAM6AgJCCQJCFwJCKANCAgJDCQJDFwJDKANDAgJECQJEFwJEKANE
                AwI6BgI6CgI6DwI6GAI6HwI6KQI6OAM6AwJCBgJCCgJCDwJCGAJCHwJCKQJCOANC
                AwJDBgJDCgJDDwJDGAJDHwJDKQJDOANDAwJEBgJECgJEDwJEGAJEHwJEKQJEOANE
                LAAALQAALwAAMAAAMwAANAAANgAANwAAOwAAPAAAPgAAPwAAQgAAQwAARQAASAEA
                AANFAANGAANHAANIAANJAANKAANLAANMAANNAANOAANPAANQAANRAANSAANTAANU
                AQJFFgNFAQJGFgNGAQJHFgNHAQJIFgNIAQJJFgNJAQJKFgNKAQJLFgNLAQJMFgNM
                AgJFCQJFFwJFKANFAgJGCQJGFwJGKANGAgJHCQJHFwJHKANHAgJICQJIFwJIKANI
                AwJFBgJFCgJFDwJFGAJFHwJFKQJFOANFAwJGBgJGCgJGDwJGGAJGHwJGKQJGOANG
                AwJHBgJHCgJHDwJHGAJHHwJHKQJHOANHAwJIBgJICgJIDwJIGAJIHwJIKQJIOANI
                AgJJCQJJFwJJKANJAgJKCQJKFwJKKANKAgJLCQJLFwJLKANLAgJMCQJMFwJMKANM
                AwJJBgJJCgJJDwJJGAJJHwJJKQJJOANJAwJKBgJKCgJKDwJKGAJKHwJKKQJKOANK
                AwJLBgJLCgJLDwJLGAJLHwJLKQJLOANLAwJMBgJMCgJMDwJMGAJMHwJMKQJMOANM
                AQJNFgNNAQJOFgNOAQJPFgNPAQJQFgNQAQJRFgNRAQJSFgNSAQJTFgNTAQJUFgNU
                AgJNCQJNFwJNKANNAgJOCQJOFwJOKANOAgJPCQJPFwJPKANPAgJQCQJQFwJQKANQ
                AwJNBgJNCgJNDwJNGAJNHwJNKQJNOANNAwJOBgJOCgJODwJOGAJOHwJOKQJOOANO
                AwJPBgJPCgJPDwJPGAJPHwJPKQJPOANPAwJQBgJQCgJQDwJQGAJQHwJQKQJQOANQ
                AgJRCQJRFwJRKANRAgJSCQJSFwJSKANSAgJTCQJTFwJTKANTAgJUCQJUFwJUKANU
                AwJRBgJRCgJRDwJRGAJRHwJRKQJROANRAwJSBgJSCgJSDwJSGAJSHwJSKQJSOANS
                AwJTBgJTCgJTDwJTGAJTHwJTKQJTOANTAwJUBgJUCgJUDwJUGAJUHwJUKQJUOANU
                AANVAANWAANXAANZAANqAANrAANxAAN2AAN3AAN4AAN5AAN6RgAARwAASQAASgEA
                AQJVFgNVAQJWFgNWAQJXFgNXAQJZFgNZAQJqFgNqAQJrFgNrAQJxFgNxAQJ2FgN2
                AgJVCQJVFwJVKANVAgJWCQJWFwJWKANWAgJXCQJXFwJXKANXAgJZCQJZFwJZKANZ
                AwJVBgJVCgJVDwJVGAJVHwJVKQJVOANVAwJWBgJWCgJWDwJWGAJWHwJWKQJWOANW
                AwJXBgJXCgJXDwJXGAJXHwJXKQJXOANXAwJZBgJZCgJZDwJZGAJZHwJZKQJZOANZ
                AgJqCQJqFwJqKANqAgJrCQJrFwJrKANrAgJxCQJxFwJxKANxAgJ2CQJ2FwJ2KAN2
                AwJqBgJqCgJqDwJqGAJqHwJqKQJqOANqAwJrBgJrCgJrDwJrGAJrHwJrKQJrOANr
                AwJxBgJxCgJxDwJxGAJxHwJxKQJxOANxAwJ2BgJ2CgJ2DwJ2GAJ2HwJ2KQJ2OAN2
                AQJ3FgN3AQJ4FgN4AQJ5FgN5AQJ6FgN6AAMmAAMqAAMsAAM7AANYAANaSwAATgAA
                AgJ3CQJ3FwJ3KAN3AgJ4CQJ4FwJ4KAN4AgJ5CQJ5FwJ5KAN5AgJ6CQJ6FwJ6KAN6
                AwJ3BgJ3CgJ3DwJ3GAJ3HwJ3KQJ3OAN3AwJ4BgJ4CgJ4DwJ4GAJ4HwJ4KQJ4OAN4
                AwJ5BgJ5CgJ5DwJ5GAJ5HwJ5KQJ5OAN5AwJ6BgJ6CgJ6DwJ6GAJ6HwJ6KQJ6OAN6
                AQImFgMmAQIqFgMqAQIsFgMsAQI7FgM7AQJYFgNYAQJaFgNaTAAATQAATwAAUQAA
                AgImCQImFwImKAMmAgIqCQIqFwIqKAMqAgIsCQIsFwIsKAMsAgI7CQI7FwI7KAM7
                AwImBgImCgImDwImGAImHwImKQImOAMmAwIqBgIqCgIqDwIqGAIqHwIqKQIqOAMq
                AwIsBgIsCgIsDwIsGAIsHwIsKQIsOAMsAwI7BgI7CgI7DwI7GAI7HwI7KQI7OAM7
                AgJYCQJYFwJYKANYAgJaCQJaFwJaKANaAAMhAAMiAAMoAAMpAAM/UAAAUgAAVAAA
                AwJYBgJYCgJYDwJYGAJYHwJYKQJYOANYAwJaBgJaCgJaDwJaGAJaHwJaKQJaOANa
                AQIhFgMhAQIiFgMiAQIoFgMoAQIpFgMpAQI/FgM/AAMnAAMrAAN8UwAAVQAAWAAA
                AgIhCQIhFwIhKAMhAgIiCQIiFwIiKAMiAgIoCQIoFwIoKAMoAgIpCQIpFwIpKAMp
                AwIhBgIhCgIhDwIhGAIhHwIhKQIhOAMhAwIiBgIiCgIiDwIiGAIiHwIiKQIiOAMi
                AwIoBgIoCgIoDwIoGAIoHwIoKQIoOAMoAwIpBgIpCgIpDwIpGAIpHwIpKQIpOAMp
                AgI/CQI/FwI/KAM/AQInFgMnAQIrFgMrAQJ8FgN8AAMjAAM+VgAAVwAAWQAAWgAA
                AwI/BgI/CgI/DwI/GAI/HwI/KQI/OAM/AgInCQInFwInKAMnAgIrCQIrFwIrKAMr
                AwInBgInCgInDwInGAInHwInKQInOAMnAwIrBgIrCgIrDwIrGAIrHwIrKQIrOAMr
                AgJ8CQJ8FwJ8KAN8AQIjFgMjAQI+FgM+AAMAAAMkAANAAANbAANdAAN+WwAAXAAA
                AwJ8BgJ8CgJ8DwJ8GAJ8HwJ8KQJ8OAN8AgIjCQIjFwIjKAMjAgI+CQI+FwI+KAM+
                AwIjBgIjCgIjDwIjGAIjHwIjKQIjOAMjAwI+BgI+CgI+DwI+GAI+HwI+KQI+OAM+
                AQIAFgMAAQIkFgMkAQJAFgNAAQJbFgNbAQJdFgNdAQJ+FgN+AANeAAN9XQAAXgAA
                AgIACQIAFwIAKAMAAgIkCQIkFwIkKAMkAgJACQJAFwJAKANAAgJbCQJbFwJbKANb
                AwIABgIACgIADwIAGAIAHwIAKQIAOAMAAwIkBgIkCgIkDwIkGAIkHwIkKQIkOAMk
                AwJABgJACgJADwJAGAJAHwJAKQJAOANAAwJbBgJbCgJbDwJbGAJbHwJbKQJbOANb
                AgJdCQJdFwJdKANdAgJ+CQJ+FwJ+KAN+AQJeFgNeAQJ9FgN9AAM8AANgAAN7XwAA
                AwJdBgJdCgJdDwJdGAJdHwJdKQJdOANdAwJ+BgJ+CgJ+DwJ+GAJ+HwJ+KQJ+OAN+
                AgJeCQJeFwJeKANeAgJ9CQJ9FwJ9KAN9AQI8FgM8AQJgFgNgAQJ7FgN7YAAAbgAA
                AwJeBgJeCgJeDwJeGAJeHwJeKQJeOANeAwJ9BgJ9CgJ9DwJ9GAJ9HwJ9KQJ9OAN9
                AgI8CQI8FwI8KAM8AgJgCQJgFwJgKANgAgJ7CQJ7FwJ7KAN7YQAAZQAAbwAAhQAA
                AwI8BgI8CgI8DwI8GAI8HwI8KQI8OAM8AwJgBgJgCgJgDwJgGAJgHwJgKQJgOANg
                AwJ7BgJ7CgJ7DwJ7GAJ7HwJ7KQJ7OAN7YgAAYwAAZgAAaQAAcAAAdwAAhgAAmQAA
                AANcAAPDAAPQZAAAZwAAaAAAagAAawAAcQAAdAAAeAAAfgAAhwAAjgAAmgAAqQAA
                AQJcFgNcAQLDFgPDAQLQFgPQAAOAAAOCAAODAAOiAAO4AAPCAAPgAAPibAAAbQAA
                AgJcCQJcFwJcKANcAgLDCQLDFwLDKAPDAgLQCQLQFwLQKAPQAQKAFgOAAQKCFgOC
                AwJcBgJcCgJcDwJcGAJcHwJcKQJcOANcAwLDBgLDCgLDDwLDGALDHwLDKQLDOAPD
                AwLQBgLQCgLQDwLQGALQHwLQKQLQOAPQAgKACQKAFwKAKAOAAgKCCQKCFwKCKAOC
                AwKABgKACgKADwKAGAKAHwKAKQKAOAOAAwKCBgKCCgKCDwKCGAKCHwKCKQKCOAOC
                AQKDFgODAQKiFgOiAQK4FgO4AQLCFgPCAQLgFgPgAQLiFgPiAAOZAAOhAAOnAAOs
                AgKDCQKDFwKDKAODAgKiCQKiFwKiKAOiAgK4CQK4FwK4KAO4AgLCCQLCFwLCKAPC
                AwKDBgKDCgKDDwKDGAKDHwKDKQKDOAODAwKiBgKiCgKiDwKiGAKiHwKiKQKiOAOi
                AwK4BgK4CgK4DwK4GAK4HwK4KQK4OAO4AwLCBgLCCgLCDwLCGALCHwLCKQLCOAPC
                AgLgCQLgFwLgKAPgAgLiCQLiFwLiKAPiAQKZFgOZAQKhFgOhAQKnFgOnAQKsFgOs
                AwLgBgLgCgLgDwLgGALgHwLgKQLgOAPgAwLiBgLiCgLiDwLiGALiHwLiKQLiOAPi
                AgKZCQKZFwKZKAOZAgKhCQKhFwKhKAOhAgKnCQKnFwKnKAOnAgKsCQKsFwKsKAOs
                AwKZBgKZCgKZDwKZGAKZHwKZKQKZOAOZAwKhBgKhCgKhDwKhGAKhHwKhKQKhOAOh
                AwKnBgKnCgKnDwKnGAKnHwKnKQKnOAOnAwKsBgKsCgKsDwKsGAKsHwKsKQKsOAOs
                cgAAcwAAdQAAdgAAeQAAewAAfwAAggAAiAAAiwAAjwAAkgAAmwAAogAAqgAAtAAA
                AAOwAAOxAAOzAAPRAAPYAAPZAAPjAAPlAAPmegAAfAAAfQAAgAAAgQAAgwAAhAAA
                AQKwFgOwAQKxFgOxAQKzFgOzAQLRFgPRAQLYFgPYAQLZFgPZAQLjFgPjAQLlFgPl
                AgKwCQKwFwKwKAOwAgKxCQKxFwKxKAOxAgKzCQKzFwKzKAOzAgLRCQLRFwLRKAPR
                AwKwBgKwCgKwDwKwGAKwHwKwKQKwOAOwAwKxBgKxCgKxDwKxGAKxHwKxKQKxOAOx
                AwKzBgKzCgKzDwKzGAKzHwKzKQKzOAOzAwLRBgLRCgLRDwLRGALRHwLRKQLROAPR
                AgLYCQLYFwLYKAPYAgLZCQLZFwLZKAPZAgLjCQLjFwLjKAPjAgLlCQLlFwLlKAPl
                AwLYBgLYCgLYDwLYGALYHwLYKQLYOAPYAwLZBgLZCgLZDwLZGALZHwLZKQLZOAPZ
                AwLjBgLjCgLjDwLjGALjHwLjKQLjOAPjAwLlBgLlCgLlDwLlGALlHwLlKQLlOAPl
                AQLmFgPmAAOBAAOEAAOFAAOGAAOIAAOSAAOaAAOcAAOgAAOjAAOkAAOpAAOqAAOt
                AgLmCQLmFwLmKAPmAQKBFgOBAQKEFgOEAQKFFgOFAQKGFgOGAQKIFgOIAQKSFgOS
                AwLmBgLmCgLmDwLmGALmHwLmKQLmOAPmAgKBCQKBFwKBKAOBAgKECQKEFwKEKAOE
                AwKBBgKBCgKBDwKBGAKBHwKBKQKBOAOBAwKEBgKECgKEDwKEGAKEHwKEKQKEOAOE
                AgKFCQKFFwKFKAOFAgKGCQKGFwKGKAOGAgKICQKIFwKIKAOIAgKSCQKSFwKSKAOS
                AwKFBgKFCgKFDwKFGAKFHwKFKQKFOAOFAwKGBgKGCgKGDwKGGAKGHwKGKQKGOAOG
                AwKIBgKICgKIDwKIGAKIHwKIKQKIOAOIAwKSBgKSCgKSDwKSGAKSHwKSKQKSOAOS
                AQKaFgOaAQKcFgOcAQKgFgOgAQKjFgOjAQKkFgOkAQKpFgOpAQKqFgOqAQKtFgOt
                AgKaCQKaFwKaKAOaAgKcCQKcFwKcKAOcAgKgCQKgFwKgKAOgAgKjCQKjFwKjKAOj
                AwKaBgKaCgKaDwKaGAKaHwKaKQKaOAOaAwKcBgKcCgKcDwKcGAKcHwKcKQKcOAOc
                AwKgBgKgCgKgDwKgGAKgHwKgKQKgOAOgAwKjBgKjCgKjDwKjGAKjHwKjKQKjOAOj
                AgKkCQKkFwKkKAOkAgKpCQKpFwKpKAOpAgKqCQKqFwKqKAOqAgKtCQKtFwKtKAOt
                AwKkBgKkCgKkDwKkGAKkHwKkKQKkOAOkAwKpBgKpCgKpDwKpGAKpHwKpKQKpOAOp
                AwKqBgKqCgKqDwKqGAKqHwKqKQKqOAOqAwKtBgKtCgKtDwKtGAKtHwKtKQKtOAOt
                iQAAigAAjAAAjQAAkAAAkQAAkwAAlgAAnAAAnwAAowAApgAAqwAArgAAtQAAvgAA
                AAOyAAO1AAO5AAO6AAO7AAO9AAO+AAPEAAPGAAPkAAPoAAPplAAAlQAAlwAAmAAA
                AQKyFgOyAQK1FgO1AQK5FgO5AQK6FgO6AQK7FgO7AQK9FgO9AQK+FgO+AQLEFgPE
                AgKyCQKyFwKyKAOyAgK1CQK1FwK1KAO1AgK5CQK5FwK5KAO5AgK6CQK6FwK6KAO6
                AwKyBgKyCgKyDwKyGAKyHwKyKQKyOAOyAwK1BgK1CgK1DwK1GAK1HwK1KQK1OAO1
                AwK5BgK5CgK5DwK5GAK5HwK5KQK5OAO5AwK6BgK6CgK6DwK6GAK6HwK6KQK6OAO6
                AgK7CQK7FwK7KAO7AgK9CQK9FwK9KAO9AgK+CQK+FwK+KAO+AgLECQLEFwLEKAPE
                AwK7BgK7CgK7DwK7GAK7HwK7KQK7OAO7AwK9BgK9CgK9DwK9GAK9HwK9KQK9OAO9
                AwK+BgK+CgK+DwK+GAK+HwK+KQK+OAO+AwLEBgLECgLEDwLEGALEHwLEKQLEOAPE
                AQLGFgPGAQLkFgPkAQLoFgPoAQLpFgPpAAMBAAOHAAOJAAOKAAOLAAOMAAONAAOP
                AgLGCQLGFwLGKAPGAgLkCQLkFwLkKAPkAgLoCQLoFwLoKAPoAgLpCQLpFwLpKAPp
                AwLGBgLGCgLGDwLGGALGHwLGKQLGOAPGAwLkBgLkCgLkDwLkGALkHwLkKQLkOAPk
                AwLoBgLoCgLoDwLoGALoHwLoKQLoOAPoAwLpBgLpCgLpDwLpGALpHwLpKQLpOAPp
                AQIBFgMBAQKHFgOHAQKJFgOJAQKKFgOKAQKLFgOLAQKMFgOMAQKNFgONAQKPFgOP
                AgIBCQIBFwIBKAMBAgKHCQKHFwKHKAOHAgKJCQKJFwKJKAOJAgKKCQKKFwKKKAOK
                AwIBBgIBCgIBDwIBGAIBHwIBKQIBOAMBAwKHBgKHCgKHDwKHGAKHHwKHKQKHOAOH
                AwKJBgKJCgKJDwKJGAKJHwKJKQKJOAOJAwKKBgKKCgKKDwKKGAKKHwKKKQKKOAOK
                AgKLCQKLFwKLKAOLAgKMCQKMFwKMKAOMAgKNCQKNFwKNKAONAgKPCQKPFwKPKAOP
                AwKLBgKLCgKLDwKLGAKLHwKLKQKLOAOLAwKMBgKMCgKMDwKMGAKMHwKMKQKMOAOM
                AwKNBgKNCgKNDwKNGAKNHwKNKQKNOAONAwKPBgKPCgKPDwKPGAKPHwKPKQKPOAOP
                nQAAngAAoAAAoQAApAAApQAApwAAqAAArAAArQAArwAAsQAAtgAAuQAAvwAAzwAA
                AAOTAAOVAAOWAAOXAAOYAAObAAOdAAOeAAOlAAOmAAOoAAOuAAOvAAO0AAO2AAO3
                AQKTFgOTAQKVFgOVAQKWFgOWAQKXFgOXAQKYFgOYAQKbFgObAQKdFgOdAQKeFgOe
                AgKTCQKTFwKTKAOTAgKVCQKVFwKVKAOVAgKWCQKWFwKWKAOWAgKXCQKXFwKXKAOX
                AwKTBgKTCgKTDwKTGAKTHwKTKQKTOAOTAwKVBgKVCgKVDwKVGAKVHwKVKQKVOAOV
                AwKWBgKWCgKWDwKWGAKWHwKWKQKWOAOWAwKXBgKXCgKXDwKXGAKXHwKXKQKXOAOX
                AgKYCQKYFwKYKAOYAgKbCQKbFwKbKAObAgKdCQKdFwKdKAOdAgKeCQKeFwKeKAOe
                AwKYBgKYCgKYDwKYGAKYHwKYKQKYOAOYAwKbBgKbCgKbDwKbGAKbHwKbKQKbOAOb
                AwKdBgKdCgKdDwKdGAKdHwKdKQKdOAOdAwKeBgKeCgKeDwKeGAKeHwKeKQKeOAOe
                AQKlFgOlAQKmFgOmAQKoFgOoAQKuFgOuAQKvFgOvAQK0FgO0AQK2FgO2AQK3FgO3
                AgKlCQKlFwKlKAOlAgKmCQKmFwKmKAOmAgKoCQKoFwKoKAOoAgKuCQKuFwKuKAOu
                AwKlBgKlCgKlDwKlGAKlHwKlKQKlOAOlAwKmBgKmCgKmDwKmGAKmHwKmKQKmOAOm
                AwKoBgKoCgKoDwKoGAKoHwKoKQKoOAOoAwKuBgKuCgKuDwKuGAKuHwKuKQKuOAOu
                AgKvCQKvFwKvKAOvAgK0CQK0FwK0KAO0AgK2CQK2FwK2KAO2AgK3CQK3FwK3KAO3
                AwKvBgKvCgKvDwKvGAKvHwKvKQKvOAOvAwK0BgK0CgK0DwK0GAK0HwK0KQK0OAO0
                AwK2BgK2CgK2DwK2GAK2HwK2KQK2OAO2AwK3BgK3CgK3DwK3GAK3HwK3KQK3OAO3
                AAO8AAO/AAPFAAPnAAPvsAAAsgAAswAAtwAAuAAAugAAuwAAwAAAxwAA0AAA3wAA
                AQK8FgO8AQK/FgO/AQLFFgPFAQLnFgPnAQLvFgPvAAMJAAOOAAOQAAORAAOUAAOf
                AgK8CQK8FwK8KAO8AgK/CQK/FwK/KAO/AgLFCQLFFwLFKAPFAgLnCQLnFwLnKAPn
                AwK8BgK8CgK8DwK8GAK8HwK8KQK8OAO8AwK/BgK/CgK/DwK/GAK/HwK/KQK/OAO/
                AwLFBgLFCgLFDwLFGALFHwLFKQLFOAPFAwLnBgLnCgLnDwLnGALnHwLnKQLnOAPn
                AgLvCQLvFwLvKAPvAQIJFgMJAQKOFgOOAQKQFgOQAQKRFgORAQKUFgOUAQKfFgOf
                AwLvBgLvCgLvDwLvGALvHwLvKQLvOAPvAgIJCQIJFwIJKAMJAgKOCQKOFwKOKAOO
                AwIJBgIJCgIJDwIJGAIJHwIJKQIJOAMJAwKOBgKOCgKODwKOGAKOHwKOKQKOOAOO
                AgKQCQKQFwKQKAOQAgKRCQKRFwKRKAORAgKUCQKUFwKUKAOUAgKfCQKfFwKfKAOf
                AwKQBgKQCgKQDwKQGAKQHwKQKQKQOAOQAwKRBgKRCgKRDwKRGAKRHwKRKQKROAOR
                AwKUBgKUCgKUDwKUGAKUHwKUKQKUOAOUAwKfBgKfCgKfDwKfGAKfHwKfKQKfOAOf
                AAOrAAPOAAPXAAPhAAPsAAPtvAAAvQAAwQAAxAAAyAAAywAA0QAA2AAA4AAA7gAA
                AQKrFgOrAQLOFgPOAQLXFgPXAQLhFgPhAQLsFgPsAQLtFgPtAAPHAAPPAAPqAAPr
                AgKrCQKrFwKrKAOrAgLOCQLOFwLOKAPOAgLXCQLXFwLXKAPXAgLhCQLhFwLhKAPh
                AwKrBgKrCgKrDwKrGAKrHwKrKQKrOAOrAwLOBgLOCgLODwLOGALOHwLOKQLOOAPO
                AwLXBgLXCgLXDwLXGALXHwLXKQLXOAPXAwLhBgLhCgLhDwLhGALhHwLhKQLhOAPh
                AgLsCQLsFwLsKAPsAgLtCQLtFwLtKAPtAQLHFgPHAQLPFgPPAQLqFgPqAQLrFgPr
                AwLsBgLsCgLsDwLsGALsHwLsKQLsOAPsAwLtBgLtCgLtDwLtGALtHwLtKQLtOAPt
                AgLHCQLHFwLHKAPHAgLPCQLPFwLPKAPPAgLqCQLqFwLqKAPqAgLrCQLrFwLrKAPr
                AwLHBgLHCgLHDwLHGALHHwLHKQLHOAPHAwLPBgLPCgLPDwLPGALPHwLPKQLPOAPP
                AwLqBgLqCgLqDwLqGALqHwLqKQLqOAPqAwLrBgLrCgLrDwLrGALrHwLrKQLrOAPr
                wgAAwwAAxQAAxgAAyQAAygAAzAAAzQAA0gAA1QAA2QAA3AAA4QAA5wAA7wAA9gAA
                AAPAAAPBAAPIAAPJAAPKAAPNAAPSAAPVAAPaAAPbAAPuAAPwAAPyAAPzAAP/zgAA
                AQLAFgPAAQLBFgPBAQLIFgPIAQLJFgPJAQLKFgPKAQLNFgPNAQLSFgPSAQLVFgPV
                AgLACQLAFwLAKAPAAgLBCQLBFwLBKAPBAgLICQLIFwLIKAPIAgLJCQLJFwLJKAPJ
                AwLABgLACgLADwLAGALAHwLAKQLAOAPAAwLBBgLBCgLBDwLBGALBHwLBKQLBOAPB
                AwLIBgLICgLIDwLIGALIHwLIKQLIOAPIAwLJBgLJCgLJDwLJGALJHwLJKQLJOAPJ
                AgLKCQLKFwLKKAPKAgLNCQLNFwLNKAPNAgLSCQLSFwLSKAPSAgLVCQLVFwLVKAPV
                AwLKBgLKCgLKDwLKGALKHwLKKQLKOAPKAwLNBgLNCgLNDwLNGALNHwLNKQLNOAPN
                AwLSBgLSCgLSDwLSGALSHwLSKQLSOAPSAwLVBgLVCgLVDwLVGALVHwLVKQLVOAPV
                AQLaFgPaAQLbFgPbAQLuFgPuAQLwFgPwAQLyFgPyAQLzFgPzAQL/FgP/AAPLAAPM
                AgLaCQLaFwLaKAPaAgLbCQLbFwLbKAPbAgLuCQLuFwLuKAPuAgLwCQLwFwLwKAPw
                AwLaBgLaCgLaDwLaGALaHwLaKQLaOAPaAwLbBgLbCgLbDwLbGALbHwLbKQLbOAPb
                AwLuBgLuCgLuDwLuGALuHwLuKQLuOAPuAwLwBgLwCgLwDwLwGALwHwLwKQLwOAPw
                AgLyCQLyFwLyKAPyAgLzCQLzFwLzKAPzAgL/CQL/FwL/KAP/AQLLFgPLAQLMFgPM
                AwLyBgLyCgLyDwLyGALyHwLyKQLyOAPyAwLzBgLzCgLzDwLzGALzHwLzKQLzOAPz
                AwL/BgL/CgL/DwL/GAL/HwL/KQL/OAP/AgLLCQLLFwLLKAPLAgLMCQLMFwLMKAPM
                AwLLBgLLCgLLDwLLGALLHwLLKQLLOAPLAwLMBgLMCgLMDwLMGALMHwLMKQLMOAPM
                0wAA1AAA1gAA1wAA2gAA2wAA3QAA3gAA4gAA5AAA6AAA6wAA8AAA8wAA9wAA+gAA
                AAPTAAPUAAPWAAPdAAPeAAPfAAPxAAP0AAP1AAP2AAP3AAP4AAP6AAP7AAP8AAP9
                AQLTFgPTAQLUFgPUAQLWFgPWAQLdFgPdAQLeFgPeAQLfFgPfAQLxFgPxAQL0FgP0
                AgLTCQLTFwLTKAPTAgLUCQLUFwLUKAPUAgLWCQLWFwLWKAPWAgLdCQLdFwLdKAPd
                AwLTBgLTCgLTDwLTGALTHwLTKQLTOAPTAwLUBgLUCgLUDwLUGALUHwLUKQLUOAPU
                AwLWBgLWCgLWDwLWGALWHwLWKQLWOAPWAwLdBgLdCgLdDwLdGALdHwLdKQLdOAPd
                AgLeCQLeFwLeKAPeAgLfCQLfFwLfKAPfAgLxCQLxFwLxKAPxAgL0CQL0FwL0KAP0
                AwLeBgLeCgLeDwLeGALeHwLeKQLeOAPeAwLfBgLfCgLfDwLfGALfHwLfKQLfOAPf
                AwLxBgLxCgLxDwLxGALxHwLxKQLxOAPxAwL0BgL0CgL0DwL0GAL0HwL0KQL0OAP0
                AQL1FgP1AQL2FgP2AQL3FgP3AQL4FgP4AQL6FgP6AQL7FgP7AQL8FgP8AQL9FgP9
                AgL1CQL1FwL1KAP1AgL2CQL2FwL2KAP2AgL3CQL3FwL3KAP3AgL4CQL4FwL4KAP4
                AwL1BgL1CgL1DwL1GAL1HwL1KQL1OAP1AwL2BgL2CgL2DwL2GAL2HwL2KQL2OAP2
                AwL3BgL3CgL3DwL3GAL3HwL3KQL3OAP3AwL4BgL4CgL4DwL4GAL4HwL4KQL4OAP4
                AgL6CQL6FwL6KAP6AgL7CQL7FwL7KAP7AgL8CQL8FwL8KAP8AgL9CQL9FwL9KAP9
                AwL6BgL6CgL6DwL6GAL6HwL6KQL6OAP6AwL7BgL7CgL7DwL7GAL7HwL7KQL7OAP7
                AwL8BgL8CgL8DwL8GAL8HwL8KQL8OAP8AwL9BgL9CgL9DwL9GAL9HwL9KQL9OAP9
                AAP+4wAA5QAA5gAA6QAA6gAA7AAA7QAA8QAA8gAA9AAA9QAA+AAA+QAA+wAA/AAA
                AQL+FgP+AAMCAAMDAAMEAAMFAAMGAAMHAAMIAAMLAAMMAAMOAAMPAAMQAAMRAAMS
                AgL+CQL+FwL+KAP+AQICFgMCAQIDFgMDAQIEFgMEAQIFFgMFAQIGFgMGAQIHFgMH
                AwL+BgL+CgL+DwL+GAL+HwL+KQL+OAP+AgICCQICFwICKAMCAgIDCQIDFwIDKAMD
                AwICBgICCgICDwICGAICHwICKQICOAMCAwIDBgIDCgIDDwIDGAIDHwIDKQIDOAMD
                AgIECQIEFwIEKAMEAgIFCQIFFwIFKAMFAgIGCQIGFwIGKAMGAgIHCQIHFwIHKAMH
                AwIEBgIECgIEDwIEGAIEHwIEKQIEOAMEAwIFBgIFCgIFDwIFGAIFHwIFKQIFOAMF
                AwIGBgIGCgIGDwIGGAIGHwIGKQIGOAMGAwIHBgIHCgIHDwIHGAIHHwIHKQIHOAMH
                AQIIFgMIAQILFgMLAQIMFgMMAQIOFgMOAQIPFgMPAQIQFgMQAQIRFgMRAQISFgMS
                AgIICQIIFwIIKAMIAgILCQILFwILKAMLAgIMCQIMFwIMKAMMAgIOCQIOFwIOKAMO
                AwIIBgIICgIIDwIIGAIIHwIIKQIIOAMIAwILBgILCgILDwILGAILHwILKQILOAML
                AwIMBgIMCgIMDwIMGAIMHwIMKQIMOAMMAwIOBgIOCgIODwIOGAIOHwIOKQIOOAMO
                AgIPCQIPFwIPKAMPAgIQCQIQFwIQKAMQAgIRCQIRFwIRKAMRAgISCQISFwISKAMS
                AwIPBgIPCgIPDwIPGAIPHwIPKQIPOAMPAwIQBgIQCgIQDwIQGAIQHwIQKQIQOAMQ
                AwIRBgIRCgIRDwIRGAIRHwIRKQIROAMRAwISBgISCgISDwISGAISHwISKQISOAMS
                AAMTAAMUAAMVAAMXAAMYAAMZAAMaAAMbAAMcAAMdAAMeAAMfAAN/AAPcAAP5/QAA
                AQITFgMTAQIUFgMUAQIVFgMVAQIXFgMXAQIYFgMYAQIZFgMZAQIaFgMaAQIbFgMb
                AgITCQITFwITKAMTAgIUCQIUFwIUKAMUAgIVCQIVFwIVKAMVAgIXCQIXFwIXKAMX
                AwITBgITCgITDwITGAITHwITKQITOAMTAwIUBgIUCgIUDwIUGAIUHwIUKQIUOAMU
                AwIVBgIVCgIVDwIVGAIVHwIVKQIVOAMVAwIXBgIXCgIXDwIXGAIXHwIXKQIXOAMX
                AgIYCQIYFwIYKAMYAgIZCQIZFwIZKAMZAgIaCQIaFwIaKAMaAgIbCQIbFwIbKAMb
                AwIYBgIYCgIYDwIYGAIYHwIYKQIYOAMYAwIZBgIZCgIZDwIZGAIZHwIZKQIZOAMZ
                AwIaBgIaCgIaDwIaGAIaHwIaKQIaOAMaAwIbBgIbCgIbDwIbGAIbHwIbKQIbOAMb
                AQIcFgMcAQIdFgMdAQIeFgMeAQIfFgMfAQJ/FgN/AQLcFgPcAQL5FgP5/gAA/wAA
                AgIcCQIcFwIcKAMcAgIdCQIdFwIdKAMdAgIeCQIeFwIeKAMeAgIfCQIfFwIfKAMf
                AwIcBgIcCgIcDwIcGAIcHwIcKQIcOAMcAwIdBgIdCgIdDwIdGAIdHwIdKQIdOAMd
                AwIeBgIeCgIeDwIeGAIeHwIeKQIeOAMeAwIfBgIfCgIfDwIfGAIfHwIfKQIfOAMf
                AgJ/CQJ/FwJ/KAN/AgLcCQLcFwLcKAPcAgL5CQL5FwL5KAP5AAMKAAMNAAMWAAQA
                AwJ/BgJ/CgJ/DwJ/GAJ/HwJ/KQJ/OAN/AwLcBgLcCgLcDwLcGALcHwLcKQLcOAPc
                AwL5BgL5CgL5DwL5GAL5HwL5KQL5OAP5AQIKFgMKAQINFgMNAQIWFgMWAAQAAAQA
                AgIKCQIKFwIKKAMKAgINCQINFwINKAMNAgIWCQIWFwIWKAMWAAQAAAQAAAQAAAQA
                AwIKBgIKCgIKDwIKGAIKHwIKKQIKOAMKAwINBgINCgINDwINGAINHwINKQINOAMN
                AwIWBgIWCgIWDwIWGAIWHwIWKQIWOAMWAAQAAAQAAAQAAAQAAAQAAAQAAAQAAAQA
                """
        return base64_table_bytes.withUTF8Buffer { buf in
            // ignore newlines in the input
            guard let result = base64DecodeBytes(buf, ignoreUnknownCharacters: true) else {
                fatalError("Failed to decode huffman decoder table from base-64 encoding")
            }
            return result.withUnsafeBytes { ptr in
                assert(ptr.count % 3 == 0)
                let dptr = ptr.baseAddress!.assumingMemoryBound(to: HuffmanDecodeEntry.self)
                let dbuf = UnsafeBufferPointer(start: dptr, count: ptr.count / 3)
                return Array(dbuf)
            }
        }
    }()

    // for posterity, here's what the table effectively looks like:
    /*
    private static let rawTable: [HuffmanDecodeEntry] = [
        
        /* 0 */

            (4, .none, 0),
            (5, .none, 0),
            (7, .none, 0),
            (8, .none, 0),
            (11, .none, 0),
            (12, .none, 0),
            (16, .none, 0),
            (19, .none, 0),
            (25, .none, 0),
            (28, .none, 0),
            (32, .none, 0),
            (35, .none, 0),
            (42, .none, 0),
            (49, .none, 0),
            (57, .none, 0),
            (64, .accepted, 0),

        /* 1 */

            (0, [.accepted, .symbol], 48),
            (0, [.accepted, .symbol], 49),
            (0, [.accepted, .symbol], 50),
            (0, [.accepted, .symbol], 97),
            (0, [.accepted, .symbol], 99),
            (0, [.accepted, .symbol], 101),
            (0, [.accepted, .symbol], 105),
            (0, [.accepted, .symbol], 111),
            (0, [.accepted, .symbol], 115),
            (0, [.accepted, .symbol], 116),
            (13, .none, 0),
            (14, .none, 0),
            (17, .none, 0),
            (18, .none, 0),
            (20, .none, 0),
            (21, .none, 0),

        /* 2 */

            (1, .symbol, 48),
            (22, [.accepted, .symbol], 48),
            (1, .symbol, 49),
            (22, [.accepted, .symbol], 49),
            (1, .symbol, 50),
            (22, [.accepted, .symbol], 50),
            (1, .symbol, 97),
            (22, [.accepted, .symbol], 97),
            (1, .symbol, 99),
            (22, [.accepted, .symbol], 99),
            (1, .symbol, 101),
            (22, [.accepted, .symbol], 101),
            (1, .symbol, 105),
            (22, [.accepted, .symbol], 105),
            (1, .symbol, 111),
            (22, [.accepted, .symbol], 111),

        /* 3 */

            (2, .symbol, 48),
            (9, .symbol, 48),
            (23, .symbol, 48),
            (40, [.accepted, .symbol], 48),
            (2, .symbol, 49),
            (9, .symbol, 49),
            (23, .symbol, 49),
            (40, [.accepted, .symbol], 49),
            (2, .symbol, 50),
            (9, .symbol, 50),
            (23, .symbol, 50),
            (40, [.accepted, .symbol], 50),
            (2, .symbol, 97),
            (9, .symbol, 97),
            (23, .symbol, 97),
            (40, [.accepted, .symbol], 97),

        /* 4 */

            (3, .symbol, 48),
            (6, .symbol, 48),
            (10, .symbol, 48),
            (15, .symbol, 48),
            (24, .symbol, 48),
            (31, .symbol, 48),
            (41, .symbol, 48),
            (56, [.accepted, .symbol], 48),
            (3, .symbol, 49),
            (6, .symbol, 49),
            (10, .symbol, 49),
            (15, .symbol, 49),
            (24, .symbol, 49),
            (31, .symbol, 49),
            (41, .symbol, 49),
            (56, [.accepted, .symbol], 49),

        /* 5 */

            (3, .symbol, 50),
            (6, .symbol, 50),
            (10, .symbol, 50),
            (15, .symbol, 50),
            (24, .symbol, 50),
            (31, .symbol, 50),
            (41, .symbol, 50),
            (56, [.accepted, .symbol], 50),
            (3, .symbol, 97),
            (6, .symbol, 97),
            (10, .symbol, 97),
            (15, .symbol, 97),
            (24, .symbol, 97),
            (31, .symbol, 97),
            (41, .symbol, 97),
            (56, [.accepted, .symbol], 97),

        /* 6 */

            (2, .symbol, 99),
            (9, .symbol, 99),
            (23, .symbol, 99),
            (40, [.accepted, .symbol], 99),
            (2, .symbol, 101),
            (9, .symbol, 101),
            (23, .symbol, 101),
            (40, [.accepted, .symbol], 101),
            (2, .symbol, 105),
            (9, .symbol, 105),
            (23, .symbol, 105),
            (40, [.accepted, .symbol], 105),
            (2, .symbol, 111),
            (9, .symbol, 111),
            (23, .symbol, 111),
            (40, [.accepted, .symbol], 111),

        /* 7 */

            (3, .symbol, 99),
            (6, .symbol, 99),
            (10, .symbol, 99),
            (15, .symbol, 99),
            (24, .symbol, 99),
            (31, .symbol, 99),
            (41, .symbol, 99),
            (56, [.accepted, .symbol], 99),
            (3, .symbol, 101),
            (6, .symbol, 101),
            (10, .symbol, 101),
            (15, .symbol, 101),
            (24, .symbol, 101),
            (31, .symbol, 101),
            (41, .symbol, 101),
            (56, [.accepted, .symbol], 101),

        /* 8 */

            (3, .symbol, 105),
            (6, .symbol, 105),
            (10, .symbol, 105),
            (15, .symbol, 105),
            (24, .symbol, 105),
            (31, .symbol, 105),
            (41, .symbol, 105),
            (56, [.accepted, .symbol], 105),
            (3, .symbol, 111),
            (6, .symbol, 111),
            (10, .symbol, 111),
            (15, .symbol, 111),
            (24, .symbol, 111),
            (31, .symbol, 111),
            (41, .symbol, 111),
            (56, [.accepted, .symbol], 111),

        /* 9 */

            (1, .symbol, 115),
            (22, [.accepted, .symbol], 115),
            (1, .symbol, 116),
            (22, [.accepted, .symbol], 116),
            (0, [.accepted, .symbol], 32),
            (0, [.accepted, .symbol], 37),
            (0, [.accepted, .symbol], 45),
            (0, [.accepted, .symbol], 46),
            (0, [.accepted, .symbol], 47),
            (0, [.accepted, .symbol], 51),
            (0, [.accepted, .symbol], 52),
            (0, [.accepted, .symbol], 53),
            (0, [.accepted, .symbol], 54),
            (0, [.accepted, .symbol], 55),
            (0, [.accepted, .symbol], 56),
            (0, [.accepted, .symbol], 57),

        /* 10 */

            (2, .symbol, 115),
            (9, .symbol, 115),
            (23, .symbol, 115),
            (40, [.accepted, .symbol], 115),
            (2, .symbol, 116),
            (9, .symbol, 116),
            (23, .symbol, 116),
            (40, [.accepted, .symbol], 116),
            (1, .symbol, 32),
            (22, [.accepted, .symbol], 32),
            (1, .symbol, 37),
            (22, [.accepted, .symbol], 37),
            (1, .symbol, 45),
            (22, [.accepted, .symbol], 45),
            (1, .symbol, 46),
            (22, [.accepted, .symbol], 46),

        /* 11 */

            (3, .symbol, 115),
            (6, .symbol, 115),
            (10, .symbol, 115),
            (15, .symbol, 115),
            (24, .symbol, 115),
            (31, .symbol, 115),
            (41, .symbol, 115),
            (56, [.accepted, .symbol], 115),
            (3, .symbol, 116),
            (6, .symbol, 116),
            (10, .symbol, 116),
            (15, .symbol, 116),
            (24, .symbol, 116),
            (31, .symbol, 116),
            (41, .symbol, 116),
            (56, [.accepted, .symbol], 116),

        /* 12 */

            (2, .symbol, 32),
            (9, .symbol, 32),
            (23, .symbol, 32),
            (40, [.accepted, .symbol], 32),
            (2, .symbol, 37),
            (9, .symbol, 37),
            (23, .symbol, 37),
            (40, [.accepted, .symbol], 37),
            (2, .symbol, 45),
            (9, .symbol, 45),
            (23, .symbol, 45),
            (40, [.accepted, .symbol], 45),
            (2, .symbol, 46),
            (9, .symbol, 46),
            (23, .symbol, 46),
            (40, [.accepted, .symbol], 46),

        /* 13 */

            (3, .symbol, 32),
            (6, .symbol, 32),
            (10, .symbol, 32),
            (15, .symbol, 32),
            (24, .symbol, 32),
            (31, .symbol, 32),
            (41, .symbol, 32),
            (56, [.accepted, .symbol], 32),
            (3, .symbol, 37),
            (6, .symbol, 37),
            (10, .symbol, 37),
            (15, .symbol, 37),
            (24, .symbol, 37),
            (31, .symbol, 37),
            (41, .symbol, 37),
            (56, [.accepted, .symbol], 37),

        /* 14 */

            (3, .symbol, 45),
            (6, .symbol, 45),
            (10, .symbol, 45),
            (15, .symbol, 45),
            (24, .symbol, 45),
            (31, .symbol, 45),
            (41, .symbol, 45),
            (56, [.accepted, .symbol], 45),
            (3, .symbol, 46),
            (6, .symbol, 46),
            (10, .symbol, 46),
            (15, .symbol, 46),
            (24, .symbol, 46),
            (31, .symbol, 46),
            (41, .symbol, 46),
            (56, [.accepted, .symbol], 46),

        /* 15 */

            (1, .symbol, 47),
            (22, [.accepted, .symbol], 47),
            (1, .symbol, 51),
            (22, [.accepted, .symbol], 51),
            (1, .symbol, 52),
            (22, [.accepted, .symbol], 52),
            (1, .symbol, 53),
            (22, [.accepted, .symbol], 53),
            (1, .symbol, 54),
            (22, [.accepted, .symbol], 54),
            (1, .symbol, 55),
            (22, [.accepted, .symbol], 55),
            (1, .symbol, 56),
            (22, [.accepted, .symbol], 56),
            (1, .symbol, 57),
            (22, [.accepted, .symbol], 57),

        /* 16 */

            (2, .symbol, 47),
            (9, .symbol, 47),
            (23, .symbol, 47),
            (40, [.accepted, .symbol], 47),
            (2, .symbol, 51),
            (9, .symbol, 51),
            (23, .symbol, 51),
            (40, [.accepted, .symbol], 51),
            (2, .symbol, 52),
            (9, .symbol, 52),
            (23, .symbol, 52),
            (40, [.accepted, .symbol], 52),
            (2, .symbol, 53),
            (9, .symbol, 53),
            (23, .symbol, 53),
            (40, [.accepted, .symbol], 53),

        /* 17 */

            (3, .symbol, 47),
            (6, .symbol, 47),
            (10, .symbol, 47),
            (15, .symbol, 47),
            (24, .symbol, 47),
            (31, .symbol, 47),
            (41, .symbol, 47),
            (56, [.accepted, .symbol], 47),
            (3, .symbol, 51),
            (6, .symbol, 51),
            (10, .symbol, 51),
            (15, .symbol, 51),
            (24, .symbol, 51),
            (31, .symbol, 51),
            (41, .symbol, 51),
            (56, [.accepted, .symbol], 51),

        /* 18 */

            (3, .symbol, 52),
            (6, .symbol, 52),
            (10, .symbol, 52),
            (15, .symbol, 52),
            (24, .symbol, 52),
            (31, .symbol, 52),
            (41, .symbol, 52),
            (56, [.accepted, .symbol], 52),
            (3, .symbol, 53),
            (6, .symbol, 53),
            (10, .symbol, 53),
            (15, .symbol, 53),
            (24, .symbol, 53),
            (31, .symbol, 53),
            (41, .symbol, 53),
            (56, [.accepted, .symbol], 53),

        /* 19 */

            (2, .symbol, 54),
            (9, .symbol, 54),
            (23, .symbol, 54),
            (40, [.accepted, .symbol], 54),
            (2, .symbol, 55),
            (9, .symbol, 55),
            (23, .symbol, 55),
            (40, [.accepted, .symbol], 55),
            (2, .symbol, 56),
            (9, .symbol, 56),
            (23, .symbol, 56),
            (40, [.accepted, .symbol], 56),
            (2, .symbol, 57),
            (9, .symbol, 57),
            (23, .symbol, 57),
            (40, [.accepted, .symbol], 57),

        /* 20 */

            (3, .symbol, 54),
            (6, .symbol, 54),
            (10, .symbol, 54),
            (15, .symbol, 54),
            (24, .symbol, 54),
            (31, .symbol, 54),
            (41, .symbol, 54),
            (56, [.accepted, .symbol], 54),
            (3, .symbol, 55),
            (6, .symbol, 55),
            (10, .symbol, 55),
            (15, .symbol, 55),
            (24, .symbol, 55),
            (31, .symbol, 55),
            (41, .symbol, 55),
            (56, [.accepted, .symbol], 55),

        /* 21 */

            (3, .symbol, 56),
            (6, .symbol, 56),
            (10, .symbol, 56),
            (15, .symbol, 56),
            (24, .symbol, 56),
            (31, .symbol, 56),
            (41, .symbol, 56),
            (56, [.accepted, .symbol], 56),
            (3, .symbol, 57),
            (6, .symbol, 57),
            (10, .symbol, 57),
            (15, .symbol, 57),
            (24, .symbol, 57),
            (31, .symbol, 57),
            (41, .symbol, 57),
            (56, [.accepted, .symbol], 57),

        /* 22 */

            (26, .none, 0),
            (27, .none, 0),
            (29, .none, 0),
            (30, .none, 0),
            (33, .none, 0),
            (34, .none, 0),
            (36, .none, 0),
            (37, .none, 0),
            (43, .none, 0),
            (46, .none, 0),
            (50, .none, 0),
            (53, .none, 0),
            (58, .none, 0),
            (61, .none, 0),
            (65, .none, 0),
            (68, .accepted, 0),

        /* 23 */

            (0, [.accepted, .symbol], 61),
            (0, [.accepted, .symbol], 65),
            (0, [.accepted, .symbol], 95),
            (0, [.accepted, .symbol], 98),
            (0, [.accepted, .symbol], 100),
            (0, [.accepted, .symbol], 102),
            (0, [.accepted, .symbol], 103),
            (0, [.accepted, .symbol], 104),
            (0, [.accepted, .symbol], 108),
            (0, [.accepted, .symbol], 109),
            (0, [.accepted, .symbol], 110),
            (0, [.accepted, .symbol], 112),
            (0, [.accepted, .symbol], 114),
            (0, [.accepted, .symbol], 117),
            (38, .none, 0),
            (39, .none, 0),

        /* 24 */

            (1, .symbol, 61),
            (22, [.accepted, .symbol], 61),
            (1, .symbol, 65),
            (22, [.accepted, .symbol], 65),
            (1, .symbol, 95),
            (22, [.accepted, .symbol], 95),
            (1, .symbol, 98),
            (22, [.accepted, .symbol], 98),
            (1, .symbol, 100),
            (22, [.accepted, .symbol], 100),
            (1, .symbol, 102),
            (22, [.accepted, .symbol], 102),
            (1, .symbol, 103),
            (22, [.accepted, .symbol], 103),
            (1, .symbol, 104),
            (22, [.accepted, .symbol], 104),

        /* 25 */

            (2, .symbol, 61),
            (9, .symbol, 61),
            (23, .symbol, 61),
            (40, [.accepted, .symbol], 61),
            (2, .symbol, 65),
            (9, .symbol, 65),
            (23, .symbol, 65),
            (40, [.accepted, .symbol], 65),
            (2, .symbol, 95),
            (9, .symbol, 95),
            (23, .symbol, 95),
            (40, [.accepted, .symbol], 95),
            (2, .symbol, 98),
            (9, .symbol, 98),
            (23, .symbol, 98),
            (40, [.accepted, .symbol], 98),

        /* 26 */

            (3, .symbol, 61),
            (6, .symbol, 61),
            (10, .symbol, 61),
            (15, .symbol, 61),
            (24, .symbol, 61),
            (31, .symbol, 61),
            (41, .symbol, 61),
            (56, [.accepted, .symbol], 61),
            (3, .symbol, 65),
            (6, .symbol, 65),
            (10, .symbol, 65),
            (15, .symbol, 65),
            (24, .symbol, 65),
            (31, .symbol, 65),
            (41, .symbol, 65),
            (56, [.accepted, .symbol], 65),

        /* 27 */

            (3, .symbol, 95),
            (6, .symbol, 95),
            (10, .symbol, 95),
            (15, .symbol, 95),
            (24, .symbol, 95),
            (31, .symbol, 95),
            (41, .symbol, 95),
            (56, [.accepted, .symbol], 95),
            (3, .symbol, 98),
            (6, .symbol, 98),
            (10, .symbol, 98),
            (15, .symbol, 98),
            (24, .symbol, 98),
            (31, .symbol, 98),
            (41, .symbol, 98),
            (56, [.accepted, .symbol], 98),

        /* 28 */

            (2, .symbol, 100),
            (9, .symbol, 100),
            (23, .symbol, 100),
            (40, [.accepted, .symbol], 100),
            (2, .symbol, 102),
            (9, .symbol, 102),
            (23, .symbol, 102),
            (40, [.accepted, .symbol], 102),
            (2, .symbol, 103),
            (9, .symbol, 103),
            (23, .symbol, 103),
            (40, [.accepted, .symbol], 103),
            (2, .symbol, 104),
            (9, .symbol, 104),
            (23, .symbol, 104),
            (40, [.accepted, .symbol], 104),

        /* 29 */

            (3, .symbol, 100),
            (6, .symbol, 100),
            (10, .symbol, 100),
            (15, .symbol, 100),
            (24, .symbol, 100),
            (31, .symbol, 100),
            (41, .symbol, 100),
            (56, [.accepted, .symbol], 100),
            (3, .symbol, 102),
            (6, .symbol, 102),
            (10, .symbol, 102),
            (15, .symbol, 102),
            (24, .symbol, 102),
            (31, .symbol, 102),
            (41, .symbol, 102),
            (56, [.accepted, .symbol], 102),

        /* 30 */

            (3, .symbol, 103),
            (6, .symbol, 103),
            (10, .symbol, 103),
            (15, .symbol, 103),
            (24, .symbol, 103),
            (31, .symbol, 103),
            (41, .symbol, 103),
            (56, [.accepted, .symbol], 103),
            (3, .symbol, 104),
            (6, .symbol, 104),
            (10, .symbol, 104),
            (15, .symbol, 104),
            (24, .symbol, 104),
            (31, .symbol, 104),
            (41, .symbol, 104),
            (56, [.accepted, .symbol], 104),

        /* 31 */

            (1, .symbol, 108),
            (22, [.accepted, .symbol], 108),
            (1, .symbol, 109),
            (22, [.accepted, .symbol], 109),
            (1, .symbol, 110),
            (22, [.accepted, .symbol], 110),
            (1, .symbol, 112),
            (22, [.accepted, .symbol], 112),
            (1, .symbol, 114),
            (22, [.accepted, .symbol], 114),
            (1, .symbol, 117),
            (22, [.accepted, .symbol], 117),
            (0, [.accepted, .symbol], 58),
            (0, [.accepted, .symbol], 66),
            (0, [.accepted, .symbol], 67),
            (0, [.accepted, .symbol], 68),

        /* 32 */

            (2, .symbol, 108),
            (9, .symbol, 108),
            (23, .symbol, 108),
            (40, [.accepted, .symbol], 108),
            (2, .symbol, 109),
            (9, .symbol, 109),
            (23, .symbol, 109),
            (40, [.accepted, .symbol], 109),
            (2, .symbol, 110),
            (9, .symbol, 110),
            (23, .symbol, 110),
            (40, [.accepted, .symbol], 110),
            (2, .symbol, 112),
            (9, .symbol, 112),
            (23, .symbol, 112),
            (40, [.accepted, .symbol], 112),

        /* 33 */

            (3, .symbol, 108),
            (6, .symbol, 108),
            (10, .symbol, 108),
            (15, .symbol, 108),
            (24, .symbol, 108),
            (31, .symbol, 108),
            (41, .symbol, 108),
            (56, [.accepted, .symbol], 108),
            (3, .symbol, 109),
            (6, .symbol, 109),
            (10, .symbol, 109),
            (15, .symbol, 109),
            (24, .symbol, 109),
            (31, .symbol, 109),
            (41, .symbol, 109),
            (56, [.accepted, .symbol], 109),

        /* 34 */

            (3, .symbol, 110),
            (6, .symbol, 110),
            (10, .symbol, 110),
            (15, .symbol, 110),
            (24, .symbol, 110),
            (31, .symbol, 110),
            (41, .symbol, 110),
            (56, [.accepted, .symbol], 110),
            (3, .symbol, 112),
            (6, .symbol, 112),
            (10, .symbol, 112),
            (15, .symbol, 112),
            (24, .symbol, 112),
            (31, .symbol, 112),
            (41, .symbol, 112),
            (56, [.accepted, .symbol], 112),

        /* 35 */

            (2, .symbol, 114),
            (9, .symbol, 114),
            (23, .symbol, 114),
            (40, [.accepted, .symbol], 114),
            (2, .symbol, 117),
            (9, .symbol, 117),
            (23, .symbol, 117),
            (40, [.accepted, .symbol], 117),
            (1, .symbol, 58),
            (22, [.accepted, .symbol], 58),
            (1, .symbol, 66),
            (22, [.accepted, .symbol], 66),
            (1, .symbol, 67),
            (22, [.accepted, .symbol], 67),
            (1, .symbol, 68),
            (22, [.accepted, .symbol], 68),

        /* 36 */

            (3, .symbol, 114),
            (6, .symbol, 114),
            (10, .symbol, 114),
            (15, .symbol, 114),
            (24, .symbol, 114),
            (31, .symbol, 114),
            (41, .symbol, 114),
            (56, [.accepted, .symbol], 114),
            (3, .symbol, 117),
            (6, .symbol, 117),
            (10, .symbol, 117),
            (15, .symbol, 117),
            (24, .symbol, 117),
            (31, .symbol, 117),
            (41, .symbol, 117),
            (56, [.accepted, .symbol], 117),

        /* 37 */

            (2, .symbol, 58),
            (9, .symbol, 58),
            (23, .symbol, 58),
            (40, [.accepted, .symbol], 58),
            (2, .symbol, 66),
            (9, .symbol, 66),
            (23, .symbol, 66),
            (40, [.accepted, .symbol], 66),
            (2, .symbol, 67),
            (9, .symbol, 67),
            (23, .symbol, 67),
            (40, [.accepted, .symbol], 67),
            (2, .symbol, 68),
            (9, .symbol, 68),
            (23, .symbol, 68),
            (40, [.accepted, .symbol], 68),

        /* 38 */

            (3, .symbol, 58),
            (6, .symbol, 58),
            (10, .symbol, 58),
            (15, .symbol, 58),
            (24, .symbol, 58),
            (31, .symbol, 58),
            (41, .symbol, 58),
            (56, [.accepted, .symbol], 58),
            (3, .symbol, 66),
            (6, .symbol, 66),
            (10, .symbol, 66),
            (15, .symbol, 66),
            (24, .symbol, 66),
            (31, .symbol, 66),
            (41, .symbol, 66),
            (56, [.accepted, .symbol], 66),

        /* 39 */

            (3, .symbol, 67),
            (6, .symbol, 67),
            (10, .symbol, 67),
            (15, .symbol, 67),
            (24, .symbol, 67),
            (31, .symbol, 67),
            (41, .symbol, 67),
            (56, [.accepted, .symbol], 67),
            (3, .symbol, 68),
            (6, .symbol, 68),
            (10, .symbol, 68),
            (15, .symbol, 68),
            (24, .symbol, 68),
            (31, .symbol, 68),
            (41, .symbol, 68),
            (56, [.accepted, .symbol], 68),

        /* 40 */

            (44, .none, 0),
            (45, .none, 0),
            (47, .none, 0),
            (48, .none, 0),
            (51, .none, 0),
            (52, .none, 0),
            (54, .none, 0),
            (55, .none, 0),
            (59, .none, 0),
            (60, .none, 0),
            (62, .none, 0),
            (63, .none, 0),
            (66, .none, 0),
            (67, .none, 0),
            (69, .none, 0),
            (72, .accepted, 0),

        /* 41 */

            (0, [.accepted, .symbol], 69),
            (0, [.accepted, .symbol], 70),
            (0, [.accepted, .symbol], 71),
            (0, [.accepted, .symbol], 72),
            (0, [.accepted, .symbol], 73),
            (0, [.accepted, .symbol], 74),
            (0, [.accepted, .symbol], 75),
            (0, [.accepted, .symbol], 76),
            (0, [.accepted, .symbol], 77),
            (0, [.accepted, .symbol], 78),
            (0, [.accepted, .symbol], 79),
            (0, [.accepted, .symbol], 80),
            (0, [.accepted, .symbol], 81),
            (0, [.accepted, .symbol], 82),
            (0, [.accepted, .symbol], 83),
            (0, [.accepted, .symbol], 84),

        /* 42 */

            (1, .symbol, 69),
            (22, [.accepted, .symbol], 69),
            (1, .symbol, 70),
            (22, [.accepted, .symbol], 70),
            (1, .symbol, 71),
            (22, [.accepted, .symbol], 71),
            (1, .symbol, 72),
            (22, [.accepted, .symbol], 72),
            (1, .symbol, 73),
            (22, [.accepted, .symbol], 73),
            (1, .symbol, 74),
            (22, [.accepted, .symbol], 74),
            (1, .symbol, 75),
            (22, [.accepted, .symbol], 75),
            (1, .symbol, 76),
            (22, [.accepted, .symbol], 76),

        /* 43 */

            (2, .symbol, 69),
            (9, .symbol, 69),
            (23, .symbol, 69),
            (40, [.accepted, .symbol], 69),
            (2, .symbol, 70),
            (9, .symbol, 70),
            (23, .symbol, 70),
            (40, [.accepted, .symbol], 70),
            (2, .symbol, 71),
            (9, .symbol, 71),
            (23, .symbol, 71),
            (40, [.accepted, .symbol], 71),
            (2, .symbol, 72),
            (9, .symbol, 72),
            (23, .symbol, 72),
            (40, [.accepted, .symbol], 72),

        /* 44 */

            (3, .symbol, 69),
            (6, .symbol, 69),
            (10, .symbol, 69),
            (15, .symbol, 69),
            (24, .symbol, 69),
            (31, .symbol, 69),
            (41, .symbol, 69),
            (56, [.accepted, .symbol], 69),
            (3, .symbol, 70),
            (6, .symbol, 70),
            (10, .symbol, 70),
            (15, .symbol, 70),
            (24, .symbol, 70),
            (31, .symbol, 70),
            (41, .symbol, 70),
            (56, [.accepted, .symbol], 70),

        /* 45 */

            (3, .symbol, 71),
            (6, .symbol, 71),
            (10, .symbol, 71),
            (15, .symbol, 71),
            (24, .symbol, 71),
            (31, .symbol, 71),
            (41, .symbol, 71),
            (56, [.accepted, .symbol], 71),
            (3, .symbol, 72),
            (6, .symbol, 72),
            (10, .symbol, 72),
            (15, .symbol, 72),
            (24, .symbol, 72),
            (31, .symbol, 72),
            (41, .symbol, 72),
            (56, [.accepted, .symbol], 72),

        /* 46 */

            (2, .symbol, 73),
            (9, .symbol, 73),
            (23, .symbol, 73),
            (40, [.accepted, .symbol], 73),
            (2, .symbol, 74),
            (9, .symbol, 74),
            (23, .symbol, 74),
            (40, [.accepted, .symbol], 74),
            (2, .symbol, 75),
            (9, .symbol, 75),
            (23, .symbol, 75),
            (40, [.accepted, .symbol], 75),
            (2, .symbol, 76),
            (9, .symbol, 76),
            (23, .symbol, 76),
            (40, [.accepted, .symbol], 76),

        /* 47 */

            (3, .symbol, 73),
            (6, .symbol, 73),
            (10, .symbol, 73),
            (15, .symbol, 73),
            (24, .symbol, 73),
            (31, .symbol, 73),
            (41, .symbol, 73),
            (56, [.accepted, .symbol], 73),
            (3, .symbol, 74),
            (6, .symbol, 74),
            (10, .symbol, 74),
            (15, .symbol, 74),
            (24, .symbol, 74),
            (31, .symbol, 74),
            (41, .symbol, 74),
            (56, [.accepted, .symbol], 74),

        /* 48 */

            (3, .symbol, 75),
            (6, .symbol, 75),
            (10, .symbol, 75),
            (15, .symbol, 75),
            (24, .symbol, 75),
            (31, .symbol, 75),
            (41, .symbol, 75),
            (56, [.accepted, .symbol], 75),
            (3, .symbol, 76),
            (6, .symbol, 76),
            (10, .symbol, 76),
            (15, .symbol, 76),
            (24, .symbol, 76),
            (31, .symbol, 76),
            (41, .symbol, 76),
            (56, [.accepted, .symbol], 76),

        /* 49 */

            (1, .symbol, 77),
            (22, [.accepted, .symbol], 77),
            (1, .symbol, 78),
            (22, [.accepted, .symbol], 78),
            (1, .symbol, 79),
            (22, [.accepted, .symbol], 79),
            (1, .symbol, 80),
            (22, [.accepted, .symbol], 80),
            (1, .symbol, 81),
            (22, [.accepted, .symbol], 81),
            (1, .symbol, 82),
            (22, [.accepted, .symbol], 82),
            (1, .symbol, 83),
            (22, [.accepted, .symbol], 83),
            (1, .symbol, 84),
            (22, [.accepted, .symbol], 84),

        /* 50 */

            (2, .symbol, 77),
            (9, .symbol, 77),
            (23, .symbol, 77),
            (40, [.accepted, .symbol], 77),
            (2, .symbol, 78),
            (9, .symbol, 78),
            (23, .symbol, 78),
            (40, [.accepted, .symbol], 78),
            (2, .symbol, 79),
            (9, .symbol, 79),
            (23, .symbol, 79),
            (40, [.accepted, .symbol], 79),
            (2, .symbol, 80),
            (9, .symbol, 80),
            (23, .symbol, 80),
            (40, [.accepted, .symbol], 80),

        /* 51 */

            (3, .symbol, 77),
            (6, .symbol, 77),
            (10, .symbol, 77),
            (15, .symbol, 77),
            (24, .symbol, 77),
            (31, .symbol, 77),
            (41, .symbol, 77),
            (56, [.accepted, .symbol], 77),
            (3, .symbol, 78),
            (6, .symbol, 78),
            (10, .symbol, 78),
            (15, .symbol, 78),
            (24, .symbol, 78),
            (31, .symbol, 78),
            (41, .symbol, 78),
            (56, [.accepted, .symbol], 78),

        /* 52 */

            (3, .symbol, 79),
            (6, .symbol, 79),
            (10, .symbol, 79),
            (15, .symbol, 79),
            (24, .symbol, 79),
            (31, .symbol, 79),
            (41, .symbol, 79),
            (56, [.accepted, .symbol], 79),
            (3, .symbol, 80),
            (6, .symbol, 80),
            (10, .symbol, 80),
            (15, .symbol, 80),
            (24, .symbol, 80),
            (31, .symbol, 80),
            (41, .symbol, 80),
            (56, [.accepted, .symbol], 80),

        /* 53 */

            (2, .symbol, 81),
            (9, .symbol, 81),
            (23, .symbol, 81),
            (40, [.accepted, .symbol], 81),
            (2, .symbol, 82),
            (9, .symbol, 82),
            (23, .symbol, 82),
            (40, [.accepted, .symbol], 82),
            (2, .symbol, 83),
            (9, .symbol, 83),
            (23, .symbol, 83),
            (40, [.accepted, .symbol], 83),
            (2, .symbol, 84),
            (9, .symbol, 84),
            (23, .symbol, 84),
            (40, [.accepted, .symbol], 84),

        /* 54 */

            (3, .symbol, 81),
            (6, .symbol, 81),
            (10, .symbol, 81),
            (15, .symbol, 81),
            (24, .symbol, 81),
            (31, .symbol, 81),
            (41, .symbol, 81),
            (56, [.accepted, .symbol], 81),
            (3, .symbol, 82),
            (6, .symbol, 82),
            (10, .symbol, 82),
            (15, .symbol, 82),
            (24, .symbol, 82),
            (31, .symbol, 82),
            (41, .symbol, 82),
            (56, [.accepted, .symbol], 82),

        /* 55 */

            (3, .symbol, 83),
            (6, .symbol, 83),
            (10, .symbol, 83),
            (15, .symbol, 83),
            (24, .symbol, 83),
            (31, .symbol, 83),
            (41, .symbol, 83),
            (56, [.accepted, .symbol], 83),
            (3, .symbol, 84),
            (6, .symbol, 84),
            (10, .symbol, 84),
            (15, .symbol, 84),
            (24, .symbol, 84),
            (31, .symbol, 84),
            (41, .symbol, 84),
            (56, [.accepted, .symbol], 84),

        /* 56 */

            (0, [.accepted, .symbol], 85),
            (0, [.accepted, .symbol], 86),
            (0, [.accepted, .symbol], 87),
            (0, [.accepted, .symbol], 89),
            (0, [.accepted, .symbol], 106),
            (0, [.accepted, .symbol], 107),
            (0, [.accepted, .symbol], 113),
            (0, [.accepted, .symbol], 118),
            (0, [.accepted, .symbol], 119),
            (0, [.accepted, .symbol], 120),
            (0, [.accepted, .symbol], 121),
            (0, [.accepted, .symbol], 122),
            (70, .none, 0),
            (71, .none, 0),
            (73, .none, 0),
            (74, .accepted, 0),

        /* 57 */

            (1, .symbol, 85),
            (22, [.accepted, .symbol], 85),
            (1, .symbol, 86),
            (22, [.accepted, .symbol], 86),
            (1, .symbol, 87),
            (22, [.accepted, .symbol], 87),
            (1, .symbol, 89),
            (22, [.accepted, .symbol], 89),
            (1, .symbol, 106),
            (22, [.accepted, .symbol], 106),
            (1, .symbol, 107),
            (22, [.accepted, .symbol], 107),
            (1, .symbol, 113),
            (22, [.accepted, .symbol], 113),
            (1, .symbol, 118),
            (22, [.accepted, .symbol], 118),

        /* 58 */

            (2, .symbol, 85),
            (9, .symbol, 85),
            (23, .symbol, 85),
            (40, [.accepted, .symbol], 85),
            (2, .symbol, 86),
            (9, .symbol, 86),
            (23, .symbol, 86),
            (40, [.accepted, .symbol], 86),
            (2, .symbol, 87),
            (9, .symbol, 87),
            (23, .symbol, 87),
            (40, [.accepted, .symbol], 87),
            (2, .symbol, 89),
            (9, .symbol, 89),
            (23, .symbol, 89),
            (40, [.accepted, .symbol], 89),

        /* 59 */

            (3, .symbol, 85),
            (6, .symbol, 85),
            (10, .symbol, 85),
            (15, .symbol, 85),
            (24, .symbol, 85),
            (31, .symbol, 85),
            (41, .symbol, 85),
            (56, [.accepted, .symbol], 85),
            (3, .symbol, 86),
            (6, .symbol, 86),
            (10, .symbol, 86),
            (15, .symbol, 86),
            (24, .symbol, 86),
            (31, .symbol, 86),
            (41, .symbol, 86),
            (56, [.accepted, .symbol], 86),

        /* 60 */

            (3, .symbol, 87),
            (6, .symbol, 87),
            (10, .symbol, 87),
            (15, .symbol, 87),
            (24, .symbol, 87),
            (31, .symbol, 87),
            (41, .symbol, 87),
            (56, [.accepted, .symbol], 87),
            (3, .symbol, 89),
            (6, .symbol, 89),
            (10, .symbol, 89),
            (15, .symbol, 89),
            (24, .symbol, 89),
            (31, .symbol, 89),
            (41, .symbol, 89),
            (56, [.accepted, .symbol], 89),

        /* 61 */

            (2, .symbol, 106),
            (9, .symbol, 106),
            (23, .symbol, 106),
            (40, [.accepted, .symbol], 106),
            (2, .symbol, 107),
            (9, .symbol, 107),
            (23, .symbol, 107),
            (40, [.accepted, .symbol], 107),
            (2, .symbol, 113),
            (9, .symbol, 113),
            (23, .symbol, 113),
            (40, [.accepted, .symbol], 113),
            (2, .symbol, 118),
            (9, .symbol, 118),
            (23, .symbol, 118),
            (40, [.accepted, .symbol], 118),

        /* 62 */

            (3, .symbol, 106),
            (6, .symbol, 106),
            (10, .symbol, 106),
            (15, .symbol, 106),
            (24, .symbol, 106),
            (31, .symbol, 106),
            (41, .symbol, 106),
            (56, [.accepted, .symbol], 106),
            (3, .symbol, 107),
            (6, .symbol, 107),
            (10, .symbol, 107),
            (15, .symbol, 107),
            (24, .symbol, 107),
            (31, .symbol, 107),
            (41, .symbol, 107),
            (56, [.accepted, .symbol], 107),

        /* 63 */

            (3, .symbol, 113),
            (6, .symbol, 113),
            (10, .symbol, 113),
            (15, .symbol, 113),
            (24, .symbol, 113),
            (31, .symbol, 113),
            (41, .symbol, 113),
            (56, [.accepted, .symbol], 113),
            (3, .symbol, 118),
            (6, .symbol, 118),
            (10, .symbol, 118),
            (15, .symbol, 118),
            (24, .symbol, 118),
            (31, .symbol, 118),
            (41, .symbol, 118),
            (56, [.accepted, .symbol], 118),

        /* 64 */

            (1, .symbol, 119),
            (22, [.accepted, .symbol], 119),
            (1, .symbol, 120),
            (22, [.accepted, .symbol], 120),
            (1, .symbol, 121),
            (22, [.accepted, .symbol], 121),
            (1, .symbol, 122),
            (22, [.accepted, .symbol], 122),
            (0, [.accepted, .symbol], 38),
            (0, [.accepted, .symbol], 42),
            (0, [.accepted, .symbol], 44),
            (0, [.accepted, .symbol], 59),
            (0, [.accepted, .symbol], 88),
            (0, [.accepted, .symbol], 90),
            (75, .none, 0),
            (78, .none, 0),

        /* 65 */

            (2, .symbol, 119),
            (9, .symbol, 119),
            (23, .symbol, 119),
            (40, [.accepted, .symbol], 119),
            (2, .symbol, 120),
            (9, .symbol, 120),
            (23, .symbol, 120),
            (40, [.accepted, .symbol], 120),
            (2, .symbol, 121),
            (9, .symbol, 121),
            (23, .symbol, 121),
            (40, [.accepted, .symbol], 121),
            (2, .symbol, 122),
            (9, .symbol, 122),
            (23, .symbol, 122),
            (40, [.accepted, .symbol], 122),

        /* 66 */

            (3, .symbol, 119),
            (6, .symbol, 119),
            (10, .symbol, 119),
            (15, .symbol, 119),
            (24, .symbol, 119),
            (31, .symbol, 119),
            (41, .symbol, 119),
            (56, [.accepted, .symbol], 119),
            (3, .symbol, 120),
            (6, .symbol, 120),
            (10, .symbol, 120),
            (15, .symbol, 120),
            (24, .symbol, 120),
            (31, .symbol, 120),
            (41, .symbol, 120),
            (56, [.accepted, .symbol], 120),

        /* 67 */

            (3, .symbol, 121),
            (6, .symbol, 121),
            (10, .symbol, 121),
            (15, .symbol, 121),
            (24, .symbol, 121),
            (31, .symbol, 121),
            (41, .symbol, 121),
            (56, [.accepted, .symbol], 121),
            (3, .symbol, 122),
            (6, .symbol, 122),
            (10, .symbol, 122),
            (15, .symbol, 122),
            (24, .symbol, 122),
            (31, .symbol, 122),
            (41, .symbol, 122),
            (56, [.accepted, .symbol], 122),

        /* 68 */

            (1, .symbol, 38),
            (22, [.accepted, .symbol], 38),
            (1, .symbol, 42),
            (22, [.accepted, .symbol], 42),
            (1, .symbol, 44),
            (22, [.accepted, .symbol], 44),
            (1, .symbol, 59),
            (22, [.accepted, .symbol], 59),
            (1, .symbol, 88),
            (22, [.accepted, .symbol], 88),
            (1, .symbol, 90),
            (22, [.accepted, .symbol], 90),
            (76, .none, 0),
            (77, .none, 0),
            (79, .none, 0),
            (81, .none, 0),

        /* 69 */

            (2, .symbol, 38),
            (9, .symbol, 38),
            (23, .symbol, 38),
            (40, [.accepted, .symbol], 38),
            (2, .symbol, 42),
            (9, .symbol, 42),
            (23, .symbol, 42),
            (40, [.accepted, .symbol], 42),
            (2, .symbol, 44),
            (9, .symbol, 44),
            (23, .symbol, 44),
            (40, [.accepted, .symbol], 44),
            (2, .symbol, 59),
            (9, .symbol, 59),
            (23, .symbol, 59),
            (40, [.accepted, .symbol], 59),

        /* 70 */

            (3, .symbol, 38),
            (6, .symbol, 38),
            (10, .symbol, 38),
            (15, .symbol, 38),
            (24, .symbol, 38),
            (31, .symbol, 38),
            (41, .symbol, 38),
            (56, [.accepted, .symbol], 38),
            (3, .symbol, 42),
            (6, .symbol, 42),
            (10, .symbol, 42),
            (15, .symbol, 42),
            (24, .symbol, 42),
            (31, .symbol, 42),
            (41, .symbol, 42),
            (56, [.accepted, .symbol], 42),

        /* 71 */

            (3, .symbol, 44),
            (6, .symbol, 44),
            (10, .symbol, 44),
            (15, .symbol, 44),
            (24, .symbol, 44),
            (31, .symbol, 44),
            (41, .symbol, 44),
            (56, [.accepted, .symbol], 44),
            (3, .symbol, 59),
            (6, .symbol, 59),
            (10, .symbol, 59),
            (15, .symbol, 59),
            (24, .symbol, 59),
            (31, .symbol, 59),
            (41, .symbol, 59),
            (56, [.accepted, .symbol], 59),

        /* 72 */

            (2, .symbol, 88),
            (9, .symbol, 88),
            (23, .symbol, 88),
            (40, [.accepted, .symbol], 88),
            (2, .symbol, 90),
            (9, .symbol, 90),
            (23, .symbol, 90),
            (40, [.accepted, .symbol], 90),
            (0, [.accepted, .symbol], 33),
            (0, [.accepted, .symbol], 34),
            (0, [.accepted, .symbol], 40),
            (0, [.accepted, .symbol], 41),
            (0, [.accepted, .symbol], 63),
            (80, .none, 0),
            (82, .none, 0),
            (84, .none, 0),

        /* 73 */

            (3, .symbol, 88),
            (6, .symbol, 88),
            (10, .symbol, 88),
            (15, .symbol, 88),
            (24, .symbol, 88),
            (31, .symbol, 88),
            (41, .symbol, 88),
            (56, [.accepted, .symbol], 88),
            (3, .symbol, 90),
            (6, .symbol, 90),
            (10, .symbol, 90),
            (15, .symbol, 90),
            (24, .symbol, 90),
            (31, .symbol, 90),
            (41, .symbol, 90),
            (56, [.accepted, .symbol], 90),

        /* 74 */

            (1, .symbol, 33),
            (22, [.accepted, .symbol], 33),
            (1, .symbol, 34),
            (22, [.accepted, .symbol], 34),
            (1, .symbol, 40),
            (22, [.accepted, .symbol], 40),
            (1, .symbol, 41),
            (22, [.accepted, .symbol], 41),
            (1, .symbol, 63),
            (22, [.accepted, .symbol], 63),
            (0, [.accepted, .symbol], 39),
            (0, [.accepted, .symbol], 43),
            (0, [.accepted, .symbol], 124),
            (83, .none, 0),
            (85, .none, 0),
            (88, .none, 0),

        /* 75 */

            (2, .symbol, 33),
            (9, .symbol, 33),
            (23, .symbol, 33),
            (40, [.accepted, .symbol], 33),
            (2, .symbol, 34),
            (9, .symbol, 34),
            (23, .symbol, 34),
            (40, [.accepted, .symbol], 34),
            (2, .symbol, 40),
            (9, .symbol, 40),
            (23, .symbol, 40),
            (40, [.accepted, .symbol], 40),
            (2, .symbol, 41),
            (9, .symbol, 41),
            (23, .symbol, 41),
            (40, [.accepted, .symbol], 41),

        /* 76 */

            (3, .symbol, 33),
            (6, .symbol, 33),
            (10, .symbol, 33),
            (15, .symbol, 33),
            (24, .symbol, 33),
            (31, .symbol, 33),
            (41, .symbol, 33),
            (56, [.accepted, .symbol], 33),
            (3, .symbol, 34),
            (6, .symbol, 34),
            (10, .symbol, 34),
            (15, .symbol, 34),
            (24, .symbol, 34),
            (31, .symbol, 34),
            (41, .symbol, 34),
            (56, [.accepted, .symbol], 34),

        /* 77 */

            (3, .symbol, 40),
            (6, .symbol, 40),
            (10, .symbol, 40),
            (15, .symbol, 40),
            (24, .symbol, 40),
            (31, .symbol, 40),
            (41, .symbol, 40),
            (56, [.accepted, .symbol], 40),
            (3, .symbol, 41),
            (6, .symbol, 41),
            (10, .symbol, 41),
            (15, .symbol, 41),
            (24, .symbol, 41),
            (31, .symbol, 41),
            (41, .symbol, 41),
            (56, [.accepted, .symbol], 41),

        /* 78 */

            (2, .symbol, 63),
            (9, .symbol, 63),
            (23, .symbol, 63),
            (40, [.accepted, .symbol], 63),
            (1, .symbol, 39),
            (22, [.accepted, .symbol], 39),
            (1, .symbol, 43),
            (22, [.accepted, .symbol], 43),
            (1, .symbol, 124),
            (22, [.accepted, .symbol], 124),
            (0, [.accepted, .symbol], 35),
            (0, [.accepted, .symbol], 62),
            (86, .none, 0),
            (87, .none, 0),
            (89, .none, 0),
            (90, .none, 0),

        /* 79 */

            (3, .symbol, 63),
            (6, .symbol, 63),
            (10, .symbol, 63),
            (15, .symbol, 63),
            (24, .symbol, 63),
            (31, .symbol, 63),
            (41, .symbol, 63),
            (56, [.accepted, .symbol], 63),
            (2, .symbol, 39),
            (9, .symbol, 39),
            (23, .symbol, 39),
            (40, [.accepted, .symbol], 39),
            (2, .symbol, 43),
            (9, .symbol, 43),
            (23, .symbol, 43),
            (40, [.accepted, .symbol], 43),

        /* 80 */

            (3, .symbol, 39),
            (6, .symbol, 39),
            (10, .symbol, 39),
            (15, .symbol, 39),
            (24, .symbol, 39),
            (31, .symbol, 39),
            (41, .symbol, 39),
            (56, [.accepted, .symbol], 39),
            (3, .symbol, 43),
            (6, .symbol, 43),
            (10, .symbol, 43),
            (15, .symbol, 43),
            (24, .symbol, 43),
            (31, .symbol, 43),
            (41, .symbol, 43),
            (56, [.accepted, .symbol], 43),

        /* 81 */

            (2, .symbol, 124),
            (9, .symbol, 124),
            (23, .symbol, 124),
            (40, [.accepted, .symbol], 124),
            (1, .symbol, 35),
            (22, [.accepted, .symbol], 35),
            (1, .symbol, 62),
            (22, [.accepted, .symbol], 62),
            (0, [.accepted, .symbol], 0),
            (0, [.accepted, .symbol], 36),
            (0, [.accepted, .symbol], 64),
            (0, [.accepted, .symbol], 91),
            (0, [.accepted, .symbol], 93),
            (0, [.accepted, .symbol], 126),
            (91, .none, 0),
            (92, .none, 0),

        /* 82 */

            (3, .symbol, 124),
            (6, .symbol, 124),
            (10, .symbol, 124),
            (15, .symbol, 124),
            (24, .symbol, 124),
            (31, .symbol, 124),
            (41, .symbol, 124),
            (56, [.accepted, .symbol], 124),
            (2, .symbol, 35),
            (9, .symbol, 35),
            (23, .symbol, 35),
            (40, [.accepted, .symbol], 35),
            (2, .symbol, 62),
            (9, .symbol, 62),
            (23, .symbol, 62),
            (40, [.accepted, .symbol], 62),

        /* 83 */

            (3, .symbol, 35),
            (6, .symbol, 35),
            (10, .symbol, 35),
            (15, .symbol, 35),
            (24, .symbol, 35),
            (31, .symbol, 35),
            (41, .symbol, 35),
            (56, [.accepted, .symbol], 35),
            (3, .symbol, 62),
            (6, .symbol, 62),
            (10, .symbol, 62),
            (15, .symbol, 62),
            (24, .symbol, 62),
            (31, .symbol, 62),
            (41, .symbol, 62),
            (56, [.accepted, .symbol], 62),

        /* 84 */

            (1, .symbol, 0),
            (22, [.accepted, .symbol], 0),
            (1, .symbol, 36),
            (22, [.accepted, .symbol], 36),
            (1, .symbol, 64),
            (22, [.accepted, .symbol], 64),
            (1, .symbol, 91),
            (22, [.accepted, .symbol], 91),
            (1, .symbol, 93),
            (22, [.accepted, .symbol], 93),
            (1, .symbol, 126),
            (22, [.accepted, .symbol], 126),
            (0, [.accepted, .symbol], 94),
            (0, [.accepted, .symbol], 125),
            (93, .none, 0),
            (94, .none, 0),

        /* 85 */

            (2, .symbol, 0),
            (9, .symbol, 0),
            (23, .symbol, 0),
            (40, [.accepted, .symbol], 0),
            (2, .symbol, 36),
            (9, .symbol, 36),
            (23, .symbol, 36),
            (40, [.accepted, .symbol], 36),
            (2, .symbol, 64),
            (9, .symbol, 64),
            (23, .symbol, 64),
            (40, [.accepted, .symbol], 64),
            (2, .symbol, 91),
            (9, .symbol, 91),
            (23, .symbol, 91),
            (40, [.accepted, .symbol], 91),

        /* 86 */

            (3, .symbol, 0),
            (6, .symbol, 0),
            (10, .symbol, 0),
            (15, .symbol, 0),
            (24, .symbol, 0),
            (31, .symbol, 0),
            (41, .symbol, 0),
            (56, [.accepted, .symbol], 0),
            (3, .symbol, 36),
            (6, .symbol, 36),
            (10, .symbol, 36),
            (15, .symbol, 36),
            (24, .symbol, 36),
            (31, .symbol, 36),
            (41, .symbol, 36),
            (56, [.accepted, .symbol], 36),

        /* 87 */

            (3, .symbol, 64),
            (6, .symbol, 64),
            (10, .symbol, 64),
            (15, .symbol, 64),
            (24, .symbol, 64),
            (31, .symbol, 64),
            (41, .symbol, 64),
            (56, [.accepted, .symbol], 64),
            (3, .symbol, 91),
            (6, .symbol, 91),
            (10, .symbol, 91),
            (15, .symbol, 91),
            (24, .symbol, 91),
            (31, .symbol, 91),
            (41, .symbol, 91),
            (56, [.accepted, .symbol], 91),

        /* 88 */

            (2, .symbol, 93),
            (9, .symbol, 93),
            (23, .symbol, 93),
            (40, [.accepted, .symbol], 93),
            (2, .symbol, 126),
            (9, .symbol, 126),
            (23, .symbol, 126),
            (40, [.accepted, .symbol], 126),
            (1, .symbol, 94),
            (22, [.accepted, .symbol], 94),
            (1, .symbol, 125),
            (22, [.accepted, .symbol], 125),
            (0, [.accepted, .symbol], 60),
            (0, [.accepted, .symbol], 96),
            (0, [.accepted, .symbol], 123),
            (95, .none, 0),

        /* 89 */

            (3, .symbol, 93),
            (6, .symbol, 93),
            (10, .symbol, 93),
            (15, .symbol, 93),
            (24, .symbol, 93),
            (31, .symbol, 93),
            (41, .symbol, 93),
            (56, [.accepted, .symbol], 93),
            (3, .symbol, 126),
            (6, .symbol, 126),
            (10, .symbol, 126),
            (15, .symbol, 126),
            (24, .symbol, 126),
            (31, .symbol, 126),
            (41, .symbol, 126),
            (56, [.accepted, .symbol], 126),

        /* 90 */

            (2, .symbol, 94),
            (9, .symbol, 94),
            (23, .symbol, 94),
            (40, [.accepted, .symbol], 94),
            (2, .symbol, 125),
            (9, .symbol, 125),
            (23, .symbol, 125),
            (40, [.accepted, .symbol], 125),
            (1, .symbol, 60),
            (22, [.accepted, .symbol], 60),
            (1, .symbol, 96),
            (22, [.accepted, .symbol], 96),
            (1, .symbol, 123),
            (22, [.accepted, .symbol], 123),
            (96, .none, 0),
            (110, .none, 0),

        /* 91 */

            (3, .symbol, 94),
            (6, .symbol, 94),
            (10, .symbol, 94),
            (15, .symbol, 94),
            (24, .symbol, 94),
            (31, .symbol, 94),
            (41, .symbol, 94),
            (56, [.accepted, .symbol], 94),
            (3, .symbol, 125),
            (6, .symbol, 125),
            (10, .symbol, 125),
            (15, .symbol, 125),
            (24, .symbol, 125),
            (31, .symbol, 125),
            (41, .symbol, 125),
            (56, [.accepted, .symbol], 125),

        /* 92 */

            (2, .symbol, 60),
            (9, .symbol, 60),
            (23, .symbol, 60),
            (40, [.accepted, .symbol], 60),
            (2, .symbol, 96),
            (9, .symbol, 96),
            (23, .symbol, 96),
            (40, [.accepted, .symbol], 96),
            (2, .symbol, 123),
            (9, .symbol, 123),
            (23, .symbol, 123),
            (40, [.accepted, .symbol], 123),
            (97, .none, 0),
            (101, .none, 0),
            (111, .none, 0),
            (133, .none, 0),

        /* 93 */

            (3, .symbol, 60),
            (6, .symbol, 60),
            (10, .symbol, 60),
            (15, .symbol, 60),
            (24, .symbol, 60),
            (31, .symbol, 60),
            (41, .symbol, 60),
            (56, [.accepted, .symbol], 60),
            (3, .symbol, 96),
            (6, .symbol, 96),
            (10, .symbol, 96),
            (15, .symbol, 96),
            (24, .symbol, 96),
            (31, .symbol, 96),
            (41, .symbol, 96),
            (56, [.accepted, .symbol], 96),

        /* 94 */

            (3, .symbol, 123),
            (6, .symbol, 123),
            (10, .symbol, 123),
            (15, .symbol, 123),
            (24, .symbol, 123),
            (31, .symbol, 123),
            (41, .symbol, 123),
            (56, [.accepted, .symbol], 123),
            (98, .none, 0),
            (99, .none, 0),
            (102, .none, 0),
            (105, .none, 0),
            (112, .none, 0),
            (119, .none, 0),
            (134, .none, 0),
            (153, .none, 0),

        /* 95 */

            (0, [.accepted, .symbol], 92),
            (0, [.accepted, .symbol], 195),
            (0, [.accepted, .symbol], 208),
            (100, .none, 0),
            (103, .none, 0),
            (104, .none, 0),
            (106, .none, 0),
            (107, .none, 0),
            (113, .none, 0),
            (116, .none, 0),
            (120, .none, 0),
            (126, .none, 0),
            (135, .none, 0),
            (142, .none, 0),
            (154, .none, 0),
            (169, .none, 0),

        /* 96 */

            (1, .symbol, 92),
            (22, [.accepted, .symbol], 92),
            (1, .symbol, 195),
            (22, [.accepted, .symbol], 195),
            (1, .symbol, 208),
            (22, [.accepted, .symbol], 208),
            (0, [.accepted, .symbol], 128),
            (0, [.accepted, .symbol], 130),
            (0, [.accepted, .symbol], 131),
            (0, [.accepted, .symbol], 162),
            (0, [.accepted, .symbol], 184),
            (0, [.accepted, .symbol], 194),
            (0, [.accepted, .symbol], 224),
            (0, [.accepted, .symbol], 226),
            (108, .none, 0),
            (109, .none, 0),

        /* 97 */

            (2, .symbol, 92),
            (9, .symbol, 92),
            (23, .symbol, 92),
            (40, [.accepted, .symbol], 92),
            (2, .symbol, 195),
            (9, .symbol, 195),
            (23, .symbol, 195),
            (40, [.accepted, .symbol], 195),
            (2, .symbol, 208),
            (9, .symbol, 208),
            (23, .symbol, 208),
            (40, [.accepted, .symbol], 208),
            (1, .symbol, 128),
            (22, [.accepted, .symbol], 128),
            (1, .symbol, 130),
            (22, [.accepted, .symbol], 130),

        /* 98 */

            (3, .symbol, 92),
            (6, .symbol, 92),
            (10, .symbol, 92),
            (15, .symbol, 92),
            (24, .symbol, 92),
            (31, .symbol, 92),
            (41, .symbol, 92),
            (56, [.accepted, .symbol], 92),
            (3, .symbol, 195),
            (6, .symbol, 195),
            (10, .symbol, 195),
            (15, .symbol, 195),
            (24, .symbol, 195),
            (31, .symbol, 195),
            (41, .symbol, 195),
            (56, [.accepted, .symbol], 195),

        /* 99 */

            (3, .symbol, 208),
            (6, .symbol, 208),
            (10, .symbol, 208),
            (15, .symbol, 208),
            (24, .symbol, 208),
            (31, .symbol, 208),
            (41, .symbol, 208),
            (56, [.accepted, .symbol], 208),
            (2, .symbol, 128),
            (9, .symbol, 128),
            (23, .symbol, 128),
            (40, [.accepted, .symbol], 128),
            (2, .symbol, 130),
            (9, .symbol, 130),
            (23, .symbol, 130),
            (40, [.accepted, .symbol], 130),

        /* 100 */

            (3, .symbol, 128),
            (6, .symbol, 128),
            (10, .symbol, 128),
            (15, .symbol, 128),
            (24, .symbol, 128),
            (31, .symbol, 128),
            (41, .symbol, 128),
            (56, [.accepted, .symbol], 128),
            (3, .symbol, 130),
            (6, .symbol, 130),
            (10, .symbol, 130),
            (15, .symbol, 130),
            (24, .symbol, 130),
            (31, .symbol, 130),
            (41, .symbol, 130),
            (56, [.accepted, .symbol], 130),

        /* 101 */

            (1, .symbol, 131),
            (22, [.accepted, .symbol], 131),
            (1, .symbol, 162),
            (22, [.accepted, .symbol], 162),
            (1, .symbol, 184),
            (22, [.accepted, .symbol], 184),
            (1, .symbol, 194),
            (22, [.accepted, .symbol], 194),
            (1, .symbol, 224),
            (22, [.accepted, .symbol], 224),
            (1, .symbol, 226),
            (22, [.accepted, .symbol], 226),
            (0, [.accepted, .symbol], 153),
            (0, [.accepted, .symbol], 161),
            (0, [.accepted, .symbol], 167),
            (0, [.accepted, .symbol], 172),

        /* 102 */

            (2, .symbol, 131),
            (9, .symbol, 131),
            (23, .symbol, 131),
            (40, [.accepted, .symbol], 131),
            (2, .symbol, 162),
            (9, .symbol, 162),
            (23, .symbol, 162),
            (40, [.accepted, .symbol], 162),
            (2, .symbol, 184),
            (9, .symbol, 184),
            (23, .symbol, 184),
            (40, [.accepted, .symbol], 184),
            (2, .symbol, 194),
            (9, .symbol, 194),
            (23, .symbol, 194),
            (40, [.accepted, .symbol], 194),

        /* 103 */

            (3, .symbol, 131),
            (6, .symbol, 131),
            (10, .symbol, 131),
            (15, .symbol, 131),
            (24, .symbol, 131),
            (31, .symbol, 131),
            (41, .symbol, 131),
            (56, [.accepted, .symbol], 131),
            (3, .symbol, 162),
            (6, .symbol, 162),
            (10, .symbol, 162),
            (15, .symbol, 162),
            (24, .symbol, 162),
            (31, .symbol, 162),
            (41, .symbol, 162),
            (56, [.accepted, .symbol], 162),

        /* 104 */

            (3, .symbol, 184),
            (6, .symbol, 184),
            (10, .symbol, 184),
            (15, .symbol, 184),
            (24, .symbol, 184),
            (31, .symbol, 184),
            (41, .symbol, 184),
            (56, [.accepted, .symbol], 184),
            (3, .symbol, 194),
            (6, .symbol, 194),
            (10, .symbol, 194),
            (15, .symbol, 194),
            (24, .symbol, 194),
            (31, .symbol, 194),
            (41, .symbol, 194),
            (56, [.accepted, .symbol], 194),

        /* 105 */

            (2, .symbol, 224),
            (9, .symbol, 224),
            (23, .symbol, 224),
            (40, [.accepted, .symbol], 224),
            (2, .symbol, 226),
            (9, .symbol, 226),
            (23, .symbol, 226),
            (40, [.accepted, .symbol], 226),
            (1, .symbol, 153),
            (22, [.accepted, .symbol], 153),
            (1, .symbol, 161),
            (22, [.accepted, .symbol], 161),
            (1, .symbol, 167),
            (22, [.accepted, .symbol], 167),
            (1, .symbol, 172),
            (22, [.accepted, .symbol], 172),

        /* 106 */

            (3, .symbol, 224),
            (6, .symbol, 224),
            (10, .symbol, 224),
            (15, .symbol, 224),
            (24, .symbol, 224),
            (31, .symbol, 224),
            (41, .symbol, 224),
            (56, [.accepted, .symbol], 224),
            (3, .symbol, 226),
            (6, .symbol, 226),
            (10, .symbol, 226),
            (15, .symbol, 226),
            (24, .symbol, 226),
            (31, .symbol, 226),
            (41, .symbol, 226),
            (56, [.accepted, .symbol], 226),

        /* 107 */

            (2, .symbol, 153),
            (9, .symbol, 153),
            (23, .symbol, 153),
            (40, [.accepted, .symbol], 153),
            (2, .symbol, 161),
            (9, .symbol, 161),
            (23, .symbol, 161),
            (40, [.accepted, .symbol], 161),
            (2, .symbol, 167),
            (9, .symbol, 167),
            (23, .symbol, 167),
            (40, [.accepted, .symbol], 167),
            (2, .symbol, 172),
            (9, .symbol, 172),
            (23, .symbol, 172),
            (40, [.accepted, .symbol], 172),

        /* 108 */

            (3, .symbol, 153),
            (6, .symbol, 153),
            (10, .symbol, 153),
            (15, .symbol, 153),
            (24, .symbol, 153),
            (31, .symbol, 153),
            (41, .symbol, 153),
            (56, [.accepted, .symbol], 153),
            (3, .symbol, 161),
            (6, .symbol, 161),
            (10, .symbol, 161),
            (15, .symbol, 161),
            (24, .symbol, 161),
            (31, .symbol, 161),
            (41, .symbol, 161),
            (56, [.accepted, .symbol], 161),

        /* 109 */

            (3, .symbol, 167),
            (6, .symbol, 167),
            (10, .symbol, 167),
            (15, .symbol, 167),
            (24, .symbol, 167),
            (31, .symbol, 167),
            (41, .symbol, 167),
            (56, [.accepted, .symbol], 167),
            (3, .symbol, 172),
            (6, .symbol, 172),
            (10, .symbol, 172),
            (15, .symbol, 172),
            (24, .symbol, 172),
            (31, .symbol, 172),
            (41, .symbol, 172),
            (56, [.accepted, .symbol], 172),

        /* 110 */

            (114, .none, 0),
            (115, .none, 0),
            (117, .none, 0),
            (118, .none, 0),
            (121, .none, 0),
            (123, .none, 0),
            (127, .none, 0),
            (130, .none, 0),
            (136, .none, 0),
            (139, .none, 0),
            (143, .none, 0),
            (146, .none, 0),
            (155, .none, 0),
            (162, .none, 0),
            (170, .none, 0),
            (180, .none, 0),

        /* 111 */

            (0, [.accepted, .symbol], 176),
            (0, [.accepted, .symbol], 177),
            (0, [.accepted, .symbol], 179),
            (0, [.accepted, .symbol], 209),
            (0, [.accepted, .symbol], 216),
            (0, [.accepted, .symbol], 217),
            (0, [.accepted, .symbol], 227),
            (0, [.accepted, .symbol], 229),
            (0, [.accepted, .symbol], 230),
            (122, .none, 0),
            (124, .none, 0),
            (125, .none, 0),
            (128, .none, 0),
            (129, .none, 0),
            (131, .none, 0),
            (132, .none, 0),

        /* 112 */

            (1, .symbol, 176),
            (22, [.accepted, .symbol], 176),
            (1, .symbol, 177),
            (22, [.accepted, .symbol], 177),
            (1, .symbol, 179),
            (22, [.accepted, .symbol], 179),
            (1, .symbol, 209),
            (22, [.accepted, .symbol], 209),
            (1, .symbol, 216),
            (22, [.accepted, .symbol], 216),
            (1, .symbol, 217),
            (22, [.accepted, .symbol], 217),
            (1, .symbol, 227),
            (22, [.accepted, .symbol], 227),
            (1, .symbol, 229),
            (22, [.accepted, .symbol], 229),

        /* 113 */

            (2, .symbol, 176),
            (9, .symbol, 176),
            (23, .symbol, 176),
            (40, [.accepted, .symbol], 176),
            (2, .symbol, 177),
            (9, .symbol, 177),
            (23, .symbol, 177),
            (40, [.accepted, .symbol], 177),
            (2, .symbol, 179),
            (9, .symbol, 179),
            (23, .symbol, 179),
            (40, [.accepted, .symbol], 179),
            (2, .symbol, 209),
            (9, .symbol, 209),
            (23, .symbol, 209),
            (40, [.accepted, .symbol], 209),

        /* 114 */

            (3, .symbol, 176),
            (6, .symbol, 176),
            (10, .symbol, 176),
            (15, .symbol, 176),
            (24, .symbol, 176),
            (31, .symbol, 176),
            (41, .symbol, 176),
            (56, [.accepted, .symbol], 176),
            (3, .symbol, 177),
            (6, .symbol, 177),
            (10, .symbol, 177),
            (15, .symbol, 177),
            (24, .symbol, 177),
            (31, .symbol, 177),
            (41, .symbol, 177),
            (56, [.accepted, .symbol], 177),

        /* 115 */

            (3, .symbol, 179),
            (6, .symbol, 179),
            (10, .symbol, 179),
            (15, .symbol, 179),
            (24, .symbol, 179),
            (31, .symbol, 179),
            (41, .symbol, 179),
            (56, [.accepted, .symbol], 179),
            (3, .symbol, 209),
            (6, .symbol, 209),
            (10, .symbol, 209),
            (15, .symbol, 209),
            (24, .symbol, 209),
            (31, .symbol, 209),
            (41, .symbol, 209),
            (56, [.accepted, .symbol], 209),

        /* 116 */

            (2, .symbol, 216),
            (9, .symbol, 216),
            (23, .symbol, 216),
            (40, [.accepted, .symbol], 216),
            (2, .symbol, 217),
            (9, .symbol, 217),
            (23, .symbol, 217),
            (40, [.accepted, .symbol], 217),
            (2, .symbol, 227),
            (9, .symbol, 227),
            (23, .symbol, 227),
            (40, [.accepted, .symbol], 227),
            (2, .symbol, 229),
            (9, .symbol, 229),
            (23, .symbol, 229),
            (40, [.accepted, .symbol], 229),

        /* 117 */

            (3, .symbol, 216),
            (6, .symbol, 216),
            (10, .symbol, 216),
            (15, .symbol, 216),
            (24, .symbol, 216),
            (31, .symbol, 216),
            (41, .symbol, 216),
            (56, [.accepted, .symbol], 216),
            (3, .symbol, 217),
            (6, .symbol, 217),
            (10, .symbol, 217),
            (15, .symbol, 217),
            (24, .symbol, 217),
            (31, .symbol, 217),
            (41, .symbol, 217),
            (56, [.accepted, .symbol], 217),

        /* 118 */

            (3, .symbol, 227),
            (6, .symbol, 227),
            (10, .symbol, 227),
            (15, .symbol, 227),
            (24, .symbol, 227),
            (31, .symbol, 227),
            (41, .symbol, 227),
            (56, [.accepted, .symbol], 227),
            (3, .symbol, 229),
            (6, .symbol, 229),
            (10, .symbol, 229),
            (15, .symbol, 229),
            (24, .symbol, 229),
            (31, .symbol, 229),
            (41, .symbol, 229),
            (56, [.accepted, .symbol], 229),

        /* 119 */

            (1, .symbol, 230),
            (22, [.accepted, .symbol], 230),
            (0, [.accepted, .symbol], 129),
            (0, [.accepted, .symbol], 132),
            (0, [.accepted, .symbol], 133),
            (0, [.accepted, .symbol], 134),
            (0, [.accepted, .symbol], 136),
            (0, [.accepted, .symbol], 146),
            (0, [.accepted, .symbol], 154),
            (0, [.accepted, .symbol], 156),
            (0, [.accepted, .symbol], 160),
            (0, [.accepted, .symbol], 163),
            (0, [.accepted, .symbol], 164),
            (0, [.accepted, .symbol], 169),
            (0, [.accepted, .symbol], 170),
            (0, [.accepted, .symbol], 173),

        /* 120 */

            (2, .symbol, 230),
            (9, .symbol, 230),
            (23, .symbol, 230),
            (40, [.accepted, .symbol], 230),
            (1, .symbol, 129),
            (22, [.accepted, .symbol], 129),
            (1, .symbol, 132),
            (22, [.accepted, .symbol], 132),
            (1, .symbol, 133),
            (22, [.accepted, .symbol], 133),
            (1, .symbol, 134),
            (22, [.accepted, .symbol], 134),
            (1, .symbol, 136),
            (22, [.accepted, .symbol], 136),
            (1, .symbol, 146),
            (22, [.accepted, .symbol], 146),

        /* 121 */

            (3, .symbol, 230),
            (6, .symbol, 230),
            (10, .symbol, 230),
            (15, .symbol, 230),
            (24, .symbol, 230),
            (31, .symbol, 230),
            (41, .symbol, 230),
            (56, [.accepted, .symbol], 230),
            (2, .symbol, 129),
            (9, .symbol, 129),
            (23, .symbol, 129),
            (40, [.accepted, .symbol], 129),
            (2, .symbol, 132),
            (9, .symbol, 132),
            (23, .symbol, 132),
            (40, [.accepted, .symbol], 132),

        /* 122 */

            (3, .symbol, 129),
            (6, .symbol, 129),
            (10, .symbol, 129),
            (15, .symbol, 129),
            (24, .symbol, 129),
            (31, .symbol, 129),
            (41, .symbol, 129),
            (56, [.accepted, .symbol], 129),
            (3, .symbol, 132),
            (6, .symbol, 132),
            (10, .symbol, 132),
            (15, .symbol, 132),
            (24, .symbol, 132),
            (31, .symbol, 132),
            (41, .symbol, 132),
            (56, [.accepted, .symbol], 132),

        /* 123 */

            (2, .symbol, 133),
            (9, .symbol, 133),
            (23, .symbol, 133),
            (40, [.accepted, .symbol], 133),
            (2, .symbol, 134),
            (9, .symbol, 134),
            (23, .symbol, 134),
            (40, [.accepted, .symbol], 134),
            (2, .symbol, 136),
            (9, .symbol, 136),
            (23, .symbol, 136),
            (40, [.accepted, .symbol], 136),
            (2, .symbol, 146),
            (9, .symbol, 146),
            (23, .symbol, 146),
            (40, [.accepted, .symbol], 146),

        /* 124 */

            (3, .symbol, 133),
            (6, .symbol, 133),
            (10, .symbol, 133),
            (15, .symbol, 133),
            (24, .symbol, 133),
            (31, .symbol, 133),
            (41, .symbol, 133),
            (56, [.accepted, .symbol], 133),
            (3, .symbol, 134),
            (6, .symbol, 134),
            (10, .symbol, 134),
            (15, .symbol, 134),
            (24, .symbol, 134),
            (31, .symbol, 134),
            (41, .symbol, 134),
            (56, [.accepted, .symbol], 134),

        /* 125 */

            (3, .symbol, 136),
            (6, .symbol, 136),
            (10, .symbol, 136),
            (15, .symbol, 136),
            (24, .symbol, 136),
            (31, .symbol, 136),
            (41, .symbol, 136),
            (56, [.accepted, .symbol], 136),
            (3, .symbol, 146),
            (6, .symbol, 146),
            (10, .symbol, 146),
            (15, .symbol, 146),
            (24, .symbol, 146),
            (31, .symbol, 146),
            (41, .symbol, 146),
            (56, [.accepted, .symbol], 146),

        /* 126 */

            (1, .symbol, 154),
            (22, [.accepted, .symbol], 154),
            (1, .symbol, 156),
            (22, [.accepted, .symbol], 156),
            (1, .symbol, 160),
            (22, [.accepted, .symbol], 160),
            (1, .symbol, 163),
            (22, [.accepted, .symbol], 163),
            (1, .symbol, 164),
            (22, [.accepted, .symbol], 164),
            (1, .symbol, 169),
            (22, [.accepted, .symbol], 169),
            (1, .symbol, 170),
            (22, [.accepted, .symbol], 170),
            (1, .symbol, 173),
            (22, [.accepted, .symbol], 173),

        /* 127 */

            (2, .symbol, 154),
            (9, .symbol, 154),
            (23, .symbol, 154),
            (40, [.accepted, .symbol], 154),
            (2, .symbol, 156),
            (9, .symbol, 156),
            (23, .symbol, 156),
            (40, [.accepted, .symbol], 156),
            (2, .symbol, 160),
            (9, .symbol, 160),
            (23, .symbol, 160),
            (40, [.accepted, .symbol], 160),
            (2, .symbol, 163),
            (9, .symbol, 163),
            (23, .symbol, 163),
            (40, [.accepted, .symbol], 163),

        /* 128 */

            (3, .symbol, 154),
            (6, .symbol, 154),
            (10, .symbol, 154),
            (15, .symbol, 154),
            (24, .symbol, 154),
            (31, .symbol, 154),
            (41, .symbol, 154),
            (56, [.accepted, .symbol], 154),
            (3, .symbol, 156),
            (6, .symbol, 156),
            (10, .symbol, 156),
            (15, .symbol, 156),
            (24, .symbol, 156),
            (31, .symbol, 156),
            (41, .symbol, 156),
            (56, [.accepted, .symbol], 156),

        /* 129 */

            (3, .symbol, 160),
            (6, .symbol, 160),
            (10, .symbol, 160),
            (15, .symbol, 160),
            (24, .symbol, 160),
            (31, .symbol, 160),
            (41, .symbol, 160),
            (56, [.accepted, .symbol], 160),
            (3, .symbol, 163),
            (6, .symbol, 163),
            (10, .symbol, 163),
            (15, .symbol, 163),
            (24, .symbol, 163),
            (31, .symbol, 163),
            (41, .symbol, 163),
            (56, [.accepted, .symbol], 163),

        /* 130 */

            (2, .symbol, 164),
            (9, .symbol, 164),
            (23, .symbol, 164),
            (40, [.accepted, .symbol], 164),
            (2, .symbol, 169),
            (9, .symbol, 169),
            (23, .symbol, 169),
            (40, [.accepted, .symbol], 169),
            (2, .symbol, 170),
            (9, .symbol, 170),
            (23, .symbol, 170),
            (40, [.accepted, .symbol], 170),
            (2, .symbol, 173),
            (9, .symbol, 173),
            (23, .symbol, 173),
            (40, [.accepted, .symbol], 173),

        /* 131 */

            (3, .symbol, 164),
            (6, .symbol, 164),
            (10, .symbol, 164),
            (15, .symbol, 164),
            (24, .symbol, 164),
            (31, .symbol, 164),
            (41, .symbol, 164),
            (56, [.accepted, .symbol], 164),
            (3, .symbol, 169),
            (6, .symbol, 169),
            (10, .symbol, 169),
            (15, .symbol, 169),
            (24, .symbol, 169),
            (31, .symbol, 169),
            (41, .symbol, 169),
            (56, [.accepted, .symbol], 169),

        /* 132 */

            (3, .symbol, 170),
            (6, .symbol, 170),
            (10, .symbol, 170),
            (15, .symbol, 170),
            (24, .symbol, 170),
            (31, .symbol, 170),
            (41, .symbol, 170),
            (56, [.accepted, .symbol], 170),
            (3, .symbol, 173),
            (6, .symbol, 173),
            (10, .symbol, 173),
            (15, .symbol, 173),
            (24, .symbol, 173),
            (31, .symbol, 173),
            (41, .symbol, 173),
            (56, [.accepted, .symbol], 173),

        /* 133 */

            (137, .none, 0),
            (138, .none, 0),
            (140, .none, 0),
            (141, .none, 0),
            (144, .none, 0),
            (145, .none, 0),
            (147, .none, 0),
            (150, .none, 0),
            (156, .none, 0),
            (159, .none, 0),
            (163, .none, 0),
            (166, .none, 0),
            (171, .none, 0),
            (174, .none, 0),
            (181, .none, 0),
            (190, .none, 0),

        /* 134 */

            (0, [.accepted, .symbol], 178),
            (0, [.accepted, .symbol], 181),
            (0, [.accepted, .symbol], 185),
            (0, [.accepted, .symbol], 186),
            (0, [.accepted, .symbol], 187),
            (0, [.accepted, .symbol], 189),
            (0, [.accepted, .symbol], 190),
            (0, [.accepted, .symbol], 196),
            (0, [.accepted, .symbol], 198),
            (0, [.accepted, .symbol], 228),
            (0, [.accepted, .symbol], 232),
            (0, [.accepted, .symbol], 233),
            (148, .none, 0),
            (149, .none, 0),
            (151, .none, 0),
            (152, .none, 0),

        /* 135 */

            (1, .symbol, 178),
            (22, [.accepted, .symbol], 178),
            (1, .symbol, 181),
            (22, [.accepted, .symbol], 181),
            (1, .symbol, 185),
            (22, [.accepted, .symbol], 185),
            (1, .symbol, 186),
            (22, [.accepted, .symbol], 186),
            (1, .symbol, 187),
            (22, [.accepted, .symbol], 187),
            (1, .symbol, 189),
            (22, [.accepted, .symbol], 189),
            (1, .symbol, 190),
            (22, [.accepted, .symbol], 190),
            (1, .symbol, 196),
            (22, [.accepted, .symbol], 196),

        /* 136 */

            (2, .symbol, 178),
            (9, .symbol, 178),
            (23, .symbol, 178),
            (40, [.accepted, .symbol], 178),
            (2, .symbol, 181),
            (9, .symbol, 181),
            (23, .symbol, 181),
            (40, [.accepted, .symbol], 181),
            (2, .symbol, 185),
            (9, .symbol, 185),
            (23, .symbol, 185),
            (40, [.accepted, .symbol], 185),
            (2, .symbol, 186),
            (9, .symbol, 186),
            (23, .symbol, 186),
            (40, [.accepted, .symbol], 186),

        /* 137 */

            (3, .symbol, 178),
            (6, .symbol, 178),
            (10, .symbol, 178),
            (15, .symbol, 178),
            (24, .symbol, 178),
            (31, .symbol, 178),
            (41, .symbol, 178),
            (56, [.accepted, .symbol], 178),
            (3, .symbol, 181),
            (6, .symbol, 181),
            (10, .symbol, 181),
            (15, .symbol, 181),
            (24, .symbol, 181),
            (31, .symbol, 181),
            (41, .symbol, 181),
            (56, [.accepted, .symbol], 181),

        /* 138 */

            (3, .symbol, 185),
            (6, .symbol, 185),
            (10, .symbol, 185),
            (15, .symbol, 185),
            (24, .symbol, 185),
            (31, .symbol, 185),
            (41, .symbol, 185),
            (56, [.accepted, .symbol], 185),
            (3, .symbol, 186),
            (6, .symbol, 186),
            (10, .symbol, 186),
            (15, .symbol, 186),
            (24, .symbol, 186),
            (31, .symbol, 186),
            (41, .symbol, 186),
            (56, [.accepted, .symbol], 186),

        /* 139 */

            (2, .symbol, 187),
            (9, .symbol, 187),
            (23, .symbol, 187),
            (40, [.accepted, .symbol], 187),
            (2, .symbol, 189),
            (9, .symbol, 189),
            (23, .symbol, 189),
            (40, [.accepted, .symbol], 189),
            (2, .symbol, 190),
            (9, .symbol, 190),
            (23, .symbol, 190),
            (40, [.accepted, .symbol], 190),
            (2, .symbol, 196),
            (9, .symbol, 196),
            (23, .symbol, 196),
            (40, [.accepted, .symbol], 196),

        /* 140 */

            (3, .symbol, 187),
            (6, .symbol, 187),
            (10, .symbol, 187),
            (15, .symbol, 187),
            (24, .symbol, 187),
            (31, .symbol, 187),
            (41, .symbol, 187),
            (56, [.accepted, .symbol], 187),
            (3, .symbol, 189),
            (6, .symbol, 189),
            (10, .symbol, 189),
            (15, .symbol, 189),
            (24, .symbol, 189),
            (31, .symbol, 189),
            (41, .symbol, 189),
            (56, [.accepted, .symbol], 189),

        /* 141 */

            (3, .symbol, 190),
            (6, .symbol, 190),
            (10, .symbol, 190),
            (15, .symbol, 190),
            (24, .symbol, 190),
            (31, .symbol, 190),
            (41, .symbol, 190),
            (56, [.accepted, .symbol], 190),
            (3, .symbol, 196),
            (6, .symbol, 196),
            (10, .symbol, 196),
            (15, .symbol, 196),
            (24, .symbol, 196),
            (31, .symbol, 196),
            (41, .symbol, 196),
            (56, [.accepted, .symbol], 196),

        /* 142 */

            (1, .symbol, 198),
            (22, [.accepted, .symbol], 198),
            (1, .symbol, 228),
            (22, [.accepted, .symbol], 228),
            (1, .symbol, 232),
            (22, [.accepted, .symbol], 232),
            (1, .symbol, 233),
            (22, [.accepted, .symbol], 233),
            (0, [.accepted, .symbol], 1),
            (0, [.accepted, .symbol], 135),
            (0, [.accepted, .symbol], 137),
            (0, [.accepted, .symbol], 138),
            (0, [.accepted, .symbol], 139),
            (0, [.accepted, .symbol], 140),
            (0, [.accepted, .symbol], 141),
            (0, [.accepted, .symbol], 143),

        /* 143 */

            (2, .symbol, 198),
            (9, .symbol, 198),
            (23, .symbol, 198),
            (40, [.accepted, .symbol], 198),
            (2, .symbol, 228),
            (9, .symbol, 228),
            (23, .symbol, 228),
            (40, [.accepted, .symbol], 228),
            (2, .symbol, 232),
            (9, .symbol, 232),
            (23, .symbol, 232),
            (40, [.accepted, .symbol], 232),
            (2, .symbol, 233),
            (9, .symbol, 233),
            (23, .symbol, 233),
            (40, [.accepted, .symbol], 233),

        /* 144 */

            (3, .symbol, 198),
            (6, .symbol, 198),
            (10, .symbol, 198),
            (15, .symbol, 198),
            (24, .symbol, 198),
            (31, .symbol, 198),
            (41, .symbol, 198),
            (56, [.accepted, .symbol], 198),
            (3, .symbol, 228),
            (6, .symbol, 228),
            (10, .symbol, 228),
            (15, .symbol, 228),
            (24, .symbol, 228),
            (31, .symbol, 228),
            (41, .symbol, 228),
            (56, [.accepted, .symbol], 228),

        /* 145 */

            (3, .symbol, 232),
            (6, .symbol, 232),
            (10, .symbol, 232),
            (15, .symbol, 232),
            (24, .symbol, 232),
            (31, .symbol, 232),
            (41, .symbol, 232),
            (56, [.accepted, .symbol], 232),
            (3, .symbol, 233),
            (6, .symbol, 233),
            (10, .symbol, 233),
            (15, .symbol, 233),
            (24, .symbol, 233),
            (31, .symbol, 233),
            (41, .symbol, 233),
            (56, [.accepted, .symbol], 233),

        /* 146 */

            (1, .symbol, 1),
            (22, [.accepted, .symbol], 1),
            (1, .symbol, 135),
            (22, [.accepted, .symbol], 135),
            (1, .symbol, 137),
            (22, [.accepted, .symbol], 137),
            (1, .symbol, 138),
            (22, [.accepted, .symbol], 138),
            (1, .symbol, 139),
            (22, [.accepted, .symbol], 139),
            (1, .symbol, 140),
            (22, [.accepted, .symbol], 140),
            (1, .symbol, 141),
            (22, [.accepted, .symbol], 141),
            (1, .symbol, 143),
            (22, [.accepted, .symbol], 143),

        /* 147 */

            (2, .symbol, 1),
            (9, .symbol, 1),
            (23, .symbol, 1),
            (40, [.accepted, .symbol], 1),
            (2, .symbol, 135),
            (9, .symbol, 135),
            (23, .symbol, 135),
            (40, [.accepted, .symbol], 135),
            (2, .symbol, 137),
            (9, .symbol, 137),
            (23, .symbol, 137),
            (40, [.accepted, .symbol], 137),
            (2, .symbol, 138),
            (9, .symbol, 138),
            (23, .symbol, 138),
            (40, [.accepted, .symbol], 138),

        /* 148 */

            (3, .symbol, 1),
            (6, .symbol, 1),
            (10, .symbol, 1),
            (15, .symbol, 1),
            (24, .symbol, 1),
            (31, .symbol, 1),
            (41, .symbol, 1),
            (56, [.accepted, .symbol], 1),
            (3, .symbol, 135),
            (6, .symbol, 135),
            (10, .symbol, 135),
            (15, .symbol, 135),
            (24, .symbol, 135),
            (31, .symbol, 135),
            (41, .symbol, 135),
            (56, [.accepted, .symbol], 135),

        /* 149 */

            (3, .symbol, 137),
            (6, .symbol, 137),
            (10, .symbol, 137),
            (15, .symbol, 137),
            (24, .symbol, 137),
            (31, .symbol, 137),
            (41, .symbol, 137),
            (56, [.accepted, .symbol], 137),
            (3, .symbol, 138),
            (6, .symbol, 138),
            (10, .symbol, 138),
            (15, .symbol, 138),
            (24, .symbol, 138),
            (31, .symbol, 138),
            (41, .symbol, 138),
            (56, [.accepted, .symbol], 138),

        /* 150 */

            (2, .symbol, 139),
            (9, .symbol, 139),
            (23, .symbol, 139),
            (40, [.accepted, .symbol], 139),
            (2, .symbol, 140),
            (9, .symbol, 140),
            (23, .symbol, 140),
            (40, [.accepted, .symbol], 140),
            (2, .symbol, 141),
            (9, .symbol, 141),
            (23, .symbol, 141),
            (40, [.accepted, .symbol], 141),
            (2, .symbol, 143),
            (9, .symbol, 143),
            (23, .symbol, 143),
            (40, [.accepted, .symbol], 143),

        /* 151 */

            (3, .symbol, 139),
            (6, .symbol, 139),
            (10, .symbol, 139),
            (15, .symbol, 139),
            (24, .symbol, 139),
            (31, .symbol, 139),
            (41, .symbol, 139),
            (56, [.accepted, .symbol], 139),
            (3, .symbol, 140),
            (6, .symbol, 140),
            (10, .symbol, 140),
            (15, .symbol, 140),
            (24, .symbol, 140),
            (31, .symbol, 140),
            (41, .symbol, 140),
            (56, [.accepted, .symbol], 140),

        /* 152 */

            (3, .symbol, 141),
            (6, .symbol, 141),
            (10, .symbol, 141),
            (15, .symbol, 141),
            (24, .symbol, 141),
            (31, .symbol, 141),
            (41, .symbol, 141),
            (56, [.accepted, .symbol], 141),
            (3, .symbol, 143),
            (6, .symbol, 143),
            (10, .symbol, 143),
            (15, .symbol, 143),
            (24, .symbol, 143),
            (31, .symbol, 143),
            (41, .symbol, 143),
            (56, [.accepted, .symbol], 143),

        /* 153 */

            (157, .none, 0),
            (158, .none, 0),
            (160, .none, 0),
            (161, .none, 0),
            (164, .none, 0),
            (165, .none, 0),
            (167, .none, 0),
            (168, .none, 0),
            (172, .none, 0),
            (173, .none, 0),
            (175, .none, 0),
            (177, .none, 0),
            (182, .none, 0),
            (185, .none, 0),
            (191, .none, 0),
            (207, .none, 0),

        /* 154 */

            (0, [.accepted, .symbol], 147),
            (0, [.accepted, .symbol], 149),
            (0, [.accepted, .symbol], 150),
            (0, [.accepted, .symbol], 151),
            (0, [.accepted, .symbol], 152),
            (0, [.accepted, .symbol], 155),
            (0, [.accepted, .symbol], 157),
            (0, [.accepted, .symbol], 158),
            (0, [.accepted, .symbol], 165),
            (0, [.accepted, .symbol], 166),
            (0, [.accepted, .symbol], 168),
            (0, [.accepted, .symbol], 174),
            (0, [.accepted, .symbol], 175),
            (0, [.accepted, .symbol], 180),
            (0, [.accepted, .symbol], 182),
            (0, [.accepted, .symbol], 183),

        /* 155 */

            (1, .symbol, 147),
            (22, [.accepted, .symbol], 147),
            (1, .symbol, 149),
            (22, [.accepted, .symbol], 149),
            (1, .symbol, 150),
            (22, [.accepted, .symbol], 150),
            (1, .symbol, 151),
            (22, [.accepted, .symbol], 151),
            (1, .symbol, 152),
            (22, [.accepted, .symbol], 152),
            (1, .symbol, 155),
            (22, [.accepted, .symbol], 155),
            (1, .symbol, 157),
            (22, [.accepted, .symbol], 157),
            (1, .symbol, 158),
            (22, [.accepted, .symbol], 158),

        /* 156 */

            (2, .symbol, 147),
            (9, .symbol, 147),
            (23, .symbol, 147),
            (40, [.accepted, .symbol], 147),
            (2, .symbol, 149),
            (9, .symbol, 149),
            (23, .symbol, 149),
            (40, [.accepted, .symbol], 149),
            (2, .symbol, 150),
            (9, .symbol, 150),
            (23, .symbol, 150),
            (40, [.accepted, .symbol], 150),
            (2, .symbol, 151),
            (9, .symbol, 151),
            (23, .symbol, 151),
            (40, [.accepted, .symbol], 151),

        /* 157 */

            (3, .symbol, 147),
            (6, .symbol, 147),
            (10, .symbol, 147),
            (15, .symbol, 147),
            (24, .symbol, 147),
            (31, .symbol, 147),
            (41, .symbol, 147),
            (56, [.accepted, .symbol], 147),
            (3, .symbol, 149),
            (6, .symbol, 149),
            (10, .symbol, 149),
            (15, .symbol, 149),
            (24, .symbol, 149),
            (31, .symbol, 149),
            (41, .symbol, 149),
            (56, [.accepted, .symbol], 149),

        /* 158 */

            (3, .symbol, 150),
            (6, .symbol, 150),
            (10, .symbol, 150),
            (15, .symbol, 150),
            (24, .symbol, 150),
            (31, .symbol, 150),
            (41, .symbol, 150),
            (56, [.accepted, .symbol], 150),
            (3, .symbol, 151),
            (6, .symbol, 151),
            (10, .symbol, 151),
            (15, .symbol, 151),
            (24, .symbol, 151),
            (31, .symbol, 151),
            (41, .symbol, 151),
            (56, [.accepted, .symbol], 151),

        /* 159 */

            (2, .symbol, 152),
            (9, .symbol, 152),
            (23, .symbol, 152),
            (40, [.accepted, .symbol], 152),
            (2, .symbol, 155),
            (9, .symbol, 155),
            (23, .symbol, 155),
            (40, [.accepted, .symbol], 155),
            (2, .symbol, 157),
            (9, .symbol, 157),
            (23, .symbol, 157),
            (40, [.accepted, .symbol], 157),
            (2, .symbol, 158),
            (9, .symbol, 158),
            (23, .symbol, 158),
            (40, [.accepted, .symbol], 158),

        /* 160 */

            (3, .symbol, 152),
            (6, .symbol, 152),
            (10, .symbol, 152),
            (15, .symbol, 152),
            (24, .symbol, 152),
            (31, .symbol, 152),
            (41, .symbol, 152),
            (56, [.accepted, .symbol], 152),
            (3, .symbol, 155),
            (6, .symbol, 155),
            (10, .symbol, 155),
            (15, .symbol, 155),
            (24, .symbol, 155),
            (31, .symbol, 155),
            (41, .symbol, 155),
            (56, [.accepted, .symbol], 155),

        /* 161 */

            (3, .symbol, 157),
            (6, .symbol, 157),
            (10, .symbol, 157),
            (15, .symbol, 157),
            (24, .symbol, 157),
            (31, .symbol, 157),
            (41, .symbol, 157),
            (56, [.accepted, .symbol], 157),
            (3, .symbol, 158),
            (6, .symbol, 158),
            (10, .symbol, 158),
            (15, .symbol, 158),
            (24, .symbol, 158),
            (31, .symbol, 158),
            (41, .symbol, 158),
            (56, [.accepted, .symbol], 158),

        /* 162 */

            (1, .symbol, 165),
            (22, [.accepted, .symbol], 165),
            (1, .symbol, 166),
            (22, [.accepted, .symbol], 166),
            (1, .symbol, 168),
            (22, [.accepted, .symbol], 168),
            (1, .symbol, 174),
            (22, [.accepted, .symbol], 174),
            (1, .symbol, 175),
            (22, [.accepted, .symbol], 175),
            (1, .symbol, 180),
            (22, [.accepted, .symbol], 180),
            (1, .symbol, 182),
            (22, [.accepted, .symbol], 182),
            (1, .symbol, 183),
            (22, [.accepted, .symbol], 183),

        /* 163 */

            (2, .symbol, 165),
            (9, .symbol, 165),
            (23, .symbol, 165),
            (40, [.accepted, .symbol], 165),
            (2, .symbol, 166),
            (9, .symbol, 166),
            (23, .symbol, 166),
            (40, [.accepted, .symbol], 166),
            (2, .symbol, 168),
            (9, .symbol, 168),
            (23, .symbol, 168),
            (40, [.accepted, .symbol], 168),
            (2, .symbol, 174),
            (9, .symbol, 174),
            (23, .symbol, 174),
            (40, [.accepted, .symbol], 174),

        /* 164 */

            (3, .symbol, 165),
            (6, .symbol, 165),
            (10, .symbol, 165),
            (15, .symbol, 165),
            (24, .symbol, 165),
            (31, .symbol, 165),
            (41, .symbol, 165),
            (56, [.accepted, .symbol], 165),
            (3, .symbol, 166),
            (6, .symbol, 166),
            (10, .symbol, 166),
            (15, .symbol, 166),
            (24, .symbol, 166),
            (31, .symbol, 166),
            (41, .symbol, 166),
            (56, [.accepted, .symbol], 166),

        /* 165 */

            (3, .symbol, 168),
            (6, .symbol, 168),
            (10, .symbol, 168),
            (15, .symbol, 168),
            (24, .symbol, 168),
            (31, .symbol, 168),
            (41, .symbol, 168),
            (56, [.accepted, .symbol], 168),
            (3, .symbol, 174),
            (6, .symbol, 174),
            (10, .symbol, 174),
            (15, .symbol, 174),
            (24, .symbol, 174),
            (31, .symbol, 174),
            (41, .symbol, 174),
            (56, [.accepted, .symbol], 174),

        /* 166 */

            (2, .symbol, 175),
            (9, .symbol, 175),
            (23, .symbol, 175),
            (40, [.accepted, .symbol], 175),
            (2, .symbol, 180),
            (9, .symbol, 180),
            (23, .symbol, 180),
            (40, [.accepted, .symbol], 180),
            (2, .symbol, 182),
            (9, .symbol, 182),
            (23, .symbol, 182),
            (40, [.accepted, .symbol], 182),
            (2, .symbol, 183),
            (9, .symbol, 183),
            (23, .symbol, 183),
            (40, [.accepted, .symbol], 183),

        /* 167 */

            (3, .symbol, 175),
            (6, .symbol, 175),
            (10, .symbol, 175),
            (15, .symbol, 175),
            (24, .symbol, 175),
            (31, .symbol, 175),
            (41, .symbol, 175),
            (56, [.accepted, .symbol], 175),
            (3, .symbol, 180),
            (6, .symbol, 180),
            (10, .symbol, 180),
            (15, .symbol, 180),
            (24, .symbol, 180),
            (31, .symbol, 180),
            (41, .symbol, 180),
            (56, [.accepted, .symbol], 180),

        /* 168 */

            (3, .symbol, 182),
            (6, .symbol, 182),
            (10, .symbol, 182),
            (15, .symbol, 182),
            (24, .symbol, 182),
            (31, .symbol, 182),
            (41, .symbol, 182),
            (56, [.accepted, .symbol], 182),
            (3, .symbol, 183),
            (6, .symbol, 183),
            (10, .symbol, 183),
            (15, .symbol, 183),
            (24, .symbol, 183),
            (31, .symbol, 183),
            (41, .symbol, 183),
            (56, [.accepted, .symbol], 183),

        /* 169 */

            (0, [.accepted, .symbol], 188),
            (0, [.accepted, .symbol], 191),
            (0, [.accepted, .symbol], 197),
            (0, [.accepted, .symbol], 231),
            (0, [.accepted, .symbol], 239),
            (176, .none, 0),
            (178, .none, 0),
            (179, .none, 0),
            (183, .none, 0),
            (184, .none, 0),
            (186, .none, 0),
            (187, .none, 0),
            (192, .none, 0),
            (199, .none, 0),
            (208, .none, 0),
            (223, .none, 0),

        /* 170 */

            (1, .symbol, 188),
            (22, [.accepted, .symbol], 188),
            (1, .symbol, 191),
            (22, [.accepted, .symbol], 191),
            (1, .symbol, 197),
            (22, [.accepted, .symbol], 197),
            (1, .symbol, 231),
            (22, [.accepted, .symbol], 231),
            (1, .symbol, 239),
            (22, [.accepted, .symbol], 239),
            (0, [.accepted, .symbol], 9),
            (0, [.accepted, .symbol], 142),
            (0, [.accepted, .symbol], 144),
            (0, [.accepted, .symbol], 145),
            (0, [.accepted, .symbol], 148),
            (0, [.accepted, .symbol], 159),

        /* 171 */

            (2, .symbol, 188),
            (9, .symbol, 188),
            (23, .symbol, 188),
            (40, [.accepted, .symbol], 188),
            (2, .symbol, 191),
            (9, .symbol, 191),
            (23, .symbol, 191),
            (40, [.accepted, .symbol], 191),
            (2, .symbol, 197),
            (9, .symbol, 197),
            (23, .symbol, 197),
            (40, [.accepted, .symbol], 197),
            (2, .symbol, 231),
            (9, .symbol, 231),
            (23, .symbol, 231),
            (40, [.accepted, .symbol], 231),

        /* 172 */

            (3, .symbol, 188),
            (6, .symbol, 188),
            (10, .symbol, 188),
            (15, .symbol, 188),
            (24, .symbol, 188),
            (31, .symbol, 188),
            (41, .symbol, 188),
            (56, [.accepted, .symbol], 188),
            (3, .symbol, 191),
            (6, .symbol, 191),
            (10, .symbol, 191),
            (15, .symbol, 191),
            (24, .symbol, 191),
            (31, .symbol, 191),
            (41, .symbol, 191),
            (56, [.accepted, .symbol], 191),

        /* 173 */

            (3, .symbol, 197),
            (6, .symbol, 197),
            (10, .symbol, 197),
            (15, .symbol, 197),
            (24, .symbol, 197),
            (31, .symbol, 197),
            (41, .symbol, 197),
            (56, [.accepted, .symbol], 197),
            (3, .symbol, 231),
            (6, .symbol, 231),
            (10, .symbol, 231),
            (15, .symbol, 231),
            (24, .symbol, 231),
            (31, .symbol, 231),
            (41, .symbol, 231),
            (56, [.accepted, .symbol], 231),

        /* 174 */

            (2, .symbol, 239),
            (9, .symbol, 239),
            (23, .symbol, 239),
            (40, [.accepted, .symbol], 239),
            (1, .symbol, 9),
            (22, [.accepted, .symbol], 9),
            (1, .symbol, 142),
            (22, [.accepted, .symbol], 142),
            (1, .symbol, 144),
            (22, [.accepted, .symbol], 144),
            (1, .symbol, 145),
            (22, [.accepted, .symbol], 145),
            (1, .symbol, 148),
            (22, [.accepted, .symbol], 148),
            (1, .symbol, 159),
            (22, [.accepted, .symbol], 159),

        /* 175 */

            (3, .symbol, 239),
            (6, .symbol, 239),
            (10, .symbol, 239),
            (15, .symbol, 239),
            (24, .symbol, 239),
            (31, .symbol, 239),
            (41, .symbol, 239),
            (56, [.accepted, .symbol], 239),
            (2, .symbol, 9),
            (9, .symbol, 9),
            (23, .symbol, 9),
            (40, [.accepted, .symbol], 9),
            (2, .symbol, 142),
            (9, .symbol, 142),
            (23, .symbol, 142),
            (40, [.accepted, .symbol], 142),

        /* 176 */

            (3, .symbol, 9),
            (6, .symbol, 9),
            (10, .symbol, 9),
            (15, .symbol, 9),
            (24, .symbol, 9),
            (31, .symbol, 9),
            (41, .symbol, 9),
            (56, [.accepted, .symbol], 9),
            (3, .symbol, 142),
            (6, .symbol, 142),
            (10, .symbol, 142),
            (15, .symbol, 142),
            (24, .symbol, 142),
            (31, .symbol, 142),
            (41, .symbol, 142),
            (56, [.accepted, .symbol], 142),

        /* 177 */

            (2, .symbol, 144),
            (9, .symbol, 144),
            (23, .symbol, 144),
            (40, [.accepted, .symbol], 144),
            (2, .symbol, 145),
            (9, .symbol, 145),
            (23, .symbol, 145),
            (40, [.accepted, .symbol], 145),
            (2, .symbol, 148),
            (9, .symbol, 148),
            (23, .symbol, 148),
            (40, [.accepted, .symbol], 148),
            (2, .symbol, 159),
            (9, .symbol, 159),
            (23, .symbol, 159),
            (40, [.accepted, .symbol], 159),

        /* 178 */

            (3, .symbol, 144),
            (6, .symbol, 144),
            (10, .symbol, 144),
            (15, .symbol, 144),
            (24, .symbol, 144),
            (31, .symbol, 144),
            (41, .symbol, 144),
            (56, [.accepted, .symbol], 144),
            (3, .symbol, 145),
            (6, .symbol, 145),
            (10, .symbol, 145),
            (15, .symbol, 145),
            (24, .symbol, 145),
            (31, .symbol, 145),
            (41, .symbol, 145),
            (56, [.accepted, .symbol], 145),

        /* 179 */

            (3, .symbol, 148),
            (6, .symbol, 148),
            (10, .symbol, 148),
            (15, .symbol, 148),
            (24, .symbol, 148),
            (31, .symbol, 148),
            (41, .symbol, 148),
            (56, [.accepted, .symbol], 148),
            (3, .symbol, 159),
            (6, .symbol, 159),
            (10, .symbol, 159),
            (15, .symbol, 159),
            (24, .symbol, 159),
            (31, .symbol, 159),
            (41, .symbol, 159),
            (56, [.accepted, .symbol], 159),

        /* 180 */

            (0, [.accepted, .symbol], 171),
            (0, [.accepted, .symbol], 206),
            (0, [.accepted, .symbol], 215),
            (0, [.accepted, .symbol], 225),
            (0, [.accepted, .symbol], 236),
            (0, [.accepted, .symbol], 237),
            (188, .none, 0),
            (189, .none, 0),
            (193, .none, 0),
            (196, .none, 0),
            (200, .none, 0),
            (203, .none, 0),
            (209, .none, 0),
            (216, .none, 0),
            (224, .none, 0),
            (238, .none, 0),

        /* 181 */

            (1, .symbol, 171),
            (22, [.accepted, .symbol], 171),
            (1, .symbol, 206),
            (22, [.accepted, .symbol], 206),
            (1, .symbol, 215),
            (22, [.accepted, .symbol], 215),
            (1, .symbol, 225),
            (22, [.accepted, .symbol], 225),
            (1, .symbol, 236),
            (22, [.accepted, .symbol], 236),
            (1, .symbol, 237),
            (22, [.accepted, .symbol], 237),
            (0, [.accepted, .symbol], 199),
            (0, [.accepted, .symbol], 207),
            (0, [.accepted, .symbol], 234),
            (0, [.accepted, .symbol], 235),

        /* 182 */

            (2, .symbol, 171),
            (9, .symbol, 171),
            (23, .symbol, 171),
            (40, [.accepted, .symbol], 171),
            (2, .symbol, 206),
            (9, .symbol, 206),
            (23, .symbol, 206),
            (40, [.accepted, .symbol], 206),
            (2, .symbol, 215),
            (9, .symbol, 215),
            (23, .symbol, 215),
            (40, [.accepted, .symbol], 215),
            (2, .symbol, 225),
            (9, .symbol, 225),
            (23, .symbol, 225),
            (40, [.accepted, .symbol], 225),

        /* 183 */

            (3, .symbol, 171),
            (6, .symbol, 171),
            (10, .symbol, 171),
            (15, .symbol, 171),
            (24, .symbol, 171),
            (31, .symbol, 171),
            (41, .symbol, 171),
            (56, [.accepted, .symbol], 171),
            (3, .symbol, 206),
            (6, .symbol, 206),
            (10, .symbol, 206),
            (15, .symbol, 206),
            (24, .symbol, 206),
            (31, .symbol, 206),
            (41, .symbol, 206),
            (56, [.accepted, .symbol], 206),

        /* 184 */

            (3, .symbol, 215),
            (6, .symbol, 215),
            (10, .symbol, 215),
            (15, .symbol, 215),
            (24, .symbol, 215),
            (31, .symbol, 215),
            (41, .symbol, 215),
            (56, [.accepted, .symbol], 215),
            (3, .symbol, 225),
            (6, .symbol, 225),
            (10, .symbol, 225),
            (15, .symbol, 225),
            (24, .symbol, 225),
            (31, .symbol, 225),
            (41, .symbol, 225),
            (56, [.accepted, .symbol], 225),

        /* 185 */

            (2, .symbol, 236),
            (9, .symbol, 236),
            (23, .symbol, 236),
            (40, [.accepted, .symbol], 236),
            (2, .symbol, 237),
            (9, .symbol, 237),
            (23, .symbol, 237),
            (40, [.accepted, .symbol], 237),
            (1, .symbol, 199),
            (22, [.accepted, .symbol], 199),
            (1, .symbol, 207),
            (22, [.accepted, .symbol], 207),
            (1, .symbol, 234),
            (22, [.accepted, .symbol], 234),
            (1, .symbol, 235),
            (22, [.accepted, .symbol], 235),

        /* 186 */

            (3, .symbol, 236),
            (6, .symbol, 236),
            (10, .symbol, 236),
            (15, .symbol, 236),
            (24, .symbol, 236),
            (31, .symbol, 236),
            (41, .symbol, 236),
            (56, [.accepted, .symbol], 236),
            (3, .symbol, 237),
            (6, .symbol, 237),
            (10, .symbol, 237),
            (15, .symbol, 237),
            (24, .symbol, 237),
            (31, .symbol, 237),
            (41, .symbol, 237),
            (56, [.accepted, .symbol], 237),

        /* 187 */

            (2, .symbol, 199),
            (9, .symbol, 199),
            (23, .symbol, 199),
            (40, [.accepted, .symbol], 199),
            (2, .symbol, 207),
            (9, .symbol, 207),
            (23, .symbol, 207),
            (40, [.accepted, .symbol], 207),
            (2, .symbol, 234),
            (9, .symbol, 234),
            (23, .symbol, 234),
            (40, [.accepted, .symbol], 234),
            (2, .symbol, 235),
            (9, .symbol, 235),
            (23, .symbol, 235),
            (40, [.accepted, .symbol], 235),

        /* 188 */

            (3, .symbol, 199),
            (6, .symbol, 199),
            (10, .symbol, 199),
            (15, .symbol, 199),
            (24, .symbol, 199),
            (31, .symbol, 199),
            (41, .symbol, 199),
            (56, [.accepted, .symbol], 199),
            (3, .symbol, 207),
            (6, .symbol, 207),
            (10, .symbol, 207),
            (15, .symbol, 207),
            (24, .symbol, 207),
            (31, .symbol, 207),
            (41, .symbol, 207),
            (56, [.accepted, .symbol], 207),

        /* 189 */

            (3, .symbol, 234),
            (6, .symbol, 234),
            (10, .symbol, 234),
            (15, .symbol, 234),
            (24, .symbol, 234),
            (31, .symbol, 234),
            (41, .symbol, 234),
            (56, [.accepted, .symbol], 234),
            (3, .symbol, 235),
            (6, .symbol, 235),
            (10, .symbol, 235),
            (15, .symbol, 235),
            (24, .symbol, 235),
            (31, .symbol, 235),
            (41, .symbol, 235),
            (56, [.accepted, .symbol], 235),

        /* 190 */

            (194, .none, 0),
            (195, .none, 0),
            (197, .none, 0),
            (198, .none, 0),
            (201, .none, 0),
            (202, .none, 0),
            (204, .none, 0),
            (205, .none, 0),
            (210, .none, 0),
            (213, .none, 0),
            (217, .none, 0),
            (220, .none, 0),
            (225, .none, 0),
            (231, .none, 0),
            (239, .none, 0),
            (246, .none, 0),

        /* 191 */

            (0, [.accepted, .symbol], 192),
            (0, [.accepted, .symbol], 193),
            (0, [.accepted, .symbol], 200),
            (0, [.accepted, .symbol], 201),
            (0, [.accepted, .symbol], 202),
            (0, [.accepted, .symbol], 205),
            (0, [.accepted, .symbol], 210),
            (0, [.accepted, .symbol], 213),
            (0, [.accepted, .symbol], 218),
            (0, [.accepted, .symbol], 219),
            (0, [.accepted, .symbol], 238),
            (0, [.accepted, .symbol], 240),
            (0, [.accepted, .symbol], 242),
            (0, [.accepted, .symbol], 243),
            (0, [.accepted, .symbol], 255),
            (206, .none, 0),

        /* 192 */

            (1, .symbol, 192),
            (22, [.accepted, .symbol], 192),
            (1, .symbol, 193),
            (22, [.accepted, .symbol], 193),
            (1, .symbol, 200),
            (22, [.accepted, .symbol], 200),
            (1, .symbol, 201),
            (22, [.accepted, .symbol], 201),
            (1, .symbol, 202),
            (22, [.accepted, .symbol], 202),
            (1, .symbol, 205),
            (22, [.accepted, .symbol], 205),
            (1, .symbol, 210),
            (22, [.accepted, .symbol], 210),
            (1, .symbol, 213),
            (22, [.accepted, .symbol], 213),

        /* 193 */

            (2, .symbol, 192),
            (9, .symbol, 192),
            (23, .symbol, 192),
            (40, [.accepted, .symbol], 192),
            (2, .symbol, 193),
            (9, .symbol, 193),
            (23, .symbol, 193),
            (40, [.accepted, .symbol], 193),
            (2, .symbol, 200),
            (9, .symbol, 200),
            (23, .symbol, 200),
            (40, [.accepted, .symbol], 200),
            (2, .symbol, 201),
            (9, .symbol, 201),
            (23, .symbol, 201),
            (40, [.accepted, .symbol], 201),

        /* 194 */

            (3, .symbol, 192),
            (6, .symbol, 192),
            (10, .symbol, 192),
            (15, .symbol, 192),
            (24, .symbol, 192),
            (31, .symbol, 192),
            (41, .symbol, 192),
            (56, [.accepted, .symbol], 192),
            (3, .symbol, 193),
            (6, .symbol, 193),
            (10, .symbol, 193),
            (15, .symbol, 193),
            (24, .symbol, 193),
            (31, .symbol, 193),
            (41, .symbol, 193),
            (56, [.accepted, .symbol], 193),

        /* 195 */

            (3, .symbol, 200),
            (6, .symbol, 200),
            (10, .symbol, 200),
            (15, .symbol, 200),
            (24, .symbol, 200),
            (31, .symbol, 200),
            (41, .symbol, 200),
            (56, [.accepted, .symbol], 200),
            (3, .symbol, 201),
            (6, .symbol, 201),
            (10, .symbol, 201),
            (15, .symbol, 201),
            (24, .symbol, 201),
            (31, .symbol, 201),
            (41, .symbol, 201),
            (56, [.accepted, .symbol], 201),

        /* 196 */

            (2, .symbol, 202),
            (9, .symbol, 202),
            (23, .symbol, 202),
            (40, [.accepted, .symbol], 202),
            (2, .symbol, 205),
            (9, .symbol, 205),
            (23, .symbol, 205),
            (40, [.accepted, .symbol], 205),
            (2, .symbol, 210),
            (9, .symbol, 210),
            (23, .symbol, 210),
            (40, [.accepted, .symbol], 210),
            (2, .symbol, 213),
            (9, .symbol, 213),
            (23, .symbol, 213),
            (40, [.accepted, .symbol], 213),

        /* 197 */

            (3, .symbol, 202),
            (6, .symbol, 202),
            (10, .symbol, 202),
            (15, .symbol, 202),
            (24, .symbol, 202),
            (31, .symbol, 202),
            (41, .symbol, 202),
            (56, [.accepted, .symbol], 202),
            (3, .symbol, 205),
            (6, .symbol, 205),
            (10, .symbol, 205),
            (15, .symbol, 205),
            (24, .symbol, 205),
            (31, .symbol, 205),
            (41, .symbol, 205),
            (56, [.accepted, .symbol], 205),

        /* 198 */

            (3, .symbol, 210),
            (6, .symbol, 210),
            (10, .symbol, 210),
            (15, .symbol, 210),
            (24, .symbol, 210),
            (31, .symbol, 210),
            (41, .symbol, 210),
            (56, [.accepted, .symbol], 210),
            (3, .symbol, 213),
            (6, .symbol, 213),
            (10, .symbol, 213),
            (15, .symbol, 213),
            (24, .symbol, 213),
            (31, .symbol, 213),
            (41, .symbol, 213),
            (56, [.accepted, .symbol], 213),

        /* 199 */

            (1, .symbol, 218),
            (22, [.accepted, .symbol], 218),
            (1, .symbol, 219),
            (22, [.accepted, .symbol], 219),
            (1, .symbol, 238),
            (22, [.accepted, .symbol], 238),
            (1, .symbol, 240),
            (22, [.accepted, .symbol], 240),
            (1, .symbol, 242),
            (22, [.accepted, .symbol], 242),
            (1, .symbol, 243),
            (22, [.accepted, .symbol], 243),
            (1, .symbol, 255),
            (22, [.accepted, .symbol], 255),
            (0, [.accepted, .symbol], 203),
            (0, [.accepted, .symbol], 204),

        /* 200 */

            (2, .symbol, 218),
            (9, .symbol, 218),
            (23, .symbol, 218),
            (40, [.accepted, .symbol], 218),
            (2, .symbol, 219),
            (9, .symbol, 219),
            (23, .symbol, 219),
            (40, [.accepted, .symbol], 219),
            (2, .symbol, 238),
            (9, .symbol, 238),
            (23, .symbol, 238),
            (40, [.accepted, .symbol], 238),
            (2, .symbol, 240),
            (9, .symbol, 240),
            (23, .symbol, 240),
            (40, [.accepted, .symbol], 240),

        /* 201 */

            (3, .symbol, 218),
            (6, .symbol, 218),
            (10, .symbol, 218),
            (15, .symbol, 218),
            (24, .symbol, 218),
            (31, .symbol, 218),
            (41, .symbol, 218),
            (56, [.accepted, .symbol], 218),
            (3, .symbol, 219),
            (6, .symbol, 219),
            (10, .symbol, 219),
            (15, .symbol, 219),
            (24, .symbol, 219),
            (31, .symbol, 219),
            (41, .symbol, 219),
            (56, [.accepted, .symbol], 219),

        /* 202 */

            (3, .symbol, 238),
            (6, .symbol, 238),
            (10, .symbol, 238),
            (15, .symbol, 238),
            (24, .symbol, 238),
            (31, .symbol, 238),
            (41, .symbol, 238),
            (56, [.accepted, .symbol], 238),
            (3, .symbol, 240),
            (6, .symbol, 240),
            (10, .symbol, 240),
            (15, .symbol, 240),
            (24, .symbol, 240),
            (31, .symbol, 240),
            (41, .symbol, 240),
            (56, [.accepted, .symbol], 240),

        /* 203 */

            (2, .symbol, 242),
            (9, .symbol, 242),
            (23, .symbol, 242),
            (40, [.accepted, .symbol], 242),
            (2, .symbol, 243),
            (9, .symbol, 243),
            (23, .symbol, 243),
            (40, [.accepted, .symbol], 243),
            (2, .symbol, 255),
            (9, .symbol, 255),
            (23, .symbol, 255),
            (40, [.accepted, .symbol], 255),
            (1, .symbol, 203),
            (22, [.accepted, .symbol], 203),
            (1, .symbol, 204),
            (22, [.accepted, .symbol], 204),

        /* 204 */

            (3, .symbol, 242),
            (6, .symbol, 242),
            (10, .symbol, 242),
            (15, .symbol, 242),
            (24, .symbol, 242),
            (31, .symbol, 242),
            (41, .symbol, 242),
            (56, [.accepted, .symbol], 242),
            (3, .symbol, 243),
            (6, .symbol, 243),
            (10, .symbol, 243),
            (15, .symbol, 243),
            (24, .symbol, 243),
            (31, .symbol, 243),
            (41, .symbol, 243),
            (56, [.accepted, .symbol], 243),

        /* 205 */

            (3, .symbol, 255),
            (6, .symbol, 255),
            (10, .symbol, 255),
            (15, .symbol, 255),
            (24, .symbol, 255),
            (31, .symbol, 255),
            (41, .symbol, 255),
            (56, [.accepted, .symbol], 255),
            (2, .symbol, 203),
            (9, .symbol, 203),
            (23, .symbol, 203),
            (40, [.accepted, .symbol], 203),
            (2, .symbol, 204),
            (9, .symbol, 204),
            (23, .symbol, 204),
            (40, [.accepted, .symbol], 204),

        /* 206 */

            (3, .symbol, 203),
            (6, .symbol, 203),
            (10, .symbol, 203),
            (15, .symbol, 203),
            (24, .symbol, 203),
            (31, .symbol, 203),
            (41, .symbol, 203),
            (56, [.accepted, .symbol], 203),
            (3, .symbol, 204),
            (6, .symbol, 204),
            (10, .symbol, 204),
            (15, .symbol, 204),
            (24, .symbol, 204),
            (31, .symbol, 204),
            (41, .symbol, 204),
            (56, [.accepted, .symbol], 204),

        /* 207 */

            (211, .none, 0),
            (212, .none, 0),
            (214, .none, 0),
            (215, .none, 0),
            (218, .none, 0),
            (219, .none, 0),
            (221, .none, 0),
            (222, .none, 0),
            (226, .none, 0),
            (228, .none, 0),
            (232, .none, 0),
            (235, .none, 0),
            (240, .none, 0),
            (243, .none, 0),
            (247, .none, 0),
            (250, .none, 0),

        /* 208 */

            (0, [.accepted, .symbol], 211),
            (0, [.accepted, .symbol], 212),
            (0, [.accepted, .symbol], 214),
            (0, [.accepted, .symbol], 221),
            (0, [.accepted, .symbol], 222),
            (0, [.accepted, .symbol], 223),
            (0, [.accepted, .symbol], 241),
            (0, [.accepted, .symbol], 244),
            (0, [.accepted, .symbol], 245),
            (0, [.accepted, .symbol], 246),
            (0, [.accepted, .symbol], 247),
            (0, [.accepted, .symbol], 248),
            (0, [.accepted, .symbol], 250),
            (0, [.accepted, .symbol], 251),
            (0, [.accepted, .symbol], 252),
            (0, [.accepted, .symbol], 253),

        /* 209 */

            (1, .symbol, 211),
            (22, [.accepted, .symbol], 211),
            (1, .symbol, 212),
            (22, [.accepted, .symbol], 212),
            (1, .symbol, 214),
            (22, [.accepted, .symbol], 214),
            (1, .symbol, 221),
            (22, [.accepted, .symbol], 221),
            (1, .symbol, 222),
            (22, [.accepted, .symbol], 222),
            (1, .symbol, 223),
            (22, [.accepted, .symbol], 223),
            (1, .symbol, 241),
            (22, [.accepted, .symbol], 241),
            (1, .symbol, 244),
            (22, [.accepted, .symbol], 244),

        /* 210 */

            (2, .symbol, 211),
            (9, .symbol, 211),
            (23, .symbol, 211),
            (40, [.accepted, .symbol], 211),
            (2, .symbol, 212),
            (9, .symbol, 212),
            (23, .symbol, 212),
            (40, [.accepted, .symbol], 212),
            (2, .symbol, 214),
            (9, .symbol, 214),
            (23, .symbol, 214),
            (40, [.accepted, .symbol], 214),
            (2, .symbol, 221),
            (9, .symbol, 221),
            (23, .symbol, 221),
            (40, [.accepted, .symbol], 221),

        /* 211 */

            (3, .symbol, 211),
            (6, .symbol, 211),
            (10, .symbol, 211),
            (15, .symbol, 211),
            (24, .symbol, 211),
            (31, .symbol, 211),
            (41, .symbol, 211),
            (56, [.accepted, .symbol], 211),
            (3, .symbol, 212),
            (6, .symbol, 212),
            (10, .symbol, 212),
            (15, .symbol, 212),
            (24, .symbol, 212),
            (31, .symbol, 212),
            (41, .symbol, 212),
            (56, [.accepted, .symbol], 212),

        /* 212 */

            (3, .symbol, 214),
            (6, .symbol, 214),
            (10, .symbol, 214),
            (15, .symbol, 214),
            (24, .symbol, 214),
            (31, .symbol, 214),
            (41, .symbol, 214),
            (56, [.accepted, .symbol], 214),
            (3, .symbol, 221),
            (6, .symbol, 221),
            (10, .symbol, 221),
            (15, .symbol, 221),
            (24, .symbol, 221),
            (31, .symbol, 221),
            (41, .symbol, 221),
            (56, [.accepted, .symbol], 221),

        /* 213 */

            (2, .symbol, 222),
            (9, .symbol, 222),
            (23, .symbol, 222),
            (40, [.accepted, .symbol], 222),
            (2, .symbol, 223),
            (9, .symbol, 223),
            (23, .symbol, 223),
            (40, [.accepted, .symbol], 223),
            (2, .symbol, 241),
            (9, .symbol, 241),
            (23, .symbol, 241),
            (40, [.accepted, .symbol], 241),
            (2, .symbol, 244),
            (9, .symbol, 244),
            (23, .symbol, 244),
            (40, [.accepted, .symbol], 244),

        /* 214 */

            (3, .symbol, 222),
            (6, .symbol, 222),
            (10, .symbol, 222),
            (15, .symbol, 222),
            (24, .symbol, 222),
            (31, .symbol, 222),
            (41, .symbol, 222),
            (56, [.accepted, .symbol], 222),
            (3, .symbol, 223),
            (6, .symbol, 223),
            (10, .symbol, 223),
            (15, .symbol, 223),
            (24, .symbol, 223),
            (31, .symbol, 223),
            (41, .symbol, 223),
            (56, [.accepted, .symbol], 223),

        /* 215 */

            (3, .symbol, 241),
            (6, .symbol, 241),
            (10, .symbol, 241),
            (15, .symbol, 241),
            (24, .symbol, 241),
            (31, .symbol, 241),
            (41, .symbol, 241),
            (56, [.accepted, .symbol], 241),
            (3, .symbol, 244),
            (6, .symbol, 244),
            (10, .symbol, 244),
            (15, .symbol, 244),
            (24, .symbol, 244),
            (31, .symbol, 244),
            (41, .symbol, 244),
            (56, [.accepted, .symbol], 244),

        /* 216 */

            (1, .symbol, 245),
            (22, [.accepted, .symbol], 245),
            (1, .symbol, 246),
            (22, [.accepted, .symbol], 246),
            (1, .symbol, 247),
            (22, [.accepted, .symbol], 247),
            (1, .symbol, 248),
            (22, [.accepted, .symbol], 248),
            (1, .symbol, 250),
            (22, [.accepted, .symbol], 250),
            (1, .symbol, 251),
            (22, [.accepted, .symbol], 251),
            (1, .symbol, 252),
            (22, [.accepted, .symbol], 252),
            (1, .symbol, 253),
            (22, [.accepted, .symbol], 253),

        /* 217 */

            (2, .symbol, 245),
            (9, .symbol, 245),
            (23, .symbol, 245),
            (40, [.accepted, .symbol], 245),
            (2, .symbol, 246),
            (9, .symbol, 246),
            (23, .symbol, 246),
            (40, [.accepted, .symbol], 246),
            (2, .symbol, 247),
            (9, .symbol, 247),
            (23, .symbol, 247),
            (40, [.accepted, .symbol], 247),
            (2, .symbol, 248),
            (9, .symbol, 248),
            (23, .symbol, 248),
            (40, [.accepted, .symbol], 248),

        /* 218 */

            (3, .symbol, 245),
            (6, .symbol, 245),
            (10, .symbol, 245),
            (15, .symbol, 245),
            (24, .symbol, 245),
            (31, .symbol, 245),
            (41, .symbol, 245),
            (56, [.accepted, .symbol], 245),
            (3, .symbol, 246),
            (6, .symbol, 246),
            (10, .symbol, 246),
            (15, .symbol, 246),
            (24, .symbol, 246),
            (31, .symbol, 246),
            (41, .symbol, 246),
            (56, [.accepted, .symbol], 246),

        /* 219 */

            (3, .symbol, 247),
            (6, .symbol, 247),
            (10, .symbol, 247),
            (15, .symbol, 247),
            (24, .symbol, 247),
            (31, .symbol, 247),
            (41, .symbol, 247),
            (56, [.accepted, .symbol], 247),
            (3, .symbol, 248),
            (6, .symbol, 248),
            (10, .symbol, 248),
            (15, .symbol, 248),
            (24, .symbol, 248),
            (31, .symbol, 248),
            (41, .symbol, 248),
            (56, [.accepted, .symbol], 248),

        /* 220 */

            (2, .symbol, 250),
            (9, .symbol, 250),
            (23, .symbol, 250),
            (40, [.accepted, .symbol], 250),
            (2, .symbol, 251),
            (9, .symbol, 251),
            (23, .symbol, 251),
            (40, [.accepted, .symbol], 251),
            (2, .symbol, 252),
            (9, .symbol, 252),
            (23, .symbol, 252),
            (40, [.accepted, .symbol], 252),
            (2, .symbol, 253),
            (9, .symbol, 253),
            (23, .symbol, 253),
            (40, [.accepted, .symbol], 253),

        /* 221 */

            (3, .symbol, 250),
            (6, .symbol, 250),
            (10, .symbol, 250),
            (15, .symbol, 250),
            (24, .symbol, 250),
            (31, .symbol, 250),
            (41, .symbol, 250),
            (56, [.accepted, .symbol], 250),
            (3, .symbol, 251),
            (6, .symbol, 251),
            (10, .symbol, 251),
            (15, .symbol, 251),
            (24, .symbol, 251),
            (31, .symbol, 251),
            (41, .symbol, 251),
            (56, [.accepted, .symbol], 251),

        /* 222 */

            (3, .symbol, 252),
            (6, .symbol, 252),
            (10, .symbol, 252),
            (15, .symbol, 252),
            (24, .symbol, 252),
            (31, .symbol, 252),
            (41, .symbol, 252),
            (56, [.accepted, .symbol], 252),
            (3, .symbol, 253),
            (6, .symbol, 253),
            (10, .symbol, 253),
            (15, .symbol, 253),
            (24, .symbol, 253),
            (31, .symbol, 253),
            (41, .symbol, 253),
            (56, [.accepted, .symbol], 253),

        /* 223 */

            (0, [.accepted, .symbol], 254),
            (227, .none, 0),
            (229, .none, 0),
            (230, .none, 0),
            (233, .none, 0),
            (234, .none, 0),
            (236, .none, 0),
            (237, .none, 0),
            (241, .none, 0),
            (242, .none, 0),
            (244, .none, 0),
            (245, .none, 0),
            (248, .none, 0),
            (249, .none, 0),
            (251, .none, 0),
            (252, .none, 0),

        /* 224 */

            (1, .symbol, 254),
            (22, [.accepted, .symbol], 254),
            (0, [.accepted, .symbol], 2),
            (0, [.accepted, .symbol], 3),
            (0, [.accepted, .symbol], 4),
            (0, [.accepted, .symbol], 5),
            (0, [.accepted, .symbol], 6),
            (0, [.accepted, .symbol], 7),
            (0, [.accepted, .symbol], 8),
            (0, [.accepted, .symbol], 11),
            (0, [.accepted, .symbol], 12),
            (0, [.accepted, .symbol], 14),
            (0, [.accepted, .symbol], 15),
            (0, [.accepted, .symbol], 16),
            (0, [.accepted, .symbol], 17),
            (0, [.accepted, .symbol], 18),

        /* 225 */

            (2, .symbol, 254),
            (9, .symbol, 254),
            (23, .symbol, 254),
            (40, [.accepted, .symbol], 254),
            (1, .symbol, 2),
            (22, [.accepted, .symbol], 2),
            (1, .symbol, 3),
            (22, [.accepted, .symbol], 3),
            (1, .symbol, 4),
            (22, [.accepted, .symbol], 4),
            (1, .symbol, 5),
            (22, [.accepted, .symbol], 5),
            (1, .symbol, 6),
            (22, [.accepted, .symbol], 6),
            (1, .symbol, 7),
            (22, [.accepted, .symbol], 7),

        /* 226 */

            (3, .symbol, 254),
            (6, .symbol, 254),
            (10, .symbol, 254),
            (15, .symbol, 254),
            (24, .symbol, 254),
            (31, .symbol, 254),
            (41, .symbol, 254),
            (56, [.accepted, .symbol], 254),
            (2, .symbol, 2),
            (9, .symbol, 2),
            (23, .symbol, 2),
            (40, [.accepted, .symbol], 2),
            (2, .symbol, 3),
            (9, .symbol, 3),
            (23, .symbol, 3),
            (40, [.accepted, .symbol], 3),

        /* 227 */

            (3, .symbol, 2),
            (6, .symbol, 2),
            (10, .symbol, 2),
            (15, .symbol, 2),
            (24, .symbol, 2),
            (31, .symbol, 2),
            (41, .symbol, 2),
            (56, [.accepted, .symbol], 2),
            (3, .symbol, 3),
            (6, .symbol, 3),
            (10, .symbol, 3),
            (15, .symbol, 3),
            (24, .symbol, 3),
            (31, .symbol, 3),
            (41, .symbol, 3),
            (56, [.accepted, .symbol], 3),

        /* 228 */

            (2, .symbol, 4),
            (9, .symbol, 4),
            (23, .symbol, 4),
            (40, [.accepted, .symbol], 4),
            (2, .symbol, 5),
            (9, .symbol, 5),
            (23, .symbol, 5),
            (40, [.accepted, .symbol], 5),
            (2, .symbol, 6),
            (9, .symbol, 6),
            (23, .symbol, 6),
            (40, [.accepted, .symbol], 6),
            (2, .symbol, 7),
            (9, .symbol, 7),
            (23, .symbol, 7),
            (40, [.accepted, .symbol], 7),

        /* 229 */

            (3, .symbol, 4),
            (6, .symbol, 4),
            (10, .symbol, 4),
            (15, .symbol, 4),
            (24, .symbol, 4),
            (31, .symbol, 4),
            (41, .symbol, 4),
            (56, [.accepted, .symbol], 4),
            (3, .symbol, 5),
            (6, .symbol, 5),
            (10, .symbol, 5),
            (15, .symbol, 5),
            (24, .symbol, 5),
            (31, .symbol, 5),
            (41, .symbol, 5),
            (56, [.accepted, .symbol], 5),

        /* 230 */

            (3, .symbol, 6),
            (6, .symbol, 6),
            (10, .symbol, 6),
            (15, .symbol, 6),
            (24, .symbol, 6),
            (31, .symbol, 6),
            (41, .symbol, 6),
            (56, [.accepted, .symbol], 6),
            (3, .symbol, 7),
            (6, .symbol, 7),
            (10, .symbol, 7),
            (15, .symbol, 7),
            (24, .symbol, 7),
            (31, .symbol, 7),
            (41, .symbol, 7),
            (56, [.accepted, .symbol], 7),

        /* 231 */

            (1, .symbol, 8),
            (22, [.accepted, .symbol], 8),
            (1, .symbol, 11),
            (22, [.accepted, .symbol], 11),
            (1, .symbol, 12),
            (22, [.accepted, .symbol], 12),
            (1, .symbol, 14),
            (22, [.accepted, .symbol], 14),
            (1, .symbol, 15),
            (22, [.accepted, .symbol], 15),
            (1, .symbol, 16),
            (22, [.accepted, .symbol], 16),
            (1, .symbol, 17),
            (22, [.accepted, .symbol], 17),
            (1, .symbol, 18),
            (22, [.accepted, .symbol], 18),

        /* 232 */

            (2, .symbol, 8),
            (9, .symbol, 8),
            (23, .symbol, 8),
            (40, [.accepted, .symbol], 8),
            (2, .symbol, 11),
            (9, .symbol, 11),
            (23, .symbol, 11),
            (40, [.accepted, .symbol], 11),
            (2, .symbol, 12),
            (9, .symbol, 12),
            (23, .symbol, 12),
            (40, [.accepted, .symbol], 12),
            (2, .symbol, 14),
            (9, .symbol, 14),
            (23, .symbol, 14),
            (40, [.accepted, .symbol], 14),

        /* 233 */

            (3, .symbol, 8),
            (6, .symbol, 8),
            (10, .symbol, 8),
            (15, .symbol, 8),
            (24, .symbol, 8),
            (31, .symbol, 8),
            (41, .symbol, 8),
            (56, [.accepted, .symbol], 8),
            (3, .symbol, 11),
            (6, .symbol, 11),
            (10, .symbol, 11),
            (15, .symbol, 11),
            (24, .symbol, 11),
            (31, .symbol, 11),
            (41, .symbol, 11),
            (56, [.accepted, .symbol], 11),

        /* 234 */

            (3, .symbol, 12),
            (6, .symbol, 12),
            (10, .symbol, 12),
            (15, .symbol, 12),
            (24, .symbol, 12),
            (31, .symbol, 12),
            (41, .symbol, 12),
            (56, [.accepted, .symbol], 12),
            (3, .symbol, 14),
            (6, .symbol, 14),
            (10, .symbol, 14),
            (15, .symbol, 14),
            (24, .symbol, 14),
            (31, .symbol, 14),
            (41, .symbol, 14),
            (56, [.accepted, .symbol], 14),

        /* 235 */

            (2, .symbol, 15),
            (9, .symbol, 15),
            (23, .symbol, 15),
            (40, [.accepted, .symbol], 15),
            (2, .symbol, 16),
            (9, .symbol, 16),
            (23, .symbol, 16),
            (40, [.accepted, .symbol], 16),
            (2, .symbol, 17),
            (9, .symbol, 17),
            (23, .symbol, 17),
            (40, [.accepted, .symbol], 17),
            (2, .symbol, 18),
            (9, .symbol, 18),
            (23, .symbol, 18),
            (40, [.accepted, .symbol], 18),

        /* 236 */

            (3, .symbol, 15),
            (6, .symbol, 15),
            (10, .symbol, 15),
            (15, .symbol, 15),
            (24, .symbol, 15),
            (31, .symbol, 15),
            (41, .symbol, 15),
            (56, [.accepted, .symbol], 15),
            (3, .symbol, 16),
            (6, .symbol, 16),
            (10, .symbol, 16),
            (15, .symbol, 16),
            (24, .symbol, 16),
            (31, .symbol, 16),
            (41, .symbol, 16),
            (56, [.accepted, .symbol], 16),

        /* 237 */

            (3, .symbol, 17),
            (6, .symbol, 17),
            (10, .symbol, 17),
            (15, .symbol, 17),
            (24, .symbol, 17),
            (31, .symbol, 17),
            (41, .symbol, 17),
            (56, [.accepted, .symbol], 17),
            (3, .symbol, 18),
            (6, .symbol, 18),
            (10, .symbol, 18),
            (15, .symbol, 18),
            (24, .symbol, 18),
            (31, .symbol, 18),
            (41, .symbol, 18),
            (56, [.accepted, .symbol], 18),

        /* 238 */

            (0, [.accepted, .symbol], 19),
            (0, [.accepted, .symbol], 20),
            (0, [.accepted, .symbol], 21),
            (0, [.accepted, .symbol], 23),
            (0, [.accepted, .symbol], 24),
            (0, [.accepted, .symbol], 25),
            (0, [.accepted, .symbol], 26),
            (0, [.accepted, .symbol], 27),
            (0, [.accepted, .symbol], 28),
            (0, [.accepted, .symbol], 29),
            (0, [.accepted, .symbol], 30),
            (0, [.accepted, .symbol], 31),
            (0, [.accepted, .symbol], 127),
            (0, [.accepted, .symbol], 220),
            (0, [.accepted, .symbol], 249),
            (253, .none, 0),

        /* 239 */

            (1, .symbol, 19),
            (22, [.accepted, .symbol], 19),
            (1, .symbol, 20),
            (22, [.accepted, .symbol], 20),
            (1, .symbol, 21),
            (22, [.accepted, .symbol], 21),
            (1, .symbol, 23),
            (22, [.accepted, .symbol], 23),
            (1, .symbol, 24),
            (22, [.accepted, .symbol], 24),
            (1, .symbol, 25),
            (22, [.accepted, .symbol], 25),
            (1, .symbol, 26),
            (22, [.accepted, .symbol], 26),
            (1, .symbol, 27),
            (22, [.accepted, .symbol], 27),

        /* 240 */

            (2, .symbol, 19),
            (9, .symbol, 19),
            (23, .symbol, 19),
            (40, [.accepted, .symbol], 19),
            (2, .symbol, 20),
            (9, .symbol, 20),
            (23, .symbol, 20),
            (40, [.accepted, .symbol], 20),
            (2, .symbol, 21),
            (9, .symbol, 21),
            (23, .symbol, 21),
            (40, [.accepted, .symbol], 21),
            (2, .symbol, 23),
            (9, .symbol, 23),
            (23, .symbol, 23),
            (40, [.accepted, .symbol], 23),

        /* 241 */

            (3, .symbol, 19),
            (6, .symbol, 19),
            (10, .symbol, 19),
            (15, .symbol, 19),
            (24, .symbol, 19),
            (31, .symbol, 19),
            (41, .symbol, 19),
            (56, [.accepted, .symbol], 19),
            (3, .symbol, 20),
            (6, .symbol, 20),
            (10, .symbol, 20),
            (15, .symbol, 20),
            (24, .symbol, 20),
            (31, .symbol, 20),
            (41, .symbol, 20),
            (56, [.accepted, .symbol], 20),

        /* 242 */

            (3, .symbol, 21),
            (6, .symbol, 21),
            (10, .symbol, 21),
            (15, .symbol, 21),
            (24, .symbol, 21),
            (31, .symbol, 21),
            (41, .symbol, 21),
            (56, [.accepted, .symbol], 21),
            (3, .symbol, 23),
            (6, .symbol, 23),
            (10, .symbol, 23),
            (15, .symbol, 23),
            (24, .symbol, 23),
            (31, .symbol, 23),
            (41, .symbol, 23),
            (56, [.accepted, .symbol], 23),

        /* 243 */

            (2, .symbol, 24),
            (9, .symbol, 24),
            (23, .symbol, 24),
            (40, [.accepted, .symbol], 24),
            (2, .symbol, 25),
            (9, .symbol, 25),
            (23, .symbol, 25),
            (40, [.accepted, .symbol], 25),
            (2, .symbol, 26),
            (9, .symbol, 26),
            (23, .symbol, 26),
            (40, [.accepted, .symbol], 26),
            (2, .symbol, 27),
            (9, .symbol, 27),
            (23, .symbol, 27),
            (40, [.accepted, .symbol], 27),

        /* 244 */

            (3, .symbol, 24),
            (6, .symbol, 24),
            (10, .symbol, 24),
            (15, .symbol, 24),
            (24, .symbol, 24),
            (31, .symbol, 24),
            (41, .symbol, 24),
            (56, [.accepted, .symbol], 24),
            (3, .symbol, 25),
            (6, .symbol, 25),
            (10, .symbol, 25),
            (15, .symbol, 25),
            (24, .symbol, 25),
            (31, .symbol, 25),
            (41, .symbol, 25),
            (56, [.accepted, .symbol], 25),

        /* 245 */

            (3, .symbol, 26),
            (6, .symbol, 26),
            (10, .symbol, 26),
            (15, .symbol, 26),
            (24, .symbol, 26),
            (31, .symbol, 26),
            (41, .symbol, 26),
            (56, [.accepted, .symbol], 26),
            (3, .symbol, 27),
            (6, .symbol, 27),
            (10, .symbol, 27),
            (15, .symbol, 27),
            (24, .symbol, 27),
            (31, .symbol, 27),
            (41, .symbol, 27),
            (56, [.accepted, .symbol], 27),

        /* 246 */

            (1, .symbol, 28),
            (22, [.accepted, .symbol], 28),
            (1, .symbol, 29),
            (22, [.accepted, .symbol], 29),
            (1, .symbol, 30),
            (22, [.accepted, .symbol], 30),
            (1, .symbol, 31),
            (22, [.accepted, .symbol], 31),
            (1, .symbol, 127),
            (22, [.accepted, .symbol], 127),
            (1, .symbol, 220),
            (22, [.accepted, .symbol], 220),
            (1, .symbol, 249),
            (22, [.accepted, .symbol], 249),
            (254, .none, 0),
            (255, .none, 0),

        /* 247 */

            (2, .symbol, 28),
            (9, .symbol, 28),
            (23, .symbol, 28),
            (40, [.accepted, .symbol], 28),
            (2, .symbol, 29),
            (9, .symbol, 29),
            (23, .symbol, 29),
            (40, [.accepted, .symbol], 29),
            (2, .symbol, 30),
            (9, .symbol, 30),
            (23, .symbol, 30),
            (40, [.accepted, .symbol], 30),
            (2, .symbol, 31),
            (9, .symbol, 31),
            (23, .symbol, 31),
            (40, [.accepted, .symbol], 31),

        /* 248 */

            (3, .symbol, 28),
            (6, .symbol, 28),
            (10, .symbol, 28),
            (15, .symbol, 28),
            (24, .symbol, 28),
            (31, .symbol, 28),
            (41, .symbol, 28),
            (56, [.accepted, .symbol], 28),
            (3, .symbol, 29),
            (6, .symbol, 29),
            (10, .symbol, 29),
            (15, .symbol, 29),
            (24, .symbol, 29),
            (31, .symbol, 29),
            (41, .symbol, 29),
            (56, [.accepted, .symbol], 29),

        /* 249 */

            (3, .symbol, 30),
            (6, .symbol, 30),
            (10, .symbol, 30),
            (15, .symbol, 30),
            (24, .symbol, 30),
            (31, .symbol, 30),
            (41, .symbol, 30),
            (56, [.accepted, .symbol], 30),
            (3, .symbol, 31),
            (6, .symbol, 31),
            (10, .symbol, 31),
            (15, .symbol, 31),
            (24, .symbol, 31),
            (31, .symbol, 31),
            (41, .symbol, 31),
            (56, [.accepted, .symbol], 31),

        /* 250 */

            (2, .symbol, 127),
            (9, .symbol, 127),
            (23, .symbol, 127),
            (40, [.accepted, .symbol], 127),
            (2, .symbol, 220),
            (9, .symbol, 220),
            (23, .symbol, 220),
            (40, [.accepted, .symbol], 220),
            (2, .symbol, 249),
            (9, .symbol, 249),
            (23, .symbol, 249),
            (40, [.accepted, .symbol], 249),
            (0, [.accepted, .symbol], 10),
            (0, [.accepted, .symbol], 13),
            (0, [.accepted, .symbol], 22),
            (0, .failure, 0),

        /* 251 */

            (3, .symbol, 127),
            (6, .symbol, 127),
            (10, .symbol, 127),
            (15, .symbol, 127),
            (24, .symbol, 127),
            (31, .symbol, 127),
            (41, .symbol, 127),
            (56, [.accepted, .symbol], 127),
            (3, .symbol, 220),
            (6, .symbol, 220),
            (10, .symbol, 220),
            (15, .symbol, 220),
            (24, .symbol, 220),
            (31, .symbol, 220),
            (41, .symbol, 220),
            (56, [.accepted, .symbol], 220),

        /* 252 */

            (3, .symbol, 249),
            (6, .symbol, 249),
            (10, .symbol, 249),
            (15, .symbol, 249),
            (24, .symbol, 249),
            (31, .symbol, 249),
            (41, .symbol, 249),
            (56, [.accepted, .symbol], 249),
            (1, .symbol, 10),
            (22, [.accepted, .symbol], 10),
            (1, .symbol, 13),
            (22, [.accepted, .symbol], 13),
            (1, .symbol, 22),
            (22, [.accepted, .symbol], 22),
            (0, .failure, 0),
            (0, .failure, 0),

        /* 253 */

            (2, .symbol, 10),
            (9, .symbol, 10),
            (23, .symbol, 10),
            (40, [.accepted, .symbol], 10),
            (2, .symbol, 13),
            (9, .symbol, 13),
            (23, .symbol, 13),
            (40, [.accepted, .symbol], 13),
            (2, .symbol, 22),
            (9, .symbol, 22),
            (23, .symbol, 22),
            (40, [.accepted, .symbol], 22),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),

        /* 254 */

            (3, .symbol, 10),
            (6, .symbol, 10),
            (10, .symbol, 10),
            (15, .symbol, 10),
            (24, .symbol, 10),
            (31, .symbol, 10),
            (41, .symbol, 10),
            (56, [.accepted, .symbol], 10),
            (3, .symbol, 13),
            (6, .symbol, 13),
            (10, .symbol, 13),
            (15, .symbol, 13),
            (24, .symbol, 13),
            (31, .symbol, 13),
            (41, .symbol, 13),
            (56, [.accepted, .symbol], 13),

        /* 255 */

            (3, .symbol, 22),
            (6, .symbol, 22),
            (10, .symbol, 22),
            (15, .symbol, 22),
            (24, .symbol, 22),
            (31, .symbol, 22),
            (41, .symbol, 22),
            (56, [.accepted, .symbol], 22),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),
            (0, .failure, 0),
    ]
     */
}
