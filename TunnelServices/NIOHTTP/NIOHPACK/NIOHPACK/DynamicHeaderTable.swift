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

/// Implements the dynamic part of the HPACK header table, as defined in
/// [RFC 7541 § 2.3](https://httpwg.org/specs/rfc7541.html#dynamic.table).
@usableFromInline
struct DynamicHeaderTable {
    public static let defaultSize = 4096
    
    /// The actual table, with items looked up by index.
    private var storage: HeaderTableStorage
    
    /// The length of the contents of the table.
    var length: Int {
        return self.storage.length
    }
    
    /// The size to which the dynamic table may currently grow. Represents
    /// the current maximum length signaled by the peer via a table-resize
    /// value at the start of an encoded header block.
    ///
    /// - note: This value cannot exceed `self.maximumTableLength`.
    var allowedLength: Int {
        get {
            return self.storage.maxSize
        }
        set {
            self.storage.setTableSize(to: newValue)
        }
    }
    
    /// The maximum permitted size of the dynamic header table as set
    /// through a SETTINGS_HEADER_TABLE_SIZE value in a SETTINGS frame.
    var maximumTableLength: Int {
        didSet {
            if self.allowedLength > maximumTableLength {
                self.allowedLength = maximumTableLength
            }
        }
    }
    
    /// The number of items in the table.
    var count: Int {
        return self.storage.count
    }
    
    init(maximumLength: Int = DynamicHeaderTable.defaultSize) {
        self.storage = HeaderTableStorage(maxSize: maximumLength)
        self.maximumTableLength = maximumLength
        self.allowedLength = maximumLength  // until we're told otherwise, this is what we assume the other side expects.
    }
    
    /// Subscripts into the dynamic table alone, using a zero-based index.
    subscript(i: Int) -> HeaderTableEntry {
        return self.storage[i]
    }
    
    // internal for testing
    func dumpHeaders() -> String {
        return self.storage.dumpHeaders(offsetBy: StaticHeaderTable.count)
    }
    
    // internal for testing -- clears the dynamic table
    mutating func clear() {
        self.storage.purge(toRelease: self.storage.length)
    }
    
    /// Searches the table for a matching header, optionally with a particular value. If
    /// a match is found, returns the index of the item and an indication whether it contained
    /// the matching value as well.
    ///
    /// Invariants: If `value` is `nil`, result `containsValue` is `false`.
    ///
    /// - Parameters:
    ///   - name: The name of the header for which to search.
    ///   - value: Optional value for the header to find. Default is `nil`.
    /// - Returns: A tuple containing the matching index and, if a value was specified as a
    ///            parameter, an indication whether that value was also found. Returns `nil`
    ///            if no matching header name could be located.
    func findExistingHeader(named name: String, value: String?) -> (index: Int, containsValue: Bool)? {
        // looking for both name and value, but can settle for just name if no value
        // has been provided. Return the first matching name (lowest index) in that case.
        guard let value = value else {
            // no `first` on AnySequence, just `first(where:)`
            return self.storage.firstIndex(matching: name).map { ($0, false) }
        }
        
        // If we have a value, locate the index of the lowest header which contains that
        // value, but if no value matches, return the index of the lowest header with a
        // matching name alone.
        switch self.storage.closestMatch(name: name, value: value) {
        case .full(let index):
            return (index, true)
        case .partial(let index):
            return (index, false)
        case .none:
            return nil
        }
    }
    
    /// Appends a header to the table. Note that if this succeeds, the new item's index
    /// is always zero.
    ///
    /// This call may result in an empty table, as per RFC 7541 § 4.4:
    /// > "It is not an error to attempt to add an entry that is larger than the maximum size;
    /// > an attempt to add an entry larger than the maximum size causes the table to be
    /// > emptied of all existing entries and results in an empty table."
    ///
    /// - Parameters:
    ///   - name: A String representing the name of the header field.
    ///   - value: A String representing the value of the header field.
    /// - Returns: `true` if the header was added to the table, `false` if not.
    mutating func addHeader(named name: String, value: String) {
        self.storage.add(name: name, value: value)
    }
}
