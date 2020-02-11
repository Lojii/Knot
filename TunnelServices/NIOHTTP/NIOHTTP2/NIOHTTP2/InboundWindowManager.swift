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

/// A simple structure that managse an inbound flow control window.
///
/// For now, this just aims to emit window update frames whenever the flow control window drops below a certain size. It's very naive.
/// We'll worry about the rest of it later.
struct InboundWindowManager {
    private var targetWindowSize: Int32

    // The last window size we were told about. Used when we get changes to SETTINGS_INITIAL_WINDOW_SIZE.
    private var lastWindowSize: Int?

    init(targetSize: Int32) {
        assert(targetSize <= HTTP2FlowControlWindow.maxSize)
        assert(targetSize >= 0)

        self.targetWindowSize = targetSize
    }

    mutating func newWindowSize(_ newSize: Int) -> Int? {
        self.lastWindowSize = newSize

        // All math here happens on 64-bit ints, as it avoids overflow problems.

        // The simplest case is where newSize >= targetWindowSize. In that case, we do nothing.
        // The next simplest case is where 0 <= newSize < targetWindowSize. In that case, if targetWindowSize >= newSize * 2, we update to full size.
        // The other case is where newSize is negative. This can happen. In those cases, we want to increment by Int32.max or the total distance between
        // newSize and targetWindowSize, whichever is *smaller*. This ensures the result fits into Int32.
        if newSize >= targetWindowSize {
            return nil
        } else if newSize >= 0 {
            let increment = self.targetWindowSize - Int32(newSize)
            if increment >= newSize {
                return Int(increment)
            } else {
                return nil
            }
        } else {
            // All math in here happens on 64-bit ints to avoid overflow issues.
            let newSize = Int64(newSize)
            let targetWindowSize = Int64(self.targetWindowSize)

            let increment = min(abs(newSize) + targetWindowSize, Int64(Int32.max))
            return Int(increment)
        }
    }

    mutating func initialWindowSizeChanged(delta: Int) -> Int? {
        self.targetWindowSize += Int32(delta)

        if let lastWindowSize = self.lastWindowSize {
            // The delta applies to the current window size as well.
            return self.newWindowSize(lastWindowSize + delta)
        } else {
            return nil
        }
    }
}
