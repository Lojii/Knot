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
  ├── type: "flow"     → FlowController.addFlow() → list + tree refresh
  ├── type: "metrics"  → DashboardController.update() → dashboard refresh
  └── type: "stats"    → Status bar refresh
```

### Lazy Loading

- Flow list: Paginated (50 per page), load more on scroll
- Payload body: Loaded on demand when request selected
- Waterfall/Dashboard: Loaded when tab activated

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

## macOS Integration

Flutter macOS app launches the Swift capture engine:
- On app start: spawn TunnelServices proxy process (or use platform channel to start it in-process)
- Flutter UI connects to `http://localhost:9090` (KnotWebService)
- On app quit: stop proxy process

For development, proxy can be started independently (`swift test --filter testStartProxyForBrowserTest`), and Flutter connects to its API.
