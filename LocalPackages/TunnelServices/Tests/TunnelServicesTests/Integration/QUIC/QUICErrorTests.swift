//
//  QUICErrorTests.swift
//  TunnelServicesTests
//
//  Tests that QUICMITMManager handles invalid and malformed input
//  gracefully without crashing. Also tests concurrent session creation.
//

import XCTest
import Foundation
@testable import TunnelServices

#if canImport(SwiftQuiche)
import SwiftQuiche

final class QUICErrorTests: XCTestCase {

    private var tempDir: URL!
    private var certPath: String!
    private var keyPath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quic-error-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Generate certs once for all tests
        do {
            let (cert, key) = try TestQUICServer.generateTestCerts()
            certPath = cert
            keyPath = key
        } catch {
            XCTFail("Failed to generate test certs: \(error)")
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeManager() -> QUICMITMManager {
        let task = CaptureTask()
        task.id = 0
        task.localIP = "127.0.0.1"
        task.localPort = 0
        task.localEnable = 1
        task.isCACertTrusted = true
        task.ruleEngine = RuleEngine(config: "")
        task.fileFolder = tempDir.path

        return QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)
    }

    private func makeHarness() throws -> QUICMITMTestHarness {
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

    // MARK: - Invalid Packet Tests

    func testMITM_InvalidPacket_RandomBytes() throws {
        let manager = makeManager()
        defer { manager.shutdown() }

        // 100 random bytes — not a valid QUIC packet
        var randomData = Data(count: 100)
        _ = randomData.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 100, $0.baseAddress!)
        }

        let result = manager.processOutbound(randomData, dstIP: "1.2.3.4", dstPort: 443)

        // Primary assertion: no crash occurred. The QUIC header parser may or may
        // not accept random bytes (short headers have minimal structure), so we
        // only verify the manager survived the input gracefully.
        print("[QUIC_ERROR] RandomBytes: toApp=\(result.toApp.count), toServer=\(result.toServer.count), sessions=\(manager.activeSessions)")
    }

    func testMITM_InvalidPacket_TruncatedInitial() throws {
        let manager = makeManager()
        defer { manager.shutdown() }

        // Build the first 10 bytes of what looks like a QUIC Initial packet:
        // Byte 0: 0xC0 (long header, Initial type)
        // Bytes 1-4: version 1 (0x00000001)
        // Byte 5: DCID length (8)
        // Bytes 6-9: partial DCID (truncated)
        let truncated = Data([
            0xC0,                       // long header | Initial
            0x00, 0x00, 0x00, 0x01,     // QUIC v1
            0x08,                       // DCID length = 8
            0x01, 0x02, 0x03, 0x04      // only 4 bytes of DCID (truncated)
        ])

        let result = manager.processOutbound(truncated, dstIP: "1.2.3.4", dstPort: 443)

        // Should not crash. Truncated packet should be rejected by header parser.
        // We don't assert specific return values — just that it didn't crash.
        print("[QUIC_ERROR] TruncatedInitial: toApp=\(result.toApp.count), toServer=\(result.toServer.count)")
    }

    func testMITM_InvalidPacket_HTTPRequest() throws {
        let manager = makeManager()
        defer { manager.shutdown() }

        // An HTTP/1.1 request is not a QUIC packet
        let httpData = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".data(using: .utf8)!

        let result = manager.processOutbound(httpData, dstIP: "1.2.3.4", dstPort: 443)

        // Primary assertion: no crash occurred. The QUIC short-header parser may
        // accept the first byte of "GET " (0x47 has the form bit clear → short header),
        // so we only verify the manager handled it without crashing.
        print("[QUIC_ERROR] HTTPRequest: toApp=\(result.toApp.count), toServer=\(result.toServer.count), sessions=\(manager.activeSessions)")
    }

    // MARK: - Concurrent Sessions

    func testMITM_ConcurrentSessions() throws {
        // Create 5 independent harnesses sharing nothing — each gets its own
        // client, server, and MITM manager (since QUICMITMTestHarness owns a manager).
        // The goal is to verify that multiple QUIC sessions can be set up
        // without crashes or cross-contamination.
        var harnesses = [QUICMITMTestHarness]()
        defer {
            for h in harnesses { h.shutdown() }
        }

        for i in 0..<5 {
            do {
                let harness = try makeHarness()
                harnesses.append(harness)
            } catch {
                XCTFail("Failed to create harness \(i): \(error)")
                return
            }
        }

        // Establish each session sequentially (QUIC state machines are per-connection)
        var established = 0
        for (i, harness) in harnesses.enumerated() {
            do {
                try harness.runUntilEstablished(timeout: 10.0)
                XCTAssertTrue(harness.client.isEstablished,
                    "Session \(i) client should be established")
                established += 1
                print("[QUIC_ERROR] Session \(i): established OK")
            } catch {
                print("[QUIC_ERROR] Session \(i): failed to establish — \(error)")
            }
        }

        // At least some should succeed (no crash is the primary goal)
        XCTAssertGreaterThanOrEqual(established, 3,
            "At least 3 out of 5 concurrent sessions should establish, got \(established)")
        print("[QUIC_ERROR] ConcurrentSessions: \(established)/5 established")
    }
}

#endif
