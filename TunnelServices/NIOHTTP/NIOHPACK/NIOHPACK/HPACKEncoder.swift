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

/// An `HPACKEncoder` maintains its own dynamic header table and uses that to
/// encode HTTP headers to an internal byte buffer.
///
/// This encoder functions as an accumulator: each encode operation will append
/// bytes to a buffer maintained by the encoder, which must be cleared using
/// `reset()` before the encode can be re-used. It maintains a header table for
/// outbound header indexing, and will update the header table as described in
/// RFC 7541, appending and evicting items as described there.
public struct HPACKEncoder {
    /// The default size of the encoder's dynamic header table.
    public static var defaultDynamicTableSize: Int { return DynamicHeaderTable.defaultSize }
    private static let defaultDataBufferSize = 128
    
    public struct HeaderDefinition {
        var name: String
        var value: String
        var indexing: HPACKIndexing
    }
    
    private enum EncoderState {
        case idle
        case resized(smallestMaxTableSize: Int?)
        case encoding
    }
    
    // private but tests
    var headerIndexTable: IndexedHeaderTable
    
    private var state: EncoderState
    private var buffer: ByteBuffer
    
    /// Whether to use Huffman encoding.
    public let useHuffmanEncoding: Bool
    
    /// The current size of the dynamic table.
    ///
    /// This is defined as the sum of [name] + [value] + 32 for each header.
    public var dynamicTableSize: Int {
        return self.headerIndexTable.dynamicTableLength
    }
    
    /// The current maximum size to which the dynamic header table may grow.
    public private(set) var allowedDynamicTableSize: Int {
        get { return self.headerIndexTable.dynamicTableAllowedLength }
        set { self.headerIndexTable.dynamicTableAllowedLength = newValue }
    }
    
    /// The hard maximum size of the dynamic header table, set via an HTTP/2
    /// SETTINGS frame.
    public var maximumDynamicTableSize: Int {
        get { return self.headerIndexTable.maxDynamicTableLength }
        set { self.headerIndexTable.maxDynamicTableLength = newValue }
    }
    
    /// Sets the maximum size for the dynamic table and encodes the new value
    /// at the start of the current packed header block to send to the peer.
    ///
    /// - Parameter size: The new maximum size for the dynamic header table.
    /// - Throws: If the encoder is currently in use, or if the requested size
    ///           exceeds the maximum value negotiated with the peer.
    public mutating func setDynamicTableSize(_ size: Int) throws {
        guard size <= self.maximumDynamicTableSize else {
            throw NIOHPACKErrors.InvalidDynamicTableSize(requestedSize: size, allowedSize: self.maximumDynamicTableSize)
        }
        guard size != self.allowedDynamicTableSize else {
            // no need to change anything
            return
        }
        
        switch self.state {
        case .idle:
            self.state = .resized(smallestMaxTableSize: nil)
        case .resized(nil) where size > self.allowedDynamicTableSize:
            self.state = .resized(smallestMaxTableSize: self.allowedDynamicTableSize)
        case .resized(let smallest?) where size < smallest:
            self.state = .resized(smallestMaxTableSize: nil)
        case .encoding:
            throw NIOHPACKErrors.EncoderAlreadyActive()
        default:
            // we don't need to change smallest recorded resize value
            break
        }
        
        // set the new size on our dynamic table
        self.allowedDynamicTableSize = size
    }
    
    /// Initializer and returns a new HPACK encoder.
    ///
    /// - Parameters:
    ///   - allocator: An allocator for `ByteBuffer`s.
    ///   - maxDynamicTableSize: An initial maximum size for the encoder's dynamic header table.
    public init(allocator: ByteBufferAllocator, useHuffmanEncoding: Bool = true, maxDynamicTableSize: Int = HPACKEncoder.defaultDynamicTableSize) {
        self.headerIndexTable = IndexedHeaderTable(allocator: allocator, maxDynamicTableSize: maxDynamicTableSize)
        self.useHuffmanEncoding = useHuffmanEncoding
        self.state = .idle

        // In my ideal world this allocation would be of size 0, but we need to have it be a little bit bigger to support the incremental encoding
        // mode. I want to remove it: see https://github.com/apple/swift-nio-http2/issues/85.
        self.buffer = allocator.buffer(capacity: 128)
    }
    
    /// Sets up the encoder to begin encoding a new header block.
    ///
    /// - Parameter allocator: Used to allocate the `ByteBuffer` that will contain the encoded
    ///                        bytes, obtained from `endEncoding()`.
    public mutating func beginEncoding(allocator: ByteBufferAllocator) throws {
        if case .encoding = self.state {
            throw NIOHPACKErrors.EncoderAlreadyActive()
        }

        self.buffer.clear()

        switch self.state {
        case .idle:
            self.state = .encoding
        case .resized(nil):
            // one resize
            self.buffer.write(encodedInteger: UInt(self.allowedDynamicTableSize), prefix: 5, prefixBits: 0x20)
            self.state = .encoding
        case let .resized(smallestSize?):
            // two resizes, one smaller than the other
            self.buffer.write(encodedInteger: UInt(smallestSize), prefix: 5, prefixBits: 0x20)
            self.buffer.write(encodedInteger: UInt(self.allowedDynamicTableSize), prefix: 5, prefixBits: 0x20)
            self.state = .encoding
        default:
            break
        }
    }
    
    /// Finishes encoding the current header block and returns the resulting buffer.
    public mutating func endEncoding() throws -> ByteBuffer {
        guard case .encoding = self.state else {
            throw NIOHPACKErrors.EncoderNotStarted()
        }
        
        self.state = .idle
        return self.buffer
    }
    
    /// A one-shot encoder that writes to a provided buffer.
    ///
    /// In general this encoding mechanism is more efficient than the incremental one.
    public mutating func encode(headers: HPACKHeaders, to buffer: inout ByteBuffer) throws {
        if case .encoding = self.state {
            throw NIOHPACKErrors.EncoderAlreadyActive()
        }

        swap(&self.buffer, &buffer)
        defer {
            swap(&self.buffer, &buffer)
            self.state = .idle
        }

        switch self.state {
        case .idle:
            self.state = .encoding
        case .resized(nil):
            // one resize
            self.buffer.write(encodedInteger: UInt(self.allowedDynamicTableSize), prefix: 5, prefixBits: 0x20)
            self.state = .encoding
        case let .resized(smallestSize?):
            // two resizes, one smaller than the other
            self.buffer.write(encodedInteger: UInt(smallestSize), prefix: 5, prefixBits: 0x20)
            self.buffer.write(encodedInteger: UInt(self.allowedDynamicTableSize), prefix: 5, prefixBits: 0x20)
            self.state = .encoding
        default:
            break
        }

        try self.append(headers: headers)
    }
    
    /// Appends() headers in the default fashion: indexed if possible, literal+indexable if not.
    ///
    /// - Parameter headers: A sequence of key/value pairs representing HTTP headers.
    public mutating func append<S: Sequence>(headers: S) throws where S.Element == (name: String, value: String) {
        try self.append(headers: headers.lazy.map { HeaderDefinition(name: $0.0, value: $0.1, indexing: .indexable) })
    }
    
    /// Appends headers with their specified indexability.
    ///
    /// - Parameter headers: A sequence of key/value/indexability tuples representing HTTP headers.
    public mutating func append<S : Sequence>(headers: S) throws where S.Element == HeaderDefinition {
        guard case .encoding = self.state else {
            throw NIOHPACKErrors.EncoderNotStarted()
        }
        
        for header in headers {
            switch header.indexing {
            case .indexable:
                try self._appendIndexed(header: header.name, value: header.value)
            case .nonIndexable:
                self._appendNonIndexed(header: header.name, value: header.value)
            case .neverIndexed:
                self._appendNeverIndexed(header: header.name, value: header.value)
            }
        }
    }
    
    /// Appends a set of headers with their associated indexability.
    ///
    /// - Parameter headers: A `HPACKHeaders` structure containing a set of HTTP/2 header values.
    public mutating func append(headers: HPACKHeaders) throws {
        guard case .encoding = self.state else {
            throw NIOHPACKErrors.EncoderNotStarted()
        }
        
        for header in headers {
            switch header.indexable {
            case .indexable:
                try self._appendIndexed(header: header.name, value: header.value)
            case .nonIndexable:
                self._appendNonIndexed(header: header.name, value: header.value)
            case .neverIndexed:
                self._appendNeverIndexed(header: header.name, value: header.value)
            }
        }
    }
    
    /// Appends a header/value pair, using indexed names/values if possible. If no indexed pair is available,
    /// it will use an indexed header and literal value, or a literal header and value. The name/value pair
    /// will be indexed for future use.
    public mutating func append(header name: String, value: String) throws {
        guard case .encoding = self.state else {
            throw NIOHPACKErrors.EncoderNotStarted()
        }
        try self._appendIndexed(header: name, value: value)
    }
    
    /// Returns `true` if the item needs to be added to the header table
    private mutating func _appendIndexed(header name: String, value: String) throws {
        if let (index, hasValue) = self.headerIndexTable.firstHeaderMatch(for: name, value: value) {
            if hasValue {
                // purely indexed. Nice & simple.
                self.buffer.write(encodedInteger: UInt(index), prefix: 7, prefixBits: 0x80)
                // everything is indexed-- nothing more to do!
                return
            } else {
                // no value, so append the index to represent the name, followed by the value's
                // length
                self.buffer.write(encodedInteger: UInt(index), prefix: 6, prefixBits: 0x40)
                // now encode and append the value string
                self.appendEncodedString(value)
            }
        } else {
            // no indexed name or value. Have to add them both, with a zero index.
            _ = self.buffer.writeInteger(UInt8(0x40))
            self.appendEncodedString(name)
            self.appendEncodedString(value)
        }
        
        // add to the header table
        try self.headerIndexTable.add(headerNamed: name, value: value)
    }
    
    private mutating func appendEncodedString(_ string: String) {
        let utf8 = string.utf8

        // encode the value
        if self.useHuffmanEncoding {
            // problem: we need to encode the length before the encoded bytes, so we can't just receive the length
            // after encoding to the target buffer itself. So we have to determine the length first.
            self.buffer.write(encodedInteger: UInt(ByteBuffer.huffmanEncodedLength(of: utf8)), prefix: 7, prefixBits: 0x80)
            self.buffer.writeHuffmanEncoded(bytes: utf8)
        } else {
            self.buffer.write(encodedInteger: UInt(utf8.count), prefix: 7, prefixBits: 0)
            self.buffer.writeBytes(utf8)
        }
    }
    
    /// Appends a header that is *not* to be entered into the dynamic header table, but allows that
    /// stipulation to be overriden by a proxy server/rewriter.
    public mutating func appendNonIndexed(header: String, value: String) throws {
        guard case .encoding = self.state else {
            throw NIOHPACKErrors.EncoderNotStarted()
        }
        self._appendNonIndexed(header: header, value: value)
    }
    
    private mutating func _appendNonIndexed(header: String, value: String) {
        if let (index, _) = self.headerIndexTable.firstHeaderMatch(for: header, value: nil) {
            // we actually don't care if it has a value in this instance; we're only indexing the
            // name.
            self.buffer.write(encodedInteger: UInt(index), prefix: 4, prefixBits: 0)
            // now append the value
            self.appendEncodedString(value)
        } else {
            self.buffer.writeInteger(UInt8(0))    // top 4 bits are zero, and index is zero (no index)
            self.appendEncodedString(header)
            self.appendEncodedString(value)
        }
    }
    
    /// Appends a header that is *never* indexed, preventing even rewriting proxies from doing so.
    public mutating func appendNeverIndexed(header: String, value: String) throws {
        guard case .encoding = self.state else {
            throw NIOHPACKErrors.EncoderNotStarted()
        }
        self._appendNeverIndexed(header: header, value: value)
    }
    
    private mutating func _appendNeverIndexed(header: String, value: String) {
        if let (index, _) = self.headerIndexTable.firstHeaderMatch(for: header, value: nil) {
            // we only use the index in this instance
            self.buffer.write(encodedInteger: UInt(index), prefix: 4, prefixBits: 0x10)
            // now append the value
            self.appendEncodedString(value)
        } else {
            self.buffer.writeInteger(UInt8(0x10))     // prefix bits + zero index
            self.appendEncodedString(header)
            self.appendEncodedString(value)
        }
    }
}
