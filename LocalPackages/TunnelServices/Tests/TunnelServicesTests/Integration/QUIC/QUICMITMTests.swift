//
//  QUICMITMTests.swift
//  TunnelServicesTests
//
//  Integration tests for QUIC MITM interception via QUICMITMManager.
//  Verifies that a QUIC handshake and HTTP/3 requests work when routed
//  through the man-in-the-middle proxy.
//

import XCTest
@testable import TunnelServices

#if canImport(SwiftQuiche)
import SwiftQuiche

final class QUICMITMTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quic-mitm-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeHarness() throws -> QUICMITMTestHarness {
        let (certPath, keyPath) = try TestQUICServer.generateTestCerts()
        let server = try TestQUICServer(certPath: certPath, keyPath: keyPath)
        let client = try TestQUICClient(serverName: "localhost")
        return try QUICMITMTestHarness(
            client: client,
            server: server,
            certPath: certPath,
            keyPath: keyPath,
            tempDir: tempDir.path
        )
    }

    // MARK: - Tests

    func testMITM_Handshake() throws {
        let harness = try makeHarness()
        defer { harness.shutdown() }

        try harness.runUntilEstablished(timeout: 10.0)

        XCTAssertTrue(harness.client.isEstablished, "Client should complete QUIC handshake through MITM")
        XCTAssertGreaterThanOrEqual(harness.sessionCount, 1, "MITM manager should have at least one active session")
    }

    func testMITM_H3_GET() throws {
        let harness = try makeHarness()
        defer { harness.shutdown() }

        try harness.runUntilEstablished(timeout: 10.0)

        // Let H3 control streams settle
        for _ in 0..<20 {
            harness.runRoundTrip()
        }

        // Send a GET request and pump through MITM
        let requestPackets = harness.client.sendRequest(method: "GET", path: "/test", authority: "localhost")
        harness.pumpClientPackets(requestPackets)

        // Check if response is already available, otherwise run more rounds
        var responses = harness.client.pollResponses()
        if responses.isEmpty {
            let deadline = Date().addingTimeInterval(10.0)
            while Date() < deadline {
                harness.runRoundTrip()
                responses.append(contentsOf: harness.client.pollResponses())
                if !responses.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }

        XCTAssertGreaterThanOrEqual(responses.count, 1, "Should receive at least one H3 response")
        if let response = responses.first {
            let status = response.headers.first(where: { $0.0 == ":status" })?.1
            XCTAssertEqual(status, "200", "Response status should be 200")

            let bodyStr = String(data: response.body, encoding: .utf8)
            XCTAssertEqual(bodyStr, "echo: /test", "Response body should echo the path")
        }
    }

    func testMITM_H3_MultipleRequests() throws {
        let harness = try makeHarness()
        defer { harness.shutdown() }

        try harness.runUntilEstablished(timeout: 10.0)

        // Let H3 control streams settle
        for _ in 0..<20 {
            harness.runRoundTrip()
        }

        let paths = ["/req1", "/req2", "/req3"]
        var allResponses: [(headers: [(String, String)], body: Data)] = []

        for path in paths {
            let requestPackets = harness.client.sendRequest(method: "GET", path: path, authority: "localhost")
            harness.pumpClientPackets(requestPackets)

            // Run round-trips to get the response
            let deadline = Date().addingTimeInterval(10.0)
            while Date() < deadline {
                harness.runRoundTrip()
                let responses = harness.client.pollResponses()
                if !responses.isEmpty {
                    allResponses.append(contentsOf: responses)
                    break
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }

        XCTAssertEqual(allResponses.count, 3, "Should receive 3 H3 responses")
        for (i, response) in allResponses.enumerated() {
            let status = response.headers.first(where: { $0.0 == ":status" })?.1
            XCTAssertEqual(status, "200", "Response \(i) status should be 200")

            let bodyStr = String(data: response.body, encoding: .utf8)
            XCTAssertEqual(bodyStr, "echo: \(paths[i])", "Response \(i) body should echo path \(paths[i])")
        }
    }
}

#endif
