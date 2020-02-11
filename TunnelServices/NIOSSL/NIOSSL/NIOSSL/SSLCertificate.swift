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

//#if compiler(>=5.1) && compiler(<5.2)
//@_implementationOnly import CNIOBoringSSL
//@_implementationOnly import CNIOBoringSSLShims
//#else
import CNIOBoringSSL
import CNIOBoringSSLShims
//#endif
import NIO

/// A reference to a BoringSSL Certificate object (`X509 *`).
///
/// This thin wrapper class allows us to use ARC to automatically manage
/// the memory associated with this TLS certificate. That ensures that BoringSSL
/// will not free the underlying buffer until we are done with the certificate.
///
/// This class also provides several convenience constructors that allow users
/// to obtain an in-memory representation of a TLS certificate from a buffer of
/// bytes or from a file path.
public class NIOSSLCertificate {
    public let _ref: UnsafeMutableRawPointer/*<X509>*/

    internal var ref: UnsafeMutablePointer<X509> {
        return self._ref.assumingMemoryBound(to: X509.self)
    }

    internal enum AlternativeName {
        case dnsName([UInt8])
        case ipAddress(IPAddress)
    }

    internal enum IPAddress {
        case ipv4(in_addr)
        case ipv6(in6_addr)
    }

    private init(withReference ref: UnsafeMutablePointer<X509>) {
        self._ref = UnsafeMutableRawPointer(ref) // erasing the type for @_implementationOnly import CNIOBoringSSL
    }

    /// Create a NIOSSLCertificate from a file at a given path in either PEM or
    /// DER format.
    ///
    /// Note that this method will only ever load the first certificate from a given file.
    public convenience init(file: String, format: NIOSSLSerializationFormats) throws {
        let fileObject = try Posix.fopen(file: file, mode: "rb")
        defer {
            fclose(fileObject)
        }

        let x509: UnsafeMutablePointer<X509>?
        switch format {
        case .pem:
            x509 = CNIOBoringSSL_PEM_read_X509(fileObject, nil, nil, nil)
        case .der:
            x509 = CNIOBoringSSL_d2i_X509_fp(fileObject, nil)
        }

        if x509 == nil {
            throw NIOSSLError.failedToLoadCertificate
        }

        self.init(withReference: x509!)
    }

    /// Create a NIOSSLCertificate from a buffer of bytes in either PEM or
    /// DER format.
    ///
    /// - SeeAlso: `NIOSSLCertificate.init(bytes:format:)`
    @available(*, deprecated, renamed: "NIOSSLCertificate.init(bytes:format:)")
    public convenience init(buffer: [Int8], format: NIOSSLSerializationFormats) throws  {
        try self.init(bytes: buffer.map(UInt8.init), format: format)
    }

    /// Create a NIOSSLCertificate from a buffer of bytes in either PEM or
    /// DER format.
    public convenience init(bytes: [UInt8], format: NIOSSLSerializationFormats) throws {
        let ref = bytes.withUnsafeBytes { (ptr) -> UnsafeMutablePointer<X509>? in
            let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress, CInt(ptr.count))!

            defer {
                CNIOBoringSSL_BIO_free(bio)
            }

            switch format {
            case .pem:
                return CNIOBoringSSL_PEM_read_bio_X509(bio, nil, nil, nil)
            case .der:
                return CNIOBoringSSL_d2i_X509_bio(bio, nil)
            }
        }

        if ref == nil {
            throw NIOSSLError.failedToLoadCertificate
        }

        self.init(withReference: ref!)
    }

    /// Create a NIOSSLCertificate wrapping a pointer into BoringSSL.
    ///
    /// This is a function that should be avoided as much as possible because it plays poorly with
    /// BoringSSL's reference-counted memory. This function does not increment the reference count for the `X509`
    /// object here, nor does it duplicate it: it just takes ownership of the copy here. This object
    /// **will** deallocate the underlying `X509` object when deinited, and so if you need to keep that
    /// `X509` object alive you should call `X509_dup` before passing the pointer here.
    ///
    /// In general, however, this function should be avoided in favour of one of the convenience
    /// initializers, which ensure that the lifetime of the `X509` object is better-managed.
    public static func fromUnsafePointer(takingOwnership pointer: UnsafeMutablePointer<X509>) -> NIOSSLCertificate {
        return NIOSSLCertificate(withReference: pointer)
    }

    /// Get a sequence of the alternative names in the certificate.
    internal func subjectAlternativeNames() -> SubjectAltNameSequence? {
        guard let sanExtension = CNIOBoringSSL_X509_get_ext_d2i(self.ref, NID_subject_alt_name, nil, nil) else {
            return nil
        }
        return SubjectAltNameSequence(nameStack: OpaquePointer(sanExtension))
    }

    /// Returns the commonName field in the Subject of this certificate.
    ///
    /// It is technically possible to have multiple common names in a certificate. As the primary
    /// purpose of this field in SwiftNIO is to validate TLS certificates, we only ever return
    /// the *most significant* (i.e. last) instance of commonName in the subject.
    internal func commonName() -> [UInt8]? {
        // No subject name is unexpected, but it gives us an easy time of handling this at least.
        guard let subjectName = CNIOBoringSSL_X509_get_subject_name(self.ref) else {
            return nil
        }

        // Per the man page, to find the first entry we set lastIndex to -1. When there are no
        // more entries, -1 is returned as the index of the next entry.
        var lastIndex: CInt = -1
        var nextIndex: CInt = -1
        repeat {
            lastIndex = nextIndex
            nextIndex = CNIOBoringSSL_X509_NAME_get_index_by_NID(subjectName, NID_commonName, lastIndex)
        } while nextIndex >= 0

        // It's totally allowed to have no commonName.
        guard lastIndex >= 0 else {
            return nil
        }

        // This is very unlikely, but it could happen.
        guard let nameData = CNIOBoringSSL_X509_NAME_ENTRY_get_data(CNIOBoringSSL_X509_NAME_get_entry(subjectName, lastIndex)) else {
            return nil
        }

        // Cool, we have the name. Let's have BoringSSL give it to us in UTF-8 form and then put those bytes
        // into our own array.
        var encodedName: UnsafeMutablePointer<UInt8>? = nil
        let stringLength = CNIOBoringSSL_ASN1_STRING_to_UTF8(&encodedName, nameData)

        guard let namePtr = encodedName else {
            return nil
        }

        let arr = [UInt8](UnsafeBufferPointer(start: namePtr, count: Int(stringLength)))
        CNIOBoringSSL_OPENSSL_free(namePtr)
        return arr
    }

    deinit {
        CNIOBoringSSL_X509_free(ref)
    }
}

// MARK:- Utility Functions
// We don't really want to get too far down the road of providing helpers for things like certificates
// and private keys: this is really the domain of alternative cryptography libraries. However, to
// enable users of swift-nio-ssl to use other cryptography libraries it will be helpful to provide
// the ability to obtain the bytes that correspond to certificates and keys.
extension NIOSSLCertificate {
    /// Obtain the public key for this `NIOSSLCertificate`.
    ///
    /// - returns: This certificate's `NIOSSLPublicKey`.
    /// - throws: If an error is encountered extracting the key.
    public func extractPublicKey() throws -> NIOSSLPublicKey {
        guard let key = CNIOBoringSSL_X509_get_pubkey(self.ref) else {
            throw NIOSSLError.unableToAllocateBoringSSLObject
        }

        return NIOSSLPublicKey.fromInternalPointer(takingOwnership: key)
    }

    /// Create an array of `NIOSSLCertificate`s from a buffer of bytes in PEM format.
    ///
    /// - Parameter buffer: The PEM buffer to read certificates from.
    /// - Throws: If an error is encountered while reading certificates.
    /// - SeeAlso: `NIOSSLCertificate.fromPEMBytes(_:)`
    @available(*, deprecated, renamed: "NIOSSLCertificate.fromPEMBytes(_:)")
    public class func fromPEMBuffer(_ buffer: [Int8]) throws -> [NIOSSLCertificate] {
        return try fromPEMBytes(buffer.map(UInt8.init))
    }

    /// Create an array of `NIOSSLCertificate`s from a buffer of bytes in PEM format.
    ///
    /// - Parameter bytes: The PEM buffer to read certificates from.
    /// - Throws: If an error is encountered while reading certificates.
    public class func fromPEMBytes(_ bytes: [UInt8]) throws -> [NIOSSLCertificate] {
        CNIOBoringSSL_ERR_clear_error()
        defer {
            CNIOBoringSSL_ERR_clear_error()
        }

        return try bytes.withUnsafeBytes { (ptr) -> [NIOSSLCertificate] in
            let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress, CInt(ptr.count))!
            defer {
                CNIOBoringSSL_BIO_free(bio)
            }

            return try readCertificatesFromBIO(bio)
        }
    }

    /// Create an array of `NIOSSLCertificate`s from a file at a given path in PEM format.
    ///
    /// - Parameter file: The PEM file to read certificates from.
    /// - Throws: If an error is encountered while reading certificates.
    public class func fromPEMFile(_ path: String) throws -> [NIOSSLCertificate] {
        CNIOBoringSSL_ERR_clear_error()
        defer {
            CNIOBoringSSL_ERR_clear_error()
        }

        guard let bio = CNIOBoringSSL_BIO_new(CNIOBoringSSL_BIO_s_file()) else {
            throw NIOSSLError.unableToAllocateBoringSSLObject
        }
        defer {
            CNIOBoringSSL_BIO_free(bio)
        }

        guard CNIOBoringSSL_BIO_read_filename(bio, path) > 0 else {
            throw NIOSSLError.failedToLoadCertificate
        }

        return try readCertificatesFromBIO(bio)
    }

    /// Reads `NIOSSLCertificate`s from the given BIO.
    private class func readCertificatesFromBIO(_ bio: UnsafeMutablePointer<BIO>) throws -> [NIOSSLCertificate] {
        guard let x509 = CNIOBoringSSL_PEM_read_bio_X509_AUX(bio, nil, nil, nil) else {
            throw NIOSSLError.failedToLoadCertificate
        }

        var certificates = [NIOSSLCertificate(withReference: x509)]

        while let x = CNIOBoringSSL_PEM_read_bio_X509(bio, nil, nil, nil) {
            certificates.append(.init(withReference: x))
        }

        let err = CNIOBoringSSL_ERR_peek_error()

        // If we hit the end of the file then it's not a real error, we just read as much as we could.
        if CNIOBoringSSLShims_ERR_GET_LIB(err) == ERR_LIB_PEM && CNIOBoringSSLShims_ERR_GET_REASON(err) == PEM_R_NO_START_LINE {
            CNIOBoringSSL_ERR_clear_error()
        } else {
            throw NIOSSLError.failedToLoadCertificate
        }

        return certificates
    }
}

extension NIOSSLCertificate: Equatable {
    public static func ==(lhs: NIOSSLCertificate, rhs: NIOSSLCertificate) -> Bool {
        return CNIOBoringSSL_X509_cmp(lhs.ref, rhs.ref) == 0
    }
}

/// A helper sequence object that enables us to represent subject alternative names
/// as an iterable Swift sequence.
internal class SubjectAltNameSequence: Sequence, IteratorProtocol {
    typealias Element = NIOSSLCertificate.AlternativeName

    private let nameStack: OpaquePointer
    private var nextIdx: Int
    private let stackSize: Int

    init(nameStack: OpaquePointer) {
        self.nameStack = nameStack
        self.stackSize = CNIOBoringSSLShims_sk_GENERAL_NAME_num(nameStack)
        self.nextIdx = 0
    }

    private func addressFromBytes(bytes: UnsafeBufferPointer<UInt8>) -> NIOSSLCertificate.IPAddress? {
        switch bytes.count {
        case 4:
            let addr = bytes.baseAddress?.withMemoryRebound(to: in_addr.self, capacity: 1) {
                return $0.pointee
            }
            guard let innerAddr = addr else {
                return nil
            }
            return .ipv4(innerAddr)
        case 16:
            let addr = bytes.baseAddress?.withMemoryRebound(to: in6_addr.self, capacity: 1) {
                return $0.pointee
            }
            guard let innerAddr = addr else {
                return nil
            }
            return .ipv6(innerAddr)
        default:
            return nil
        }
    }

    func next() -> NIOSSLCertificate.AlternativeName? {
        guard self.nextIdx < self.stackSize else {
            return nil
        }

        guard let name = CNIOBoringSSLShims_sk_GENERAL_NAME_value(self.nameStack, self.nextIdx) else {
            fatalError("Unexpected null pointer when unwrapping SAN value")
        }

        self.nextIdx += 1

        switch name.pointee.type {
        case GEN_DNS:
            let namePtr = UnsafeBufferPointer(start: CNIOBoringSSL_ASN1_STRING_get0_data(name.pointee.d.ia5),
                                              count: Int(CNIOBoringSSL_ASN1_STRING_length(name.pointee.d.ia5)))
            let nameString = [UInt8](namePtr)
            return .dnsName(nameString)
        case GEN_IPADD:
            let addrPtr = UnsafeBufferPointer(start: CNIOBoringSSL_ASN1_STRING_get0_data(name.pointee.d.ia5),
                                              count: Int(CNIOBoringSSL_ASN1_STRING_length(name.pointee.d.ia5)))
            guard let addr = addressFromBytes(bytes: addrPtr) else {
                // This should throw, but we can't throw from next(). Skip this instead.
                return self.next()
            }
            return .ipAddress(addr)
        default:
            // We don't recognise this name type. Skip it.
            return next()
        }
    }

    deinit {
        CNIOBoringSSL_GENERAL_NAMES_free(self.nameStack)
    }
}
