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
@testable import NIOSSL

func connectInMemory(client: EmbeddedChannel, server: EmbeddedChannel) throws {
    let addr = try assertNoThrowWithValue(SocketAddress(unixDomainSocketPath: "/tmp/whatever2"))
    let connectFuture = client.connect(to: addr)
    server.pipeline.fireChannelActive()
    XCTAssertNoThrow(try interactInMemory(clientChannel: client, serverChannel: server))
    XCTAssertNoThrow(try connectFuture.wait())
}

extension ChannelPipeline {
    func assertContains(handler: ChannelHandler, file: StaticString = #file, line: UInt = #line) {
        do {
            _ = try self.context(handler: handler).wait()
        } catch {
            XCTFail("Handler \(handler) missing from \(self)", file: file, line: line)
        }
    }

    func assertDoesNotContain(handler: ChannelHandler, file: StaticString = #file, line: UInt = #line) {
        do {
            _ = try self.context(handler: handler).wait()
            XCTFail("Handler \(handler) present in \(self)", file: file, line: line)
        } catch {
            // Expected
        }
    }
}

final class UnwrappingTests: XCTestCase {
    static var cert: NIOSSLCertificate!
    static var key: NIOSSLPrivateKey!
    static var encryptedKeyPath: String!

    override class func setUp() {
        super.setUp()
        guard boringSSLIsInitialized else { fatalError() }
        let (cert, key) = generateSelfSignedCert()
        NIOSSLIntegrationTest.cert = cert
        NIOSSLIntegrationTest.key = key
    }

    override class func tearDown() {
        _ = unlink(NIOSSLIntegrationTest.encryptedKeyPath)
    }

    private func configuredSSLContext(file: StaticString = #file, line: UInt = #line) throws -> NIOSSLContext {
        let config = TLSConfiguration.forServer(certificateChain: [.certificate(NIOSSLIntegrationTest.cert)],
                                                privateKey: .privateKey(NIOSSLIntegrationTest.key),
                                                trustRoots: .certificates([NIOSSLIntegrationTest.cert]))
        return try assertNoThrowWithValue(NIOSSLContext(configuration: config), file: file, line: line)
    }

    func testSimpleUnwrapping() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var clientClosed = false
        var serverClosed = false
        var unwrapped = false

        defer {
            // We expect the server case to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertNoThrow(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Mark the closure of the channels.
        clientChannel.closeFuture.whenComplete { _ in
            clientClosed = true
        }
        serverChannel.closeFuture.whenComplete { _ in
            serverClosed = true
        }

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection. With no additional configuration, this will cause the server
        // to close. The client will not close because interactInMemory does not propagate closure.
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        stopPromise.futureResult.whenComplete { _ in
            unwrapped = true
        }
        clientHandler.stopTLS(promise: stopPromise)

        XCTAssertFalse(clientClosed)
        XCTAssertFalse(serverClosed)
        XCTAssertFalse(unwrapped)

        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))

        clientChannel.pipeline.assertDoesNotContain(handler: clientHandler)

        (serverChannel.eventLoop as! EmbeddedEventLoop).run()
        (clientChannel.eventLoop as! EmbeddedEventLoop).run()

        XCTAssertFalse(clientClosed)
        XCTAssertTrue(serverClosed)
        XCTAssertTrue(unwrapped)
    }

    func testSimultaneousUnwrapping() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var clientClosed = false
        var serverClosed = false
        var clientUnwrapped = false
        var serverUnwrapped = false

        defer {
            XCTAssertNoThrow(try serverChannel.finish())
            XCTAssertNoThrow(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        let serverHandler = try assertNoThrowWithValue(NIOSSLServerHandler(context: context))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(serverHandler).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Mark the closure of the channels.
        clientChannel.closeFuture.whenComplete { _ in
            clientClosed = true
        }
        serverChannel.closeFuture.whenComplete { _ in
            serverClosed = true
        }

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection and the server connection at the same time. This should
        // not close either channel.
        let clientStopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        clientStopPromise.futureResult.whenComplete { _ in
            clientUnwrapped = true
        }
        clientHandler.stopTLS(promise: clientStopPromise)

        let serverStopPromise: EventLoopPromise<Void> = serverChannel.eventLoop.makePromise()
        serverStopPromise.futureResult.whenComplete { _ in
            serverUnwrapped = true
        }
        serverHandler.stopTLS(promise: serverStopPromise)

        XCTAssertFalse(clientClosed)
        XCTAssertFalse(serverClosed)
        XCTAssertFalse(clientUnwrapped)
        XCTAssertFalse(serverUnwrapped)

        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))

        clientChannel.pipeline.assertDoesNotContain(handler: clientHandler)
        serverChannel.pipeline.assertDoesNotContain(handler: serverHandler)

        (serverChannel.eventLoop as! EmbeddedEventLoop).run()
        (clientChannel.eventLoop as! EmbeddedEventLoop).run()

        XCTAssertFalse(clientClosed)
        XCTAssertFalse(serverClosed)
        XCTAssertTrue(clientUnwrapped)
        XCTAssertTrue(serverUnwrapped)
    }

    func testUnwrappingFollowedByClosure() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var clientClosed = false
        var clientUnwrapped = false

        defer {
            // Both channels will already be closed
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertThrowsError(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Mark the closure of the client.
        clientChannel.closeFuture.whenComplete { _ in
            clientClosed = true
        }

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection.
        let clientStopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        clientStopPromise.futureResult.map {
            XCTFail("Must not succeed")
        }.whenFailure { error in
            XCTAssertEqual(error as? NIOTLSUnwrappingError, NIOTLSUnwrappingError.closeRequestedDuringUnwrap)
            clientUnwrapped = true
        }
        clientHandler.stopTLS(promise: clientStopPromise)

        // Now we're going to close the client.
        clientChannel.close().whenComplete { _ in
            XCTAssertFalse(clientClosed)
            XCTAssertTrue(clientUnwrapped)
        }

        XCTAssertFalse(clientClosed)
        XCTAssertFalse(clientUnwrapped)

        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))
        clientChannel.pipeline.assertContains(handler: clientHandler)

        (serverChannel.eventLoop as! EmbeddedEventLoop).run()
        (clientChannel.eventLoop as! EmbeddedEventLoop).run()

        XCTAssertTrue(clientClosed)
        XCTAssertTrue(clientUnwrapped)
    }

    func testUnwrappingMeetsTCPFIN() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var clientClosed = false
        var clientUnwrapped = false

        defer {
            // The errors here are expected
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertThrowsError(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Mark the closure of the client.
        clientChannel.closeFuture.whenComplete { _ in
            clientClosed = true
        }

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection.
        let clientStopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        clientStopPromise.futureResult.map {
            XCTFail("Must not succeed")
        }.whenFailure { error in
            XCTAssertEqual(error as? NIOSSLError, .uncleanShutdown)
            clientUnwrapped = true
        }
        clientHandler.stopTLS(promise: clientStopPromise)

        XCTAssertFalse(clientClosed)
        XCTAssertFalse(clientUnwrapped)

        // Now we're going to simulate the client receiving a TCP FIN the other way.
        clientChannel.pipeline.fireChannelInactive()
        clientChannel.pipeline.assertContains(handler: clientHandler)

        (clientChannel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertTrue(clientUnwrapped)

        // Clean up by bringing the server up to speed
        serverChannel.pipeline.fireChannelInactive()
    }

    func testDoubleUnwrapping() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var promiseCalled = false

        defer {
            // We expect the server case to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertNoThrow(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection twice. We'll ignore the first promise.
        let dummyPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        stopPromise.futureResult.whenComplete { _ in
            promiseCalled = true
        }
        clientHandler.stopTLS(promise: dummyPromise)
        clientHandler.stopTLS(promise: stopPromise)

        XCTAssertFalse(promiseCalled)
        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))
        XCTAssertTrue(promiseCalled)
    }

    func testUnwrappingAfterIgnoredUnwrapping() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var promiseCalled = false

        defer {
            // We expect the server case to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertNoThrow(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection twice. We'll only send a promise the second time.
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        stopPromise.futureResult.whenComplete { _ in
            promiseCalled = true
        }
        clientHandler.stopTLS(promise: nil)
        clientHandler.stopTLS(promise: stopPromise)

        XCTAssertFalse(promiseCalled)
        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))
        XCTAssertTrue(promiseCalled)
    }

    func testUnwrappingIdleChannel() throws {
        let channel = EmbeddedChannel()

        var promiseCalled = false

        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let handler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try channel.pipeline.addHandler(handler).wait())
        channel.pipeline.assertContains(handler: handler)

        // Let's unwrap. This should succeed easily.
        let stopPromise: EventLoopPromise<Void> = channel.eventLoop.makePromise()
        stopPromise.futureResult.whenComplete { _ in
            promiseCalled = true
        }

        XCTAssertFalse(promiseCalled)
        handler.stopTLS(promise: stopPromise)
        XCTAssertTrue(promiseCalled)
    }

    func testUnwrappingAfterSuccessfulUnwrap() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var promiseCalled = false

        defer {
            // We expect the server case to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertNoThrow(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection.
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        stopPromise.futureResult.whenComplete { _ in
            promiseCalled = true
        }
        clientHandler.stopTLS(promise: stopPromise)

        XCTAssertFalse(promiseCalled)
        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))
        XCTAssertTrue(promiseCalled)

        // Now, let's unwrap it again.
        let secondPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        clientHandler.stopTLS(promise: secondPromise)
        do {
            try secondPromise.futureResult.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnwrappingAfterClosure() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        defer {
            // We expect both casees to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertThrowsError(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's close everything down.
        clientChannel.close(promise: nil)
        serverChannel.close(promise: nil)
        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))

        // We haven't spun the event loop, so the handlers are still in the pipeline. Now attempt to unwrap.
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        clientHandler.stopTLS(promise: stopPromise)

        do {
            try stopPromise.futureResult.wait()
            XCTFail("Did not throw")
        } catch NIOTLSUnwrappingError.alreadyClosed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReceivingGibberishAfterAttemptingToUnwrap() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        var clientClosed = false
        var clientUnwrapped = false

        defer {
            // The errors here are expected
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertThrowsError(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Mark the closure of the client.
        clientChannel.closeFuture.whenComplete { _ in
            clientClosed = true
        }

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection.
        let clientStopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        clientStopPromise.futureResult.map {
            XCTFail("Must not succeed")
        }.whenFailure { error in
            switch error as? NIOSSLError {
            case .some(.shutdownFailed):
                // Expected
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }

            clientUnwrapped = true
        }
        clientHandler.stopTLS(promise: clientStopPromise)

        XCTAssertFalse(clientClosed)
        XCTAssertFalse(clientUnwrapped)

        // Now we're going to simulate the client receiving gibberish data in response, instead
        // of a CLOSE_NOTIFY.
        var buffer = clientChannel.allocator.buffer(capacity: 1024)
        buffer.writeStaticString("GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")

        do {
            try clientChannel.writeInbound(buffer)
            XCTFail("Did not error")
        } catch NIOSSLError.shutdownFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // The client should have errored out now. The handler should still be there, as unwrapping
        // has failed.
        XCTAssertTrue(clientUnwrapped)
        clientChannel.pipeline.assertContains(handler: clientHandler)

        // Clean up by bringing the server up to speed
        serverChannel.pipeline.fireChannelInactive()
    }

    func testPendingWritesFailOnUnwrap() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        defer {
            // We expect the server to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertNoThrow(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Queue up a write.
        var writeCompleted = false
        var buffer = clientChannel.allocator.buffer(capacity: 1024)
        buffer.writeStaticString("Hello, world!")
        clientChannel.write(buffer).map {
            XCTFail("Must not succeed")
        }.whenFailure { error in
            XCTAssertEqual(error as? NIOTLSUnwrappingError, .unflushedWriteOnUnwrap)
            writeCompleted = true
        }

        // We haven't spun the event loop, so the handlers are still in the pipeline. Now attempt to unwrap.
        var unwrapped = false
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        stopPromise.futureResult.whenSuccess {
            XCTAssertTrue(writeCompleted)
            unwrapped = true
        }
        XCTAssertFalse(writeCompleted)
        clientHandler.stopTLS(promise: stopPromise)
        XCTAssertFalse(writeCompleted)
        XCTAssertFalse(unwrapped)

        XCTAssertNoThrow(try interactInMemory(clientChannel: clientChannel, serverChannel: serverChannel))
        XCTAssertTrue(writeCompleted)
        XCTAssertTrue(unwrapped)
    }

    func testPendingWritesFailWhenFlushedOnUnwrap() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        defer {
            // We expect both cases to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertThrowsError(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Queue up a write.
        var writeCompleted = false
        var buffer = clientChannel.allocator.buffer(capacity: 1024)
        buffer.writeStaticString("Hello, world!")
        clientChannel.write(buffer).map {
            XCTFail("Must not succeed")
        }.whenFailure { error in
            XCTAssertEqual(error as? ChannelError, .ioOnClosedChannel)
            writeCompleted = true
        }

        // We haven't spun the event loop, so the handlers are still in the pipeline. Now attempt to unwrap.
        var unwrapped = false
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        stopPromise.futureResult.whenFailure { error in
            switch error as? BoringSSLError {
            case .some(.sslError):
                // ok
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
            unwrapped = true
        }
        XCTAssertFalse(writeCompleted)
        clientHandler.stopTLS(promise: stopPromise)
        XCTAssertFalse(writeCompleted)
        XCTAssertFalse(unwrapped)

        // Now try to flush the write. This should fail the write early, and take out the connection.
        clientChannel.flush()
        XCTAssertTrue(writeCompleted)
        XCTAssertTrue(unwrapped)

        // Bring the server up to speed.
        serverChannel.pipeline.fireChannelInactive()
    }

    func testDataReceivedAfterCloseNotifyIsPassedDownThePipeline() throws {
        let serverChannel = EmbeddedChannel()
        let clientChannel = EmbeddedChannel()

        defer {
            // We expect the server case to throw
            XCTAssertThrowsError(try serverChannel.finish())
            XCTAssertNoThrow(try clientChannel.finish())
        }

        let context = try assertNoThrowWithValue(configuredSSLContext())

        let clientHandler = try assertNoThrowWithValue(NIOSSLClientHandler(context: context, serverHostname: nil))
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(NIOSSLServerHandler(context: context)).wait())
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(clientHandler).wait())
        let handshakeHandler = HandshakeCompletedHandler()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(handshakeHandler).wait())
        let readPromise: EventLoopPromise<ByteBuffer> = clientChannel.eventLoop.makePromise()
        XCTAssertNoThrow(try clientChannel.pipeline.addHandler(PromiseOnReadHandler(promise: readPromise)).wait())

        var readCompleted = false
        readPromise.futureResult.whenSuccess { buffer in
            XCTAssertEqual(buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes), "Hello, world!")
            readCompleted = true
        }

        // Connect. This should lead to a completed handshake.
        XCTAssertNoThrow(try connectInMemory(client: clientChannel, server: serverChannel))
        XCTAssertTrue(handshakeHandler.handshakeSucceeded)

        // Let's unwrap the client connection. With no additional configuration, this will cause the server
        // to close. The client will not close because interactInMemory does not propagate closure.
        var unwrapped = false
        let stopPromise: EventLoopPromise<Void> = clientChannel.eventLoop.makePromise()
        stopPromise.futureResult.whenSuccess {
            unwrapped = true
        }
        clientHandler.stopTLS(promise: stopPromise)

        // Now we want to manually handle the interaction. The client will have sent a CLOSE_NOTIFY: send it to the server.
        let clientCloseNotify = try clientChannel.readOutbound(as: ByteBuffer.self)!
        XCTAssertNoThrow(try serverChannel.writeInbound(clientCloseNotify))

        // The server will have sent a CLOSE_NOTIFY: grab it.
        var serverCloseNotify = try serverChannel.readOutbound(as: ByteBuffer.self)!

        // We're going to append some plaintext data.
        serverCloseNotify.writeStaticString("Hello, world!")

        // Now we're going to send it to the client.
        XCTAssertFalse(unwrapped)
        XCTAssertFalse(readCompleted)
        XCTAssertNoThrow(try clientChannel.writeInbound(serverCloseNotify))

        // This will have triggered an unwrap.
        XCTAssertTrue(unwrapped)

        // We should also have received the plaintext data.
        XCTAssertTrue(readCompleted)
    }
}
