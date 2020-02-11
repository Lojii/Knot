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

internal struct HeaderTableEntry {
    var name: String

    var value: String

    // RFC 7541 § 4.1:
    //
    //      The size of an entry is the sum of its name's length in octets (as defined in
    //      Section 5.2), its value's length in octets, and 32.
    //
    //      The size of an entry is calculated using the length of its name and value
    //      without any Huffman encoding applied.
    var length: Int {
        return self.name.utf8.count + self.value.utf8.count + 32
    }
}

/// Storage for the header tables, both static and dynamic. Similar in spirit to
/// `HPACKHeaders` and `NIOHTTP1.HTTPHeaders`, but uses a ring buffer to hold the bytes to
/// avoid allocation churn while evicting and replacing entries.
@usableFromInline
struct HeaderTableStorage {
    static let defaultMaxSize = 4096

    private var headers: CircularBuffer<HeaderTableEntry>
    
    internal private(set) var maxSize: Int
    internal private(set) var length: Int = 0
    
    var count: Int {
        return self.headers.count
    }
    
    init(maxSize: Int = HeaderTableStorage.defaultMaxSize) {
        self.maxSize = maxSize
        self.headers = CircularBuffer(initialCapacity: self.maxSize / 64)    // rough guess: 64 bytes per header
    }
    
    init(staticHeaderList: [(String, String)]) {
        self.headers = CircularBuffer(initialCapacity: staticHeaderList.count)

        var len = 0
        for header in staticHeaderList {
            let entry = HeaderTableEntry(name: header.0, value: header.1)
            self.headers.append(entry)
            len += entry.length
        }

        self.maxSize = len
    }
    
    subscript(index: Int) -> HeaderTableEntry {
        let baseIndex = self.headers.index(self.headers.startIndex, offsetBy: index)
        return self.headers[baseIndex]
    }

    enum MatchType {
        case full(Int)
        case partial(Int)
        case none
    }

    func closestMatch(name: String, value: String) -> MatchType {
        var partialIndex: Int? = nil

        for (index, header) in self.headers.enumerated() {
            // Check if the header name matches.
            guard header.name.isEqualCaseInsensitiveASCIIBytes(to: name) else {
                continue
            }

            if partialIndex == nil {
                partialIndex = index
            }

            if value == header.value {
                return .full(index)
            }
        }

        if let partial = partialIndex {
            return .partial(partial)
        } else {
            return .none
        }
    }
    
    func firstIndex(matching name: String) -> Int? {
        for (idx, header) in self.headers.enumerated() {
            if header.name.isEqualCaseInsensitiveASCIIBytes(to: name) {
                return idx
            }
        }
        return nil
    }
    
    mutating func setTableSize(to newSize: Int) {
        precondition(newSize >= 0)
        if newSize < self.length {
            // need to clear out some things first.
            while newSize < self.length {
                purgeOne()
            }
        }

        self.maxSize = newSize
    }
    
    mutating func add(name: String, value: String) {
        let entry = HeaderTableEntry(name: name, value: value)

        var newLength = self.length + entry.length
        if newLength > self.maxSize {
            self.purge(toRelease: newLength - maxSize)
            newLength = self.length + entry.length
        }


        if newLength > self.maxSize {
            // We can't free up enough space. This is not an error: RFC 7541 § 4.4 explicitly allows it.
            // In this case, the append fails but the above purge is preserved.
            return
        }

        self.headers.prepend(entry)
        self.length = newLength
    }
    
    /// Purges `toRelease` bytes from the table, where 'bytes' refers to the byte-count
    /// of a table entry specified in RFC 7541: [name octets] + [value octets] + 32.
    ///
    /// - parameter toRelease: The table entry length of bytes to remove from the table.
    mutating func purge(toRelease count: Int) {
        guard count < self.length else {
            // clear all the things
            self.headers.removeAll()
            self.length = 0
            return
        }
        
        var available = self.maxSize - self.length
        let needed = available + count
        while available < needed && !self.headers.isEmpty {
            available += self.purgeOne()
        }
    }
    
    @discardableResult
    private mutating func purgeOne() -> Int {
        precondition(self.headers.isEmpty == false, "should not call purgeOne() unless we have something to purge")
        // Remember: we're removing from the *end* of the header list, since we *prepend* new items there, but we're
        // removing bytes from the *start* of the storage, because we *append* there.
        let entry = self.headers.removeLast()
        self.length -= entry.length
        return entry.length
    }
    
    // internal for testing
    func dumpHeaders(offsetBy amount: Int = 0) -> String {
        return self.headers.enumerated().reduce("") {
            $0 + "\($1.0 + amount) - \($1.1.name) : \($1.1.value)\n"
        }
    }
}

extension HeaderTableStorage : CustomStringConvertible {
    @usableFromInline
    var description: String {
        var array: [(String, String)] = []
        for header in self.headers {
            array.append((header.name, header.value))
        }
        return array.description
    }
}
