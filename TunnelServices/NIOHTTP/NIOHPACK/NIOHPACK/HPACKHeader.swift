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
import NIOHTTP1

/// Very similar to `NIOHTTP1.HTTPHeaders`, but with extra data for storing indexing
/// information.
public struct HPACKHeaders: ExpressibleByDictionaryLiteral {
    @usableFromInline
    internal var headers: [HPACKHeader]

    // see 8.1.2.2. Connection-Specific Header Fields in RFC 7540
    static let illegalHeaders: [String] = ["connection", "keep-alive", "proxy-connection",
                                           "transfer-encoding", "upgrade"]

    /// Constructor that can be used to map between `HTTPHeaders` and `HPACKHeaders` types.
    public init(httpHeaders: HTTPHeaders, normalizeHTTPHeaders: Bool) {
        if normalizeHTTPHeaders {
            self.headers = httpHeaders.map { HPACKHeader(name: $0.name.lowercased(), value: $0.value) }

            let connectionHeaderValue = httpHeaders[canonicalForm: "connection"]
            if !connectionHeaderValue.isEmpty {
                self.headers.removeAll { header in
                    return HPACKHeaders.illegalHeaders.contains(header.name) ||
                        connectionHeaderValue.contains(header.name[...])
                }
            }
        } else {
            self.headers = httpHeaders.map { HPACKHeader(name: $0.name, value: $0.value) }
        }
    }

    /// Constructor that can be used to map between `HTTPHeaders` and `HPACKHeaders` types.
    public init(httpHeaders: HTTPHeaders) {
        self.init(httpHeaders: httpHeaders, normalizeHTTPHeaders: true)
    }
    
    /// Construct a `HPACKHeaders` structure.
    ///
    /// The indexability of all headers is assumed to be the default, i.e. indexable and
    /// rewritable by proxies.
    ///
    /// - parameters
    ///     - headers: An initial set of headers to use to populate the header block.
    public init(_ headers: [(String, String)] = []) {
        self.headers = headers.map { HPACKHeader(name: $0.0, value: $0.1) }
    }

    /// Construct a `HPACKHeaders` structure.
    ///
    /// The indexability of all headers is assumed to be the default, i.e. indexable and
    /// rewritable by proxies.
    ///
    /// - Parameter elements: name, value pairs provided by a dictionary literal.
    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements)
    }

    /// Construct a `HPACKHeaders` structure.
    ///
    /// The indexability of all headers is assumed to be the default, i.e. indexable and
    /// rewritable by proxies.
    ///
    /// - parameters
    ///     - headers: An initial set of headers to use to populate the header block.
    ///     - allocator: The allocator to use to allocate the underlying storage.
    @available(*, deprecated, renamed: "init(_:)")
    public init(_ headers: [(String, String)] = [], allocator: ByteBufferAllocator) {
        // We no longer use an allocator so we don't need this method anymore.
        self.init(headers)
    }
    
    /// Internal initializer to make things easier for unit tests.
    init(fullHeaders: [(HPACKIndexing, String, String)]) {
        self.headers = fullHeaders.map { HPACKHeader(name: $0.1, value: $0.2, indexing: $0.0) }
    }

    /// Internal initializer for use in HPACK decoding.
    init(headers: [HPACKHeader]) {
        self.headers = headers
    }
    
    /// Add a header name/value pair to the block.
    ///
    /// This method is strictly additive: if there are other values for the given header name
    /// already in the block, this will add a new entry. `add` performs case-insensitive
    /// comparisons on the header field name.
    ///
    /// - Parameter name: The header field name. This must be an ASCII string. For HTTP/2 lowercase
    ///     header names are strongly encouraged.
    /// - Parameter value: The header field value to add for the given name.
    public mutating func add(name: String, value: String, indexing: HPACKIndexing = .indexable) {
        precondition(!name.utf8.contains(where: { !$0.isASCII }), "name must be ASCII")
        self.headers.append(HPACKHeader(name: name, value: value, indexing: indexing))
    }

    /// Add a sequence of header name/value pairs to the block.
    ///
    /// This method is strictly additive: if there are other entries with the same header
    /// name already in the block, this will add new entries.
    ///
    /// - Parameter contentsOf: The sequence of header name/value pairs. Header names must be ASCII
    ///     strings. For HTTP/2 lowercase header names are strongly recommended.
    @inlinable
    public mutating func add<S: Sequence>(contentsOf other: S, indexing: HPACKIndexing = .indexable) where S.Element == (String, String) {
        self.headers.reserveCapacity(self.headers.count + other.underestimatedCount)
        for (name, value) in other {
            self.add(name: name, value: value, indexing: indexing)
        }
    }

    /// Add a sequence of header name/value/indexing triplet to the block.
    ///
    /// This method is strictly additive: if there are other entries with the same header
    /// name already in the block, this will add new entries.
    ///
    /// - Parameter contentsOf: The sequence of header name/value/indexing triplets. Header names
    ///     must be ASCII strings. For HTTP/2 lowercase header names are strongly recommended.
    @inlinable
    public mutating func add<S: Sequence>(contentsOf other: S) where S.Element == HPACKHeaders.Element {
        self.headers.reserveCapacity(self.headers.count + other.underestimatedCount)
        for (name, value, indexing) in other {
            self.add(name: name, value: value, indexing: indexing)
        }
    }
    
    /// Retrieve all of the values for a given header field name from the block.
    ///
    /// This method uses case-insensitive comparisons for the header field name. It
    /// does not return a maximally-decomposed list of the header fields, but instead
    /// returns them in their original representation: that means that a comma-separated
    /// header field list may contain more than one entry, some of which contain commas
    /// and some do not. If you want a representation of the header fields suitable for
    /// performing computation on, consider `getCanonicalForm`.
    ///
    /// - Parameter name: The header field name whose values are to be retrieved.
    /// - Returns: A list of the values for that header field name.
    public subscript(name: String) -> [String] {
        guard !self.headers.isEmpty else {
            return []
        }

        var array: [String] = []
        for header in self.headers {
            if header.name.isEqualCaseInsensitiveASCIIBytes(to: name) {
                array.append(header.value)
            }
        }
        
        return array
    }
    
    /// Checks if a header is present
    ///
    /// - parameters:
    ///     - name: The name of the header
    /// - returns: `true` if a header with the name (and value) exists, `false` otherwise.
    public func contains(name: String) -> Bool {
        guard !self.headers.isEmpty else {
            return false
        }

        for header in self.headers {
            if header.name.isEqualCaseInsensitiveASCIIBytes(to: name) {
                return true
            }
        }
        return false
    }
    
    /// Retrieves the header values for the given header field in "canonical form": that is,
    /// splitting them on commas as extensively as possible such that multiple values received on the
    /// one line are returned as separate entries. Also respects the fact that Set-Cookie should not
    /// be split in this way.
    ///
    /// - Parameter name: The header field name whose values are to be retrieved.
    /// - Returns: A list of the values for that header field name.
    public subscript(canonicalForm name: String) -> [String] {
        let result = self[name]
        guard result.count > 0 else {
            return []
        }
        
        // It's not safe to split Set-Cookie on comma.
        guard name.lowercased() != "set-cookie" else {
            return result
        }
        
        return result.flatMap { $0.split(separator: ",") }.map { String($0.trimWhitespace()) }
    }
    
    /// Special internal function for use by tests.
    internal subscript(position: Int) -> (String, String) {
        precondition(position < self.headers.endIndex, "Position \(position) is beyond bounds of \(self.headers.endIndex)")
        let header = self.headers[position]
        return (header.name, header.value)
    }
}


extension HPACKHeaders: RandomAccessCollection {
    public typealias Element = (name: String, value: String, indexable: HPACKIndexing)

    public struct Index: Comparable {
        fileprivate let base: Array<HPACKHeaders>.Index
        public static func < (lhs: Index, rhs: Index) -> Bool {
            return lhs.base < rhs.base
        }
    }

    public var startIndex: HPACKHeaders.Index {
        return .init(base: self.headers.startIndex)
    }

    public var endIndex: HPACKHeaders.Index {
        return .init(base: self.headers.endIndex)
    }

    public func index(before i: HPACKHeaders.Index) -> HPACKHeaders.Index {
        return .init(base: self.headers.index(before: i.base))
    }

    public func index(after i: HPACKHeaders.Index) -> HPACKHeaders.Index {
        return .init(base: self.headers.index(after: i.base))
    }

    public subscript(position: HPACKHeaders.Index) -> Element {
        let element = self.headers[position.base]
        return (name: element.name, value: element.value, indexable: element.indexing)
    }

    // Why are we providing an `Iterator` when we could just use the default one?
    // The answer is that we changed from Sequence to RandomAccessCollection in a SemVer minor release. The
    // previous code had a special-case Iterator, and so to avoid breaking that abstraction we need to provide one
    // here too. Happily, however, we can simply delegate to the underlying Iterator type.

    /// An iterator of HTTP header fields.
    ///
    /// This iterator will return each value for a given header name separately. That
    /// means that `name` is not guaranteed to be unique in a given block of headers.
    public struct Iterator: IteratorProtocol {
        private var base: Array<HPACKHeader>.Iterator

        init(_ base: HPACKHeaders) {
            self.base = base.headers.makeIterator()
        }

        public mutating func next() -> Element? {
            guard let element = self.base.next() else {
                return nil
            }
            return (name: element.name, value: element.value, indexable: element.indexing)
        }
    }

    public func makeIterator() -> HPACKHeaders.Iterator {
        return Iterator(self)
    }
}


extension HPACKHeaders: CustomStringConvertible {
    public var description: String {
        var headersArray: [(HPACKIndexing, String, String)] = []
        headersArray.reserveCapacity(self.headers.count)

        for h in self.headers {
            headersArray.append((h.indexing, h.name, h.value))
        }
        return headersArray.description
    }
}

extension HPACKHeaders: Equatable {
    public static func ==(lhs: HPACKHeaders, rhs: HPACKHeaders) -> Bool {
        guard lhs.headers.count == rhs.headers.count else {
            return false
        }
        let lhsNames = Set(lhs.headers.map { $0.name })
        let rhsNames = Set(rhs.headers.map { $0.name })
        guard lhsNames == rhsNames else {
            return false
        }

        for name in lhsNames {
            guard lhs[name].sorted() == rhs[name].sorted() else {
                return false
            }
        }

        return true
    }
}

/// Defines the types of indexing and rewriting operations a decoder may take with
/// regard to this header.
public enum HPACKIndexing: CustomStringConvertible {
    /// Header may be written into the dynamic index table or may be rewritten by
    /// proxy servers.
    case indexable
    /// Header is not written to the dynamic index table, but proxies may rewrite
    /// it en-route, as long as they preserve its non-indexable attribute.
    case nonIndexable
    /// Header may not be written to the dynamic index table, and proxies must
    /// pass it on as-is without rewriting.
    case neverIndexed
    
    public var description: String {
        switch self {
        case .indexable:
            return "[]"
        case .nonIndexable:
            return "[non-indexable]"
        case .neverIndexed:
            return "[neverIndexed]"
        }
    }
}

@usableFromInline
internal struct HPACKHeader {
    var indexing: HPACKIndexing
    var name: String
    var value: String
    
    internal init(name: String, value: String, indexing: HPACKIndexing = .indexable) {
        self.indexing = indexing
        self.name = name
        self.value = value
    }
}


extension HPACKHeader {
    internal var size: Int {
        // RFC 7541 § 4.1:
        //
        //      The size of an entry is the sum of its name's length in octets (as defined in
        //      Section 5.2), its value's length in octets, and 32.
        //
        //      The size of an entry is calculated using the length of its name and value
        //      without any Huffman encoding applied.
        return name.utf8.count + value.utf8.count + 32
    }
}


internal extension UInt8 {
    var isASCII: Bool {
        return self <= 127
    }
}

/* private but tests */
internal extension Character {
    var isASCIIWhitespace: Bool {
        return self == " " || self == "\t" || self == "\r" || self == "\n" || self == "\r\n"
    }
}

/* private but tests */
internal extension String {
    func trimASCIIWhitespace() -> Substring {
        return self.dropFirst(0).trimWhitespace()
    }
}

private extension Substring {
    func trimWhitespace() -> Substring {
        var me = self
        while me.first?.isASCIIWhitespace == .some(true) {
            me = me.dropFirst()
        }
        while me.last?.isASCIIWhitespace == .some(true) {
            me = me.dropLast()
        }
        return me
    }
}


extension Sequence where Self.Element == UInt8 {
    /// Compares the collection of `UInt8`s to a case insensitive collection.
    ///
    /// This collection could be get from applying the `UTF8View`
    ///   property on the string protocol.
    ///
    /// - Parameter bytes: The string constant in the form of a collection of `UInt8`
    /// - Returns: Whether the collection contains **EXACTLY** this array or no, but by ignoring case.
    fileprivate func compareCaseInsensitiveASCIIBytes<T: Sequence>(to other: T) -> Bool
        where T.Element == UInt8 {
            // fast path: we can get the underlying bytes of both
            let maybeMaybeResult = self.withContiguousStorageIfAvailable { lhsBuffer -> Bool? in
                other.withContiguousStorageIfAvailable { rhsBuffer in
                    if lhsBuffer.count != rhsBuffer.count {
                        return false
                    }

                    for idx in 0 ..< lhsBuffer.count {
                        // let's hope this gets vectorised ;)
                        if lhsBuffer[idx] & 0xdf != rhsBuffer[idx] & 0xdf && lhsBuffer[idx].isASCII {
                            return false
                        }
                    }
                    return true
                }
            }

            if let maybeResult = maybeMaybeResult, let result = maybeResult {
                return result
            } else {
                return self._compareCaseInsensitiveASCIIBytesSlowPath(to: other)
            }
    }

    @inline(never)
    private func _compareCaseInsensitiveASCIIBytesSlowPath<T: Sequence>(to other: T) -> Bool where T.Element == UInt8 {
        return self.elementsEqual(other, by: { return (($0 & 0xdf) == ($1 & 0xdf) && $0.isASCII) })
    }
}


extension String {
    internal func isEqualCaseInsensitiveASCIIBytes(to: String) -> Bool {
        return self.utf8.compareCaseInsensitiveASCIIBytes(to: to.utf8)
    }
}

