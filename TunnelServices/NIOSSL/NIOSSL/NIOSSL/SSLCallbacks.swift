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

/// The result of an attempt to verify an X.509 certificate.
public enum NIOSSLVerificationResult {
    /// The certificate was successfully verified.
    case certificateVerified

    /// The certificate was not verified.
    case failed

    internal init(fromBoringSSLPreverify preverify: CInt) {
        switch preverify {
        case 1:
            self = .certificateVerified
        case 0:
            self = .failed
        default:
            preconditionFailure("Invalid preverify value: \(preverify)")
        }
    }
}

/// A custom verification callback.
///
/// This verification callback is usually called more than once per connection, as it is called once
/// per certificate in the peer's complete certificate chain (including the root CA). The calls proceed
/// from root to leaf, ending with the peer's leaf certificate. Each time it is invoked with 2 arguments:
///
/// 1. The result of the BoringSSL verification for this certificate
/// 2. The `SSLCertificate` for this level of the chain.
///
/// Please be cautious with calling out from this method. This method is always invoked on the event loop,
/// so you must not block or wait. It is not possible to return an `EventLoopFuture` from this method, as it
/// must not block or wait. Additionally, this method must take care to ensure that it does not cause any
/// ChannelHandler to recursively call back into the `NIOSSLHandler` that triggered it, as making re-entrant
/// calls into BoringSSL is not supported by SwiftNIO and leads to undefined behaviour.
///
/// In general, the only safe thing to do here is to either perform some cryptographic operations, to log,
/// or to store the `NIOSSLCertificate` somewhere for later consumption. The easiest way to be sure that the
/// `NIOSSLCertificate` is safe to consume is to wait for a user event that shows the handshake as completed,
/// or for channelInactive.
public typealias NIOSSLVerificationCallback = (NIOSSLVerificationResult, NIOSSLCertificate) -> NIOSSLVerificationResult


/// A callback that can be used to implement `SSLKEYLOGFILE` support.
///
/// Wireshark can decrypt packet captures that contain encrypted TLS connections if they have access to the
/// session keys used to perform the encryption. These keys are normally stored in a file that has a specific
/// file format. This callback is the low-level primitive that can be used to write such a file.
///
/// When set, this callback will be invoked once per secret. The provided `ByteBuffer` will contain the bytes
/// that need to be written into the file, including the newline character.
///
/// - warning: Please be aware that enabling support for `SSLKEYLOGFILE` through this callback will put the secrecy of
///     your connections at risk. You should only do so when you are confident that it will not be possible to
///     extract those secrets unnecessarily.
///
public typealias NIOSSLKeyLogCallback = (ByteBuffer) -> Void


/// An object that provides helpers for working with a NIOSSLKeyLogCallback
internal struct KeyLogCallbackManager {
    private var callback: NIOSSLKeyLogCallback

    private var scratchBuffer: ByteBuffer
}

extension KeyLogCallbackManager {
    init(callback: @escaping NIOSSLKeyLogCallback) {
        self.callback = callback

        // We need to allocate a bytebuffer into which we can write the string. Normally we wouldn't just magic
        // a ByteBufferAllocator into existence, but here it's just worthwhile doing, not least because a SSLContext doesn't
        // necessarily belong to only one Channel anyway. As for 512: it seemed a reasonable guess that 512 bytes was about as long as this
        // needed to be (most secrets won't be longer than 256 bits, which is 32 bytes, so even when base64 encoded we have loads of headroom).
        self.scratchBuffer = ByteBufferAllocator().buffer(capacity: 512)
    }
}

extension KeyLogCallbackManager {
    /// Called to log a string to the user.
    mutating func log(_ stringPointer: UnsafePointer<CChar>) {
        self.scratchBuffer.clear()

        let len = strlen(stringPointer)
        let bufferPointer = UnsafeRawBufferPointer(start: stringPointer, count: Int(len))
        self.scratchBuffer.writeBytes(bufferPointer)
        self.scratchBuffer.writeInteger(UInt8(ascii: "\n"))
        self.callback(self.scratchBuffer)
    }
}
