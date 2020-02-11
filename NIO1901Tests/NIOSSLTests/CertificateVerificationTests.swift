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

import XCTest
import NIO
@testable import NIOSSL

final class CertificateVerificationTests: XCTestCase {
    func testCanFindCAFileOnLinux() {
        // This test only runs on Linux
        #if os(Linux)
            // A valid Linux system means we can find a CA file.
            XCTAssertNotNil(rootCAFilePath)
        #endif
    }
}
