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

#if compiler(>=5.1) && compiler(<5.2)
@_implementationOnly import CNIOBoringSSL
#else
import CNIOBoringSSL
#endif

/// Initialize BoringSSL. Note that this function IS NOT THREAD SAFE, and so must be called inside
/// either an explicit or implicit dispatch_once.
func initializeBoringSSL() -> Bool {
    CNIOBoringSSL_CRYPTO_library_init()
    return true
}
