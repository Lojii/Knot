//
//  HTTP1IntegrationTests.swift
//  TunnelServicesTests
//
//  Smoke test: validates that TestEchoServer, TestProxyLauncher, and TestNIOClient
//  work together for a basic HTTP/1.1 request end-to-end, including database recording.
//

import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1
@testable import TunnelServices

final class HTTP1IntegrationTests: XCTestCase {

    private var echoServer: TestEchoServer!
    private var launcher: TestProxyLauncher!
    private var client: TestNIOClient!
    private var serverPort: Int!
    private var proxyPort: Int!

    override func setUp() {
        super.setUp()
        do {
            // Start echo server (plain HTTP/1.1)
            echoServer = TestEchoServer(mode: .http1)
            serverPort = try echoServer.start()

            // Start proxy (no SSL for smoke test)
            launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
            proxyPort = try launcher.start()

            // Create client
            client = TestNIOClient(proxyPort: proxyPort)
        } catch {
            XCTFail("setUp failed: \(error)")
        }

        addTeardownBlock { [weak self] in
            self?.client?.shutdown()
            self?.launcher?.stop()
            try? self?.echoServer?.stop()
        }
    }

    func testHTTP1_Plaintext_BasicRequest() throws {
        // Send a GET request through the proxy to the echo server
        let response = try client.httpRequest(
            method: .GET, host: "127.0.0.1", port: serverPort, uri: "/hello"
        )

        // Response should be 200 OK
        XCTAssertEqual(response.status, 200)

        // Wait for async DB write (FlowDAO.insert is dispatched to protoWriteQueue)
        Thread.sleep(forTimeInterval: 1.0)

        // Database assertions
        let flows = try launcher.queryFlows()
        XCTAssertGreaterThanOrEqual(flows.count, 1, "Expected at least 1 flow record in database")

        let flow = flows.first!
        XCTAssertEqual(flow.protocolName, "HTTP")
        XCTAssertEqual(flow.status, .completed)
        XCTAssertEqual(flow.connReuse, 0, "First request should be new connection")
        XCTAssertTrue(flow.uploadBytes > 0, "Should have upload bytes")
        XCTAssertTrue(flow.downloadBytes > 0, "Should have download bytes")

        // Timeline assertions
        XCTAssertTrue(flow.startedAt > 0, "startedAt should be set")
        if let ended = flow.endedAt {
            XCTAssertTrue(ended > flow.startedAt, "endedAt should be after startedAt")
        }
    }
}
