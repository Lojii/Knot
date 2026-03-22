# Knot Flutter UI Design

## Goal

Build a cross-platform Flutter UI for the Knot proxy app, starting with macOS desktop. The UI connects to KnotWebService (REST + WebSocket) for all data. Two layout variants: desktop/tablet/web (three-panel) and iPhone (single-column, future P3).

## Project Structure

Flutter project at root, Swift packages as subdirectories.

```
Knot/
├── pubspec.yaml
├── lib/
│   ├── api/                          HTTP + WebSocket client
│   ├── models/                       Dart data models
│   ├── controllers/                  GetX controllers
│   ├── layout/
│   │   ├── desktop_layout.dart       Desktop/tablet/web main frame
│   │   └── phone_layout.dart         iPhone layout (P3)
│   ├── pages/
│   │   ├── capture/                  Live capture workspace
│   │   ├── connections/              TCP/UDP view (P2)
│   │   ├── history/                  History management (P2)
│   │   └── settings/                 Settings (P2)
│   └── widgets/                      Shared components
├── macos/                            macOS runner
├── web/                              Web runner (P3)
├── ios/                              iOS runner (P3)
├── native/
│   ├── KnotStorage/                  Moved from LocalPackages/
│   ├── KnotWebService/               Moved from LocalPackages/
│   └── TunnelServices/               Moved from LocalPackages/
├── Knot.xcodeproj/                   macOS/iOS native project
└── scripts/
```

### Migration from Current Repo

1. Create branch `feature/flutter-ui`
2. Run `flutter create` at project root
3. Move `LocalPackages/{KnotStorage,KnotWebService,TunnelServices}` → `native/`
4. Update Package.swift relative paths (`../KnotStorage` → still works within native/)
5. Update Xcode project references
6. Add Flutter `.gitignore` entries

## Desktop Layout

Five horizontal bands, no left activity bar.

```
┌─────────────────────────────────────────────────────────────┐
│ Row 0: Global Bar (40px)                                    │
│ 🔴🟡🟢    📋 Task: 2026-03-22 20:30 ▼  [📂History][Proto⇄TCP][⚙]│
├─────────────────────────────────────────────────────────────┤
│ Row 1: Toolbar (40px)                                       │
│ [▶ Start] [⏹ Stop] [🗑 Clear]               🔍 Search...    │
├─────────────────────────────────────────────────────────────┤
│ Row 2: Filter Bar (36px)                                    │
│ Proto: [HTTP][HTTPS][WS][H2]  Type: [JSON][IMG]  Status:[2xx]│
├────────────┬────────────────────────────────────────────────┤
│ Row 3: Content (fills remaining)                            │
│ Left:      │ Right:                                         │
│ Tree List  │ [List] [Waterfall] [Dashboard]  ← tab switch   │
│ (220px     │ ┌──────────────────────────────────────────┐   │
│  resizable)│ │ Active tab content                       │   │
│            │ │ (table / chart / dashboard)              │   │
│ ⭐ Pinned  │ ├──────────────────────────────────────────┤   │
│ 📱 App     │ │ Selected request detail                  │   │
│ 🌐 Domain  │ │ [Headers][Body][Query][Timing]           │   │
│  ▼ httpbin │ │ [Connection][Certificate]                │   │
│    GET /get│ └──────────────────────────────────────────┘   │
├────────────┴────────────────────────────────────────────────┤
│ Row 4: Status Bar (28px)                                    │
│ 128 requests │ ⬆45KB ⬇1.2MB │ 💾58MB │ 🔌12 connections     │
└─────────────────────────────────────────────────────────────┘
```

### Row 0: Global Bar

Spans full width. Contains:
- **Window controls**: Close/minimize/maximize (left on macOS, right on Windows)
- **Task name**: Editable label with dropdown to switch tasks. Default name is timestamp.
- **History button**: Opens history management page (new page or modal)
- **Protocol ⇄ TCP/UDP toggle**: Switches the entire content area between protocol-layer view (HTTP/WS) and transport-layer view (TCP/UDP connections)
- **Settings button**: Opens settings panel (proxy config, certificates, ports)

### Row 1: Toolbar

- Start/Stop/Clear buttons for capture control
- Search field (filters the request list in real-time)

### Row 2: Filter Bar

Chip-style toggle buttons in three groups:
- **Protocol**: HTTP, HTTPS, WS, WSS, H2, FTP, ALL
- **Content type**: JSON, HTML, JS, CSS, IMG, ALL
- **Status code**: 2xx, 3xx, 4xx, 5xx, ALL

Multiple chips can be active simultaneously within each group. ALL deselects others.

### Row 3: Content Area

Split into left sidebar + right main panel with draggable divider.

**Left: Tree List (220px default, resizable)**

Three-level grouping:
- ⭐ Pinned: User-pinned domains/requests
- 📱 App: Grouped by source application (when detectable)
- 🌐 Domain: Grouped by hostname

Clicking a domain filters the right-side list to show only that domain's requests. Clicking a specific request in the tree selects it in the right-side list and shows its detail.

**Right: Tab Content + Detail**

Upper section has three tabs:
- **List Tab**: Request table (Method, Host, Path, Status, Size, Time columns). Sortable columns. Clicking a row selects it and shows detail below.
- **Waterfall Tab**: Chrome DevTools-style timeline chart. Horizontal time axis, each request as a colored bar showing DNS/Connect/TLS/TTFB/Download phases.
- **Dashboard Tab**: Status dashboard — protocol distribution pie chart, real-time traffic line chart, CPU/memory gauges, connection pool status.

Lower section (when List Tab is active): Selected request detail panel with tabs:
- **Headers**: Collapsible request/response headers
- **Body**: Request/response body. JSON auto-formatted. Plain text for others.
- **Query**: URL parameters as key-value table
- **Timing**: Waterfall bar for single request (DNS → TCP Connect → TLS → Request Send → TTFB → Response Download)
- **Connection**: TCP connection info (src/dst IP:port, state, reuse type, bytes)
- **Certificate**: TLS certificate chain (subject, issuer, validity, SANs)

Upper/lower sections divided by draggable splitter.

### Row 4: Status Bar

Fixed at bottom. Shows:
- Total request count
- Upload/download bytes
- Memory usage (RSS)
- Active connection count

Updated in real-time from WebSocket metrics push.

## Data Flow

```
Flutter App
  ↕ HTTP (REST API)     → Query historical data, flow list, payload
  ↕ WebSocket (/ws)     → Receive real-time flow, metrics push
KnotWebService (:9090)
  ↕
KnotStorage (SQLite)
```

Flutter never accesses the database directly. All data through KnotWebService API.

### GetX Controllers

| Controller | Responsibility | Data Source |
|-----------|---------------|-------------|
| TaskController | Current task, start/stop, task switching | `GET /api/tasks` |
| FlowController | Flow list, filtering, search, selection | `GET /api/tasks/{id}/flows` |
| LiveController | WebSocket connection, event dispatch | `WS /ws` |
| TreeController | Domain/app tree construction, selection | Derived from FlowController |
| DetailController | Selected request detail, payload loading | `GET .../flows/{fid}`, `.../request`, `.../response` |
| DashboardController | Dashboard metrics (CPU/mem/protocols) | Derived from LiveController metrics |

### Real-time Data Flow

```
WebSocket /ws
  ↓ JSON message
LiveController (parse type, dispatch)
  ├── type: "flow"          → FlowController.addFlow()     → list + tree refresh
  ├── type: "flow_update"   → FlowController.updateFlow()  → update existing row
  ├── type: "metrics"       → DashboardController.update()  → dashboard + status bar
  ├── type: "stats"         → Status bar refresh
  ├── type: "retest"        → (P2, ignored in P1)
  └── type: "surf_progress" → (P2, ignored in P1)
```

New flows are prepended to the top of the list (most recent first). When the user has scrolled away from the top, a "New flows available" indicator appears instead of auto-scrolling. When a non-default sort is active, new flows are buffered and the indicator shows the count.

### Search & Filtering

Search performs a **remote API call** with 300ms debounce: `GET /api/tasks/{id}/flows?keyword={q}`. Filter bar chips are combined as additional query parameters (`&protocol=HTTP&status=200`). Filters + search are AND-combined.

When the user types in search or toggles filter chips, the flow list reloads from the API with the combined query.

### Lazy Loading

- Flow list: Paginated (50 per page), load more on scroll
- Payload body: Loaded on demand when request selected
- Waterfall/Dashboard: Loaded when tab activated

## Dart Models

Corresponding to KnotWebService REST API responses.

### Task

```dart
class TaskModel {
  final int id;
  final String name;
  final double createdAt;
  final double? startedAt;
  final double? stoppedAt;
  final int status;         // 0=created, 1=running, 2=stopped
  final int flowCount;
  final int uploadBytes;
  final int downloadBytes;
}
```

### FlowSummary (list item)

```dart
class FlowSummary {
  final String flowId;
  final String protocol;    // "HTTP", "HTTPS", "H2", "WS", "WSS"
  final String host;
  final int port;
  final double startedAt;
  final double? endedAt;
  final double? durationMs;
  final int uploadBytes;
  final int downloadBytes;
  final int status;         // FlowStatus: 0=inProgress, 1=completed, 2=failed
  final String summary;     // e.g. "GET /api → 200"
  final String searchKey1;  // method
  final String searchKey2;  // uri
  final String searchKey3;  // statusCode
  final String searchKey4;  // contentType
  final int protoFlags;
  final int connReuse;
}
```

### FlowDetail (single flow)

```dart
class FlowDetail {
  final FlowSummary summary;
  final Map<String, dynamic> metadata;
  final String? reqPayloadRef;
  final String? rspPayloadRef;
  final double? connectAt;
  final double? connectedAt;
  final double? tlsDoneAt;
  final double? reqEndAt;
  final double? rspStartAt;
  final ConnectionInfo? connection;
  final String? certChainRef;
}

class ConnectionInfo {
  final String srcIp;
  final String dstIp;
  final int srcPort;
  final int dstPort;
  final String state;
  final String? tlsVersion;
  final String? tlsCipher;
  final String? tlsSni;
}
```

### WebSocket Message

```dart
class WsMessage {
  final String type;        // "flow", "flow_update", "metrics", etc.
  final Map<String, dynamic> data;
}
```

## Tech Stack

| Package | Purpose |
|---------|---------|
| `get` | State management + routing + DI |
| `http` | REST API calls |
| `web_socket_channel` | WebSocket real-time push |
| `multi_split_view` | Draggable split panels |
| `google_fonts` | Monospace font for headers/code |
| `json_view` or similar | JSON formatting and highlight |

No code generation (freezed/json_serializable). GetX handles routing. Keep dependencies minimal.

## Theme

Follow system preference (dark/light). Use `ThemeMode.system`.

- Dark theme: Dark backgrounds (#1a1a2e style), green/blue accents
- Light theme: White backgrounds, standard Material colors
- Both: Monospace font for code/headers, proportional for UI chrome

## Phased Delivery

| Phase | Scope | Dependency |
|-------|-------|-----------|
| **P1** | Flutter project + macOS build + live capture panel (list tab + detail + tree + toolbar + filters + status bar + WS push) | KnotWebService API |
| **P2** | Waterfall tab, Dashboard tab, TCP/UDP panel, History page, Settings page, Body advanced viewer (Hex/image) | P1 |
| **P3** | Web build embedded in KnotWebService, iPhone layout | P1 |

P1 delivers a usable macOS desktop capture tool.

## Error Handling

### WebSocket Reconnection

LiveController implements auto-reconnect with exponential backoff:
- On disconnect: wait 1s, 2s, 4s, 8s, max 30s between retries
- On reconnect: reload current flow list from REST API (may have missed events)
- Status bar shows connectivity indicator: 🟢 connected / 🔴 disconnected / 🟡 reconnecting

### REST API Errors

- Network error / service not running → show banner at top: "Cannot connect to Knot service at localhost:9090"
- 404 / 500 → show snackbar with error message, keep UI functional
- Timeout (10s) → retry once, then show error

### Backend Not Running

On app launch, Flutter checks `GET /api/tasks`:
- Success → normal startup, load task list
- Fail → show connection screen: "Start the Knot proxy service to begin capturing" with a retry button
- Status bar shows 🔴 until connected

## Capture Control

### P1: Platform Channel (macOS)

Flutter macOS app communicates with Swift via a platform channel:

```
Channel: "com.knot.proxy"
Methods:
  startCapture(taskName: String?) → {port: Int, taskId: Int}
  stopCapture() → void
  getStatus() → {running: Bool, port: Int?, taskId: Int?}
```

The Swift side (in macOS runner's AppDelegate) starts/stops the ProxyServer + KnotWebServer. Flutter receives the bound port and connects.

### P3: REST API Fallback (Web)

For the web build where platform channels are unavailable, capture control is external — the user starts the proxy independently. The web UI is read-only (connects to already-running service). Start/Stop buttons are hidden in web mode.

If capture control via REST API is needed later, add `POST /api/capture/start` and `POST /api/capture/stop` to KnotWebService.

## Task Switching

When the user selects a different task from the dropdown:

1. LiveController disconnects WebSocket, reconnects with `?taskId={newId}`
2. FlowController clears current list, reloads from `GET /api/tasks/{newId}/flows`
3. TreeController rebuilds domain tree from new flow data
4. DetailController clears selected flow

The currently capturing task shows a 🔴 recording indicator next to its name. Historical tasks show no indicator. Only the live task receives WebSocket push events.

## macOS Integration

Flutter macOS app launches the Swift capture engine:
- On app start: use platform channel `com.knot.proxy/startCapture` to start proxy in-process
- Flutter UI connects to `http://localhost:{port}` returned by platform channel
- On app quit: call `com.knot.proxy/stopCapture`, then exit

Required macOS entitlements in `macos/Runner/Release.entitlements`:
- `com.apple.security.network.client` (connect to localhost)
- `com.apple.security.network.server` (proxy listens on port)

For development, proxy can be started independently (`swift test --filter testStartProxyForBrowserTest`), and Flutter connects to `localhost:9090`.

## Tree List Grouping

Left sidebar tree has two groups (P1):
- ⭐ **Pinned**: User-pinned domains (stored in local preferences)
- 🌐 **Domain**: Grouped by hostname, auto-built from flow list

App grouping (📱) is deferred to P2 — requires source process detection which is platform-specific and not currently in `FlowRecord`.

## Dashboard Tab Data Sources

| Widget | Data Source |
|--------|-----------|
| Protocol distribution pie chart | `GET /api/tasks/{id}/flows/stats` → `protocols` field |
| Status code distribution | `GET /api/tasks/{id}/flows/stats` → `statuses` field |
| Total bytes | `GET /api/tasks/{id}/flows/stats` → `totalUploadBytes` + `totalDownloadBytes` |
| CPU/Memory gauges | WebSocket `metrics` messages → `memory.rss_mb`, `cpu.usage_percent` |
| Connection pool status | WebSocket `metrics` messages → `connections.pool_total`, `connections.pool_breakdown` |
| Real-time traffic curve | Accumulated from WebSocket `flow` messages (bytes per second) |
