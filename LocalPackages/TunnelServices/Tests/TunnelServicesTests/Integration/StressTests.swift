//
//  StressTests.swift
//  TunnelServicesTests
//
//  Three-tier stress tests (light / medium / heavy) for plain HTTP and HTTPS MITM.
//  Measures success rate, latency, memory growth, and database record count.
//

import XCTest
import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
@testable import TunnelServices

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

// MARK: - StressResult

private struct StressResult {
    let testName: String
    let total: Int
    let successes: Int
    let failures: Int
    let durationMs: Double
    let avgLatencyMs: Double
    let p99LatencyMs: Double
    let baselineMemory: Int64
    let peakMemory: Int64
    let deltaMemory: Int64
    let flowsInDB: Int
    let poolAfter: Int

    var successRate: Double {
        total > 0 ? Double(successes) / Double(total) * 100.0 : 0.0
    }

    func printMetric() {
        let line = "[STRESS_METRIC] test=\(testName) total=\(total) success=\(successes) failed=\(failures) duration_ms=\(String(format: "%.1f", durationMs)) avg_latency_ms=\(String(format: "%.1f", avgLatencyMs)) p99_latency_ms=\(String(format: "%.1f", p99LatencyMs)) baseline_mem=\(baselineMemory) peak_mem=\(peakMemory) delta_mem=\(deltaMemory) flows_in_db=\(flowsInDB) pool_after=\(poolAfter)"
        print(line)
    }
}

// MARK: - Shared NIO Client

/// A stress-test client that shares a single NIO event loop group across all requests.
/// This avoids the overhead of creating/destroying an ELG per request and prevents
/// deadlocks from too many concurrent syncShutdownGracefully() calls.
private final class StressNIOClient {
    private let group: MultiThreadedEventLoopGroup
    private let proxyHost: String
    private let proxyPort: Int

    init(proxyHost: String = "127.0.0.1", proxyPort: Int, threads: Int = 2) {
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
    }

    func shutdown() {
        try? group.syncShutdownGracefully()
    }

    /// Send a plain HTTP GET request through the proxy. Returns (statusCode, latencyMs).
    func httpGET(host: String, port: Int, uri: String) -> (UInt, Double) {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let el = group.next()
            let responsePromise = el.makePromise(of: TestHTTPResponse.self)

            let bootstrap = ClientBootstrap(group: el)
                .connectTimeout(.seconds(10))
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers().flatMap {
                        channel.pipeline.addHandler(StressHTTPCollector(promise: responsePromise))
                    }
                }

            let channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()

            let absoluteURI = "http://\(host):\(port)\(uri)"
            var headers = HTTPHeaders()
            headers.add(name: "Host", value: "\(host):\(port)")

            let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: absoluteURI, headers: headers)
            channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
            channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

            // Schedule timeout to avoid hanging forever
            let timeout = el.scheduleTask(in: .seconds(30)) {
                responsePromise.fail(StressTestError.timeout)
            }

            let response = try responsePromise.futureResult.wait()
            timeout.cancel()
            try? channel.close().wait()
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            return (response.status, ms)
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            return (0, ms)
        }
    }

    /// Send an HTTPS GET request through the proxy via CONNECT tunnel. Returns (statusCode, latencyMs).
    func httpsGET(host: String, port: Int, uri: String, trustCA: NIOSSLCertificate?) -> (UInt, Double) {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let client = TestNIOClient(proxyPort: proxyPort)
            defer { client.shutdown() }
            let response = try client.httpsRequest(
                method: .GET,
                host: host,
                port: port,
                uri: uri,
                trustCA: trustCA
            )
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            return (response.status, ms)
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            return (0, ms)
        }
    }
}

private enum StressTestError: Error {
    case timeout
}

/// Minimal HTTP response collector for stress tests (avoids importing TestNIOClient internals).
private final class StressHTTPCollector: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private var head: HTTPResponseHead?
    private var body = Data()
    private let promise: EventLoopPromise<TestHTTPResponse>

    init(promise: EventLoopPromise<TestHTTPResponse>) {
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h):
            head = h
        case .body(var buf):
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            let response = TestHTTPResponse(
                status: UInt(head?.status.code ?? 0),
                headers: head?.headers.map { ($0.name, $0.value) } ?? [],
                body: body
            )
            promise.succeed(response)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
    }
}

// MARK: - Stress Runner

/// Fires `total` requests sequentially in batches of `batchSize`.
/// Each batch runs concurrently using DispatchQueue.concurrentPerform.
/// This avoids thread-pool exhaustion while still exercising concurrency.
private func runStressBatched(
    total: Int,
    batchSize: Int,
    iteration: @escaping (_ index: Int) -> (success: Bool, latencyMs: Double)
) -> (latencies: [Double], successes: Int, failures: Int, peakMemory: Int64, baselineMemory: Int64) {
    let baselineMemory = currentRSS()

    let lock = NSLock()
    var latencies: [Double] = []
    latencies.reserveCapacity(total)
    var successCount = 0
    var failCount = 0
    var peakMemory = baselineMemory

    var offset = 0
    while offset < total {
        let thisBatch = min(batchSize, total - offset)
        let batchOffset = offset

        DispatchQueue.concurrentPerform(iterations: thisBatch) { j in
            let i = batchOffset + j
            let (ok, latencyMs) = iteration(i)

            lock.lock()
            if ok { successCount += 1 } else { failCount += 1 }
            latencies.append(latencyMs)
            lock.unlock()
        }

        // Sample memory after each batch
        let mem = currentRSS()
        lock.lock()
        if mem > peakMemory { peakMemory = mem }
        lock.unlock()

        offset += thisBatch
    }

    let finalMem = currentRSS()
    if finalMem > peakMemory { peakMemory = finalMem }

    return (latencies, successCount, failCount, peakMemory, baselineMemory)
}

private func buildResult(
    testName: String,
    total: Int,
    latencies: [Double],
    successes: Int,
    failures: Int,
    baselineMemory: Int64,
    peakMemory: Int64,
    flowsInDB: Int,
    poolAfter: Int,
    durationMs: Double
) -> StressResult {
    let sorted = latencies.sorted()
    let avg = sorted.isEmpty ? 0.0 : sorted.reduce(0.0, +) / Double(sorted.count)
    let p99Idx = sorted.isEmpty ? 0 : min(Int(Double(sorted.count) * 0.99), sorted.count - 1)
    let p99 = sorted.isEmpty ? 0.0 : sorted[p99Idx]

    return StressResult(
        testName: testName,
        total: total,
        successes: successes,
        failures: failures,
        durationMs: durationMs,
        avgLatencyMs: avg,
        p99LatencyMs: p99,
        baselineMemory: baselineMemory,
        peakMemory: peakMemory,
        deltaMemory: peakMemory - baselineMemory,
        flowsInDB: flowsInDB,
        poolAfter: poolAfter
    )
}

// MARK: - Plain HTTP Stress Tests

final class StressTests_HTTP1_Plaintext: XCTestCase {

    private func runHTTPStress(
        testName: String,
        concurrency: Int
    ) throws -> StressResult {
        let echoServer = TestEchoServer(mode: .http1)
        let serverPort = try echoServer.start()

        let launcher = try TestProxyLauncher(sslEnabled: false, withCA: false)
        let proxyPort = try launcher.start()

        // Shared client with 2 NIO threads -- handles all connections.
        let stressClient = StressNIOClient(proxyPort: proxyPort, threads: 2)

        defer {
            stressClient.shutdown()
            launcher.stop()
            try? echoServer.stop()
        }

        // Use batches of 4: concurrentPerform limits to CPU cores,
        // each iteration blocks on .wait() but the NIO ELG is shared.
        // Keep batch size small to avoid overwhelming the proxy's 2 worker threads.
        let batchSize = 4
        let startTime = CFAbsoluteTimeGetCurrent()

        let (latencies, successes, failures, peakMem, baseMem) = runStressBatched(
            total: concurrency,
            batchSize: batchSize
        ) { i in
            let (status, latencyMs) = stressClient.httpGET(
                host: "127.0.0.1", port: serverPort, uri: "/stress/\(i)"
            )
            return (status == 200, latencyMs)
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        // Wait for DB writes to flush
        Thread.sleep(forTimeInterval: 2.0)

        let flows: [FlowRecord]
        do { flows = try launcher.queryFlows() } catch { flows = [] }

        let poolAfter = launcher.connectionPool?.count ?? 0

        let result = buildResult(
            testName: testName,
            total: concurrency,
            latencies: latencies,
            successes: successes,
            failures: failures,
            baselineMemory: baseMem,
            peakMemory: peakMem,
            flowsInDB: flows.count,
            poolAfter: poolAfter,
            durationMs: durationMs
        )
        result.printMetric()
        return result
    }

    func testStress_HTTP1_Plaintext_Light() throws {
        let result = try runHTTPStress(testName: "HTTP1_Plaintext_Light", concurrency: 100)

        // Allow up to 2 failures for connection timing edge cases under load
        let minSuccess = result.total - 2
        XCTAssertGreaterThanOrEqual(result.successes, minSuccess,
            "Light: expected >=98% success rate, got \(result.successes)/\(result.total)")
        XCTAssertLessThan(result.deltaMemory, 50 * 1024 * 1024,
            "Light: memory delta \(result.deltaMemory) should be < 50MB")
    }

    func testStress_HTTP1_Plaintext_Medium() throws {
        let result = try runHTTPStress(testName: "HTTP1_Plaintext_Medium", concurrency: 1000)

        let minSuccess = Int(Double(result.total) * 0.99)
        XCTAssertGreaterThanOrEqual(result.successes, minSuccess,
            "Medium: expected >=99% success rate, got \(result.successes)/\(result.total)")
        XCTAssertLessThan(result.deltaMemory, 100 * 1024 * 1024,
            "Medium: memory delta \(result.deltaMemory) should be < 100MB")
    }

    func testStress_HTTP1_Plaintext_Heavy() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_STRESS_HEAVY"] == nil,
            "Set RUN_STRESS_HEAVY=1 to run"
        )

        let result = try runHTTPStress(testName: "HTTP1_Plaintext_Heavy", concurrency: 5000)

        let minSuccess = Int(Double(result.total) * 0.95)
        XCTAssertGreaterThanOrEqual(result.successes, minSuccess,
            "Heavy: expected >=95% success rate, got \(result.successes)/\(result.total)")
        XCTAssertLessThan(result.deltaMemory, 200 * 1024 * 1024,
            "Heavy: memory delta \(result.deltaMemory) should be < 200MB")
    }
}

// MARK: - HTTPS MITM Stress Tests

final class StressTests_HTTPS_MITM: XCTestCase {

    private func runHTTPSStress(
        testName: String,
        concurrency: Int
    ) throws -> StressResult {
        let (cert, key) = try TestEchoServer.generateServerCert()
        let echoServer = TestEchoServer(mode: .http1TLS(cert: cert, key: key))
        let serverPort = try echoServer.start()

        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        let caCert = launcher.caCertificate

        defer {
            launcher.stop()
            try? echoServer.stop()
        }

        // HTTPS MITM: each request needs its own TestNIOClient (CONNECT + TLS).
        // Use batches of 2 with concurrentPerform to get parallelism without
        // exhausting the GCD thread pool. Batch of 2 avoids TLS handshake
        // contention that can cause timeouts at higher parallelism.
        let batchSize = 2
        let startTime = CFAbsoluteTimeGetCurrent()

        let (latencies, successes, failures, peakMem, baseMem) = runStressBatched(
            total: concurrency,
            batchSize: batchSize
        ) { i in
            let client = TestNIOClient(proxyPort: proxyPort)
            defer { client.shutdown() }
            let iterStart = CFAbsoluteTimeGetCurrent()
            do {
                let response = try client.httpsRequest(
                    method: .GET,
                    host: "localhost",
                    port: serverPort,
                    uri: "/stress/\(i)",
                    trustCA: caCert
                )
                let ms = (CFAbsoluteTimeGetCurrent() - iterStart) * 1000.0
                return (response.status == 200, ms)
            } catch {
                let ms = (CFAbsoluteTimeGetCurrent() - iterStart) * 1000.0
                return (false, ms)
            }
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        // Wait for DB writes to flush
        Thread.sleep(forTimeInterval: 2.0)

        let flows: [FlowRecord]
        do { flows = try launcher.queryFlows() } catch { flows = [] }

        let poolAfter = launcher.connectionPool?.count ?? 0

        let result = buildResult(
            testName: testName,
            total: concurrency,
            latencies: latencies,
            successes: successes,
            failures: failures,
            baselineMemory: baseMem,
            peakMemory: peakMem,
            flowsInDB: flows.count,
            poolAfter: poolAfter,
            durationMs: durationMs
        )
        result.printMetric()
        return result
    }

    func testStress_HTTPS_MITM_Light() throws {
        let result = try runHTTPSStress(testName: "HTTPS_MITM_Light", concurrency: 100)

        // Allow up to 1 failure for TLS handshake timing edge cases
        let minSuccess = result.total - 1
        XCTAssertGreaterThanOrEqual(result.successes, minSuccess,
            "Light: expected >=99% success rate, got \(result.successes)/\(result.total)")
        XCTAssertLessThan(result.deltaMemory, 100 * 1024 * 1024,
            "Light: memory delta \(result.deltaMemory) should be < 100MB")
    }

    func testStress_HTTPS_MITM_Medium() throws {
        let result = try runHTTPSStress(testName: "HTTPS_MITM_Medium", concurrency: 1000)

        let minSuccess = Int(Double(result.total) * 0.99)
        XCTAssertGreaterThanOrEqual(result.successes, minSuccess,
            "Medium: expected >=99% success rate, got \(result.successes)/\(result.total)")
        XCTAssertLessThan(result.deltaMemory, 200 * 1024 * 1024,
            "Medium: memory delta \(result.deltaMemory) should be < 200MB")
    }

    func testStress_HTTPS_MITM_Heavy() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_STRESS_HEAVY"] == nil,
            "Set RUN_STRESS_HEAVY=1 to run"
        )

        let result = try runHTTPSStress(testName: "HTTPS_MITM_Heavy", concurrency: 5000)

        let minSuccess = Int(Double(result.total) * 0.95)
        XCTAssertGreaterThanOrEqual(result.successes, minSuccess,
            "Heavy: expected >=95% success rate, got \(result.successes)/\(result.total)")
        XCTAssertLessThan(result.deltaMemory, 300 * 1024 * 1024,
            "Heavy: memory delta \(result.deltaMemory) should be < 300MB")
    }
}
