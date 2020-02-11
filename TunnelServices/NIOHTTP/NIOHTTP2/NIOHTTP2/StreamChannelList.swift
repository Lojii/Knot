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


/// A linked list for storing HTTP2StreamChannels.
///
/// Note that while this object *could* conform to `Sequence`, there is minimal value in doing
/// that here, as it's so single-use. If we find ourselves needing to expand on this data type
/// in future we can revisit that idea.
struct StreamChannelList {
    private var head: HTTP2StreamChannel?
    private var tail: HTTP2StreamChannel?
}

/// A node for objects stored in an intrusive linked list.
///
/// Any object that wishes to be stored in a linked list must embed one of these nodes.
struct StreamChannelListNode {
    fileprivate enum ListState {
        case inList(next: HTTP2StreamChannel?)
        case notInList
    }

    fileprivate var state: ListState = .notInList

    internal init() { }
}


extension StreamChannelList {
    /// Append an element to the linked list.
    mutating func append(_ element: HTTP2StreamChannel) {
        precondition(!element.inList)

        guard case .notInList = element.streamChannelListNode.state else {
            preconditionFailure("Appended an element already in a list")
        }

        element.streamChannelListNode.state = .inList(next: nil)

        if let tail = self.tail {
            tail.streamChannelListNode.state = .inList(next: element)
            self.tail = element
        } else {
            assert(self.head == nil)
            self.head = element
            self.tail = element
        }
    }

    mutating func removeFirst() -> HTTP2StreamChannel? {
        guard let head = self.head else {
            assert(self.tail == nil)
            return nil
        }

        guard case .inList(let next) = head.streamChannelListNode.state else {
            preconditionFailure("Popped an element not in a list")
        }

        self.head = next
        if self.head == nil {
            assert(self.tail === head)
            self.tail = nil
        }

        head.streamChannelListNode = .init()
        return head
    }

    mutating func removeAll() {
        while self.removeFirst() != nil { }
    }
}


// MARK:- IntrusiveLinkedListElement helpers.
extension HTTP2StreamChannel {
    /// Whether this element is currently in a list.
    internal var inList: Bool {
        switch self.streamChannelListNode.state {
        case .inList:
            return true
        case .notInList:
            return false
        }
    }
}
