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

import XCTest
import NIO
import CNIOBoringSSL
@testable import NIOSSL


final class ByteBufferBIOTest: XCTestCase {
    override func setUp() {
        guard boringSSLIsInitialized else {
            fatalError("Cannot run tests without BoringSSL")
        }
    }

    private func retainedBIO() -> UnsafeMutablePointer<BIO> {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        return swiftBIO.retainedBIO()
    }

    func testExtractingBIOWrite() throws {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        XCTAssertNil(swiftBIO.outboundCiphertext())

        var bytesToWrite: [UInt8] = [1, 2, 3, 4, 5]
        let rc = CNIOBoringSSL_BIO_write(cBIO, &bytesToWrite, 5)
        XCTAssertEqual(rc, 5)

        guard let extractedBytes = swiftBIO.outboundCiphertext().flatMap({ $0.getBytes(at: $0.readerIndex, length: $0.readableBytes) }) else {
            XCTFail("No received bytes")
            return
        }
        XCTAssertEqual(extractedBytes, bytesToWrite)
        XCTAssertNil(swiftBIO.outboundCiphertext())
    }

    func testManyBIOWritesAreCoalesced() throws {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        XCTAssertNil(swiftBIO.outboundCiphertext())

        var bytesToWrite: [UInt8] = [1, 2, 3, 4, 5]
        var expectedBytes = [UInt8]()
        for _ in 0..<10 {
            let rc = CNIOBoringSSL_BIO_write(cBIO, &bytesToWrite, 5)
            XCTAssertEqual(rc, 5)
            expectedBytes.append(contentsOf: bytesToWrite)
        }

        guard let extractedBytes = swiftBIO.outboundCiphertext().flatMap({ $0.getBytes(at: $0.readerIndex, length: $0.readableBytes) }) else {
            XCTFail("No received bytes")
            return
        }
        XCTAssertEqual(extractedBytes, expectedBytes)
        XCTAssertNil(swiftBIO.outboundCiphertext())
    }

    func testReadWithNoDataInBIO() throws {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        var targetBuffer = [UInt8](repeating: 0, count: 512)
        let rc = CNIOBoringSSL_BIO_read(cBIO, &targetBuffer, 512)
        XCTAssertEqual(rc, -1)
        XCTAssertTrue(CNIOBoringSSL_BIO_should_retry(cBIO) != 0)
        XCTAssertTrue(CNIOBoringSSL_BIO_should_read(cBIO) != 0)
        XCTAssertEqual(targetBuffer, [UInt8](repeating: 0, count: 512))
    }

    func testReadWithDataInBIO() throws {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        var inboundBytes = ByteBufferAllocator().buffer(capacity: 1024)
        inboundBytes.writeBytes([1, 2, 3, 4, 5])
        swiftBIO.receiveFromNetwork(buffer: inboundBytes)

        var receivedBytes = ByteBufferAllocator().buffer(capacity: 1024)
        let rc = receivedBytes.writeWithUnsafeMutableBytes { pointer in
            let innerRC = CNIOBoringSSL_BIO_read(cBIO, pointer.baseAddress!, CInt(pointer.count))
            XCTAssertTrue(innerRC > 0)
            return innerRC > 0 ? Int(innerRC) : 0
        }

        XCTAssertEqual(rc, 5)
        XCTAssertEqual(receivedBytes, inboundBytes)

        let secondRC = receivedBytes.withUnsafeMutableWritableBytes { pointer in
            CNIOBoringSSL_BIO_read(cBIO, pointer.baseAddress!, CInt(pointer.count))
        }
        XCTAssertEqual(secondRC, -1)
        XCTAssertTrue(CNIOBoringSSL_BIO_should_retry(cBIO) != 0)
        XCTAssertTrue(CNIOBoringSSL_BIO_should_read(cBIO) != 0)
    }

    func testShortReads() throws {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        var inboundBytes = ByteBufferAllocator().buffer(capacity: 1024)
        inboundBytes.writeBytes([1, 2, 3, 4, 5])
        swiftBIO.receiveFromNetwork(buffer: inboundBytes)

        var receivedBytes = ByteBufferAllocator().buffer(capacity: 1024)
        for _ in 0..<5 {
            let rc = receivedBytes.writeWithUnsafeMutableBytes { pointer in
                let innerRC = CNIOBoringSSL_BIO_read(cBIO, pointer.baseAddress!, 1)
                XCTAssertTrue(innerRC > 0)
                return innerRC > 0 ? Int(innerRC) : 0
            }

            XCTAssertEqual(rc, 1)
        }
        XCTAssertEqual(receivedBytes, inboundBytes)

        let secondRC = receivedBytes.withUnsafeMutableWritableBytes { pointer in
            CNIOBoringSSL_BIO_read(cBIO, pointer.baseAddress!, CInt(pointer.count))
        }
        XCTAssertEqual(secondRC, -1)
        XCTAssertTrue(CNIOBoringSSL_BIO_should_retry(cBIO) != 0)
        XCTAssertTrue(CNIOBoringSSL_BIO_should_read(cBIO) != 0)
    }

    func testDropRefToBaseObjectOnRead() throws {
        let cBIO = self.retainedBIO()
        let receivedBytes = ByteBufferAllocator().buffer(capacity: 1024)
        receivedBytes.withVeryUnsafeBytes { pointer in
            let rc = CNIOBoringSSL_BIO_read(cBIO, UnsafeMutableRawPointer(mutating: pointer.baseAddress!), 1)
            XCTAssertEqual(rc, -1)
            XCTAssertTrue(CNIOBoringSSL_BIO_should_retry(cBIO) == 0)
        }
    }

    func testDropRefToBaseObjectOnWrite() throws {
        let cBIO = self.retainedBIO()
        var receivedBytes = ByteBufferAllocator().buffer(capacity: 1024)
        receivedBytes.writeBytes([1, 2, 3, 4, 5])
        receivedBytes.withVeryUnsafeBytes { pointer in
            let rc = CNIOBoringSSL_BIO_write(cBIO, pointer.baseAddress!, 1)
            XCTAssertEqual(rc, -1)
            XCTAssertTrue(CNIOBoringSSL_BIO_should_retry(cBIO) == 0)
        }
    }

    func testZeroLengthReadsAlwaysSucceed() throws {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        var targetBuffer = [UInt8](repeating: 0, count: 512)
        let rc = CNIOBoringSSL_BIO_read(cBIO, &targetBuffer, 0)
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(targetBuffer, [UInt8](repeating: 0, count: 512))
    }

    func testWriteWhenHoldingBufferTriggersCoW() throws {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        var bytesToWrite: [UInt8] = [1, 2, 3, 4, 5]
        let rc = CNIOBoringSSL_BIO_write(cBIO, &bytesToWrite, 5)
        XCTAssertEqual(rc, 5)

        guard let firstWrite = swiftBIO.outboundCiphertext() else {
            XCTFail("Did not write")
            return
        }

        let secondRC = CNIOBoringSSL_BIO_write(cBIO, &bytesToWrite, 5)
        XCTAssertEqual(secondRC, 5)
        guard let secondWrite = swiftBIO.outboundCiphertext() else {
            XCTFail("Did not write second time")
            return
        }

        XCTAssertNotEqual(firstWrite.baseAddress(), secondWrite.baseAddress())
    }

    func testWriteWhenDroppedBufferDoesNotTriggerCoW() {
        func writeAddress(swiftBIO: ByteBufferBIO, cBIO: UnsafeMutablePointer<BIO>) -> UInt? {
            var bytesToWrite: [UInt8] = [1, 2, 3, 4, 5]
            let rc = CNIOBoringSSL_BIO_write(cBIO, &bytesToWrite, 5)
            XCTAssertEqual(rc, 5)
            return swiftBIO.outboundCiphertext()?.baseAddress()
        }

        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        let firstAddress = writeAddress(swiftBIO: swiftBIO, cBIO: cBIO)
        let secondAddress = writeAddress(swiftBIO: swiftBIO, cBIO: cBIO)
        XCTAssertNotNil(firstAddress)
        XCTAssertNotNil(secondAddress)
        XCTAssertEqual(firstAddress, secondAddress)
    }

    func testZeroLengthWriteIsNoOp() {
        // This test works by emulating testWriteWhenHoldingBufferTriggersCoW, but
        // with the second write at zero length. This will not trigger a CoW, as no
        // actual write will occur.
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        var bytesToWrite: [UInt8] = [1, 2, 3, 4, 5]
        let rc = CNIOBoringSSL_BIO_write(cBIO, &bytesToWrite, 5)
        XCTAssertEqual(rc, 5)

        guard let firstWrite = swiftBIO.outboundCiphertext() else {
            XCTFail("Did not write")
            return
        }
        withExtendedLifetime(firstWrite) {
            let secondRC = CNIOBoringSSL_BIO_write(cBIO, &bytesToWrite, 0)
            XCTAssertEqual(secondRC, 0)
            XCTAssertNil(swiftBIO.outboundCiphertext())
        }
    }

    func testSimplePuts() {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        XCTAssertNil(swiftBIO.outboundCiphertext())

        let stringToWrite = "Hello, world!"
        let rc = stringToWrite.withCString {
            CNIOBoringSSL_BIO_puts(cBIO, $0)
        }
        XCTAssertEqual(rc, 13)

        let extractedString = swiftBIO.outboundCiphertext().flatMap { $0.getString(at: $0.readerIndex, length: $0.readableBytes) }
        XCTAssertEqual(extractedString, stringToWrite)
        XCTAssertNil(swiftBIO.outboundCiphertext())
    }

    func testGetsNotSupported() {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        buffer.writeStaticString("Hello, world!")
        swiftBIO.receiveFromNetwork(buffer: buffer)

        buffer.withUnsafeMutableReadableBytes { pointer in
            let myPointer = pointer.baseAddress!.bindMemory(to: Int8.self, capacity: pointer.count)
            let rc = CNIOBoringSSL_BIO_gets(cBIO, myPointer, CInt(pointer.count))
            XCTAssertEqual(rc, -2)
            XCTAssertTrue(CNIOBoringSSL_BIO_should_retry(cBIO) == 0)
        }
    }

    func testBasicCtrlDance() {
        let swiftBIO = ByteBufferBIO(allocator: ByteBufferAllocator())
        let cBIO = swiftBIO.retainedBIO()
        defer {
            CNIOBoringSSL_BIO_free(cBIO)
        }

        let originalShutdown = CNIOBoringSSL_BIO_ctrl(cBIO, BIO_CTRL_GET_CLOSE, 0, nil)
        XCTAssertEqual(originalShutdown, CLong(BIO_CLOSE))

        let rc = CNIOBoringSSL_BIO_set_close(cBIO, CInt(BIO_NOCLOSE))
        XCTAssertEqual(rc, 1)

        let newShutdown = CNIOBoringSSL_BIO_ctrl(cBIO, BIO_CTRL_GET_CLOSE, 0, nil)
        XCTAssertEqual(newShutdown, CLong(BIO_NOCLOSE))

        let rc2 = CNIOBoringSSL_BIO_set_close(cBIO, CInt(BIO_CLOSE))
        XCTAssertEqual(rc2, 1)

        let newShutdown2 = CNIOBoringSSL_BIO_ctrl(cBIO, BIO_CTRL_GET_CLOSE, 0, nil)
        XCTAssertEqual(newShutdown2, CLong(BIO_CLOSE))
    }
}


extension ByteBuffer {
    func baseAddress() -> UInt {
        return self.withVeryUnsafeBytes { return UInt(bitPattern: $0.baseAddress! )}
    }
}
