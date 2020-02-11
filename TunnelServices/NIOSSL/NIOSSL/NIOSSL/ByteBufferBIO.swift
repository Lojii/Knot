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


/// The BoringSSL entry point to write to the `ByteBufferBIO`. This thunk unwraps the user data
/// and then passes the call on to the specific BIO reference.
///
/// This specific type signature is annoying (I'd rather have UnsafeRawPointer, and rather than a separate
/// len I'd like a buffer pointer), but this interface is required because this is passed to an BoringSSL
/// function pointer and so needs to be @convention(c).
internal func boringSSLBIOWriteFunc(bio: UnsafeMutablePointer<BIO>?, buf: UnsafePointer<CChar>?, len: CInt) -> CInt {
    guard let concreteBIO = bio, let concreteBuf = buf else {
        preconditionFailure("Invalid pointers in boringSSLBIOWriteFunc: bio: \(String(describing: bio)) buf: \(String(describing: buf))")
    }

    // This unwrap may fail if the user has dropped the ref to the ByteBufferBIO but still has
    // a ref to the other pointer. Sigh heavily and just fail.
    guard let userPtr = CNIOBoringSSL_BIO_get_data(concreteBIO) else {
        return -1
    }

    // Begin by clearing retry flags. We do this at all BoringSSL entry points.
    CNIOBoringSSL_BIO_clear_retry_flags(concreteBIO)

    // In the event a write of 0 bytes has been asked for, just return early, don't bother with the other work.
    guard len > 0 else {
        return 0
    }

    let swiftBIO: ByteBufferBIO = Unmanaged.fromOpaque(userPtr).takeUnretainedValue()
    let bufferPtr = UnsafeRawBufferPointer(start: concreteBuf, count: Int(len))
    return swiftBIO.sslWrite(buffer: bufferPtr)
}

/// The BoringSSL entry point to read from the `ByteBufferBIO`. This thunk unwraps the user data
/// and then passes the call on to the specific BIO reference.
///
/// This specific type signature is annoying (I'd rather have UnsafeRawPointer, and rather than a separate
/// len I'd like a buffer pointer), but this interface is required because this is passed to an BoringSSL
/// function pointer and so needs to be @convention(c).
internal func boringSSLBIOReadFunc(bio: UnsafeMutablePointer<BIO>?, buf: UnsafeMutablePointer<CChar>?, len: CInt) -> CInt {
    guard let concreteBIO = bio, let concreteBuf = buf else {
        preconditionFailure("Invalid pointers in boringSSLBIOReadFunc: bio: \(String(describing: bio)) buf: \(String(describing: buf))")
    }

    // This unwrap may fail if the user has dropped the ref to the ByteBufferBIO but still has
    // a ref to the other pointer. Sigh heavily and just fail.
    guard let userPtr = CNIOBoringSSL_BIO_get_data(concreteBIO) else {
        return -1
    }

    // Begin by clearing retry flags. We do this at all BoringSSL entry points.
    CNIOBoringSSL_BIO_clear_retry_flags(concreteBIO)

    // In the event a read for 0 bytes has been asked for, just return early, don't bother with the other work.
    guard len > 0 else {
        return 0
    }

    let swiftBIO: ByteBufferBIO = Unmanaged.fromOpaque(userPtr).takeUnretainedValue()
    let bufferPtr = UnsafeMutableRawBufferPointer(start: concreteBuf, count: Int(len))
    return swiftBIO.sslRead(buffer: bufferPtr)
}

/// The BoringSSL entry point for `puts`. This is a silly function, so we're just going to implement it
/// in terms of write.
///
/// This specific type signature is annoying (I'd rather have UnsafeRawPointer, and rather than a separate
/// len I'd like a buffer pointer), but this interface is required because this is passed to an BoringSSL
/// function pointer and so needs to be @convention(c).
internal func boringSSLBIOPutsFunc(bio: UnsafeMutablePointer<BIO>?, buf: UnsafePointer<CChar>?) -> CInt {
    guard let concreteBIO = bio, let concreteBuf = buf else {
        preconditionFailure("Invalid pointers in boringSSLBIOPutsFunc: bio: \(String(describing: bio)) buf: \(String(describing: buf))")
    }
    return boringSSLBIOWriteFunc(bio: concreteBIO, buf: concreteBuf, len: CInt(strlen(concreteBuf)))
}

/// The BoringSSL entry point for `gets`. This is a *really* silly function and we can't implement it nicely
/// in terms of read, so we just refuse to support it.
///
/// This specific type signature is annoying (I'd rather have UnsafeRawPointer, and rather than a separate
/// len I'd like a buffer pointer), but this interface is required because this is passed to an BoringSSL
/// function pointer and so needs to be @convention(c).
internal func boringSSLBIOGetsFunc(bio: UnsafeMutablePointer<BIO>?, buf: UnsafeMutablePointer<CChar>?, len: CInt) -> CInt {
    return -2
}

/// The BoringSSL entry point for `BIO_ctrl`. We don't support most of these.
internal func boringSSLBIOCtrlFunc(bio: UnsafeMutablePointer<BIO>?, cmd: CInt, larg: CLong, parg: UnsafeMutableRawPointer?) -> CLong {
    switch cmd {
    case BIO_CTRL_GET_CLOSE:
        return CLong(CNIOBoringSSL_BIO_get_shutdown(bio))
    case BIO_CTRL_SET_CLOSE:
        CNIOBoringSSL_BIO_set_shutdown(bio, CInt(larg))
        return 1
    case BIO_CTRL_FLUSH:
        return 1
    default:
        return 0
    }
}

internal func boringSSLBIOCreateFunc(bio: UnsafeMutablePointer<BIO>?) -> CInt {
    return 1
}

internal func boringSSLBIODestroyFunc(bio: UnsafeMutablePointer<BIO>?) -> CInt {
    return 1
}


/// An BoringSSL BIO object that wraps `ByteBuffer` objects.
///
/// BoringSSL extensively uses an abstraction called `BIO` to manage its input and output
/// channels. For NIO we want a BIO that operates entirely in-memory, and it's tempting
/// to assume that BoringSSL's `BIO_s_mem` is the best choice for that. However, ultimately
/// `BIO_s_mem` is a flat memory buffer that we end up using as a staging between one
/// `ByteBuffer` of plaintext and one of ciphertext. We'd like to cut out that middleman.
///
/// For this reason, we want to create an object that implements the `BIO` abstraction
/// but which use `ByteBuffer`s to do so. This allows us to avoid unnecessary memory copies,
/// which can be a really large win.
final class ByteBufferBIO {
    /// The unsafe pointer to the BoringSSL BIO_METHOD.
    ///
    /// This is used to give BoringSSL pointers to the methods that need to be invoked when
    /// using a ByteBufferBIO. There will only ever be one value of this in a NIO program,
    /// and it will always be non-NULL. Failure to initialize this structure is fatal to
    /// the program.
    private static let boringSSLBIOMethod: UnsafeMutablePointer<BIO_METHOD> = {
        guard boringSSLIsInitialized else {
            preconditionFailure("Failed to initialize BoringSSL")
        }

        let bioType = CNIOBoringSSL_BIO_get_new_index() | BIO_TYPE_SOURCE_SINK
        guard let method = CNIOBoringSSL_BIO_meth_new(bioType, "ByteBuffer BIO") else {
            preconditionFailure("Unable to allocate new BIO_METHOD")
        }

        CNIOBoringSSL_BIO_meth_set_write(method, boringSSLBIOWriteFunc)
        CNIOBoringSSL_BIO_meth_set_read(method, boringSSLBIOReadFunc)
        CNIOBoringSSL_BIO_meth_set_puts(method, boringSSLBIOPutsFunc)
        CNIOBoringSSL_BIO_meth_set_gets(method, boringSSLBIOGetsFunc)
        CNIOBoringSSL_BIO_meth_set_ctrl(method, boringSSLBIOCtrlFunc)
        CNIOBoringSSL_BIO_meth_set_create(method, boringSSLBIOCreateFunc)
        CNIOBoringSSL_BIO_meth_set_destroy(method, boringSSLBIODestroyFunc)

        return method
    }()

    /// Pointer to the backing BoringSSL BIO object.
    ///
    /// Generally speaking BoringSSL wants to own the object initialization logic for a BIO.
    /// This doesn't work for us, because we'd like to ensure that the `ByteBufferBIO` is
    /// correctly initialized with all the state it needs. One of those bits of state is
    /// a `ByteBuffer`, which BoringSSL cannot give us, so we need to build our `ByteBufferBIO`
    /// *first* and then use that to drive `BIO` initialization.
    ///
    /// Because of this split initialization dance, we elect to initialize this data structure,
    /// and have it own building an BoringSSL `BIO` structure.
    private let bioPtr: UnsafeMutablePointer<BIO>

    /// The buffer of bytes received from the network.
    ///
    /// By default, `ByteBufferBIO` expects to pass data directly to BoringSSL whenever it
    /// is received. It is, in essence, a temporary container for a `ByteBuffer` on the
    /// read side. This provides a powerful optimisation, which is that the read buffer
    /// passed to the `NIOSSLHandler` can be re-used immediately upon receipt. Given that
    /// the `NIOSSLHandler` is almost always the first handler in the pipeline, this greatly
    /// improves the allocation profile of busy connections, which can more-easily re-use
    /// the receive buffer.
    private var inboundBuffer: ByteBuffer?

    /// The buffer of bytes to send to the network.
    ///
    /// While on the read side `ByteBufferBIO` expects to hold each bytebuffer only temporarily,
    /// on the write side we attempt to coalesce as many writes as possible. This is because a
    /// buffer can only be re-used if it is flushed to the network, and that can only happen
    /// on flush calls, so we are incentivised to write as many SSL_write calls into one buffer
    /// as possible.
    private var outboundBuffer: ByteBuffer

    /// Whether the outbound buffer should be cleared before writing.
    ///
    /// This is true only if we've flushed the buffer to the network. Rather than track an annoying
    /// boolean for this, we use a quick check on the properties of the buffer itself. This clear
    /// wants to be delayed as long as possible to maximise the possibility that it does not
    /// trigger an allocation.
    private var mustClearOutboundBuffer: Bool {
        return outboundBuffer.readerIndex == outboundBuffer.writerIndex && outboundBuffer.readerIndex > 0
    }

    init(allocator: ByteBufferAllocator) {
        // We allocate enough space for a single TLS record. We may not actually write a record that size, but we want to
        // give ourselves the option. We may also write more data than that: if we do, the ByteBuffer will just handle it.
        self.outboundBuffer = allocator.buffer(capacity: SSL_MAX_RECORD_SIZE)

        guard let bio = CNIOBoringSSL_BIO_new(ByteBufferBIO.boringSSLBIOMethod) else {
            preconditionFailure("Unable to initialize custom BIO")
        }

        // We now need to complete the BIO initialization. The BIO does not have an owned pointer
        // to us, as that would create an annoying-to-break reference cycle.
        self.bioPtr = bio
        CNIOBoringSSL_BIO_set_data(self.bioPtr, Unmanaged.passUnretained(self).toOpaque())
        CNIOBoringSSL_BIO_set_init(self.bioPtr, 1)
        CNIOBoringSSL_BIO_set_shutdown(self.bioPtr, 1)
    }

    deinit {
        // On deinit we need to drop our reference to the BIO, and also ensure that it doesn't hold any
        // pointers to this object anymore.
        CNIOBoringSSL_BIO_set_data(self.bioPtr, nil)
        CNIOBoringSSL_BIO_free(self.bioPtr)
    }

    /// Obtain an owned pointer to the backing BoringSSL BIO object.
    ///
    /// This pointer is safe to use elsewhere, as it has increased the reference to the backing
    /// `BIO`. This makes it safe to use with BoringSSL functions that require an owned reference
    /// (that is, that consume a reference count).
    ///
    /// Note that the BIO may not remain useful for long periods of time: if the `ByteBufferBIO`
    /// object that owns the BIO goes out of scope, the BIO will have its pointers invalidated
    /// and will no longer be able to send/receive data.
    internal func retainedBIO() -> UnsafeMutablePointer<BIO> {
        CNIOBoringSSL_BIO_up_ref(self.bioPtr)
        return self.bioPtr
    }


    /// Called to obtain the outbound ciphertext written by BoringSSL.
    ///
    /// This function obtains a buffer of ciphertext that needs to be written to the network. In a
    /// normal application, this should be obtained on a call to `flush`. If no bytes have been flushed
    /// to the network, then this call will return `nil` rather than an empty byte buffer, to help signal
    /// that the `write` call should be elided.
    ///
    /// - returns: A buffer of ciphertext to send to the network, or `nil` if no buffer is available.
    func outboundCiphertext() -> ByteBuffer? {
        guard self.outboundBuffer.readableBytes > 0 else {
            // No data to send.
            return nil
        }

        /// Once we return from this function, we want to account for the bytes we've handed off.
        defer {
            self.outboundBuffer.moveReaderIndex(to: self.outboundBuffer.writerIndex)
        }

        return self.outboundBuffer
    }

    /// Stores a buffer received from the network for delivery to BoringSSL.
    ///
    /// Whenever a buffer is received from the network, it is passed to the BIO via this function
    /// call. In almost all cases this BIO should be immediately consumed by BoringSSL, but in some cases
    /// it may not be. In those cases, additional calls will cause byte-by-byte copies. This should
    /// be avoided, but usually only happens during asynchronous certificate verification in the
    /// handshake.
    ///
    /// - parameters:
    ///     - buffer: The buffer of ciphertext bytes received from the network.
    func receiveFromNetwork(buffer: ByteBuffer) {
        var buffer = buffer

        if self.inboundBuffer == nil {
            self.inboundBuffer = buffer
        } else {
            self.inboundBuffer!.writeBuffer(&buffer)
        }
    }

    /// Retrieves any inbound data that has not been processed by BoringSSL.
    ///
    /// When unwrapping TLS from a connection, there may be application bytes that follow the terminating
    /// CLOSE_NOTIFY message. Those bytes may be in the buffer passed to this BIO, and so we need to
    /// retrieve them.
    ///
    /// This function extracts those bytes and returns them to the user, and drops the reference to them
    /// in this BIO.
    ///
    /// - returns: The unconsumed `ByteBuffer`, if any.
    func evacuateInboundData() -> ByteBuffer? {
        defer {
            self.inboundBuffer = nil
        }
        return self.inboundBuffer
    }

    /// BoringSSL has requested to read ciphertext bytes from the network.
    ///
    /// This function is invoked whenever BoringSSL is looking to read data.
    ///
    /// - parameters:
    ///     - buffer: The buffer for NIO to copy bytes into.
    /// - returns: The number of bytes we have copied.
    fileprivate func sslRead(buffer: UnsafeMutableRawBufferPointer) -> CInt {
        guard var inboundBuffer = self.inboundBuffer else {
            // We have no bytes to read. Mark this as "needs read retry".
            CNIOBoringSSL_BIO_set_retry_read(self.bioPtr)
            return -1
        }

        let bytesToCopy = min(buffer.count, inboundBuffer.readableBytes)
        _ = inboundBuffer.readWithUnsafeReadableBytes { bytePointer in
            assert(bytePointer.count >= bytesToCopy, "Copying more bytes (\(bytesToCopy)) than fits in readable bytes \((bytePointer.count))")
            assert(buffer.count >= bytesToCopy, "Copying more bytes (\(bytesToCopy) than contained in source buffer (\(buffer.count))")
            buffer.baseAddress!.copyMemory(from: bytePointer.baseAddress!, byteCount: bytesToCopy)
            return bytesToCopy
        }

        // If we have read all the bytes from the inbound buffer, nil it out.
        if inboundBuffer.readableBytes > 0 {
            self.inboundBuffer = inboundBuffer
        } else {
            self.inboundBuffer = nil
        }

        return CInt(bytesToCopy)
    }

    /// BoringSSL has requested to write ciphertext bytes from the network.
    ///
    /// - parameters:
    ///     - buffer: The buffer for NIO to copy bytes from.
    /// - returns: The number of bytes we have copied.
    fileprivate func sslWrite(buffer: UnsafeRawBufferPointer) -> CInt {
        if self.mustClearOutboundBuffer {
            // We just flushed, and this is a new write. Let's clear the buffer now.
            self.outboundBuffer.clear()
            assert(!self.mustClearOutboundBuffer)
        }

        let writtenBytes = self.outboundBuffer.writeBytes(buffer)
        return CInt(writtenBytes)
    }
}
