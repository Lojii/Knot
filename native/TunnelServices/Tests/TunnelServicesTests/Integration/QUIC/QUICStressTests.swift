//
//  QUICStressTests.swift
//  TunnelServicesTests
//
//  Stress tests for QUIC MITM: exercises multiple connections through
//  QUICMITMManager with memory monitoring.
//

import XCTest
import Foundation
@testable import TunnelServices

#if canImport(SwiftQuiche)
import SwiftQuiche

// MARK: - Memory Monitoring

private func currentRSS() -> Int64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
}

final class QUICStressTests: XCTestCase {

    private var tempDir: URL!
    private var certPath: String!
    private var keyPath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quic-stress-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

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

    private func makeHarness(server: TestQUICServer) throws -> QUICMITMTestHarness {
        let client = try TestQUICClient(serverName: "localhost")
        return try QUICMITMTestHarness(
            client: client,
            server: server,
            certPath: certPath,
            keyPath: keyPath,
            tempDir: tempDir.path
        )
    }

    /// Run a QUIC stress loop: create `count` connections through MITM, each sends 1 H3 GET.
    /// Returns (successCount, failCount, baselineMemory, peakMemory).
    private func runQUICStress(
        testName: String,
        count: Int
    ) throws -> (successes: Int, failures: Int, baselineMem: Int64, peakMem: Int64, durationMs: Double) {
        let baselineMem = currentRSS()
        var peakMem = baselineMem
        var successCount = 0
        var failCount = 0

        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<count {
            // Each connection gets its own server + harness to avoid state contamination.
            // The server is lightweight (in-memory, no sockets).
            let server: TestQUICServer
            do {
                server = try TestQUICServer(certPath: certPath, keyPath: keyPath)
            } catch {
                print("[QUIC_STRESS] Connection \(i): FAIL (server create: \(error))")
                failCount += 1
                continue
            }

            let harness: QUICMITMTestHarness
            do {
                harness = try makeHarness(server: server)
            } catch {
                print("[QUIC_STRESS] Connection \(i): FAIL (harness create: \(error))")
                failCount += 1
                continue
            }

            defer { harness.shutdown() }

            do {
                try harness.runUntilEstablished(timeout: 5.0)

                // Let H3 control streams settle
                for _ in 0..<20 {
                    harness.runRoundTrip()
                }

                // Send H3 GET request
                let requestPackets = harness.client.sendRequest(
                    method: "GET", path: "/stress/\(i)", authority: "localhost"
                )
                harness.pumpClientPackets(requestPackets)

                // Wait for response
                var responses = harness.client.pollResponses()
                if responses.isEmpty {
                    let deadline = Date().addingTimeInterval(5.0)
                    while Date() < deadline {
                        harness.runRoundTrip()
                        responses.append(contentsOf: harness.client.pollResponses())
                        if !responses.isEmpty { break }
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                }

                if !responses.isEmpty {
                    successCount += 1
                    print("[QUIC_STRESS] Connection \(i): OK")
                } else {
                    failCount += 1
                    print("[QUIC_STRESS] Connection \(i): FAIL (no response)")
                }
            } catch {
                failCount += 1
                print("[QUIC_STRESS] Connection \(i): FAIL (\(error))")
            }

            // Sample memory periodically
            if i % 5 == 0 {
                let mem = currentRSS()
                if mem > peakMem { peakMem = mem }
            }
        }

        let finalMem = currentRSS()
        if finalMem > peakMem { peakMem = finalMem }
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        let deltaMB = Double(peakMem - baselineMem) / (1024.0 * 1024.0)
        print("[STRESS_METRIC] test=\(testName) total=\(count) success=\(successCount) failed=\(failCount) duration_ms=\(String(format: "%.1f", durationMs)) baseline_mem=\(baselineMem) peak_mem=\(peakMem) delta_mem_mb=\(String(format: "%.1f", deltaMB))")

        return (successCount, failCount, baselineMem, peakMem, durationMs)
    }

    // MARK: - Tests

    func testQUICStress_Light() throws {
        let count = 10
        let (successes, _, baselineMem, peakMem, _) = try runQUICStress(
            testName: "QUIC_MITM_Light", count: count
        )

        let minSuccess = Int(Double(count) * 0.80) // 80% threshold
        XCTAssertGreaterThanOrEqual(successes, minSuccess,
            "Light: expected >=80% success rate, got \(successes)/\(count)")

        let deltaMem = peakMem - baselineMem
        XCTAssertLessThan(deltaMem, 10 * 1024 * 1024,
            "Light: memory delta \(deltaMem) bytes should be < 10MB")
    }

    func testQUICStress_Medium() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_STRESS_HEAVY"] == nil,
            "Set RUN_STRESS_HEAVY=1 to run"
        )

        let count = 50
        let (successes, _, baselineMem, peakMem, _) = try runQUICStress(
            testName: "QUIC_MITM_Medium", count: count
        )

        let minSuccess = Int(Double(count) * 0.70) // 70% threshold
        XCTAssertGreaterThanOrEqual(successes, minSuccess,
            "Medium: expected >=70% success rate, got \(successes)/\(count)")

        let deltaMem = peakMem - baselineMem
        XCTAssertLessThan(deltaMem, 30 * 1024 * 1024,
            "Medium: memory delta \(deltaMem) bytes should be < 30MB")
    }
}

#endif
