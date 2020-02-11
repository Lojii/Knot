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

/// An `NIOSSLPublicKey` is an abstract handle to a public key owned by BoringSSL.
///
/// This object is of minimal utility, as it cannot be used for very many operations
/// in `NIOSSL`. Its primary purpose is to allow extracting public keys from
/// `NIOSSLCertificate` objects to be serialized, so that they can be passed to
/// general-purpose cryptography libraries.
public class NIOSSLPublicKey {
    private let _ref: UnsafeMutableRawPointer /*<EVP_PKEY>*/

    private var ref: UnsafeMutablePointer<EVP_PKEY> {
        return self._ref.assumingMemoryBound(to: EVP_PKEY.self)
    }

    fileprivate init(withOwnedReference ref: UnsafeMutablePointer<EVP_PKEY>) {
        self._ref = UnsafeMutableRawPointer(ref) // erasing the type for @_implementationOnly import CNIOBoringSSL
    }

    deinit {
        CNIOBoringSSL_EVP_PKEY_free(self.ref)
    }
}

// MARK:- Helpful initializers
extension NIOSSLPublicKey {
    /// Create an `NIOSSLPublicKey` object from an internal `EVP_PKEY` pointer.
    ///
    /// This method expects `pointer` to be passed at +1, and consumes that reference.
    ///
    /// - parameters:
    ///    - pointer: A pointer to an `EVP_PKEY` structure containing the public key.
    /// - returns: An `NIOSSLPublicKey` wrapping the pointer.
    internal static func fromInternalPointer(takingOwnership pointer: UnsafeMutablePointer<EVP_PKEY>) -> NIOSSLPublicKey {
        return NIOSSLPublicKey(withOwnedReference: pointer)
    }
}

extension NIOSSLPublicKey {
    /// Extracts the bytes of this public key in the SubjectPublicKeyInfo format.
    ///
    /// The SubjectPublicKeyInfo format is defined in RFC 5280. In addition to the raw key bytes, it also
    /// provides an identifier of the algorithm, ensuring that the key can be unambiguously decoded.
    ///
    /// - returns: The DER-encoded SubjectPublicKeyInfo bytes for this public key.
    /// - throws: If an error occurred while serializing the key.
    public func toSPKIBytes() throws -> [UInt8] {
        guard let bio = CNIOBoringSSL_BIO_new(CNIOBoringSSL_BIO_s_mem()) else {
            throw NIOSSLError.unableToAllocateBoringSSLObject
        }

        defer {
            CNIOBoringSSL_BIO_free(bio)
        }

        let rc = CNIOBoringSSL_i2d_PUBKEY_bio(bio, self.ref)
        guard rc == 1 else {
            let errorStack = BoringSSLError.buildErrorStack()
            throw BoringSSLError.unknownError(errorStack)
        }

        var dataPtr: UnsafeMutablePointer<CChar>? = nil
        let length = CNIOBoringSSL_BIO_get_mem_data(bio, &dataPtr)

        guard let bytes = dataPtr.map({ UnsafeMutableRawBufferPointer(start: $0, count: length) }) else {
            throw NIOSSLError.unableToAllocateBoringSSLObject
        }

        return Array(bytes)
    }
}
