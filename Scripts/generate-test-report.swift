#!/usr/bin/env swift
import Foundation

// MARK: - Models

struct TestCase {
    let className: String
    let name: String
    let time: Double
    let status: String      // "passed", "failed", "skipped"
    let failure: String?
}

struct StressMetric {
    let test: String
    let total: Int
    let success: Int
    let failed: Int
    let durationMs: Double
    let avgLatencyMs: Double
    let p99LatencyMs: Double
    let baselineMem: Int
    let peakMem: Int
    let deltaMem: Int
    let flowsInDB: Int
    let poolAfter: Int
}

// MARK: - JUnit XML Parser

func parseJUnitXML(at path: String) -> [TestCase] {
    guard let data = FileManager.default.contents(atPath: path) else {
        fputs("Error: cannot read \(path)\n", stderr)
        return []
    }

    var results: [TestCase] = []

    do {
        let doc = try XMLDocument(data: data)
        let testcases = try doc.nodes(forXPath: "//testcase")

        for node in testcases {
            guard let element = node as? XMLElement else { continue }

            let className = element.attribute(forName: "classname")?.stringValue ?? ""
            let name = element.attribute(forName: "name")?.stringValue ?? ""
            let time = Double(element.attribute(forName: "time")?.stringValue ?? "0") ?? 0

            let failures = element.elements(forName: "failure")
            let skipped = element.elements(forName: "skipped")

            let status: String
            let failure: String?

            if !failures.isEmpty {
                status = "failed"
                failure = failures.first?.attribute(forName: "message")?.stringValue
                    ?? failures.first?.stringValue
                    ?? "Test failed"
            } else if !skipped.isEmpty {
                status = "skipped"
                failure = nil
            } else {
                status = "passed"
                failure = nil
            }

            results.append(TestCase(
                className: className,
                name: name,
                time: time,
                status: status,
                failure: failure
            ))
        }
    } catch {
        fputs("Error parsing XML: \(error)\n", stderr)
    }

    return results
}

// MARK: - Stress Metric Parser

func parseStressMetrics(logPath: String) -> [StressMetric] {
    guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
        return []
    }

    var metrics: [StressMetric] = []
    let lines = content.components(separatedBy: .newlines)

    for line in lines {
        guard line.contains("[STRESS_METRIC]") else { continue }

        // Parse key=value pairs after the tag
        let payload = line.components(separatedBy: "[STRESS_METRIC]").last ?? ""
        var kv: [String: String] = [:]

        let parts = payload.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        for part in parts {
            let pair = part.components(separatedBy: "=")
            if pair.count == 2 {
                kv[pair[0]] = pair[1]
            }
        }

        guard let test = kv["test"] else { continue }

        metrics.append(StressMetric(
            test: test,
            total: Int(kv["total"] ?? "0") ?? 0,
            success: Int(kv["success"] ?? "0") ?? 0,
            failed: Int(kv["failed"] ?? "0") ?? 0,
            durationMs: Double(kv["duration_ms"] ?? "0") ?? 0,
            avgLatencyMs: Double(kv["avg_latency_ms"] ?? "0") ?? 0,
            p99LatencyMs: Double(kv["p99_latency_ms"] ?? "0") ?? 0,
            baselineMem: Int(kv["baseline_mem"] ?? "0") ?? 0,
            peakMem: Int(kv["peak_mem"] ?? "0") ?? 0,
            deltaMem: Int(kv["delta_mem"] ?? "0") ?? 0,
            flowsInDB: Int(kv["flows_in_db"] ?? "0") ?? 0,
            poolAfter: Int(kv["pool_after"] ?? "0") ?? 0
        ))
    }

    return metrics
}

// MARK: - JSON Builder

func escapeJSON(_ s: String) -> String {
    return s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

func buildJSON(tests: [TestCase], stress: [StressMetric], duration: Double) -> String {
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: Date())

    let passed = tests.filter { $0.status == "passed" }.count
    let failed = tests.filter { $0.status == "failed" }.count
    let skipped = tests.filter { $0.status == "skipped" }.count

    var json = "{\n"
    json += "  \"timestamp\": \"\(timestamp)\",\n"
    json += "  \"summary\": { \"total\": \(tests.count), \"passed\": \(passed), \"failed\": \(failed), \"skipped\": \(skipped), \"duration\": \(String(format: "%.1f", duration)) },\n"

    // Tests array
    json += "  \"tests\": [\n"
    for (i, t) in tests.enumerated() {
        let failStr = t.failure.map { "\"\(escapeJSON($0))\"" } ?? "null"
        json += "    { \"className\": \"\(escapeJSON(t.className))\", \"name\": \"\(escapeJSON(t.name))\", \"time\": \(String(format: "%.2f", t.time)), \"status\": \"\(t.status)\", \"failure\": \(failStr) }"
        json += i < tests.count - 1 ? ",\n" : "\n"
    }
    json += "  ],\n"

    // Stress array
    json += "  \"stress\": [\n"
    for (i, s) in stress.enumerated() {
        json += "    { \"test\": \"\(escapeJSON(s.test))\", \"total\": \(s.total), \"success\": \(s.success), \"failed\": \(s.failed), "
        json += "\"duration_ms\": \(String(format: "%.1f", s.durationMs)), \"avg_latency_ms\": \(String(format: "%.1f", s.avgLatencyMs)), "
        json += "\"p99_latency_ms\": \(String(format: "%.1f", s.p99LatencyMs)), "
        json += "\"baseline_mem\": \(s.baselineMem), \"peak_mem\": \(s.peakMem), \"delta_mem\": \(s.deltaMem), "
        json += "\"flows_in_db\": \(s.flowsInDB), \"pool_after\": \(s.poolAfter) }"
        json += i < stress.count - 1 ? ",\n" : "\n"
    }
    json += "  ]\n"

    json += "}"
    return json
}

// MARK: - HTML Generator

func escapeHTML(_ s: String) -> String {
    return s
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

func formatBytes(_ bytes: Int) -> String {
    let mb = Double(bytes) / (1024 * 1024)
    return String(format: "%.1f MB", mb)
}

func generateHTML(tests: [TestCase], stress: [StressMetric], jsonData: String) -> String {
    let passed = tests.filter { $0.status == "passed" }.count
    let failed = tests.filter { $0.status == "failed" }.count
    let skipped = tests.filter { $0.status == "skipped" }.count
    let totalDuration = tests.reduce(0.0) { $0 + $1.time }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = formatter.string(from: Date())

    var html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Integration Test Report</title>
    <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
        background: #f8f9fa; color: #1a1a2e; line-height: 1.6; padding: 24px; max-width: 1200px; margin: 0 auto;
    }
    h1 { font-size: 1.5rem; margin-bottom: 4px; }
    h2 { font-size: 1.2rem; margin: 32px 0 16px; color: #374151; }
    .meta { color: #6b7280; font-size: 0.85rem; margin-bottom: 24px; }

    /* Summary bar */
    .summary {
        display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 24px;
        padding: 16px; background: #fff; border-radius: 8px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    .summary-card {
        flex: 1; min-width: 100px; text-align: center; padding: 12px;
        border-radius: 6px; background: #f9fafb;
    }
    .summary-card .num { font-size: 1.8rem; font-weight: 700; }
    .summary-card .label { font-size: 0.75rem; text-transform: uppercase; color: #6b7280; letter-spacing: 0.05em; }
    .card-passed .num { color: #22c55e; }
    .card-failed .num { color: #ef4444; }
    .card-skipped .num { color: #eab308; }
    .card-total .num { color: #3b82f6; }
    .card-time .num { color: #6b7280; font-size: 1.4rem; }

    /* Table */
    table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
    th { background: #f3f4f6; text-align: left; padding: 10px 14px; font-size: 0.8rem; text-transform: uppercase; color: #6b7280; letter-spacing: 0.04em; }
    td { padding: 10px 14px; border-top: 1px solid #f0f0f0; font-size: 0.9rem; }
    tr:hover { background: #fafbfc; }

    /* Badges */
    .badge {
        display: inline-block; padding: 2px 10px; border-radius: 9999px;
        font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.03em;
    }
    .badge-passed { background: #dcfce7; color: #166534; }
    .badge-failed { background: #fee2e2; color: #991b1b; }
    .badge-skipped { background: #fef9c3; color: #854d0e; }

    /* Failure details */
    details { cursor: pointer; }
    details summary { font-size: 0.8rem; color: #ef4444; }
    details pre { margin-top: 8px; padding: 10px; background: #fef2f2; border-radius: 4px; font-size: 0.8rem; overflow-x: auto; white-space: pre-wrap; word-break: break-word; }

    /* Stress dashboard */
    .stress-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 16px; }
    .stress-card {
        background: #fff; border-radius: 8px; padding: 16px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    .stress-card h3 { font-size: 0.95rem; margin-bottom: 12px; color: #1e293b; }
    .stress-row { display: flex; justify-content: space-between; padding: 4px 0; font-size: 0.85rem; }
    .stress-label { color: #6b7280; }
    .stress-value { font-weight: 600; color: #1e293b; }
    .mem-bar-container { margin-top: 8px; height: 12px; background: #f0f0f0; border-radius: 6px; overflow: hidden; }
    .mem-bar { height: 100%; border-radius: 6px; background: linear-gradient(90deg, #22c55e, #eab308, #ef4444); transition: width 0.3s; }
    .success-rate { font-size: 1.1rem; font-weight: 700; }
    .rate-good { color: #22c55e; }
    .rate-warn { color: #eab308; }
    .rate-bad { color: #ef4444; }
    </style>
    </head>
    <body>
    <h1>Integration Test Report</h1>
    <p class="meta">\(escapeHTML(timestamp)) &middot; \(tests.count) tests &middot; \(String(format: "%.1f", totalDuration))s</p>

    <!-- Summary -->
    <div class="summary">
        <div class="summary-card card-total"><div class="num">\(tests.count)</div><div class="label">Total</div></div>
        <div class="summary-card card-passed"><div class="num">\(passed)</div><div class="label">Passed</div></div>
        <div class="summary-card card-failed"><div class="num">\(failed)</div><div class="label">Failed</div></div>
        <div class="summary-card card-skipped"><div class="num">\(skipped)</div><div class="label">Skipped</div></div>
        <div class="summary-card card-time"><div class="num">\(String(format: "%.1f", totalDuration))s</div><div class="label">Duration</div></div>
    </div>

    <!-- Test Results -->
    <h2>Test Results</h2>
    <table>
    <thead><tr><th>Class</th><th>Test</th><th>Status</th><th>Time</th><th>Details</th></tr></thead>
    <tbody>
    """

    for t in tests {
        let badgeClass = "badge-\(t.status)"
        let detailCell: String
        if let failure = t.failure {
            detailCell = "<details><summary>Show failure</summary><pre>\(escapeHTML(failure))</pre></details>"
        } else {
            detailCell = "&mdash;"
        }
        html += "<tr>"
        html += "<td>\(escapeHTML(t.className))</td>"
        html += "<td>\(escapeHTML(t.name))</td>"
        html += "<td><span class=\"badge \(badgeClass)\">\(t.status)</span></td>"
        html += "<td>\(String(format: "%.2f", t.time))s</td>"
        html += "<td>\(detailCell)</td>"
        html += "</tr>\n"
    }

    html += """
    </tbody>
    </table>
    """

    // Stress dashboard
    if !stress.isEmpty {
        html += "\n<h2>Stress Test Dashboard</h2>\n<div class=\"stress-grid\">\n"

        for s in stress {
            let successRate = s.total > 0 ? Double(s.success) / Double(s.total) * 100 : 0
            let rateClass: String
            if successRate >= 99.0 { rateClass = "rate-good" }
            else if successRate >= 95.0 { rateClass = "rate-warn" }
            else { rateClass = "rate-bad" }

            let throughput = s.durationMs > 0 ? Double(s.total) / (s.durationMs / 1000.0) : 0

            // Memory bar: delta as percentage of peak (capped at 100%)
            let memPercent = s.peakMem > 0 ? min(100, Int(Double(s.deltaMem) / Double(s.peakMem) * 100)) : 0

            html += """
            <div class="stress-card">
                <h3>\(escapeHTML(s.test))</h3>
                <div class="stress-row"><span class="stress-label">Success Rate</span><span class="success-rate \(rateClass)">\(String(format: "%.1f", successRate))%</span></div>
                <div class="stress-row"><span class="stress-label">Requests</span><span class="stress-value">\(s.total) total, \(s.failed) failed</span></div>
                <div class="stress-row"><span class="stress-label">Avg Latency</span><span class="stress-value">\(String(format: "%.1f", s.avgLatencyMs)) ms</span></div>
                <div class="stress-row"><span class="stress-label">p99 Latency</span><span class="stress-value">\(String(format: "%.1f", s.p99LatencyMs)) ms</span></div>
                <div class="stress-row"><span class="stress-label">Throughput</span><span class="stress-value">\(String(format: "%.1f", throughput)) req/s</span></div>
                <div class="stress-row"><span class="stress-label">Memory (base / peak / delta)</span><span class="stress-value">\(formatBytes(s.baselineMem)) / \(formatBytes(s.peakMem)) / \(formatBytes(s.deltaMem))</span></div>
                <div class="mem-bar-container"><div class="mem-bar" style="width: \(memPercent)%"></div></div>
                <div class="stress-row"><span class="stress-label">DB Records</span><span class="stress-value">\(s.flowsInDB)</span></div>
                <div class="stress-row"><span class="stress-label">Pool Connections After</span><span class="stress-value">\(s.poolAfter)</span></div>
            </div>

            """
        }

        html += "</div>\n"
    }

    // Embedded JSON
    html += "\n<script>window.testResults = \(jsonData);</script>\n"

    html += """
    </body>
    </html>
    """

    return html
}

// MARK: - Main

guard CommandLine.arguments.count >= 4 else {
    fputs("Usage: generate-test-report.swift <junit.xml> <test-output.log> <output.html>\n", stderr)
    exit(1)
}

let xmlPath = CommandLine.arguments[1]
let logPath = CommandLine.arguments[2]
let outputPath = CommandLine.arguments[3]

let tests = parseJUnitXML(at: xmlPath)
let stress = parseStressMetrics(logPath: logPath)
let totalDuration = tests.reduce(0.0) { $0 + $1.time }
let jsonData = buildJSON(tests: tests, stress: stress, duration: totalDuration)
let html = generateHTML(tests: tests, stress: stress, jsonData: jsonData)

do {
    try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Report generated: \(outputPath)")
} catch {
    fputs("Error writing report: \(error)\n", stderr)
    exit(1)
}
