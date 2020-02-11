//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
// swift-tools-version:4.0
//
// swift-tools-version:4.0
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Network)
import XCTest
import NIO
import NIOConcurrencyHelpers
import NIOTransportServices

class NIOTSEventLoopTest: XCTestCase {
    func testIsInEventLoopWorks() throws {
        let group = NIOTSEventLoopGroup()
        let loop = group.next()
        XCTAssertFalse(loop.inEventLoop)
        try loop.scheduleTask(in: .nanoseconds(0)) {
            XCTAssertTrue(loop.inEventLoop)
        }.futureResult.wait()
    }

    func testDelayedTask() throws {
        let group = NIOTSEventLoopGroup()
        let loop = group.next()
        let now = DispatchTime.now()

        try loop.scheduleTask(in: .milliseconds(100)) {
            let newNow = DispatchTime.now()
            XCTAssertGreaterThan(newNow.uptimeNanoseconds - now.uptimeNanoseconds,
                                 100 * 1000 * 1000)
        }.futureResult.wait()
    }

    func testCancellingDelayedTask() throws {
        let group = NIOTSEventLoopGroup()
        let loop = group.next()
        let now = DispatchTime.now()

        let firstTask = loop.scheduleTask(in: .milliseconds(30)) {
            XCTFail("Must not be called")
        }
        let secondTask = loop.scheduleTask(in: .milliseconds(10)) {
            firstTask.cancel()
        }
        let thirdTask = loop.scheduleTask(in: .milliseconds(50)) { }
        firstTask.futureResult.whenComplete { (_: Result<Void, Error>) in
            let newNow = DispatchTime.now()
            XCTAssertLessThan(newNow.uptimeNanoseconds - now.uptimeNanoseconds,
                              300 * 1000 * 1000)
        }

        XCTAssertNoThrow(try secondTask.futureResult.wait())
        do {
            try firstTask.futureResult.wait()
        } catch EventLoopError.cancelled {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Wait just to be sure the cancelled job doesn't execute.
        XCTAssertNoThrow(try thirdTask.futureResult.wait())
    }

    func testLoopsAreNotInEachOther() throws {
        let group = NIOTSEventLoopGroup(loopCount: 2)
        let firstLoop = group.next()
        let secondLoop = group.next()
        XCTAssertFalse(firstLoop === secondLoop)

        let firstTask = firstLoop.scheduleTask(in: .nanoseconds(0)) {
            XCTAssertTrue(firstLoop.inEventLoop)
            XCTAssertFalse(secondLoop.inEventLoop)
        }
        let secondTask = secondLoop.scheduleTask(in: .nanoseconds(0)) {
            XCTAssertFalse(firstLoop.inEventLoop)
            XCTAssertTrue(secondLoop.inEventLoop)
        }
        try EventLoopFuture<Void>.andAllComplete([firstTask.futureResult, secondTask.futureResult], on: firstLoop).wait()
    }

    func testWeDontHoldELOrELGReferencesImmeditelyFollowingAConnect() {
        weak var weakEL: EventLoop? = nil
        weak var weakELG: EventLoopGroup? = nil
        func make() throws {
            let group = NIOTSEventLoopGroup(loopCount: 1)
            defer {
                XCTAssertNoThrow(try group.syncShutdownGracefully())
            }
            weakELG = group
            weakEL = group.next()

            let counter = Atomic<Int>(value: 0)
            let acceptedChan = group.next().makePromise(of: Channel.self)
            let server = try NIOTSListenerBootstrap(group: group)
                .childChannelInitializer { channel in
                    XCTAssertEqual(0, counter.add(1))
                    acceptedChan.succeed(channel)
                    return channel.eventLoop.makeSucceededFuture(())
                }
                .bind(host: "127.0.0.1", port: 0).wait()
            // leave this "localhost" so we need to resolve it (involving happy eyeballs)
            let client = try NIOTSConnectionBootstrap(group: group).connect(host: "localhost",
                                                                            port: server.localAddress!.port!).wait()
            XCTAssertNoThrow(try client.close().wait())
            XCTAssertNoThrow(try acceptedChan.futureResult.wait().close().flatMapErrorThrowing { error in
                if let error = error as? ChannelError, error == .alreadyClosed {
                    // this is okay because we previously closed the other end
                } else {
                    throw error
                }
            })
            XCTAssertNoThrow(try server.close().wait())
        }
        XCTAssertNoThrow(try make())
        usleep(100_000) // to give the other thread chance to deallocate everything
        XCTAssertNil(weakELG)
        XCTAssertNil(weakEL)
    }
}
#endif
