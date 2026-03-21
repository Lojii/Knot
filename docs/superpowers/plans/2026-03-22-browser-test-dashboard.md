# Browser Test + Real-Time Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed a real-time web dashboard in the proxy process (NIO HTTP+WebSocket on port 9090), launch Puppeteer-controlled Chromium for manual/auto browsing through the proxy, and automatically retest failed requests after browsing.

**Architecture:** DashboardServer is a NIO ServerBootstrap sharing the existing EventLoopGroup. It serves a self-contained HTML page and pushes flow/metrics/stats via WebSocket. Puppeteer launches Chromium with `--proxy-server`. On browser close, a Swift XCTest retests failed flows using TestNIOClient.

**Tech Stack:** SwiftNIO (HTTP+WebSocket), Node.js/Puppeteer, XCTest

**Spec:** `docs/superpowers/specs/2026-03-22-browser-test-dashboard-design.md`

---

## File Structure

### New Files (Swift Source)
- `Sources/TunnelServices/Dashboard/DashboardServer.swift` — NIO HTTP+WS server, connection management, push logic
- `Sources/TunnelServices/Dashboard/DashboardHTML.swift` — Self-contained HTML page as Swift string
- `Sources/TunnelServices/Dashboard/MetricsCollector.swift` — CPU/memory/connection metrics collection

### New Files (Tests)
- `Tests/TunnelServicesTests/Integration/RetestFailedFlows.swift` — Failed flow retester

### New Files (Scripts)
- `Scripts/browser-test/package.json` — Node.js dependencies (puppeteer)
- `Scripts/browser-test/browser-test.js` — Main Puppeteer script
- `Scripts/browser-test/sites.json` — 100 common websites list

### Modified Files
- `Sources/TunnelServices/Config/ProxyConfig.swift` — Add `Dashboard` enum
- `Sources/TunnelServices/Proxy/ProxyServer.swift` — Start/stop DashboardServer
- `Sources/TunnelServices/Framework/SessionRecorder.swift` — Push flow to dashboard
- `Sources/TunnelServices/CaptureTask.swift` — Hold dashboardServer ref, add MITMFailedHostTracker.count
- `Sources/TunnelServices/Proxy/OutboundConnectionPool.swift` — Add perKeyBreakdown()

---

## Priority Order

| P | Task | Impact |
|---|------|--------|
| P0 | Task 1: ProxyConfig + API additions | Config + missing APIs needed by dashboard |
| P0 | Task 2: DashboardServer core | HTTP+WS server, HTML page, push logic |
| P0 | Task 3: MetricsCollector | System metrics (CPU/memory/connections) |
| P0 | Task 4: Wire into ProxyServer + SessionRecorder | Integration |
| P1 | Task 5: Puppeteer scripts | Browser launcher + auto-surf |
| P1 | Task 6: RetestFailedFlows | Failed request retester |
| P2 | Task 7: End-to-end smoke test | Verify everything works together |

---

### Task 1: ProxyConfig + API Additions

**Files:**
- Modify: `Sources/TunnelServices/Config/ProxyConfig.swift`
- Modify: `Sources/TunnelServices/Proxy/OutboundConnectionPool.swift`
- Modify: `Sources/TunnelServices/CaptureTask.swift`

- [ ] **Step 1: Add Dashboard config to ProxyConfig**

In `ProxyConfig.swift`, add after the `Connection` enum (around line 135):

```swift
    public enum Dashboard {
        public static var port: Int = 9090
        public static var enabled: Bool = true
        public static var metricsIntervalMs: Int = 2000
        public static var statsIntervalMs: Int = 1000
    }
```

- [ ] **Step 2: Add perKeyBreakdown to OutboundConnectionPool**

Read `OutboundConnectionPool.swift`. Add after the `count(for:)` method:

```swift
    /// Returns per-key connection counts for dashboard metrics.
    public func perKeyBreakdown() -> [(key: String, count: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return pool.map { (key, entries) in
            ("\(key.host):\(key.port):\(key.isSSL ? "ssl" : "tcp")", entries.count)
        }
    }
```

- [ ] **Step 3: Add count to MITMFailedHostTracker**

In `CaptureTask.swift`, add to `MITMFailedHostTracker`:

```swift
    /// Number of hosts currently in the failed tracker.
    public var count: Int {
        lock.withLock { hosts.count }
    }
```

- [ ] **Step 4: Add dashboardServer reference to CaptureTask**

In `CaptureTask.swift`, in the CaptureTask class, add:

```swift
    /// Dashboard WebSocket server for real-time push (set by ProxyServer)
    public weak var dashboardServer: DashboardServer?
```

(Use `weak` since ProxyServer owns DashboardServer, not CaptureTask.)

- [ ] **Step 5: Build and test**

Run: `swift build --package-path LocalPackages/TunnelServices`
Run: `swift test --package-path LocalPackages/TunnelServices --filter "HTTP1Integration"`
Expected: Build passes, existing tests pass

- [ ] **Step 6: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/
git commit -m "feat: add Dashboard config, pool breakdown, tracker count, dashboardServer ref"
```

---

### Task 2: DashboardServer Core

**Files:**
- Create: `Sources/TunnelServices/Dashboard/DashboardServer.swift`
- Create: `Sources/TunnelServices/Dashboard/DashboardHTML.swift`

**Problem:** Need an HTTP+WebSocket server on port 9090 that serves an HTML dashboard and pushes real-time flow data.

- [ ] **Step 1: Create DashboardServer**

Create `Sources/TunnelServices/Dashboard/DashboardServer.swift`:

Key components:
- `ServerBootstrap` with `configureHTTPServerPipeline(withServerUpgrade:)` for WebSocket
- `DashboardHTTPHandler` — serves GET / (HTML), GET /api/stats (JSON)
- `DashboardWebSocketHandler` — manages WS connections, sends/receives frames
- `hasClients` — thread-safe via `NIOLockedValueBox<Int>`
- `pushFlow()` — serializes FlowRecord to JSON, broadcasts to all WS connections
- `pushStats()` — broadcasts stats JSON
- `pushMetrics()` — broadcasts system metrics JSON

WebSocket upgrade pattern (from TestEchoServer):
```swift
let upgrader = NIOWebSocketServerUpgrader(
    shouldUpgrade: { channel, _ in channel.eventLoop.makeSucceededFuture(HTTPHeaders()) },
    upgradePipelineHandler: { [weak self] channel, _ in
        if let h = try? channel.pipeline.syncOperations.handler(type: HTTPServerProtocolErrorHandler.self) {
            channel.pipeline.removeHandler(h).flatMap {
                channel.pipeline.addHandler(DashboardWebSocketHandler(server: self))
            }
        } else {
            channel.pipeline.addHandler(DashboardWebSocketHandler(server: self))
        }
    }
)
```

Push method (dispatch to dashboard EventLoop):
```swift
public func pushFlow(_ flowData: [String: Any]) {
    guard hasClients else { return }
    guard let json = try? JSONSerialization.data(withJSONObject: ["type": "flow", "data": flowData]) else { return }
    let text = String(data: json, encoding: .utf8) ?? ""
    dashboardEventLoop.execute { [weak self] in
        self?.broadcastText(text)
    }
}
```

- [ ] **Step 2: Create DashboardHTML**

Create `Sources/TunnelServices/Dashboard/DashboardHTML.swift`:

A single `static let html: String` containing the full self-contained HTML page. Use a raw string literal `#"""..."""#`.

The HTML includes:
- Top stats bar (total flows, success/fail, protocols, upload/download)
- System metrics cards (memory, CPU, connections, pool, uptime)
- Auto-surf progress bar (if applicable)
- Real-time flow table (auto-scroll, failed rows highlighted red)
- Retest results section
- WebSocket connection with auto-reconnect
- All CSS inline, no external deps

JavaScript handles:
```javascript
const ws = new WebSocket(`ws://${location.host}/ws`);
ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    switch(msg.type) {
        case 'flow': addFlowRow(msg.data); break;
        case 'stats': updateStats(msg.data); break;
        case 'metrics': updateMetrics(msg.data); break;
        case 'retest': addRetestRow(msg.data); break;
        case 'surf_progress': updateSurfProgress(msg.data); break;
    }
};
// Auto-reconnect
ws.onclose = () => setTimeout(() => location.reload(), 2000);
```

- [ ] **Step 3: Build to verify**

Run: `swift build --package-path LocalPackages/TunnelServices`

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/
git commit -m "feat: add DashboardServer with HTTP+WebSocket and HTML page"
```

---

### Task 3: MetricsCollector

**Files:**
- Create: `Sources/TunnelServices/Dashboard/MetricsCollector.swift`

- [ ] **Step 1: Implement MetricsCollector**

```swift
import Foundation

public struct SystemMetrics {
    public let rssMB: Double
    public let rssBytes: Int64
    public let cpuPercent: Double
    public let threadCount: Int
    public let activeInbound: Int
    public let poolTotal: Int
    public let poolBreakdown: [(key: String, count: Int)]
    public let mitmSessions: Int
    public let mitmFailedHosts: Int
    public let totalFlows: Int64
    public let totalBytesIn: Int64
    public let totalBytesOut: Int64
    public let uptimeSeconds: Double
}

public enum MetricsCollector {
    /// Collect all metrics. Safe to call from any thread (uses syscalls + locks).
    public static func collect(task: CaptureTask, startTime: TimeInterval) -> SystemMetrics {
        let rss = currentRSS()
        let (cpu, threads) = currentCPUUsage()
        let pool = task.connectionPool

        return SystemMetrics(
            rssMB: Double(rss) / 1_048_576,
            rssBytes: rss,
            cpuPercent: cpu,
            threadCount: threads,
            activeInbound: 0,  // TODO: track in ProxyServer
            poolTotal: pool.count,
            poolBreakdown: pool.perKeyBreakdown(),
            mitmSessions: 0,   // TODO: track active MITM
            mitmFailedHosts: task.mitmFailedHosts.count,
            totalFlows: 0,     // Updated from DashboardServer counters
            totalBytesIn: 0,
            totalBytesOut: 0,
            uptimeSeconds: Date().timeIntervalSince1970 - startTime
        )
    }

    // currentRSS() and currentCPUUsage() — same as StressTests.swift
}
```

- [ ] **Step 2: Build and commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Dashboard/MetricsCollector.swift
git commit -m "feat: add MetricsCollector for system metrics (CPU, memory, connections)"
```

---

### Task 4: Wire into ProxyServer + SessionRecorder

**Files:**
- Modify: `Sources/TunnelServices/Proxy/ProxyServer.swift`
- Modify: `Sources/TunnelServices/Framework/SessionRecorder.swift`

- [ ] **Step 1: Start DashboardServer in ProxyServer**

In `ProxyServer.swift`, read the `start(task:callback:)` method. Inside the `DispatchQueue.global().async` block, BEFORE `self.startServer(...)`, add:

```swift
// Start dashboard server (non-blocking bind)
if ProxyConfig.Dashboard.enabled {
    let dashboard = DashboardServer(group: self.workerGroup, task: task)
    do {
        try dashboard.start(port: ProxyConfig.Dashboard.port)
        self.dashboardServer = dashboard
        task.dashboardServer = dashboard
        AxLogger.log("[ProxyServer] Dashboard at http://127.0.0.1:\(ProxyConfig.Dashboard.port)", level: .Info)
    } catch {
        AxLogger.log("[ProxyServer] Dashboard failed to start: \(error)", level: .Error)
    }
}
```

Add property: `private var dashboardServer: DashboardServer?`

In `stop()`, BEFORE closing TCP channels:
```swift
dashboardServer?.stop()
dashboardServer = nil
```

- [ ] **Step 2: Push flows from SessionRecorder**

In `SessionRecorder.swift`, in `recordClosed()`, BEFORE the async DB write block, add:

```swift
// Push to real-time dashboard (if connected)
if let dashboard = task.dashboardServer, dashboard.hasClients {
    let flowData: [String: Any] = [
        "flowId": flowId ?? "",
        "host": session.host ?? "",
        "method": session.methods ?? "",
        "uri": session.uri ?? "",
        "protocol": session.schemes ?? "",
        "status": recorder?.status.rawValue ?? 0,
        "statusCode": Int(session.state ?? "0") ?? 0,
        "uploadBytes": _uploadBytes,
        "downloadBytes": _downloadBytes,
        "protoFlags": _protoFlags.rawValue,
        "connReuse": _connReuse.rawValue,
        "timestamp": Date().timeIntervalSince1970
    ]
    dashboard.pushFlow(flowData)
}
```

- [ ] **Step 3: Build and test**

Run: `swift build --package-path LocalPackages/TunnelServices`
Run: `swift test --package-path LocalPackages/TunnelServices --filter HTTP1Integration`
Expected: All pass (dashboard is opt-in, default enabled but no clients connected = no overhead)

- [ ] **Step 4: Commit**

```bash
git add LocalPackages/TunnelServices/Sources/
git commit -m "feat: wire DashboardServer into ProxyServer and SessionRecorder"
```

---

### Task 5: Puppeteer Scripts

**Files:**
- Create: `Scripts/browser-test/package.json`
- Create: `Scripts/browser-test/browser-test.js`
- Create: `Scripts/browser-test/sites.json`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "knot-browser-test",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "test": "node browser-test.js --auto",
    "manual": "node browser-test.js --manual"
  },
  "dependencies": {
    "puppeteer": "^22.0.0"
  }
}
```

- [ ] **Step 2: Create sites.json**

100 common websites covering search, social, news, tech, commerce, media, CDN, API, government:

```json
[
  "https://www.google.com",
  "https://www.bing.com",
  "https://www.baidu.com",
  "https://duckduckgo.com",
  "https://www.youtube.com",
  "https://twitter.com",
  "https://www.reddit.com",
  "https://www.linkedin.com",
  "https://www.facebook.com",
  "https://www.instagram.com",
  ... // 100 total
]
```

- [ ] **Step 3: Create browser-test.js**

Main script with:
- `--manual` mode: open browser, wait for user to close
- `--auto` mode: visit sites.json with simulated behavior (scroll, click)
- `--auto --then-manual`: auto-surf then wait for user
- `--concurrency N`: max concurrent tabs (default 3)
- `--sites file.json`: custom sites list

Auto-surf per page:
1. `page.goto(url, { waitUntil: 'networkidle2', timeout: 15000 })`
2. Scroll 3 times (80% viewport, 800-1200ms intervals)
3. Click up to 2 same-origin links
4. Close tab

After browser disconnects:
- Call `swift test --package-path LocalPackages/TunnelServices --filter RetestFailedFlows`

Push surf progress to dashboard via WebSocket:
```javascript
const dashWs = new WebSocket(`ws://localhost:${DASHBOARD_PORT}/ws`);
dashWs.send(JSON.stringify({type: 'surf_progress', data: {...}}));
```

- [ ] **Step 4: Test script**

```bash
cd Scripts/browser-test && npm install
node browser-test.js --help  # Should print usage
```

- [ ] **Step 5: Commit**

```bash
git add Scripts/browser-test/
git commit -m "feat: add Puppeteer browser test script with auto-surf mode"
```

---

### Task 6: RetestFailedFlows

**Files:**
- Create: `Tests/TunnelServicesTests/Integration/RetestFailedFlows.swift`

- [ ] **Step 1: Implement retester**

```swift
import XCTest
@testable import TunnelServices

final class RetestFailedFlows: XCTestCase {

    func testRetestAllFailedFlows() throws {
        // 1. Find the most recent task
        guard let task = CatalogDAO.findLastTask(db: DatabaseManager.shared.catalogDB) else {
            print("[RETEST] No task found")
            return
        }

        // 2. Open task databases
        let group = try DatabaseManager.shared.openTask(task.id)
        defer { DatabaseManager.shared.closeTask(task.id) }

        // 3. Query failed flows
        let allFlows = try FlowDAO.query(db: group.proto)
        let failedFlows = allFlows.filter { $0.status == .failed }

        print("[RETEST] Found \(failedFlows.count) failed flows out of \(allFlows.count) total")
        guard !failedFlows.isEmpty else { return }

        // 4. Start proxy for retesting (reuse existing or start new)
        // Use the most recently bound port or default
        let proxyPort = 8080  // TODO: read from task

        var results = [(flow: FlowRecord, success: Bool, newStatus: UInt?, error: String?)]()

        for flow in failedFlows {
            // Skip conditions
            if shouldSkip(flow) {
                print("[RETEST] SKIP \(flow.host) \(flow.searchKey2) — \(skipReason(flow))")
                continue
            }

            let client = TestNIOClient(proxyPort: proxyPort)
            defer { client.shutdown() }

            do {
                let rsp: TestHTTPResponse
                switch flow.protocolName {
                case "HTTPS", "H2":
                    rsp = try client.httpsRequest(
                        method: .init(rawValue: flow.searchKey1) ?? .GET,
                        host: flow.host, port: flow.port,
                        uri: flow.searchKey2
                    )
                default:
                    rsp = try client.httpRequest(
                        method: .init(rawValue: flow.searchKey1) ?? .GET,
                        host: flow.host, port: flow.port,
                        uri: flow.searchKey2
                    )
                }

                let success = rsp.status >= 200 && rsp.status < 400
                results.append((flow, success, rsp.status, nil))
                print("[RETEST] \(success ? "✅" : "❌") \(flow.host)\(flow.searchKey2) → \(rsp.status)")
            } catch {
                results.append((flow, false, nil, error.localizedDescription))
                print("[RETEST] ❌ \(flow.host)\(flow.searchKey2) → \(error)")
            }

            // Push to dashboard
            // task.dashboardServer?.pushRetest(...)
        }

        // Summary
        let recovered = results.filter { $0.success }.count
        let stillFailing = results.filter { !$0.success }.count
        print("\n[RETEST] Summary: \(recovered) recovered, \(stillFailing) still failing out of \(results.count) retested")
    }

    private func shouldSkip(_ flow: FlowRecord) -> Bool {
        let host = flow.host
        if host == "localhost" || host == "127.0.0.1" || host.isEmpty { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        if flow.errorMessage.contains("DNS") || flow.errorMessage.contains("resolve") { return true }
        if flow.errorMessage.contains("certificate") || flow.errorMessage.contains("CERT") { return true }
        if flow.searchKey1 == "POST" || flow.searchKey1 == "PUT" { return true }
        return false
    }

    private func skipReason(_ flow: FlowRecord) -> String {
        if flow.host == "localhost" || flow.host == "127.0.0.1" { return "localhost" }
        if flow.errorMessage.contains("DNS") { return "DNS failure" }
        if flow.searchKey1 == "POST" { return "POST (side effects)" }
        return "skip rule"
    }
}
```

- [ ] **Step 2: Build and verify compiles**

Run: `swift build --package-path LocalPackages/TunnelServices --build-tests`

- [ ] **Step 3: Commit**

```bash
git add LocalPackages/TunnelServices/Tests/TunnelServicesTests/Integration/RetestFailedFlows.swift
git commit -m "feat: add RetestFailedFlows for replaying failed requests via TestNIOClient"
```

---

### Task 7: End-to-End Smoke Test

- [ ] **Step 1: Manual verification**

1. Start proxy with dashboard enabled
2. Open `http://localhost:9090` in your browser — should see the dashboard HTML
3. Send a request through the proxy (e.g., `curl -x http://127.0.0.1:8080 http://httpbin.org/get`)
4. Dashboard should show the flow in real-time
5. Check system metrics cards update every 2 seconds

- [ ] **Step 2: Puppeteer smoke test**

```bash
cd Scripts/browser-test && npm install
node browser-test.js --auto --concurrency 2
# Should open Chromium, auto-visit sites, close, retest
```

- [ ] **Step 3: Commit any fixes**

---

## Post-Implementation Verification

1. **Build**: `swift build --package-path LocalPackages/TunnelServices` — pass
2. **Existing tests**: `swift test --package-path LocalPackages/TunnelServices` — all 315 pass
3. **Dashboard accessible**: `curl http://localhost:9090/` returns HTML
4. **WebSocket works**: Open dashboard in browser, send request through proxy, see flow appear
5. **Metrics update**: Memory/CPU/connections cards update every 2 seconds
6. **Auto-surf**: `node browser-test.js --auto` visits sites without crashing
7. **Retest**: `swift test --filter RetestFailedFlows` runs without errors
