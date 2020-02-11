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

/// Wraps a single error from BoringSSL.
public struct BoringSSLInternalError: Equatable, CustomStringConvertible {
    let errorCode: UInt32

    var errorMessage: String? {
        // TODO(cory): This should become non-optional in the future, as it always succeeds.
        var scratchBuffer = [CChar](repeating: 0, count: 512)
        return scratchBuffer.withUnsafeMutableBufferPointer { pointer in
            CNIOBoringSSL_ERR_error_string_n(self.errorCode, pointer.baseAddress!, pointer.count)
            return String(cString: pointer.baseAddress!)
        }
    }

    public var description: String {
        return "Error: \(errorCode) \(errorMessage ?? "")"
    }

    init(errorCode: UInt32) {
        self.errorCode = errorCode
    }

    public static func ==(lhs: BoringSSLInternalError, rhs: BoringSSLInternalError) -> Bool {
        return lhs.errorCode == rhs.errorCode
    }

}

/// A representation of BoringSSL's internal error stack: a list of BoringSSL errors.
public typealias NIOBoringSSLErrorStack = [BoringSSLInternalError]


/// Errors that can be raised by NIO's BoringSSL wrapper.
public enum NIOSSLError: Error {
    case writeDuringTLSShutdown
    case unableToAllocateBoringSSLObject
    case noSuchFilesystemObject
    case failedToLoadCertificate
    case failedToLoadPrivateKey
    case handshakeFailed(BoringSSLError)
    case shutdownFailed(BoringSSLError)
    case cannotMatchULabel
    case noCertificateToValidate
    case unableToValidateCertificate
    case cannotFindPeerIP
    case readInInvalidTLSState
    case uncleanShutdown
}

extension NIOSSLError: Equatable {
    public static func ==(lhs: NIOSSLError, rhs: NIOSSLError) -> Bool {
        switch (lhs, rhs) {
        case (.writeDuringTLSShutdown, .writeDuringTLSShutdown),
             (.unableToAllocateBoringSSLObject, .unableToAllocateBoringSSLObject),
             (.noSuchFilesystemObject, .noSuchFilesystemObject),
             (.failedToLoadCertificate, .failedToLoadCertificate),
             (.failedToLoadPrivateKey, .failedToLoadPrivateKey),
             (.cannotMatchULabel, .cannotMatchULabel),
             (.noCertificateToValidate, .noCertificateToValidate),
             (.unableToValidateCertificate, .unableToValidateCertificate),
             (.uncleanShutdown, .uncleanShutdown):
            return true
        case (.handshakeFailed(let err1), .handshakeFailed(let err2)),
             (.shutdownFailed(let err1), .shutdownFailed(let err2)):
            return err1 == err2
        default:
            return false
        }
    }
}

/// Closing the TLS channel cleanly timed out, so it was closed uncleanly.
public struct NIOSSLCloseTimedOutError: Error {}

/// An enum that wraps individual BoringSSL errors directly.
public enum BoringSSLError: Error {
    case noError
    case zeroReturn
    case wantRead
    case wantWrite
    case wantConnect
    case wantAccept
    case wantX509Lookup
    case wantCertificateVerify
    case syscallError
    case sslError(NIOBoringSSLErrorStack)
    case unknownError(NIOBoringSSLErrorStack)
    case invalidSNIName(NIOBoringSSLErrorStack)
    case failedToSetALPN(NIOBoringSSLErrorStack)
}

extension BoringSSLError: Equatable {}

public func ==(lhs: BoringSSLError, rhs: BoringSSLError) -> Bool {
    switch (lhs, rhs) {
    case (.noError, .noError),
         (.zeroReturn, .zeroReturn),
         (.wantRead, .wantRead),
         (.wantWrite, .wantWrite),
         (.wantConnect, .wantConnect),
         (.wantAccept, .wantAccept),
         (.wantCertificateVerify, .wantCertificateVerify),
         (.wantX509Lookup, .wantX509Lookup),
         (.syscallError, .syscallError):
        return true
    case (.sslError(let e1), .sslError(let e2)),
         (.unknownError(let e1), .unknownError(let e2)):
        return e1 == e2
    default:
        return false
    }
}

internal extension BoringSSLError {
    static func fromSSLGetErrorResult(_ result: CInt) -> BoringSSLError? {
        switch result {
        case SSL_ERROR_NONE:
            return .noError
        case SSL_ERROR_ZERO_RETURN:
            return .zeroReturn
        case SSL_ERROR_WANT_READ:
            return .wantRead
        case SSL_ERROR_WANT_WRITE:
            return .wantWrite
        case SSL_ERROR_WANT_CONNECT:
            return .wantConnect
        case SSL_ERROR_WANT_ACCEPT:
            return .wantAccept
        case SSL_ERROR_WANT_CERTIFICATE_VERIFY:
            return .wantCertificateVerify
        case SSL_ERROR_WANT_X509_LOOKUP:
            return .wantX509Lookup
        case SSL_ERROR_SYSCALL:
            return .syscallError
        case SSL_ERROR_SSL:
            return .sslError(buildErrorStack())
        default:
            return .unknownError(buildErrorStack())
        }
    }
    
    static func buildErrorStack() -> NIOBoringSSLErrorStack {
        var errorStack = NIOBoringSSLErrorStack()
        
        while true {
            let errorCode = CNIOBoringSSL_ERR_get_error()
            if errorCode == 0 { break }
            errorStack.append(BoringSSLInternalError(errorCode: errorCode))
        }
        
        return errorStack
    }
}

/// Represents errors that may occur while attempting to unwrap TLS from a connection.
public enum NIOTLSUnwrappingError: Error {
    /// The TLS channel has already been closed, so it is not possible to unwrap it.
    case alreadyClosed

    /// The internal state of the handler is not able to process the unwrapping request.
    case invalidInternalState

    /// We were unwrapping the connection, but during the unwrap process a close call
    /// was made. This means the connection is now closed, not unwrapped.
    case closeRequestedDuringUnwrap

    /// This write was failed because the channel was unwrapped before it was flushed.
    case unflushedWriteOnUnwrap
}
