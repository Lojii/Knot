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
import NIOTLS
import NIOSSL


class ClientSNITests: XCTestCase {
    static var cert: NIOSSLCertificate!
    static var key: NIOSSLPrivateKey!

    override class func setUp() {
        super.setUp()
        let (cert, key) = generateSelfSignedCert()
        NIOSSLIntegrationTest.cert = cert
        NIOSSLIntegrationTest.key = key
    }

    private func configuredSSLContext() throws -> NIOSSLContext {
        let config = TLSConfiguration.forServer(certificateChain: [.certificate(NIOSSLIntegrationTest.cert)],
                                                privateKey: .privateKey(NIOSSLIntegrationTest.key),
                                                trustRoots: .certificates([NIOSSLIntegrationTest.cert]))
        let context = try NIOSSLContext(configuration: config)
        return context
    }

    private func assertSniResult(sniField: String?, expectedResult: SNIResult) throws {
        let context = try configuredSSLContext()

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try? group.syncShutdownGracefully()
        }

        let sniPromise: EventLoopPromise<SNIResult> = group.next().makePromise()
        let sniHandler = ByteToMessageHandler(SNIHandler {
            sniPromise.succeed($0)
            return group.next().makeSucceededFuture(())
        })
        let serverChannel = try serverTLSChannel(context: context, preHandlers: [sniHandler], postHandlers: [], group: group)
        defer {
            _ = try? serverChannel.close().wait()
        }

        let clientChannel = try clientTLSChannel(context: context,
                                                 preHandlers: [],
                                                 postHandlers: [],
                                                 group: group,
                                                 connectingTo: serverChannel.localAddress!,
                                                 serverHostname: sniField)
        defer {
            _ = try? clientChannel.close().wait()
        }

        let sniResult = try sniPromise.futureResult.wait()
        XCTAssertEqual(sniResult, expectedResult)
    }

    func testSNIIsTransmitted() throws {
        try assertSniResult(sniField: "httpbin.org", expectedResult: .hostname("httpbin.org"))
    }

    func testNoSNILeadsToNoExtension() throws {
        try assertSniResult(sniField: nil, expectedResult: .fallback)
    }

    func testSNIIsRejectedForIPv4Addresses() throws {
        let context = try configuredSSLContext()

        do {
            _ = try NIOSSLClientHandler(context: context, serverHostname: "192.168.0.1")
            XCTFail("Created client handler with invalid SNI name")
        } catch BoringSSLError.invalidSNIName {
            // All fine.
        }
    }

    func testSNIIsRejectedForIPv6Addresses() throws {
        let context = try configuredSSLContext()

        do {
            _ = try NIOSSLClientHandler(context: context, serverHostname: "fe80::200:f8ff:fe21:67cf")
            XCTFail("Created client handler with invalid SNI name")
        } catch BoringSSLError.invalidSNIName {
            // All fine.
        }
    }
}
