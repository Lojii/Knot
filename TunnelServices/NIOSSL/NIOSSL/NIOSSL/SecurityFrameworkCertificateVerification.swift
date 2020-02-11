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

/// The current state of the platform verification helper, if one is in use.
///
/// Only used on Apple platforms currently.
internal struct PlatformVerificationState {
    #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    fileprivate var state: SecurityFrameworkVerificationState? = nil
    #endif
}

// We can only use Security.framework to validate TLS certificates on Apple platforms.
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Dispatch
import Foundation
import Security

/// A custom certificate verification function for BoringSSL that uses Security.framework to provide certificate verification.
///
/// - parameters:
///     - ssl: The pointer to the SSL * object for this connection.
///     - outAlert: A C-style inout parameter that contains a pointer to an alert. Is assumed to be non-null.
internal func securityFrameworkCustomVerify(_ ssl: OpaquePointer?, _ outAlert: UnsafeMutablePointer<UInt8>?) -> ssl_verify_result_t {
    guard let unwrappedSSL = ssl, let unwrappedOutAlert = outAlert else {
        preconditionFailure("Unexpected null pointer in custom verification callback. ssl: \(String(describing: ssl)) outAlert: \(String(describing: outAlert))")
    }

    // Ok, this call may be a resumption of a previous negotiation. We need to check if our connection object has a pre-existing verifiation state.
    guard let connectionPointer = CNIOBoringSSL_SSL_get_ex_data(unwrappedSSL, sslConnectionExDataIndex) else {
        // Uh-ok, our application state is gone. Don't let this error silently pass, go bang.
        preconditionFailure("Unable to find application data from SSL * \(unwrappedSSL), index \(sslConnectionExDataIndex)")
    }

    let connection = Unmanaged<SSLConnection>.fromOpaque(connectionPointer).takeUnretainedValue()

    do {
        return try connection.performSecurityFrameworkValidation()
    } catch {
        unwrappedOutAlert.pointee = UInt8(SSL_AD_INTERNAL_ERROR)
        return ssl_verify_invalid
    }
}

extension PlatformVerificationState {
    fileprivate enum SecurityFrameworkVerificationState {
        case pendingResult

        case complete(SecTrustResultType)
    }
}

extension SSLConnection {
    func performSecurityFrameworkValidation() throws -> ssl_verify_result_t {
        // First, check whether we have an outstanding or completed query. If we do, don't do any other work.
        switch self.platformVerificationState.state {
        case .some(.complete(.proceed)), .some(.complete(.unspecified)):
            // These two cases mean we have successfully validated the certificate. We're done! Wipe out the state so
            // that if we need to reverify we can, and return the success.
            self.platformVerificationState.state = nil
            return ssl_verify_ok
        case .some(.complete):
            // Ok, this broader case means we failed. We're still done, but return the failure instead.
            self.platformVerificationState.state = nil
            return ssl_verify_invalid
        case .some(.pendingResult):
            // We've got a validation attempt outstanding. Tell BoringSSL to hold its horses.
            return ssl_verify_retry
        case .none:
            // No verification outstanding: do more work.
            break
        }

        // Ok, time to kick off a validation. Let's get some certificate buffers.
        let certificates: [SecCertificate] = try self.withPeerCertificateChainBuffers { buffers in
            guard let buffers = buffers else {
                throw NIOSSLError.unableToValidateCertificate
            }

            return try buffers.map { buffer in
                let data = Data(bytes: buffer.baseAddress!, count: buffer.count)
                guard let cert = SecCertificateCreateWithData(nil, data as CFData) else {
                    throw NIOSSLError.unableToValidateCertificate
                }
                return cert
            }
        }

        // This force-unwrap is safe as we must have decided if we're a client or a server before validation.
        var trust: SecTrust? = nil
        var result: OSStatus
        let policy = SecPolicyCreateSSL(self.role! == .client, self.expectedHostname as CFString?)
        result = SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust)
        guard result == errSecSuccess, let actualTrust = trust else {
            throw NIOSSLError.unableToValidateCertificate
        }

        // We create a DispatchQueue here to be called back on, as this validation may perform network activity.
        let callbackQueue = DispatchQueue(label: "io.swiftnio.ssl.validationCallbackQueue")

        // Now we need to grab some things we need in the callback block. Specifically, we need the parent handler
        // and the event loop it belongs to. This is because we cannot safely access these things from inside the
        // block, and we need the eventLoop to get back onto a safe thread.
        //
        // We don't hold these references weak because we are ok with keeping the handler alive longer than necessary
        // in the rare case that the handler is removed before the callback completes.
        // The force-unwrap is safe, as we cannot be midway through handshaking before the connection has become active.
        let eventLoop = self.eventLoop!

        result = SecTrustEvaluateAsync(actualTrust, callbackQueue) { (_, result) in
            // When we complete here we need to set our result state, and then ask to respin certificate verification.
            // If we can't respin verification because we've dropped the parent handler, that's fine, no harm no foul.
            eventLoop.execute {
                self.platformVerificationState.state = .complete(result)
                self.parentHandler?.asynchronousCertificateVerificationComplete()
            }
        }

        guard result == errSecSuccess else {
            throw NIOSSLError.unableToValidateCertificate
        }

        return ssl_verify_retry
    }
}

#endif
