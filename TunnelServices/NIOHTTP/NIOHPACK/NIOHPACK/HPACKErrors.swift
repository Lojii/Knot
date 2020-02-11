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

public protocol NIOHPACKError : Error, Equatable { }

/// Errors raised by NIOHPACK while encoding/decoding data.
public enum NIOHPACKErrors {
    /// An indexed header referenced an index that doesn't exist in our
    /// header tables.
    public struct InvalidHeaderIndex : NIOHPACKError {
        /// The offending index.
        public let suppliedIndex: Int
        
        /// The highest index we have available.
        public let availableIndex: Int
    }
    
    /// A header block indicated an indexed header with no accompanying
    /// value, but the index referenced an entry with no value of its own
    /// e.g. one of the many valueless items in the static header table.
    public struct IndexedHeaderWithNoValue : NIOHPACKError {
        /// The offending index.
        public let index: Int
    }
    
    /// An encoded string contained an invalid length that extended
    /// beyond its frame's payload size.
    public struct StringLengthBeyondPayloadSize : NIOHPACKError {
        /// The length supplied.
        public let length: Int
        
        /// The available number of bytes.
        public let available: Int
    }
    
    /// Decoded string data could not be parsed as valid UTF-8.
    public struct InvalidUTF8Data : NIOHPACKError {
        /// The offending bytes.
        public let bytes: ByteBuffer
    }
    
    /// The start byte of a header did not match any format allowed by
    /// the HPACK specification.
    public struct InvalidHeaderStartByte : NIOHPACKError {
        /// The offending byte.
        public let byte: UInt8
    }
    
    /// A dynamic table size update specified an invalid size.
    public struct InvalidDynamicTableSize : NIOHPACKError {
        /// The offending size.
        public let requestedSize: Int
        
        /// The actual maximum size that was set by the protocol.
        public let allowedSize: Int
    }
    
    /// A dynamic table size update was found outside its allowed place.
    /// They may only be included at the start of a header block.
    public struct IllegalDynamicTableSizeChange : NIOHPACKError {}
    
    /// A new header could not be added to the dynamic table. Usually
    /// this means the header itself is larger than the current
    /// dynamic table size.
    public struct FailedToAddIndexedHeader<Name: Collection, Value: Collection> : NIOHPACKError where Name.Element == UInt8, Value.Element == UInt8 {
        /// The table size required to be able to add this header to the table.
        public let bytesNeeded: Int
        
        /// The name of the header that could not be written.
        public let name: Name
        
        /// The value of the header that could not be written.
        public let value: Value
        
        public static func == (lhs: NIOHPACKErrors.FailedToAddIndexedHeader<Name, Value>, rhs: NIOHPACKErrors.FailedToAddIndexedHeader<Name, Value>) -> Bool {
            guard lhs.bytesNeeded == rhs.bytesNeeded else {
                return false
            }
            return lhs.name.elementsEqual(rhs.name) && lhs.value.elementsEqual(rhs.value)
        }
    }
    
    /// Ran out of input bytes while decoding.
    public struct InsufficientInput : NIOHPACKError {}
    
    /// HPACK encoder asked to begin a new header block while partway through encoding
    /// another block.
    public struct EncoderAlreadyActive : NIOHPACKError {}
    
    /// HPACK encoder asked to append a header without first calling `beginEncoding(allocator:)`.
    public struct EncoderNotStarted : NIOHPACKError {}

    /// HPACK decoder asked to decode an indexed header with index zero.
    public struct ZeroHeaderIndex: NIOHPACKError {
        public init() { }
    }

    /// HPACK decoder asked to decode a header list that would violate the configured
    /// max header list size.
    public struct MaxHeaderListSizeViolation: NIOHPACKError {
        public init() { }
    }

    /// HPACK decoder asked to decode a header field name that was empty.
    public struct EmptyLiteralHeaderFieldName: NIOHPACKError {
        public init() { }
    }
}
