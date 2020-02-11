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
import NIO


/// A container of a single PKCS#12 bundle.
///
/// PKCS#12 is a specification that defines an archive format for storing multiple
/// cryptographic objects together in one file. Its most common usage, and the one
/// that SwiftNIO is most interested in, is its use to bundle one or more X.509
/// certificates (`NIOSSLCertificate`) together with an associated private key
/// (`NIOSSLPrivateKey`).
///
/// ### Working with TLSConfiguration
///
/// In many cases users will want to configure a `TLSConfiguration` with the data
/// from a PKCS#12 bundle. This object assists in unpacking that bundle into its
/// associated pieces.
///
/// If you have a PKCS12 bundle, you configure a `TLSConfiguration` like this:
///
///     let p12Bundle = NIOSSLPKCS12Bundle(file: pathToMyP12)
///     let config = TLSConfiguration.forServer(certificateChain: p12Bundle.certificateChain,
///                                             privateKey: p12Bundle.privateKey)
///
/// The created `TLSConfiguration` can then be safely used for your endpoint.
public struct NIOSSLPKCS12Bundle {
    public let certificateChain: [NIOSSLCertificate]
    public let privateKey: NIOSSLPrivateKey

    private init<Bytes: Collection>(ref: OpaquePointer, passphrase: Bytes?) throws where Bytes.Element == UInt8 {
        var pkey: UnsafeMutablePointer<EVP_PKEY>? = nil
        var cert: UnsafeMutablePointer<X509>? = nil
        var caCerts: OpaquePointer? = nil

        let rc = try passphrase.withSecureCString { passphrase in
            CNIOBoringSSL_PKCS12_parse(ref, passphrase, &pkey, &cert, &caCerts)
        }
        guard rc == 1 else {
            throw BoringSSLError.unknownError(BoringSSLError.buildErrorStack())
        }

        // Successfully parsed, let's unpack. The key and cert are mandatory,
        // the ca stack is not.
        guard let actualCert = cert, let actualKey = pkey else {
            // Free the pointers that we have.
            cert.map { CNIOBoringSSL_X509_free($0) }
            pkey.map { CNIOBoringSSL_EVP_PKEY_free($0) }
            caCerts.map { CNIOBoringSSL_sk_X509_pop_free($0, CNIOBoringSSL_X509_free) }
            throw NIOSSLError.unableToAllocateBoringSSLObject
        }

        let certStackSize = caCerts.map { CNIOBoringSSL_sk_X509_num($0) } ?? 0
        var certs = [NIOSSLCertificate]()
        certs.reserveCapacity(Int(certStackSize) + 1)
        certs.append(NIOSSLCertificate.fromUnsafePointer(takingOwnership: actualCert))

        for idx in 0..<certStackSize {
            guard let stackCertPtr = CNIOBoringSSL_sk_X509_value(caCerts, idx) else {
                preconditionFailure("Unable to get cert \(idx) from stack \(String(describing: caCerts))")
            }
            certs.append(NIOSSLCertificate.fromUnsafePointer(takingOwnership: stackCertPtr))
        }

        self.certificateChain = certs
        self.privateKey = NIOSSLPrivateKey.fromUnsafePointer(takingOwnership: actualKey)

    }

    /// Create a `NIOSSLPKCS12Bundle` from the given bytes in memory,
    /// optionally decrypting the bundle with the given passphrase.
    ///
    /// - parameters:
    ///     - buffer: The bytes of the PKCS#12 bundle.
    ///     - passphrase: The passphrase used for the bundle, as a sequence of UTF-8 bytes.
    public init<Bytes: Collection>(buffer: [UInt8], passphrase: Bytes?) throws where Bytes.Element == UInt8 {
        guard boringSSLIsInitialized else { fatalError("Failed to initialize BoringSSL") }
        
        let p12 = buffer.withUnsafeBytes { pointer -> OpaquePointer? in
            let bio = CNIOBoringSSL_BIO_new_mem_buf(pointer.baseAddress, CInt(pointer.count))!
            defer {
                CNIOBoringSSL_BIO_free(bio)
            }
            return CNIOBoringSSL_d2i_PKCS12_bio(bio, nil)
        }
        defer {
            p12.map { CNIOBoringSSL_PKCS12_free($0) }
        }

        if let p12 = p12 {
            try self.init(ref: p12, passphrase: passphrase)
        } else {
            throw BoringSSLError.unknownError(BoringSSLError.buildErrorStack())
        }
    }

    /// Create a `NIOSSLPKCS12Bundle` from the given bytes on disk,
    /// optionally decrypting the bundle with the given passphrase.
    ///
    /// - parameters:
    ///     - file: The path to the PKCS#12 bundle on disk.
    ///     - passphrase: The passphrase used for the bundle, as a sequence of UTF-8 bytes.
    public init<Bytes: Collection>(file: String, passphrase: Bytes?) throws where Bytes.Element == UInt8 {
        guard boringSSLIsInitialized else { fatalError("Failed to initialize BoringSSL") }

        let fileObject = try Posix.fopen(file: file, mode: "rb")
        defer {
            fclose(fileObject)
        }

        let p12 = CNIOBoringSSL_d2i_PKCS12_fp(fileObject, nil)
        defer {
            p12.map(CNIOBoringSSL_PKCS12_free)
        }

        if let p12 = p12 {
            try self.init(ref: p12, passphrase: passphrase)
        } else {
            throw BoringSSLError.unknownError(BoringSSLError.buildErrorStack())
        }
    }

    /// Create a `NIOSSLPKCS12Bundle` from the given bytes on disk,
    /// assuming it has no passphrase.
    ///
    /// If the bundle does have a passphrase, call `init(file:passphrase:)` instead.
    ///
    /// - parameters:
    ///     - file: The path to the PKCS#12 bundle on disk.
    public init(file: String) throws {
        try self.init(file: file, passphrase: Optional<[UInt8]>.none)
    }

    /// Create a `NIOSSLPKCS12Bundle` from the given bytes in memory,
    /// assuming it has no passphrase.
    ///
    /// If the bundle does have a passphrase, call `init(buffer:passphrase:)` instead.
    ///
    /// - parameters:
    ///     - buffer: The bytes of the PKCS#12 bundle.
    public init(buffer: [UInt8]) throws {
        try self.init(buffer: buffer, passphrase: Optional<[UInt8]>.none)
    }
}


extension Collection where Element == UInt8 {
    /// Provides a contiguous copy of the bytes of this collection in a heap-allocated
    /// memory region that is locked into memory (that is, which can never be backed by a file),
    /// and which will be scrubbed and freed after use, and which is null-terminated.
    ///
    /// This method should be used when it is necessary to take a secure copy of a collection of
    /// bytes. Its implementation relies on BoringSSL directly.
    func withSecureCString<T>(_ block: (UnsafePointer<Int8>) throws -> T) throws -> T {
        // We need to allocate some memory and prevent it being swapped to disk while we use it.
        // For that reason we use mlock.
        let bufferSize = Int(self.count) + 1
        let bufferPtr = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            bufferPtr.deallocate()
        }

        try Posix.mlock(addr: bufferPtr.baseAddress!, len: bufferPtr.count)
        defer {
            // If munlock fails take out the process.
            try! Posix.munlock(addr: bufferPtr.baseAddress!, len: bufferPtr.count)
        }

        let (_, nextIndex) = bufferPtr.initialize(from: self)
        assert(nextIndex == (bufferPtr.endIndex - 1))

        // Add a null terminator.
        bufferPtr[nextIndex] = 0

        defer {
            // We use OpenSSL_cleanse here because the compiler can't optimize this away.
            // .initialize(repeating: 0) can be, and empirically is, optimized away, bzero
            // is deprecated, memset_s is not well supported cross-platform, and memset-to-zero
            // is famously easily optimised away. This is our best bet.
            CNIOBoringSSL_OPENSSL_cleanse(bufferPtr.baseAddress!, bufferPtr.count)
            bufferPtr.baseAddress!.deinitialize(count: bufferPtr.count)
        }

        // Ok, the memory is ready for use. Call the user.
        return try bufferPtr.withMemoryRebound(to: Int8.self) {
            try block($0.baseAddress!)
        }
    }
}


internal extension Optional where Wrapped: Collection, Wrapped.Element == UInt8 {
    func withSecureCString<T>(_ block: (UnsafePointer<Int8>?) throws -> T) throws -> T {
        if let `self` = self {
            return try self.withSecureCString(block)
        } else {
            return try block(nil)
        }
    }
}
