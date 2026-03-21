//
//  QUICDirectTests.swift
//  TunnelServicesTests
//
//  Integration tests verifying direct in-memory client <-> server QUIC/H3 communication.
//

import XCTest
@testable import TunnelServices
import SwiftQuiche

final class QUICDirectTests: XCTestCase {

    func testDirectClientServerHandshake() throws {
        let (certPath, keyPath) = try TestQUICServer.generateTestCerts()
        let server = try TestQUICServer(certPath: certPath, keyPath: keyPath)
        let client = try TestQUICClient(serverName: "localhost")

        var clientPackets = client.startConnection()
        XCTAssertFalse(clientPackets.isEmpty, "Client should produce Initial packets")

        for _ in 0..<50 {
            // Client -> Server
            var serverResponses = [Data]()
            for pkt in clientPackets {
                serverResponses.append(contentsOf: server.receive(pkt))
            }
            let serverOut = server.pendingOutbound()
            let allToClient = serverResponses + serverOut

            if allToClient.isEmpty && client.isEstablished { break }

            // Server -> Client
            clientPackets = client.receive(allToClient)

            if client.isEstablished {
                break
            }
        }

        XCTAssertTrue(client.isEstablished, "QUIC handshake should complete")
    }

    /// Helper: exchange packets between client and server in a loop until idle or limit reached.
    private func exchangeUntilIdle(client: TestQUICClient, server: TestQUICServer, initialPackets: [Data], maxRounds: Int = 50) -> [Data] {
        var clientPackets = initialPackets
        for _ in 0..<maxRounds {
            var serverResponses = [Data]()
            for pkt in clientPackets {
                serverResponses.append(contentsOf: server.receive(pkt))
            }
            serverResponses.append(contentsOf: server.pendingOutbound())

            if serverResponses.isEmpty && clientPackets.isEmpty { break }
            if serverResponses.isEmpty { break }

            clientPackets = client.receive(serverResponses)
        }
        return clientPackets
    }

    func testDirectClientServerH3Request() throws {
        let (certPath, keyPath) = try TestQUICServer.generateTestCerts()
        let server = try TestQUICServer(certPath: certPath, keyPath: keyPath)
        let client = try TestQUICClient(serverName: "localhost")

        // Handshake
        var clientPackets = client.startConnection()
        clientPackets = exchangeUntilIdle(client: client, server: server, initialPackets: clientPackets)

        XCTAssertTrue(client.isEstablished, "Handshake must complete before sending request")

        // Let H3 control streams settle with a few more round-trips
        for _ in 0..<10 {
            let out = client.drainOutbound()
            if out.isEmpty { break }
            let _ = exchangeUntilIdle(client: client, server: server, initialPackets: out, maxRounds: 5)
        }

        // Send H3 GET request
        let requestPackets = client.sendRequest(method: "GET", path: "/hello", authority: "localhost")

        // Exchange packets until we get a response
        var responses: [(headers: [(String, String)], body: Data)] = []
        var outgoing = requestPackets
        for _ in 0..<50 {
            outgoing = exchangeUntilIdle(client: client, server: server, initialPackets: outgoing, maxRounds: 5)
            responses = client.pollResponses()
            if !responses.isEmpty { break }
            outgoing = client.drainOutbound()
            if outgoing.isEmpty { break }
        }

        XCTAssertEqual(responses.count, 1, "Should receive exactly one response")
        if let response = responses.first {
            let status = response.headers.first(where: { $0.0 == ":status" })?.1
            XCTAssertEqual(status, "200", "Response status should be 200")

            let bodyStr = String(data: response.body, encoding: .utf8)
            XCTAssertEqual(bodyStr, "echo: /hello", "Response body should echo the path")
        }

        XCTAssertEqual(server.requestCount, 1, "Server should have processed 1 request")
    }
}
