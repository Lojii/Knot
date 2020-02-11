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


/// Implements some simple denial of service heuristics on inbound frames.
struct DOSHeuristics {
    /// The number of "empty" (zero bytes of useful payload) DATA frames we've received since the
    /// last useful frame.
    ///
    /// We reset this count each time we see END_STREAM, or a HEADERS frame, both of which we count
    /// as doing useful work. We have a small budget for these because we want to tolerate buggy
    /// implementations that occasionally emit empty DATA frames, but don't want to drown in them.
    private var receivedEmptyDataFrames: Int

    /// The maximum number of "empty" data frames we're willing to tolerate.
    private let maximumSequentialEmptyDataFrames: Int

    internal init(maximumSequentialEmptyDataFrames: Int) {
        precondition(maximumSequentialEmptyDataFrames >= 0,
                     "maximum sequential empty data frames must be positive, got \(maximumSequentialEmptyDataFrames)")
        self.maximumSequentialEmptyDataFrames = maximumSequentialEmptyDataFrames
        self.receivedEmptyDataFrames = 0
    }
}


extension DOSHeuristics {
    mutating func process(_ frame: HTTP2Frame) throws {
        switch frame.payload {
        case .data(let payload):
            if payload.data.readableBytes == 0 {
                self.receivedEmptyDataFrames += 1
            }

            if payload.endStream {
                self.receivedEmptyDataFrames = 0
            }
        case .headers:
            self.receivedEmptyDataFrames = 0
        case .alternativeService, .goAway, .origin, .ping, .priority, .pushPromise, .rstStream, .settings, .windowUpdate:
            // Currently we don't assess these for DoS risk.
            ()
        }

        if self.receivedEmptyDataFrames > self.maximumSequentialEmptyDataFrames {
            throw NIOHTTP2Errors.ExcessiveEmptyDataFrames()
        }
    }
}
