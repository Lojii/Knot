# Browser Test + Real-Time Dashboard Design

**Goal:** A Puppeteer-controlled browser sends all traffic through the proxy while a real-time web dashboard (same process, separate port) shows captured flows, system metrics, and retest results. Includes auto-surf mode that visits 100 common websites with simulated user behavior.

**Approach:** DashboardServer is a NIO HTTP+WebSocket server embedded in the ProxyServer process, sharing the same EventLoopGroup. Puppeteer launches Chromium with `--proxy-server`. The dashboard port is physically isolated from the proxy port (no traffic loop). Failed requests are retested with TestNIOClient after the browser closes.

---

## Architecture

### Process Layout

```
Process 1: Swift (ProxyServer)
  ├─ TCP Proxy        :8080   (Chromium connects here)
  ├─ UDP/QUIC Proxy   :8443
  └─ Dashboard HTTP+WS :9090  (user views in own browser, NOT through proxy)

Process 2: Node.js (Puppeteer)
  ├─ Launches Chromium with --proxy-server=127.0.0.1:8080
  ├─ Auto-surf mode: visits 100 sites with simulated scrolling/clicking
  ├─ Detects browser close → triggers failed flow retest
  └─ Connects to dashboard WS to push surf progress

Chromium (Puppeteer-controlled)
  └─ All HTTP/HTTPS traffic → proxy :8080
```

### Port Isolation (Anti-Loop)

| Port | Purpose | Who connects |
|------|---------|-------------|
| 8080 | Proxy TCP | Chromium via `--proxy-server` |
| 8443 | Proxy UDP/QUIC | Chromium (if H3) |
| 9090 | Dashboard HTTP+WS | User's own browser (not proxied) |

Dashboard traffic never touches the proxy. Zero loop risk.

---

## DashboardServer

### Embedding in ProxyServer

Same process, same `EventLoopGroup`, separate `ServerBootstrap`.

**Start location:** Dashboard must be started BEFORE the TCP bootstrap's blocking `closeFuture.wait()`. In `ProxyServer.start(task:callback:)`, the dashboard is started inside the `DispatchQueue.global().async` block, before `startServer()` is called:

```swift
DispatchQueue.global().async {
    // Start dashboard first (non-blocking bind)
    let dashboard = DashboardServer(task: task, group: self.workerGroup)
    try? dashboard.start(port: ProxyConfig.Dashboard.port)
    self.dashboardServer = dashboard
    task.dashboardServer = dashboard

    // Then start TCP server (blocks on closeFuture.wait())
    self.startServer(host: host, port: port, task: task, ...)
}
```

**Shutdown ordering:** `DashboardServer.stop()` must be called BEFORE `ProxyServer.stop()` shuts down EventLoopGroups, to allow clean WebSocket close frames.

### NIO Pipeline

Uses `configureHTTPServerPipeline(withServerUpgrade:)` for correct WebSocket upgrade:

```swift
let upgrader = NIOWebSocketServerUpgrader(
    shouldUpgrade: { channel, head in
        // Accept all upgrade requests to /ws
        channel.eventLoop.makeSucceededFuture(HTTPHeaders())
    },
    upgradePipelineHandler: { channel, req in
        channel.pipeline.addHandler(DashboardWebSocketHandler(server: self))
    }
)

channel.pipeline.configureHTTPServerPipeline(
    withServerUpgrade: .init(upgraders: [upgrader], completionHandler: { ctx in })
).flatMap {
    channel.pipeline.addHandler(DashboardHTTPHandler(server: self))
}
```

`DashboardHTTPHandler` handles non-upgrade HTTP requests (GET /, GET /api/stats). WebSocket upgrade is handled by NIO's built-in upgrader which installs `DashboardWebSocketHandler`.

### Push Condition

```swift
// Thread-safe: use NIOLockedValueBox since hasClients is read from
// multiple EventLoops (SessionRecorder runs on worker ELs)
private let _clientCount = NIOLockedValueBox<Int>(0)
public var hasClients: Bool { _clientCount.withLockedValue { $0 > 0 } }
```

SessionRecorder calls `dashboard.pushFlow()` only when `hasClients == true`. Zero overhead when no dashboard is open.

### Push Timing

`pushFlow()` is called at the top of `SessionRecorder.recordClosed()`, BEFORE the async DB write block. It reads synchronously-populated fields (host, method, uri, status, bytes, duration, protoFlags, connReuse) which are already finalized at this point. The push itself dispatches to the dashboard's EventLoop:

```swift
public func pushFlow(_ record: FlowRecord) {
    guard hasClients else { return }
    dashboardEventLoop.execute {
        // Serialize JSON and broadcast to all WS connections
    }
}
```

### WebSocket Protocol

**Flow event** (on each `recordClosed`):
```json
{"type": "flow", "data": {
  "flowId": "xxx", "host": "example.com", "method": "GET", "uri": "/api",
  "protocol": "HTTPS", "status": "completed", "statusCode": 200,
  "uploadBytes": 1234, "downloadBytes": 5678,
  "duration": 123, "protoFlags": 321,
  "connReuse": 1, "timestamp": 1711100000
}}
```

**Stats summary** (every 1 second):
```json
{"type": "stats", "data": {
  "totalFlows": 150, "completed": 140, "failed": 8, "inProgress": 2,
  "totalUpload": 1234567, "totalDownload": 9876543,
  "protocols": {"HTTP": 30, "HTTPS": 100, "H2": 15, "WS": 3, "WSS": 2},
  "connReuse": {"new": 80, "keepAlive": 50, "pooled": 20}
}}
```

**System metrics** (every 2 seconds):
```json
{"type": "metrics", "data": {
  "memory": {"rss_mb": 45.2, "rss_bytes": 47396864},
  "cpu": {"usage_percent": 12.3, "thread_count": 18},
  "connections": {
    "active_inbound": 8,
    "pool_total": 12,
    "pool_breakdown": [{"key": "httpbin.org:443:ssl", "count": 3}],
    "mitm_sessions": 5,
    "mitm_failed_hosts": 1,
    "quic_sessions": 0
  },
  "nio": {"event_loops": 12},
  "totals": {"flows": 342, "bytes_in": 12345678, "bytes_out": 2345678, "uptime_s": 127.5}
}}
```

**Surf progress** (from Puppeteer via WS):
```json
{"type": "surf_progress", "data": {
  "current": 42, "total": 100,
  "url": "https://github.com", "status": "loading",
  "tabsOpen": 3
}}
```

**Retest result** (per failed flow):
```json
{"type": "retest", "data": {
  "flowId": "xxx", "host": "example.com", "uri": "/failed",
  "originalError": "timeout",
  "retestResult": "success", "retestStatusCode": 200
}}
```

---

## System Metrics Collection

### Memory
`mach_task_basic_info.resident_size` (existing `currentRSS()` function).

### CPU
`task_threads()` + `thread_basic_info` per thread. Sum `cpu_usage / TH_USAGE_SCALE * 100`.

### Proxy Metrics
- `task.connectionPool.count` — pooled idle connections
- Active inbound connections — tracked by ProxyServer (count of child channels)
- MITM sessions — tracked by MITMFailedHostTracker
- QUIC sessions — `QUICMITMManager.activeSessions` (if enabled)

### Collection
DashboardServer runs a `scheduleRepeatedTask` every 2 seconds. Only collects when `hasClients == true`. Syscalls (`mach_task_basic_info`, `task_threads`) are dispatched to `DispatchQueue.global()` to avoid blocking the EventLoop:

```swift
DispatchQueue.global().async {
    let metrics = MetricsCollector.collect(task: self.task)
    self.dashboardEventLoop.execute {
        self.broadcastMetrics(metrics)
    }
}
```

### Required New APIs
- `OutboundConnectionPool.perKeyBreakdown() -> [(key: String, count: Int)]` — per-host pool counts
- `MITMFailedHostTracker.count: Int` — number of failed hosts

---

## Puppeteer Test Script

### File Structure

```
scripts/browser-test/
├── package.json
├── browser-test.js       — main script
├── sites.json            — 100 common websites
└── retest-failed.js      — triggers swift test for failed flows
```

### Run Modes

```bash
# Manual: open browser, user browses freely
node scripts/browser-test/browser-test.js --manual

# Auto: visit 100 sites with simulated user behavior
node scripts/browser-test/browser-test.js --auto

# Auto then manual: auto-surf first, then wait for user, retest on close
node scripts/browser-test/browser-test.js --auto --then-manual

# Custom options
node scripts/browser-test/browser-test.js --auto --concurrency 5 --sites custom.json
```

### Chromium Launch

```javascript
const browser = await puppeteer.launch({
    headless: false,
    args: [
        `--proxy-server=127.0.0.1:${PROXY_PORT}`,
        '--ignore-certificate-errors',
        '--no-first-run',
        '--disable-default-apps',
    ],
    defaultViewport: null,
});
```

### Auto-Surf: 100 Websites

**Concurrency control:** max 3 tabs open simultaneously.

**Per-site behavior:**
1. `page.goto(url, { waitUntil: 'networkidle2', timeout: 15000 })`
2. Scroll 3 times (80% viewport height each, 800-1200ms intervals)
3. Find up to 2 same-origin links, click and visit each
4. Sub-pages: scroll once, wait 500ms
5. Close tab

**Sites list** (100 sites covering):
- Search engines (Google, Bing, Baidu, DuckDuckGo)
- Social media (YouTube, Twitter, Reddit, LinkedIn)
- News (BBC, CNN, HackerNews, Reuters)
- Tech (GitHub, StackOverflow, MDN, npm)
- E-commerce (Amazon, eBay)
- Media (Netflix, Twitch, Spotify)
- CDN/Infrastructure (Cloudflare, AWS, Akamai)
- API endpoints (httpbin.org, nghttp2.org)
- Government (.gov sites)
- Regional (various country-specific sites)

**Error handling:** Individual site failures don't stop the queue. Errors logged, tab closed, next site proceeds.

---

## Failed Request Retest

### Trigger
Puppeteer detects `browser.on('disconnected')` → calls swift test.

### Flow
1. Query DB: `SELECT * FROM flow WHERE status = 2` (failed)
2. Skip localhost, DNS-failed flows
3. For each failed flow:
   - Extract method/host/port/uri/protocol from FlowRecord + metadata
   - Use TestNIOClient: `httpRequest` / `httpsRequest` / `h2Request` based on protocol
   - Record result (success/fail, status code, error)
   - Push `{"type": "retest"}` to dashboard
4. Summary: X recovered, Y still failing, grouped by error type

### Retest Success Definition
- HTTP status 2xx or 3xx
- Or response has body where original had 0 bytes

### Retester is an XCTest
`RetestFailedFlows.swift` is an XCTest case. Puppeteer invokes it via `swift test --filter RetestFailedFlows`. Not a standalone binary.

### Skip Conditions
- Host is localhost/127.0.0.1 or private IP (10.x, 192.168.x, 172.16-31.x)
- Original error is DNS resolution failure
- Original error is certificate-related (MITM issue, not server issue)
- Method is POST/PUT with body (retesting may cause side effects)
- Protocol is RAW/unknown (cannot meaningfully replay)

---

## Dashboard HTML Page

Self-contained HTML served at `GET /`. No external dependencies.

### Layout

```
┌─────────────────────────────────────────────────────────┐
│  🔴 Knot Proxy Dashboard        ⏱ Uptime: 2m 07s      │
├──────────┬──────────┬──────────┬──────────┬─────────────┤
│ Memory   │ CPU      │ Conns    │ Pool     │ Flows       │
│ 45.2 MB  │ 12.3%    │ 8 active │ 12 idle  │ 342 total   │
│ ▓▓▓░░░░░ │ ▓▓░░░░░░ │          │ 3 hosts  │ 8 failed    │
├──────────┴──────────┴──────────┴──────────┴─────────────┤
│  Protocol Distribution: HTTP:30  HTTPS:100  H2:15  WS:3 │
├─────────────────────────────────────────────────────────┤
│  [Auto-Surf] [42/100] github.com 🔄                     │
├─────────────────────────────────────────────────────────┤
│  Time    Proto  Method Host           URI     Code Size  │
│  12:01   HTTPS  GET    github.com     /       200  45KB  │
│  12:01   HTTPS  GET    github.com     /style  200  12KB  │
│  12:02   H2     GET    api.github.com /user   200  2KB   │
│  12:02   HTTPS  GET    cdn.example.com/img   ❌ timeout  │
│  ...                                                     │
├─────────────────────────────────────────────────────────┤
│  === Retest Results ===                                  │
│  [1/8] cdn.example.com/img — timeout → 200 OK ✅        │
│  [2/8] bad.example.com/api — refused → still failing ❌  │
└─────────────────────────────────────────────────────────┘
```

### Features
- Auto-scroll to bottom on new flows
- Failed flows highlighted red
- Click flow row to expand details (headers, metadata, timing)
- Protocol distribution pie/bar chart (CSS-only)
- Memory/CPU mini bar charts updated every 2s
- Connection pool breakdown expandable
- Retest section appears after browser closes
- WebSocket auto-reconnect on disconnect

---

## Configuration

```swift
public enum Dashboard {
    public static var port: Int = 9090
    public static var enabled: Bool = true
    public static var metricsIntervalMs: Int = 2000
    public static var statsIntervalMs: Int = 1000
}
```

---

## File Structure

### New Files (Swift Source)
- `Sources/TunnelServices/Dashboard/DashboardServer.swift` — HTTP+WS server, push management
- `Sources/TunnelServices/Dashboard/DashboardHTML.swift` — Self-contained HTML string
- `Sources/TunnelServices/Dashboard/MetricsCollector.swift` — CPU/memory/connection metrics

### New Files (Tests)
- `Tests/.../Integration/RetestFailedFlows.swift` — Failed flow retester (XCTest)

### New Files (Scripts)
- `scripts/browser-test/package.json`
- `scripts/browser-test/browser-test.js`
- `scripts/browser-test/sites.json`

### Modified Files
- `Sources/TunnelServices/Config/ProxyConfig.swift` — Add `Dashboard` config
- `Sources/TunnelServices/Proxy/ProxyServer.swift` — Start/stop DashboardServer (before TCP bootstrap)
- `Sources/TunnelServices/Framework/SessionRecorder.swift` — Push flow on recordClosed
- `Sources/TunnelServices/CaptureTask.swift` — Hold `dashboardServer` reference
- `Sources/TunnelServices/Proxy/OutboundConnectionPool.swift` — Add `perKeyBreakdown()` method
- `Sources/TunnelServices/CaptureTask.swift` — Add `MITMFailedHostTracker.count` property

---

## Out of Scope
- HTTPS for dashboard port (plain HTTP is fine for localhost)
- Authentication on dashboard
- Historical data playback (dashboard shows live only)
- Mobile-responsive layout
- Custom site lists from UI (use `--sites` CLI flag)
