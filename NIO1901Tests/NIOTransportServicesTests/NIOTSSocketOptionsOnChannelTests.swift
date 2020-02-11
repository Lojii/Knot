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
import Network
@testable import NIOTransportServices


private extension Channel {
    private func getSocketOption(_ option: SocketOption) -> EventLoopFuture<SocketOptionValue> {
        return self.getOption(option)
    }

    private func setSocketOption(_ option: SocketOption, to value: SocketOptionValue) -> EventLoopFuture<Void> {
        return self.setOption(option, value: value)
    }

    /// Asserts that a given socket option has a default value, that its value can be changed to a new value, and that it can then be
    /// switched back.
    func assertOptionRoundTrips(option: SocketOption, initialValue: SocketOptionValue, testAlternativeValue: SocketOptionValue) -> EventLoopFuture<Void> {
        return self.getSocketOption(option).flatMap { actualInitialValue in
            XCTAssertEqual(actualInitialValue, initialValue)
            return self.setSocketOption(option, to: testAlternativeValue)
        }.flatMap {
            self.getSocketOption(option)
        }.flatMap { actualNewValue in
            XCTAssertEqual(actualNewValue, testAlternativeValue)
            return self.setSocketOption(option, to: initialValue)
        }.flatMap {
            self.getSocketOption(option)
        }.map { returnedToValue in
            XCTAssertEqual(returnedToValue, initialValue)
        }
    }
}


class NIOTSSocketOptionsOnChannelTests: XCTestCase {
    private var group: NIOTSEventLoopGroup!

    override func setUp() {
        self.group = NIOTSEventLoopGroup()
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    }

    func assertChannelOptionAfterCreation(option: SocketOption, initialValue: SocketOptionValue, testAlternativeValue: SocketOptionValue) throws {
        let listener = try NIOTSListenerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).wait()
        defer {
            XCTAssertNoThrow(try listener.close().wait())
        }
        let connector = try NIOTSConnectionBootstrap(group: group).connect(to: listener.localAddress!).wait()
        defer {
            XCTAssertNoThrow(try connector.close().wait())
        }

        XCTAssertNoThrow(try listener.assertOptionRoundTrips(option: option, initialValue: initialValue, testAlternativeValue: testAlternativeValue).wait())
        XCTAssertNoThrow(try connector.assertOptionRoundTrips(option: option, initialValue: initialValue, testAlternativeValue: testAlternativeValue).wait())
    }

    func testNODELAY() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_NODELAY), initialValue: 0, testAlternativeValue: 1)
    }

    func testNOPUSH() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_NOPUSH), initialValue: 0, testAlternativeValue: 1)
    }

    func testNOOPT() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_NOOPT), initialValue: 0, testAlternativeValue: 1)
    }

    func testKEEPCNT() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_KEEPCNT), initialValue: 0, testAlternativeValue: 5)
    }

    func testKEEPALIVE() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_KEEPALIVE), initialValue: 0, testAlternativeValue: 5)
    }

    func testKEEPINTVL() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_KEEPINTVL), initialValue: 0, testAlternativeValue: 5)
    }

    func testMAXSEG() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_MAXSEG), initialValue: 0, testAlternativeValue: 5)
    }

    func testCONNECTIONTIMEOUT() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_CONNECTIONTIMEOUT), initialValue: 0, testAlternativeValue: 5)
    }

    func testRXT_CONNDROPTIME() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_RXT_CONNDROPTIME), initialValue: 0, testAlternativeValue: 5)
    }

    func testRXT_FINDROP() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_RXT_FINDROP), initialValue: 0, testAlternativeValue: 1)
    }

    func testSENDMOREACKS() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: IPPROTO_TCP, name: TCP_SENDMOREACKS), initialValue: 0, testAlternativeValue: 1)
    }

    func testSO_KEEPALIVE() throws {
        try self.assertChannelOptionAfterCreation(option: SocketOption(level: SOL_SOCKET, name: SO_KEEPALIVE), initialValue: 0, testAlternativeValue: 1)
    }

    func testMultipleSocketOptions() throws {
        let listener = try NIOTSListenerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .serverChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .bind(host: "127.0.0.1", port: 0).wait()
        defer {
            XCTAssertNoThrow(try listener.close().wait())
        }
        let connector = try NIOTSConnectionBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .connect(to: listener.localAddress!).wait()
        defer {
            XCTAssertNoThrow(try connector.close().wait())
        }

        XCTAssertNoThrow(XCTAssertEqual(1, try listener.getOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR)).wait()))
        XCTAssertNoThrow(XCTAssertEqual(1, try listener.getOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY)).wait()))
        XCTAssertNoThrow(XCTAssertEqual(1, try connector.getOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR)).wait()))
        XCTAssertNoThrow(XCTAssertEqual(1, try connector.getOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY)).wait()))
    }
}
#endif
