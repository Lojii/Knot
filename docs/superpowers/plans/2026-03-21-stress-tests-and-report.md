# Stress Tests + Script + HTML Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three-tier stress tests (100/1000/5000 concurrent requests) with memory profiling, a shell script runner, and an HTML test report that Claude can read for debugging.

**Architecture:** StressTests.swift uses the existing TestEchoServer + TestProxyLauncher + TestNIOClient infrastructure. A shell script runs tests via `swift test --xunit-output`, then a Swift script parses JUnit XML + stress metrics from stdout to generate a self-contained HTML report.

**Tech Stack:** Swift, XCTest, SwiftNIO, JUnit XML, HTML/CSS/JS

**Spec:** `docs/superpowers/specs/2026-03-21-integration-tests-design.md` (Stress Tests section)

**Depends on:** Plan 1 (integration tests infrastructure) — completed.

---

## File Structure

### New Files (Tests)
- `Tests/TunnelServicesTests/Integration/StressTests.swift` — Three-tier stress tests with memory monitoring

### New Files (Scripts)
- `scripts/run-integration-tests.sh` — Test runner with JUnit XML capture
- `scripts/generate-test-report.swift` — Parses JUnit XML + stress metrics → HTML report

---

## Priority Order

| P | Task | Impact |
|---|------|--------|
| P0 | Task 1: StressTests.swift | Core stress test code |
| P0 | Task 2: run-integration-tests.sh | Test execution script |
| P1 | Task 3: generate-test-report.swift + HTML | Report generation |

---

### Task 1: StressTests.swift

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/StressTests.swift`

**Design:** Each stress test creates an echo server + proxy, fires N concurrent requests using DispatchGroup + DispatchQueue.concurrentPerform, collects results, asserts thresholds, and prints structured `[STRESS_METRIC]` lines for the report generator.

- [ ] **Step 1: Implement StressResult and memory monitoring**

```swift
import XCTest
import Foundation
import NIO
import NIOHTTP1
@testable import TunnelServices

struct StressResult {
    let totalRequests: Int
    let successCount: Int
    let failureCount: Int
    let totalDurationMs: Double
    let avgLatencyMs: Double
    let p99LatencyMs: Double
    let peakMemoryBytes: Int64
    let baselineMemoryBytes: Int64
    let memoryDeltaBytes: Int64
    let flowsInDB: Int
    let pooledConnectionsAfter: Int
}

func currentRSS() -> Int64 {
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
```

- [ ] **Step 2: Implement stress test runner helper**

```swift
final class StressTests: XCTestCase {

    /// Run a stress test with the given concurrency level.
    private func runStress(
        name: String,
        concurrency: Int,
        sslEnabled: Bool = false,
        timeout: TimeInterval = 60
    ) throws -> StressResult {
        // 1. Start echo server + proxy
        let echoServer = TestEchoServer(mode: .http1)
        let serverPort = try echoServer.start()
        let launcher = try TestProxyLauncher(sslEnabled: sslEnabled, withCA: sslEnabled)
        let proxyPort = try launcher.start()
        defer {
            launcher.stop()
            try? echoServer.stop()
        }

        // 2. Baseline memory
        let baseline = currentRSS()
        var peak = baseline

        // 3. Fire concurrent requests
        var latencies = [Double](repeating: 0, count: concurrency)
        var successes = [Bool](repeating: false, count: concurrency)
        let startTime = Date()

        DispatchQueue.concurrentPerform(iterations: concurrency) { i in
            let client = TestNIOClient(proxyPort: proxyPort)
            defer { client.shutdown() }
            let t0 = Date()
            do {
                let rsp = try client.httpRequest(
                    method: .GET, host: "127.0.0.1", port: serverPort, uri: "/stress/\(i)"
                )
                successes[i] = (rsp.status == 200)
            } catch {
                successes[i] = false
            }
            latencies[i] = Date().timeIntervalSince(t0) * 1000

            // Sample memory every 100 requests
            if i % 100 == 0 {
                let mem = currentRSS()
                if mem > peak { peak = mem }
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime) * 1000
        let successCount = successes.filter { $0 }.count
        let sortedLatencies = latencies.sorted()
        let p99Index = min(Int(Double(concurrency) * 0.99), concurrency - 1)

        // 4. Wait for DB writes
        Thread.sleep(forTimeInterval: 2.0)
        let flows = try launcher.queryFlows()

        let result = StressResult(
            totalRequests: concurrency,
            successCount: successCount,
            failureCount: concurrency - successCount,
            totalDurationMs: totalDuration,
            avgLatencyMs: latencies.reduce(0, +) / Double(concurrency),
            p99LatencyMs: sortedLatencies[p99Index],
            peakMemoryBytes: peak,
            baselineMemoryBytes: baseline,
            memoryDeltaBytes: peak - baseline,
            flowsInDB: flows.count,
            pooledConnectionsAfter: launcher.connectionPool?.count ?? 0
        )

        // 5. Print structured metric for report generator
        print("[STRESS_METRIC] test=\(name) total=\(result.totalRequests) success=\(result.successCount) failed=\(result.failureCount) duration_ms=\(Int(result.totalDurationMs)) avg_latency_ms=\(String(format: "%.1f", result.avgLatencyMs)) p99_latency_ms=\(String(format: "%.1f", result.p99LatencyMs)) baseline_mem=\(result.baselineMemoryBytes) peak_mem=\(result.peakMemoryBytes) delta_mem=\(result.memoryDeltaBytes) flows_in_db=\(result.flowsInDB) pool_after=\(result.pooledConnectionsAfter)")

        return result
    }
}
```

- [ ] **Step 3: Implement HTTP/1.1 plaintext stress tests (3 levels)**

```swift
    func testStress_HTTP1_Plaintext_Light() throws {
        let result = try runStress(name: "HTTP1_Plaintext_Light", concurrency: 100, timeout: 30)
        XCTAssertEqual(result.successCount, result.totalRequests, "Light: 100% success required")
        XCTAssertEqual(result.flowsInDB, result.successCount, "Every success must be recorded")
        XCTAssertLessThan(result.memoryDeltaBytes, 10_000_000, "Memory delta < 10MB")
        XCTAssertLessThanOrEqual(result.pooledConnectionsAfter, 32, "Pool max 32")
    }

    func testStress_HTTP1_Plaintext_Medium() throws {
        let result = try runStress(name: "HTTP1_Plaintext_Medium", concurrency: 1000, timeout: 60)
        XCTAssertGreaterThanOrEqual(Double(result.successCount) / Double(result.totalRequests), 0.99, "Medium: >= 99% success")
        XCTAssertEqual(result.flowsInDB, result.successCount)
        XCTAssertLessThan(result.memoryDeltaBytes, 50_000_000, "Memory delta < 50MB")
    }

    func testStress_HTTP1_Plaintext_Heavy() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_STRESS_HEAVY"] == nil,
            "Heavy stress test skipped. Set RUN_STRESS_HEAVY=1 to run."
        )
        let result = try runStress(name: "HTTP1_Plaintext_Heavy", concurrency: 5000, timeout: 180)
        XCTAssertGreaterThanOrEqual(Double(result.successCount) / Double(result.totalRequests), 0.95, "Heavy: >= 95% success")
        XCTAssertEqual(result.flowsInDB, result.successCount)
        XCTAssertLessThan(result.memoryDeltaBytes, 200_000_000, "Memory delta < 200MB")
    }
```

- [ ] **Step 4: Implement HTTPS MITM stress tests**

```swift
    func testStress_HTTPS_MITM_Light() throws {
        let result = try runStress(name: "HTTPS_MITM_Light", concurrency: 100, sslEnabled: true, timeout: 60)
        XCTAssertEqual(result.successCount, result.totalRequests)
        XCTAssertEqual(result.flowsInDB, result.successCount)
        XCTAssertLessThan(result.memoryDeltaBytes, 20_000_000, "MITM has higher overhead")
    }

    func testStress_HTTPS_MITM_Medium() throws {
        let result = try runStress(name: "HTTPS_MITM_Medium", concurrency: 1000, sslEnabled: true, timeout: 120)
        XCTAssertGreaterThanOrEqual(Double(result.successCount) / Double(result.totalRequests), 0.99)
        XCTAssertEqual(result.flowsInDB, result.successCount)
        XCTAssertLessThan(result.memoryDeltaBytes, 100_000_000)
    }

    func testStress_HTTPS_MITM_Heavy() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_STRESS_HEAVY"] == nil,
            "Heavy stress test skipped. Set RUN_STRESS_HEAVY=1 to run."
        )
        let result = try runStress(name: "HTTPS_MITM_Heavy", concurrency: 5000, sslEnabled: true, timeout: 300)
        XCTAssertGreaterThanOrEqual(Double(result.successCount) / Double(result.totalRequests), 0.95)
        XCTAssertLessThan(result.memoryDeltaBytes, 300_000_000)
    }
```

- [ ] **Step 5: Run stress tests (light only for CI)**

Run: `swift test --package-path LocalPackages/TunnelServices --filter "testStress.*Light"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/StressTests.swift
git commit -m "feat: add three-tier stress tests with memory monitoring"
```

---

### Task 2: run-integration-tests.sh

**Files:**
- Create: `scripts/run-integration-tests.sh`

- [ ] **Step 1: Implement the script**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$PROJECT_DIR/LocalPackages/TunnelServices"
REPORT_DIR="${TEST_REPORT_DIR:-$PROJECT_DIR/build/test-reports}"
JUNIT_XML="$REPORT_DIR/results.xml"
STDOUT_LOG="$REPORT_DIR/test-output.log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Parse args
RUN_ALL=false
FILTER=""
STRESS_ONLY=false
NO_OPEN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)       RUN_ALL=true; shift ;;
        --filter)    FILTER="$2"; shift 2 ;;
        --stress-only) STRESS_ONLY=true; shift ;;
        --no-open)   NO_OPEN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --all          Run all tests including heavy stress"
            echo "  --filter NAME  Run only tests matching NAME"
            echo "  --stress-only  Run only stress tests"
            echo "  --no-open      Don't open HTML report in browser"
            echo ""
            echo "Environment:"
            echo "  RUN_STRESS_HEAVY=1  Enable heavy stress tests"
            echo "  TEST_REPORT_DIR=dir Custom report output directory"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Create report dir
mkdir -p "$REPORT_DIR"

# Build filter
TEST_FILTER=""
if [[ -n "$FILTER" ]]; then
    TEST_FILTER="--filter $FILTER"
elif [[ "$STRESS_ONLY" == "true" ]]; then
    TEST_FILTER="--filter Stress"
else
    TEST_FILTER="--filter 'Integration|EdgeCase|Stress'"
fi

# Set env for heavy tests
if [[ "$RUN_ALL" == "true" ]]; then
    export RUN_STRESS_HEAVY=1
fi

echo "=== TunnelServices Integration Tests ==="
echo "Report dir: $REPORT_DIR"
echo "Filter: ${TEST_FILTER:-all}"
echo ""

# Run tests with JUnit XML output, capture stdout for stress metrics
set +e
swift test \
    --package-path "$PACKAGE_DIR" \
    --xunit-output "$JUNIT_XML" \
    $TEST_FILTER \
    2>&1 | tee "$STDOUT_LOG"
TEST_EXIT=$?
set -e

echo ""
echo "=== Test Exit Code: $TEST_EXIT ==="

# Generate HTML report
if command -v swift &>/dev/null; then
    echo "Generating HTML report..."
    swift "$SCRIPT_DIR/generate-test-report.swift" \
        "$JUNIT_XML" "$STDOUT_LOG" "$REPORT_DIR/integration-test-report.html"

    if [[ "$NO_OPEN" != "true" ]] && [[ -f "$REPORT_DIR/integration-test-report.html" ]]; then
        open "$REPORT_DIR/integration-test-report.html" 2>/dev/null || true
    fi
fi

echo "=== Done ==="
echo "JUnit XML: $JUNIT_XML"
echo "HTML Report: $REPORT_DIR/integration-test-report.html"
echo "Raw Log: $STDOUT_LOG"

exit $TEST_EXIT
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/run-integration-tests.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/run-integration-tests.sh
git commit -m "feat: add integration test runner script with JUnit XML capture"
```

---

### Task 3: generate-test-report.swift + HTML

**Files:**
- Create: `scripts/generate-test-report.swift`

- [ ] **Step 1: Implement the report generator**

A standalone Swift script that:
1. Reads JUnit XML (from `swift test --xunit-output`)
2. Reads stdout log for `[STRESS_METRIC]` lines
3. Generates a self-contained HTML file with:
   - Summary bar (pass/fail/skip, duration)
   - Protocol coverage matrix
   - Per-test details (collapsible, with failure messages)
   - Stress dashboard (latency, memory, throughput)
   - Embedded JSON (`window.testResults = {...}`) for Claude to parse

The HTML must be:
- Self-contained (inline CSS/JS, no external deps)
- Machine-readable (embedded JSON in `<script>`)
- Human-readable (clean layout, color-coded)

Key sections:
```swift
#!/usr/bin/env swift
import Foundation

// 1. Parse JUnit XML
struct TestCase { let className, name: String; let time: Double; let failure: String? }
func parseJUnit(xmlPath: String) -> [TestCase] { ... }

// 2. Parse stress metrics from stdout
struct StressMetric { let test: String; let total, success, failed: Int; ... }
func parseStressMetrics(logPath: String) -> [StressMetric] { ... }

// 3. Generate HTML
func generateHTML(tests: [TestCase], stress: [StressMetric]) -> String { ... }

// Main
let args = CommandLine.arguments
guard args.count == 4 else { print("Usage: ..."); exit(1) }
let tests = parseJUnit(xmlPath: args[1])
let stress = parseStressMetrics(logPath: args[2])
let html = generateHTML(tests: tests, stress: stress)
try html.write(toFile: args[3], atomically: true, encoding: .utf8)
```

The HTML template should include:
- Green/red/yellow badges for pass/fail/skip
- Collapsible test details
- Bar charts for stress memory (CSS-only, no JS framework)
- `window.testResults = { tests: [...], stress: [...] }` JSON blob

- [ ] **Step 2: Test the report generator**

```bash
# Run tests first to generate data
./scripts/run-integration-tests.sh --no-open
# Check report exists and is valid HTML
ls -la build/test-reports/integration-test-report.html
```

- [ ] **Step 3: Commit**

```bash
git add scripts/generate-test-report.swift
git commit -m "feat: add HTML test report generator with stress dashboard"
```

---

## Post-Implementation Verification

1. **Light stress tests pass**: `swift test --package-path LocalPackages/TunnelServices --filter "testStress.*Light"`
2. **Script works**: `./scripts/run-integration-tests.sh --no-open`
3. **HTML report exists**: `build/test-reports/integration-test-report.html`
4. **Report is readable by Claude**: `cat build/test-reports/integration-test-report.html` should show embedded JSON with test results
5. **Heavy tests (manual)**: `RUN_STRESS_HEAVY=1 ./scripts/run-integration-tests.sh --stress-only`
