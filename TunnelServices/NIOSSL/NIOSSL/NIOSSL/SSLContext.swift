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
#if compiler(>=5.1) && compiler(<5.2)
@_implementationOnly import CNIOBoringSSL
@_implementationOnly import CNIOBoringSSLShims
#else
import CNIOBoringSSL
import CNIOBoringSSLShims
#endif

// This is a neat trick. Swift lazily initializes module-globals based on when they're first
// used. This lets us defer BoringSSL intialization as late as possible and only do it if people
// actually create any object that uses BoringSSL.
internal var boringSSLIsInitialized: Bool = initializeBoringSSL()

internal enum FileSystemObject {
    case directory
    case file

    static internal func pathType(path: String) -> FileSystemObject? {
        var statObj = stat()
        do {
            try Posix.stat(path: path, buf: &statObj)
        } catch {
            return nil
        }

#if os(Android)
        return (statObj.st_mode & UInt32(Glibc.S_IFDIR)) != 0 ? .directory : .file
#else
        return (statObj.st_mode & S_IFDIR) != 0 ? .directory : .file
#endif
    }
}

// This bizarre extension to UnsafeBufferPointer is very useful for handling ALPN identifiers. BoringSSL
// likes to work with them in wire format, so rather than us decoding them we can just encode ours to
// the wire format and then work with them from there.
private extension UnsafeBufferPointer where Element == UInt8 {
    func locateAlpnIdentifier<T>(identifier: UnsafeBufferPointer<T>) -> (index: Int, length: Int)? where T == Element {
        precondition(identifier.count != 0)
        let targetLength = Int(identifier[0])

        var index = 0
        outerLoop: while index < self.count {
            let length = Int(self[index])
            guard index + length + 1 <= self.count else {
                // Invalid length of ALPN identifier, no match.
                return nil
            }

            guard targetLength == length else {
                index += length + 1
                continue outerLoop
            }

            for innerIndex in 1...length {
                guard identifier[innerIndex] == self[index + innerIndex] else {
                    index += length + 1
                    continue outerLoop
                }
            }

            // Found it
            return (index: index + 1, length: length)
        }
        return nil
    }
}

private func alpnCallback(ssl: OpaquePointer?,
                          out: UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
                          outlen: UnsafeMutablePointer<UInt8>?,
                          in: UnsafePointer<UInt8>?,
                          inlen: UInt32,
                          appData: UnsafeMutableRawPointer?) -> CInt {
    // Perform some sanity checks. We don't want NULL pointers around here.
    guard let ssl = ssl, let out = out, let outlen = outlen, let `in` = `in` else {
        return SSL_TLSEXT_ERR_NOACK
    }

    // We want to take the SSL pointer and extract the parent Swift object.
    let parentCtx = CNIOBoringSSL_SSL_get_SSL_CTX(ssl)!
    let parentPtr = CNIOBoringSSLShims_SSL_CTX_get_app_data(parentCtx)!
    let parentSwiftContext: NIOSSLContext = Unmanaged.fromOpaque(parentPtr).takeUnretainedValue()

    let offeredProtocols = UnsafeBufferPointer(start: `in`, count: Int(inlen))
    guard let (index, length) = parentSwiftContext.alpnSelectCallback(offeredProtocols: offeredProtocols) else {
        out.pointee = nil
        outlen.pointee = 0
        return SSL_TLSEXT_ERR_NOACK
    }

    out.pointee = `in` + index
    outlen.pointee = UInt8(length)
    return SSL_TLSEXT_ERR_OK
}

/// A wrapper class that encapsulates BoringSSL's `SSL_CTX *` object.
///
/// This class represents configuration for a collection of TLS connections, all of
/// which are expected to be broadly the same.
public final class NIOSSLContext {
    private let sslContext: OpaquePointer
    private let callbackManager: CallbackManagerProtocol?
    private var keyLogManager: KeyLogCallbackManager?
    internal let configuration: TLSConfiguration

    /// Initialize a context that will create multiple connections, all with the same
    /// configuration.
    internal init(configuration: TLSConfiguration, callbackManager: CallbackManagerProtocol?) throws {
        guard boringSSLIsInitialized else { fatalError("Failed to initialize BoringSSL") }
        guard let context = CNIOBoringSSL_SSL_CTX_new(CNIOBoringSSL_TLS_method()) else { throw NIOSSLError.unableToAllocateBoringSSLObject }

        let minTLSVersion: CInt
        switch configuration.minimumTLSVersion {
        case .tlsv13:
            minTLSVersion = TLS1_3_VERSION
        case .tlsv12:
            minTLSVersion = TLS1_2_VERSION
        case .tlsv11:
            minTLSVersion = TLS1_1_VERSION
        case .tlsv1:
            minTLSVersion = TLS1_VERSION
        }
        var returnCode = CNIOBoringSSL_SSL_CTX_set_min_proto_version(context, UInt16(minTLSVersion))
        precondition(1 == returnCode)

        let maxTLSVersion: CInt

        switch configuration.maximumTLSVersion {
        case .some(.tlsv1):
            maxTLSVersion = TLS1_VERSION
        case .some(.tlsv11):
            maxTLSVersion = TLS1_1_VERSION
        case .some(.tlsv12):
            maxTLSVersion = TLS1_2_VERSION
        case .some(.tlsv13), .none:
            // Unset defaults to TLS1.3 for now. BoringSSL's default is TLS 1.2.
            maxTLSVersion = TLS1_3_VERSION
        }
        returnCode = CNIOBoringSSL_SSL_CTX_set_max_proto_version(context, UInt16(maxTLSVersion))
        precondition(1 == returnCode)

        // Cipher suites. We just pass this straight to BoringSSL.
        returnCode = CNIOBoringSSL_SSL_CTX_set_cipher_list(context, configuration.cipherSuites)
        precondition(1 == returnCode)

        // Configure certificate validation
        try NIOSSLContext.configureCertificateValidation(context: context,
                                                      verification: configuration.certificateVerification,
                                                      trustRoots: configuration.trustRoots)

        // If we were given a certificate chain to use, load it and its associated private key. Before
        // we do, set up a passphrase callback if we need to.
        if let callbackManager = callbackManager {
            CNIOBoringSSL_SSL_CTX_set_default_passwd_cb(context, globalBoringSSLPassphraseCallback(buf:size:rwflag:u:))
            CNIOBoringSSL_SSL_CTX_set_default_passwd_cb_userdata(context, Unmanaged.passUnretained(callbackManager as AnyObject).toOpaque())
        }

        var leaf = true
        try configuration.certificateChain.forEach {
            switch $0 {
            case .file(let p):
                NIOSSLContext.useCertificateChainFile(p, context: context)
                leaf = false
            case .certificate(let cert):
                if leaf {
                    try NIOSSLContext.setLeafCertificate(cert, context: context)
                    leaf = false
                } else {
                    try NIOSSLContext.addAdditionalChainCertificate(cert, context: context)
                }
            }
        }

        if let pkey = configuration.privateKey {
            switch pkey {
            case .file(let p):
                try NIOSSLContext.usePrivateKeyFile(p, context: context)
            case .privateKey(let key):
                try NIOSSLContext.setPrivateKey(key, context: context)
            }
        }

        if configuration.applicationProtocols.count > 0 {
            try NIOSSLContext.setAlpnProtocols(configuration.encodedApplicationProtocols, context: context)
            NIOSSLContext.setAlpnCallback(context: context)
        }

        // Add a key log callback.
        if let keyLogCallback = configuration.keyLogCallback {
            self.keyLogManager = KeyLogCallbackManager(callback: keyLogCallback)
            try NIOSSLContext.setKeylogCallback(context: context)
        } else {
            self.keyLogManager = nil
        }

        self.sslContext = context
        self.configuration = configuration
        self.callbackManager = callbackManager

        // Always make it possible to get from an SSL_CTX structure back to this.
        let ptrToSelf = Unmanaged.passUnretained(self).toOpaque()
        CNIOBoringSSLShims_SSL_CTX_set_app_data(context, ptrToSelf)
    }

    /// Initialize a context that will create multiple connections, all with the same
    /// configuration.
    public convenience init(configuration: TLSConfiguration) throws {
        try self.init(configuration: configuration, callbackManager: nil)
    }

    /// Initialize a context that will create multiple connections, all with the same
    /// configuration, along with a callback that will be called when needed to decrypt any
    /// encrypted private keys.
    ///
    /// - parameters:
    ///     - configuration: The `TLSConfiguration` to use for all the connections with this
    ///         `NIOSSLContext`.
    ///     - passphraseCallback: The callback to use to decrypt any private keys used by this
    ///         `NIOSSLContext`. For more details on this parameter see the documentation for
    ///         `NIOSSLPassphraseCallback`.
    public convenience init<T: Collection>(configuration: TLSConfiguration,
                                           passphraseCallback: @escaping NIOSSLPassphraseCallback<T>) throws where T.Element == UInt8 {
        let manager = BoringSSLPassphraseCallbackManager(userCallback: passphraseCallback)
        try self.init(configuration: configuration, callbackManager: manager)
    }

    /// Create a new connection object with the configuration from this
    /// context.
    internal func createConnection() -> SSLConnection? {
        guard let ssl = CNIOBoringSSL_SSL_new(self.sslContext) else {
            return nil
        }
        return SSLConnection(ownedSSL: ssl, parentContext: self)
    }

    fileprivate func alpnSelectCallback(offeredProtocols: UnsafeBufferPointer<UInt8>) ->  (index: Int, length: Int)? {
        for possibility in configuration.encodedApplicationProtocols {
            let match = possibility.withUnsafeBufferPointer {
                offeredProtocols.locateAlpnIdentifier(identifier: $0)
            }
            if match != nil { return match }
        }

        return nil
    }

    deinit {
        CNIOBoringSSL_SSL_CTX_free(self.sslContext)
    }
}


extension NIOSSLContext {
    private static func useCertificateChainFile(_ path: String, context: OpaquePointer) {
        // TODO(cory): This shouldn't be an assert but should instead be actual error handling.
        // assert(path.isFileURL)
        let result = path.withCString { (pointer) -> CInt in
            return CNIOBoringSSL_SSL_CTX_use_certificate_chain_file(context, pointer)
        }
        
        // TODO(cory): again, some error handling would be good.
        precondition(result == 1)
    }

    private static func setLeafCertificate(_ cert: NIOSSLCertificate, context: OpaquePointer) throws {
        let rc = CNIOBoringSSL_SSL_CTX_use_certificate(context, cert.ref)
        guard rc == 1 else {
            throw NIOSSLError.failedToLoadCertificate
        }
    }
    
    private static func addAdditionalChainCertificate(_ cert: NIOSSLCertificate, context: OpaquePointer) throws {
        guard 1 == CNIOBoringSSL_SSL_CTX_add1_chain_cert(context, cert.ref) else {
            throw NIOSSLError.failedToLoadCertificate
        }
    }
    
    private static func setPrivateKey(_ key: NIOSSLPrivateKey, context: OpaquePointer) throws {
        guard 1 == CNIOBoringSSL_SSL_CTX_use_PrivateKey(context, key.ref) else {
            throw NIOSSLError.failedToLoadPrivateKey
        }
    }

    private static func usePrivateKeyFile(_ path: String, context: OpaquePointer) throws {
        let pathExtension = path.split(separator: ".").last
        let fileType: CInt
        
        switch pathExtension?.lowercased() {
        case .some("pem"):
            fileType = SSL_FILETYPE_PEM
        case .some("der"), .some("key"):
            fileType = SSL_FILETYPE_ASN1
        default:
            // TODO(cory): Again, error handling here would be good.
            fatalError("Unknown private key file type.")
        }
        
        let result = path.withCString { (pointer) -> CInt in
            return CNIOBoringSSL_SSL_CTX_use_PrivateKey_file(context, pointer, fileType)
        }
        
        guard result == 1 else {
            throw NIOSSLError.failedToLoadPrivateKey
        }
    }
    

    private static func setAlpnProtocols(_ protocols: [[UInt8]], context: OpaquePointer) throws {
        // This copy should be done infrequently, so we don't worry too much about it.
        let protoBuf = protocols.reduce([UInt8](), +)
        let rc = protoBuf.withUnsafeBufferPointer {
            CNIOBoringSSL_SSL_CTX_set_alpn_protos(context, $0.baseAddress!, CUnsignedInt($0.count))
        }

        // Annoyingly this function reverses the error convention: 0 is success, non-zero is failure.
        if rc != 0 {
            let errorStack = BoringSSLError.buildErrorStack()
            throw BoringSSLError.failedToSetALPN(errorStack)
        }
    }

    private static func setAlpnCallback(context: OpaquePointer) {
        // This extra closure here is very silly, but it exists to allow us to avoid writing down the type of the first
        // argument. Combined with the helper above, the compiler will be able to solve its way to success here.
        CNIOBoringSSL_SSL_CTX_set_alpn_select_cb(context,
                                                 { alpnCallback(ssl:  $0, out: $1, outlen: $2, in: $3, inlen: $4, appData: $5) },
                                                 nil)
    }
}


// Configuring certificate verification
extension NIOSSLContext {
    private static func configureCertificateValidation(context: OpaquePointer, verification: CertificateVerification, trustRoots: NIOSSLTrustRoots?) throws {
        // If validation is turned on, set the trust roots and turn on cert validation.
        switch verification {
        case .fullVerification, .noHostnameVerification:
            CNIOBoringSSL_SSL_CTX_set_verify(context, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, nil)

            switch trustRoots {
            case .some(.default), .none:
                try NIOSSLContext.platformDefaultConfiguration(context: context)
            case .some(.file(let f)):
                try NIOSSLContext.loadVerifyLocations(f, context: context)
            case .some(.certificates(let certs)):
                try certs.forEach { try NIOSSLContext.addRootCertificate($0, context: context) }
            }
        default:
            break
        }
    }

    private static func loadVerifyLocations(_ path: String, context: OpaquePointer) throws {
        let isDirectory: Bool
        switch FileSystemObject.pathType(path: path) {
        case .some(.directory):
            isDirectory = true
        case .some(.file):
            isDirectory = false
        case .none:
            throw NIOSSLError.noSuchFilesystemObject
        }

        let result = path.withCString { (pointer) -> CInt in
            let file = !isDirectory ? pointer : nil
            let directory = isDirectory ? pointer: nil
            return CNIOBoringSSL_SSL_CTX_load_verify_locations(context, file, directory)
        }

        if result == 0 {
            let errorStack = BoringSSLError.buildErrorStack()
            throw BoringSSLError.unknownError(errorStack)
        }
    }

    private static func addRootCertificate(_ cert: NIOSSLCertificate, context: OpaquePointer) throws {
        let store = CNIOBoringSSL_SSL_CTX_get_cert_store(context)!
        if 0 == CNIOBoringSSL_X509_STORE_add_cert(store, cert.ref) {
            throw NIOSSLError.failedToLoadCertificate
        }
    }

    private static func platformDefaultConfiguration(context: OpaquePointer) throws {
        // Platform default trust is configured differently in different places. On Darwin we invoke Security.framework in a custom callback.
        // On Linux, we use our searched heuristics to guess about where the platform trust store is.
        #if os(Linux)
        let result = rootCAFilePath.withCString { rootCAFilePointer in
            rootCADirectoryPath.withCString { rootCADirectoryPointer in
                CNIOBoringSSL_SSL_CTX_load_verify_locations(context, rootCAFilePointer, rootCADirectoryPointer)
            }
        }

        if result == 0 {
            let errorStack = BoringSSLError.buildErrorStack()
            throw BoringSSLError.unknownError(errorStack)
        }
        #elseif os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        CNIOBoringSSL_SSL_CTX_set_custom_verify(context, SSL_VERIFY_PEER, securityFrameworkCustomVerify)
        #endif
    }

    private static func setKeylogCallback(context: OpaquePointer) throws {
        CNIOBoringSSL_SSL_CTX_set_keylog_callback(context) { (ssl, linePointer) in
            guard let ssl = ssl, let linePointer = linePointer else {
                return
            }

            // We want to take the SSL pointer and extract the parent Swift object. These force-unwraps are for
            // safety: a correct NIO program can never fail to set these pointers, and if it does failing loudly is
            // more useful than failing quietly.
            let parentCtx = CNIOBoringSSL_SSL_get_SSL_CTX(ssl)!
            let parentPtr = CNIOBoringSSLShims_SSL_CTX_get_app_data(parentCtx)!
            let parentSwiftContext: NIOSSLContext = Unmanaged.fromOpaque(parentPtr).takeUnretainedValue()

            // Similarly, this force-unwrap is safe because a correct NIO program can never fail to unwrap this entry
            // either.
            parentSwiftContext.keyLogManager!.log(linePointer)
        }
    }
}

extension Optional where Wrapped == String {
    internal func withCString<Result>(_ body: (UnsafePointer<CChar>?) throws -> Result) rethrows -> Result {
        switch self {
        case .some(let s):
            return try s.withCString(body)
        case .none:
            return try body(nil)
        }
    }
}
