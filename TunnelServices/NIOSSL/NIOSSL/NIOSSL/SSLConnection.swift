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
#else
import CNIOBoringSSL
#endif

internal let SSL_MAX_RECORD_SIZE = 16 * 1024

/// This is used as the application data index to store pointers to `SSLConnection` objects in
/// `SSL` objects. It is only safe to use after BoringSSL initialization. As it's declared global,
/// it will be lazily initialized and protected by a dispatch_once, ensuring that it's thread-safe.
internal let sslConnectionExDataIndex = CNIOBoringSSL_SSL_get_ex_new_index(0, nil, nil, nil, nil)

/// Encodes the return value of a non-blocking BoringSSL method call.
///
/// This enum maps BoringSSL's return values to a small number of cases. A success
/// value naturally maps to `.complete`, and most errors map to `.failed`. However,
/// the BoringSSL "errors" `WANT_READ` and `WANT_WRITE` are mapped to `.incomplete`, to
/// help distinguish them from the other error cases. This makes it easier for code to
/// handle the "must wait for more data" case by calling it out directly.
enum AsyncOperationResult<T> {
    case incomplete
    case complete(T)
    case failed(BoringSSLError)
}

/// A wrapper class that encapsulates BoringSSL's `SSL *` object.
///
/// This class represents a single TLS connection, and performs all of crypto and record
/// framing required by TLS. It also records the configuration and parent `NIOSSLContext` object
/// used to create the connection.
internal final class SSLConnection {
    private let ssl: OpaquePointer
    private let parentContext: NIOSSLContext
    private var bio: ByteBufferBIO?
    private var verificationCallback: NIOSSLVerificationCallback?
    internal var platformVerificationState: PlatformVerificationState = PlatformVerificationState()
    internal var expectedHostname: String?
    internal var role: ConnectionRole?
    internal var parentHandler: NIOSSLHandler?
    internal var eventLoop: EventLoop?

    /// Whether certificate hostnames should be validated.
    var validateHostnames: Bool {
        if case .fullVerification = parentContext.configuration.certificateVerification {
            return true
        }
        return false
    }

    init(ownedSSL: OpaquePointer, parentContext: NIOSSLContext) {
        self.ssl = ownedSSL
        self.parentContext = parentContext

        // We pass the SSL object an unowned reference to this object.
        let pointerToSelf = Unmanaged.passUnretained(self).toOpaque()
        CNIOBoringSSL_SSL_set_ex_data(self.ssl, sslConnectionExDataIndex, pointerToSelf)

        self.setRenegotiationSupport(self.parentContext.configuration.renegotiationSupport)
    }
    
    deinit {
        CNIOBoringSSL_SSL_free(ssl)
    }

    /// Configures this as a server connection.
    func setAcceptState() {
        CNIOBoringSSL_SSL_set_accept_state(ssl)
        self.role = .server
    }

    /// Configures this as a client connection.
    func setConnectState() {
        CNIOBoringSSL_SSL_set_connect_state(ssl)
        self.role = .client
    }

    func setAllocator(_ allocator: ByteBufferAllocator) {
        self.bio = ByteBufferBIO(allocator: allocator)

        // This weird dance where we pass the *exact same* pointer in to both objects is because, weirdly,
        // the BoringSSL docs claim that only one reference count will be consumed here. We therefore need to
        // avoid calling BIO_up_ref too many times.
        let bioPtr = self.bio!.retainedBIO()
        CNIOBoringSSL_SSL_set_bio(self.ssl, bioPtr, bioPtr)
    }

    /// Sets the value of the SNI extension to send to the server.
    ///
    /// This method must only be called with a hostname, not an IP address. Sending
    /// an IP address in the SNI extension is invalid, and may result in handshake
    /// failure.
    func setServerName(name: String) throws {
        CNIOBoringSSL_ERR_clear_error()
        let rc = name.withCString {
            return CNIOBoringSSL_SSL_set_tlsext_host_name(ssl, $0)
        }
        guard rc == 1 else {
            throw BoringSSLError.invalidSNIName(BoringSSLError.buildErrorStack())
        }
        self.expectedHostname = name
    }

    /// Sets the BoringSSL verification callback.
    func setVerificationCallback(_ callback: @escaping NIOSSLVerificationCallback) {
        // Store the verification callback. We need to do this to keep it alive throughout the connection.
        // We'll drop this when we're told that it's no longer needed to ensure we break the reference cycles
        // that this callback inevitably produces.
        self.verificationCallback = callback

        // We need to know what the current mode is.
        let currentMode = CNIOBoringSSL_SSL_get_verify_mode(self.ssl)
        CNIOBoringSSL_SSL_set_verify(self.ssl, currentMode) { preverify, storeContext in
            // To start out, let's grab the certificate we're operating on.
            guard let certPointer = CNIOBoringSSL_X509_STORE_CTX_get_current_cert(storeContext) else {
                preconditionFailure("Can only have verification function invoked with actual certificate: bad store \(String(describing: storeContext))")
            }
            CNIOBoringSSL_X509_up_ref(certPointer)
            let cert = NIOSSLCertificate.fromUnsafePointer(takingOwnership: certPointer)

            // Next, prepare the verification result.
            let verificationResult = NIOSSLVerificationResult(fromBoringSSLPreverify: preverify)

            // Now, grab the SSLConnection object.
            guard let ssl = CNIOBoringSSL_X509_STORE_CTX_get_ex_data(storeContext, CNIOBoringSSL_SSL_get_ex_data_X509_STORE_CTX_idx()) else {
                preconditionFailure("Unable to obtain SSL * from X509_STORE_CTX * \(String(describing: storeContext))")
            }
            guard let connectionPointer = CNIOBoringSSL_SSL_get_ex_data(OpaquePointer(ssl), sslConnectionExDataIndex) else {
                // Uh-ok, our application state is gone. Don't let this error silently pass, go bang.
                preconditionFailure("Unable to find application data from SSL * \(ssl), index \(sslConnectionExDataIndex)")
            }

            // Grab a connection
            let connection = Unmanaged<SSLConnection>.fromOpaque(connectionPointer).takeUnretainedValue()
            switch connection.verificationCallback!(verificationResult, cert) {
            case .certificateVerified:
                return 1
            case .failed:
                return 0
            }
        }
    }

    /// Sets whether renegotiation is supported.
    func setRenegotiationSupport(_ state: NIORenegotiationSupport) {
        var baseState: ssl_renegotiate_mode_t

        switch state {
        case .none:
            baseState = ssl_renegotiate_never
        case .once:
            baseState = ssl_renegotiate_once
        case .always:
            baseState = ssl_renegotiate_freely
        }

        CNIOBoringSSL_SSL_set_renegotiate_mode(self.ssl, baseState)
    }

    /// Performs hostname validation against the peer certificate using the configured server name.
    func validateHostname(address: SocketAddress) throws {
        // We want the leaf certificate.
        guard let peerCert = self.getPeerCertificate() else {
            throw NIOSSLError.noCertificateToValidate
        }

        guard try validIdentityForService(serverHostname: self.expectedHostname,
                                          socketAddress: address,
                                          leafCertificate: peerCert) else {
            throw NIOSSLError.unableToValidateCertificate
        }
    }

    /// Spins the handshake state machine and performs the next step of the handshake
    /// protocol.
    ///
    /// This method may write data into internal buffers that must be sent: call
    /// `getDataForNetwork` after this method is called. This method also consumes
    /// data from internal buffers: call `consumeDataFromNetwork` before calling this
    /// method.
    func doHandshake() -> AsyncOperationResult<CInt> {
        CNIOBoringSSL_ERR_clear_error()
        let rc = CNIOBoringSSL_SSL_do_handshake(ssl)
        
        if (rc == 1) { return .complete(rc) }
        
        let result = CNIOBoringSSL_SSL_get_error(ssl, rc)
        let error = BoringSSLError.fromSSLGetErrorResult(result)!
        
        switch error {
        case .wantRead,
             .wantWrite,
             .wantCertificateVerify:
            return .incomplete
        default:
            return .failed(error)
        }
    }

    /// Spins the shutdown state machine and performs the next step of the shutdown
    /// protocol.
    ///
    /// This method may write data into internal buffers that must be sent: call
    /// `getDataForNetwork` after this method is called. This method also consumes
    /// data from internal buffers: call `consumeDataFromNetwork` before calling this
    /// method.
    func doShutdown() -> AsyncOperationResult<CInt> {
        CNIOBoringSSL_ERR_clear_error()
        let rc = CNIOBoringSSL_SSL_shutdown(ssl)
        
        switch rc {
        case 1:
            return .complete(rc)
        case 0:
            return .incomplete
        default:
            let result = CNIOBoringSSL_SSL_get_error(ssl, rc)
            let error = BoringSSLError.fromSSLGetErrorResult(result)!
            
            switch error {
            case .wantRead,
                 .wantWrite:
                return .incomplete
            default:
                return .failed(error)
            }
        }
    }
    
    /// Given some unprocessed data from the remote peer, places it into
    /// BoringSSL's receive buffer ready for handling by BoringSSL.
    ///
    /// This method should be called whenever data is received from the remote
    /// peer. It must be immediately followed by an I/O operation, e.g. `readDataFromNetwork`
    /// or `doHandshake` or `doShutdown`.
    func consumeDataFromNetwork(_ data: ByteBuffer) {
        self.bio!.receiveFromNetwork(buffer: data)
    }

    /// Obtains some encrypted data ready for the network from BoringSSL.
    ///
    /// This call obtains only data that BoringSSL has already written into its send
    /// buffer. As a result, it should be called last, after all other operations have
    /// been performed, to allow BoringSSL to write as much data as necessary into the
    /// `BIO`.
    ///
    /// Returns `nil` if there is no data to write. Otherwise, returns all of the pending
    /// data.
    func getDataForNetwork() -> ByteBuffer? {
        return self.bio!.outboundCiphertext()
    }

    /// Attempts to decrypt any application data sent by the remote peer, and fills a buffer
    /// containing the cleartext bytes.
    ///
    /// This method can only consume data previously fed into BoringSSL in `consumeDataFromNetwork`.
    func readDataFromNetwork(outputBuffer: inout ByteBuffer) -> AsyncOperationResult<Int> {
        // TODO(cory): It would be nice to have an withUnsafeMutableWriteableBytes here, but we don't, so we
        // need to make do with writeWithUnsafeMutableBytes instead. The core issue is that we can't
        // safely return any of the error values that SSL_read might provide here because writeWithUnsafeMutableBytes
        // will try to use that as the number of bytes written and blow up. If we could prevent it doing that (which
        // we can with reading) that would be grand, but we can't, so instead we need to use a temp variable. Not ideal.
        //
        // We require that there is space to write at least one TLS record.
        var bytesRead: CInt = 0
        let rc = outputBuffer.writeWithUnsafeMutableBytes(minimumWritableBytes: SSL_MAX_RECORD_SIZE) { (pointer) -> Int in
            bytesRead = CNIOBoringSSL_SSL_read(self.ssl, pointer.baseAddress, CInt(pointer.count))
            return bytesRead >= 0 ? Int(bytesRead) : 0
        }
        
        if bytesRead > 0 {
            return .complete(rc)
        } else {
            let result = CNIOBoringSSL_SSL_get_error(ssl, CInt(bytesRead))
            let error = BoringSSLError.fromSSLGetErrorResult(result)!
            
            switch error {
            case .wantRead,
                 .wantWrite:
                return .incomplete
            default:
                return .failed(error)
            }
        }
    }

    /// Encrypts cleartext application data ready for sending on the network.
    ///
    /// This call will only write the data into BoringSSL's internal buffers. It needs to be obtained
    /// by calling `getDataForNetwork` after this call completes.
    func writeDataToNetwork(_ data: inout ByteBuffer) -> AsyncOperationResult<CInt> {
        // BoringSSL does not allow calling SSL_write with zero-length buffers. Zero-length
        // writes always succeed.
        guard data.readableBytes > 0 else {
            return .complete(0)
        }

        let writtenBytes = data.withUnsafeReadableBytes { (pointer) -> CInt in
            return CNIOBoringSSL_SSL_write(ssl, pointer.baseAddress, CInt(pointer.count))
        }
        
        if writtenBytes > 0 {
            // The default behaviour of SSL_write is to only return once *all* of the data has been written,
            // unless the underlying BIO cannot satisfy the need (in which case WANT_WRITE will be returned).
            // We're using our BIO, which is always writable, so WANT_WRITE cannot fire so we'd always
            // expect this to write the complete quantity of readable bytes in our buffer.
            precondition(writtenBytes == data.readableBytes)
            data.moveReaderIndex(forwardBy: Int(writtenBytes))
            return .complete(writtenBytes)
        } else {
            let result = CNIOBoringSSL_SSL_get_error(ssl, writtenBytes)
            let error = BoringSSLError.fromSSLGetErrorResult(result)!
            
            switch error {
            case .wantRead, .wantWrite:
                return .incomplete
            default:
                return .failed(error)
            }
        }
    }

    /// Returns the protocol negotiated via ALPN, if any. Returns `nil` if no protocol
    /// was negotiated.
    func getAlpnProtocol() -> String? {
        var protoName = UnsafePointer<UInt8>(bitPattern: 0)
        var protoLen: CUnsignedInt = 0

        CNIOBoringSSL_SSL_get0_alpn_selected(ssl, &protoName, &protoLen)
        guard protoLen > 0 else {
            return nil
        }

        return String(decoding: UnsafeBufferPointer(start: protoName, count: Int(protoLen)), as: UTF8.self)
    }

    /// Get the leaf certificate from the peer certificate chain as a managed object,
    /// if available.
    func getPeerCertificate() -> NIOSSLCertificate? {
        guard let certPtr = CNIOBoringSSL_SSL_get_peer_certificate(ssl) else {
            return nil
        }

        return NIOSSLCertificate.fromUnsafePointer(takingOwnership: certPtr)
    }

    /// Drops persistent connection state.
    ///
    /// Must only be called when the connection is no longer needed. The rest of this object
    /// preconditions on that being true, so we'll find out quickly when that's not the case.
    func close() {
        /// Drop the verification callback. This breaks any reference cycles that are inevitably
        /// created by this callback.
        self.verificationCallback = nil

        // Also drop the reference to the parent channel handler, which is a trivial reference cycle.
        self.parentHandler = nil
    }

    /// Retrieves any inbound data that has not been processed by BoringSSL.
    ///
    /// When unwrapping TLS from a connection, there may be application bytes that follow the terminating
    /// CLOSE_NOTIFY message. Those bytes may have been passed to this `SSLConnection`, and so we need to
    /// retrieve them.
    ///
    /// This function extracts those bytes and returns them to the user. This should only be called when
    /// the connection has been shutdown.
    ///
    /// - returns: The unconsumed `ByteBuffer`, if any.
    func extractUnconsumedData() -> ByteBuffer? {
        return self.bio?.evacuateInboundData()
    }
}


/// MARK: ConnectionRole
extension SSLConnection {
    internal enum ConnectionRole {
        case server
        case client
    }
}


// MARK: Certificate Peer Chain Buffers
extension SSLConnection {
    /// A collection of buffers representing the DER-encoded bytes of the peer certificate chain.
    struct PeerCertificateChainBuffers {
        private let basePointer: OpaquePointer

        fileprivate init(basePointer: OpaquePointer) {
            self.basePointer = basePointer
        }
    }

    /// Invokes a block with a collection of pointers to DER-encoded bytes of the peer certificate chain.
    ///
    /// The pointers are only guaranteed to be valid for the duration of this call: it is undefined behaviour to escape
    /// any of these pointers from the block, or the certificate iterator itself from the block. Users must either use the
    /// bytes synchronously within the block, or they must copy them to a new buffer that they own.
    ///
    /// If there are no peer certificates, the body will be called with nil.
    func withPeerCertificateChainBuffers<Result>(_ body: (PeerCertificateChainBuffers?) throws -> Result) rethrows -> Result {
        guard let stackPointer = CNIOBoringSSL_SSL_get0_peer_certificates(self.ssl) else {
            return try body(nil)
        }

        return try body(PeerCertificateChainBuffers(basePointer: stackPointer))
    }
}

extension SSLConnection.PeerCertificateChainBuffers: RandomAccessCollection {
    struct Index: Hashable, Comparable, Strideable {
        typealias Stride = Int

        fileprivate var index: Int

        fileprivate init(_ index: Int) {
            self.index = index
        }

        static func < (lhs: Index, rhs: Index) -> Bool {
            return lhs.index < rhs.index
        }

        func advanced(by n: SSLConnection.PeerCertificateChainBuffers.Index.Stride) -> SSLConnection.PeerCertificateChainBuffers.Index {
            var result = self
            result.index += n
            return result
        }

        func distance(to other: SSLConnection.PeerCertificateChainBuffers.Index) -> SSLConnection.PeerCertificateChainBuffers.Index.Stride {
            return other.index - self.index
        }
    }

    typealias Element = UnsafeRawBufferPointer

    var startIndex: Index {
        return Index(0)
    }

    var endIndex: Index {
        return Index(self.count)
    }

    var count: Int {
        return CNIOBoringSSL_sk_CRYPTO_BUFFER_num(self.basePointer)
    }

    subscript(_ index: Index) -> UnsafeRawBufferPointer {
        precondition(index < self.endIndex)
        guard let ptr = CNIOBoringSSL_sk_CRYPTO_BUFFER_value(self.basePointer, index.index) else {
            preconditionFailure("Unable to locate backing pointer.")
        }
        guard let dataPointer = CNIOBoringSSL_CRYPTO_BUFFER_data(ptr) else {
            preconditionFailure("Unable to retrieve data pointer from crypto_buffer")
        }
        let byteCount = CNIOBoringSSL_CRYPTO_BUFFER_len(ptr)

        // We want an UnsafeRawBufferPointer here, so we need to erase the pointer type.
        let bufferDataPointer = UnsafeBufferPointer(start: dataPointer, count: byteCount)
        return UnsafeRawBufferPointer(bufferDataPointer)
    }
}
