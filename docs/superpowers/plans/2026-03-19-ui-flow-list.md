# UI Flow List Implementation Plan (Sub-project B1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SessionListView with FlowListView that reads from new FlowDAO, with multi-protocol cell display and protocol filtering.

**Architecture:** New SwiftUI views in KnotUI package reading from FlowDAO/DecodedEntryDAO. FlowCell renders differently per protocol. Protocol filter chips at top. Keyword search across host/uri/summary.

**Tech Stack:** SwiftUI, SQLite.swift (via TunnelServices Storage layer)

**Spec:** `docs/superpowers/specs/2026-03-19-multi-protocol-ui-cleanup-design.md` (Sub-project B1)

---

## File Structure

```
LocalPackages/KnotUI/Sources/KnotUI/
├── ViewModels/
│   └── FlowListViewModel.swift           # NEW: data loading, filtering, pagination
├── Views/
│   └── FlowList/
│       └── FlowListView.swift            # NEW: list + search bar + protocol filter
├── Components/
│   ├── FlowCell.swift                    # NEW: multi-protocol cell
│   ├── ProtocolBadge.swift               # NEW: protocol icon + method badge
│   └── ProtocolFilterBar.swift           # NEW: horizontal filter chips

LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/
└── FlowDAO+Count.swift                   # NEW: countByProtocol query
```

---

### Task 1: FlowDAO.countByProtocol

**Files:**
- Create: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/FlowDAO+Count.swift`
- Create: `LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/FlowDAOCountTests.swift`

- [ ] **Step 1: Write test**

```swift
import XCTest
import SQLite
@testable import TunnelServices

final class FlowDAOCountTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "protocol.db")
        try! ProtocolSchema.create(db)
        // Seed: 5 HTTP, 3 DNS, 2 WS
        for i in 0..<5 {
            var r = FlowRecord(flowId: "http_\(i)", protocolName: "HTTP", host: "h", port: 80, startedAt: Double(i))
            try! FlowDAO.insert(db: db, record: r)
        }
        for i in 0..<3 {
            var r = FlowRecord(flowId: "dns_\(i)", protocolName: "DNS", host: "h", port: 53, startedAt: Double(10+i))
            try! FlowDAO.insert(db: db, record: r)
        }
        for i in 0..<2 {
            var r = FlowRecord(flowId: "ws_\(i)", protocolName: "WS", host: "h", port: 443, startedAt: Double(20+i))
            try! FlowDAO.insert(db: db, record: r)
        }
    }
    override func tearDown() { helper = nil }

    func testCountByProtocol() throws {
        let counts = try FlowDAO.countByProtocol(db: db)
        XCTAssertEqual(counts["HTTP"], 5)
        XCTAssertEqual(counts["DNS"], 3)
        XCTAssertEqual(counts["WS"], 2)
    }

    func testTotalCount() throws {
        let counts = try FlowDAO.countByProtocol(db: db)
        let total = counts.values.reduce(0, +)
        XCTAssertEqual(total, 10)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation
import SQLite

extension FlowDAO {
    /// Returns a dictionary of protocol name → count
    public static func countByProtocol(db: Connection) throws -> [String: Int] {
        var result: [String: Int] = [:]
        let stmt = try db.prepare("SELECT protocol, COUNT(*) FROM flow GROUP BY protocol")
        for row in stmt {
            let proto = row[0] as? String ?? ""
            let count = Int(row[1] as? Int64 ?? 0)
            result[proto] = count
        }
        return result
    }
}
```

- [ ] **Step 3: Build, test, commit**

```bash
git add LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DAO/FlowDAO+Count.swift \
       LocalPackages/TunnelServices/Tests/TunnelServicesTests/Storage/FlowDAOCountTests.swift
git commit -m "feat(storage): add FlowDAO.countByProtocol for filter chip counts"
```

---

### Task 2: ProtocolBadge component

**Files:**
- Create: `LocalPackages/KnotUI/Sources/KnotUI/Components/ProtocolBadge.swift`

- [ ] **Step 1: Implement ProtocolBadge**

```swift
import SwiftUI

/// Displays a protocol-specific icon and method badge
public struct ProtocolBadge: View {
    let protocolName: String
    let searchKey1: String  // method for HTTP, subprotocol for WS, queryType for DNS, etc.

    public init(protocolName: String, searchKey1: String = "") {
        self.protocolName = protocolName
        self.searchKey1 = searchKey1
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 12))
                .frame(width: 16)
            if !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(badgeColor)
                    .cornerRadius(3)
            }
        }
    }

    private var iconName: String {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3": return "globe"
        case "WS", "WSS": return "arrow.up.arrow.down"
        case "DNS": return "magnifyingglass"
        case "gRPC": return "arrow.triangle.branch"
        default: return "network"
        }
    }

    private var iconColor: Color {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3": return .blue
        case "WS", "WSS": return .purple
        case "DNS": return .cyan
        case "gRPC": return .orange
        default: return .gray
        }
    }

    private var badgeText: String {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3": return searchKey1.uppercased() // GET, POST, etc.
        case "WS", "WSS": return "WS"
        case "DNS": return searchKey1.uppercased() // A, AAAA, etc.
        case "gRPC": return "gRPC"
        case "H2": return "H2"
        case "H3": return "H3"
        default: return protocolName
        }
    }

    private var badgeColor: Color {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3":
            switch searchKey1.uppercased() {
            case "GET": return .blue
            case "POST": return .green
            case "PUT": return .orange
            case "DELETE": return .red
            case "PATCH": return .purple
            default: return .gray
            }
        case "WS", "WSS": return .purple
        case "DNS": return .cyan
        case "gRPC": return .orange
        default: return .gray
        }
    }
}
```

- [ ] **Step 2: Build, commit**

```bash
git add LocalPackages/KnotUI/Sources/KnotUI/Components/ProtocolBadge.swift
git commit -m "feat(ui): add ProtocolBadge component for multi-protocol display"
```

---

### Task 3: FlowCell component

**Files:**
- Create: `LocalPackages/KnotUI/Sources/KnotUI/Components/FlowCell.swift`

- [ ] **Step 1: Implement FlowCell**

Read `LocalPackages/KnotUI/Sources/KnotUI/Components/SessionCell.swift` for existing patterns.

```swift
import SwiftUI
import TunnelServices

/// Unified cell for displaying any protocol's Flow in the list
public struct FlowCell: View {
    let flow: FlowRecord

    public init(flow: FlowRecord) {
        self.flow = flow
    }

    public var body: some View {
        HStack(spacing: 8) {
            ProtocolBadge(protocolName: flow.protocolName, searchKey1: flow.searchKey1)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(flow.host)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(flow.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                statusView
                trafficView
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch flow.protocolName {
        case "HTTP", "HTTPS", "H2", "H3":
            if !flow.searchKey3.isEmpty {
                Text(flow.searchKey3)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(httpStatusColor(flow.searchKey3))
            }
        case "WS", "WSS":
            Text("↑\(flow.searchKey3)") // total frames
                .font(.system(size: 11))
                .foregroundColor(.purple)
        case "DNS":
            Text(flow.searchKey3.isEmpty ? flow.searchKey4 : flow.searchKey3)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        case "gRPC":
            Text(flow.searchKey4) // grpc message
                .font(.system(size: 11))
                .foregroundColor(flow.searchKey3 == "0" ? .green : .red)
        default:
            EmptyView()
        }
    }

    private var trafficView: some View {
        HStack(spacing: 2) {
            if flow.durationMs != nil {
                Text(formatDuration(flow.durationMs!))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func httpStatusColor(_ status: String) -> Color {
        guard let code = Int(status) else { return .gray }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .gray
        }
    }

    private func formatDuration(_ ms: Double) -> String {
        if ms < 1000 { return String(format: "%.0fms", ms) }
        return String(format: "%.1fs", ms / 1000)
    }
}
```

- [ ] **Step 2: Build, commit**

```bash
git add LocalPackages/KnotUI/Sources/KnotUI/Components/FlowCell.swift
git commit -m "feat(ui): add FlowCell component with multi-protocol display"
```

---

### Task 4: ProtocolFilterBar component

**Files:**
- Create: `LocalPackages/KnotUI/Sources/KnotUI/Components/ProtocolFilterBar.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Horizontal scrollable filter chips for protocol selection
public struct ProtocolFilterBar: View {
    @Binding var selected: String?  // nil = all
    let counts: [String: Int]       // protocol → count

    private let order = ["HTTP", "H2", "H3", "WS", "WSS", "DNS", "gRPC"]

    public init(selected: Binding<String?>, counts: [String: Int]) {
        self._selected = selected
        self.counts = counts
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                FilterChip(
                    label: "全部",
                    count: counts.values.reduce(0, +),
                    isSelected: selected == nil,
                    action: { selected = nil }
                )
                // Per-protocol chips (only show if count > 0)
                ForEach(sortedProtocols, id: \.self) { proto in
                    FilterChip(
                        label: proto,
                        count: counts[proto] ?? 0,
                        isSelected: selected == proto,
                        action: { selected = proto }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 36)
    }

    private var sortedProtocols: [String] {
        let known = order.filter { counts[$0] != nil && counts[$0]! > 0 }
        let unknown = counts.keys.filter { !order.contains($0) }.sorted()
        return known + unknown
    }
}

struct FilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Text("(\(count))")
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build, commit**

```bash
git add LocalPackages/KnotUI/Sources/KnotUI/Components/ProtocolFilterBar.swift
git commit -m "feat(ui): add ProtocolFilterBar with horizontal filter chips"
```

---

### Task 5: FlowListViewModel

**Files:**
- Create: `LocalPackages/KnotUI/Sources/KnotUI/ViewModels/FlowListViewModel.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import SwiftUI
import TunnelServices
import SQLite

/// ViewModel for the unified Flow list
public class FlowListViewModel: ObservableObject {
    @Published public var flows: [FlowRecord] = []
    @Published public var protocolCounts: [String: Int] = [:]
    @Published public var isLoading = false
    @Published public var hasMore = true

    public var protocolFilter: String?
    public var keyword: String?

    private let dbGroup: TaskDatabaseGroup
    private var pageIndex: Int = 0
    private let pageSize: Int = 50

    public init(dbGroup: TaskDatabaseGroup) {
        self.dbGroup = dbGroup
    }

    public func loadFlows() {
        isLoading = true
        pageIndex = 0

        let results = (try? FlowDAO.query(
            db: dbGroup.proto,
            protocolFilter: protocolFilter,
            keyword: keyword,
            offset: 0,
            limit: pageSize
        )) ?? []

        flows = results
        hasMore = results.count >= pageSize
        isLoading = false

        loadCounts()
    }

    public func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        pageIndex += 1

        let results = (try? FlowDAO.query(
            db: dbGroup.proto,
            protocolFilter: protocolFilter,
            keyword: keyword,
            offset: pageIndex * pageSize,
            limit: pageSize
        )) ?? []

        flows.append(contentsOf: results)
        hasMore = results.count >= pageSize
        isLoading = false
    }

    public func refresh() {
        loadFlows()
    }

    private func loadCounts() {
        protocolCounts = (try? FlowDAO.countByProtocol(db: dbGroup.proto)) ?? [:]
    }
}
```

- [ ] **Step 2: Build, commit**

```bash
git add LocalPackages/KnotUI/Sources/KnotUI/ViewModels/FlowListViewModel.swift
git commit -m "feat(ui): add FlowListViewModel with filtering and pagination"
```

---

### Task 6: FlowListView

**Files:**
- Create: `LocalPackages/KnotUI/Sources/KnotUI/Views/FlowList/FlowListView.swift`

- [ ] **Step 1: Implement**

Read `LocalPackages/KnotUI/Sources/KnotUI/Views/SessionList/SessionListView.swift` for existing patterns.

```swift
import SwiftUI
import TunnelServices

/// Unified flow list view replacing SessionListView
public struct FlowListView: View {
    @StateObject private var vm: FlowListViewModel
    @State private var searchText = ""
    @State private var protocolFilter: String?

    public init(dbGroup: TaskDatabaseGroup) {
        _vm = StateObject(wrappedValue: FlowListViewModel(dbGroup: dbGroup))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Protocol filter bar
            ProtocolFilterBar(selected: $protocolFilter, counts: vm.protocolCounts)

            // Flow list
            List {
                ForEach(vm.flows, id: \.flowId) { flow in
                    NavigationLink(value: flow.flowId) {
                        FlowCell(flow: flow)
                    }
                }

                // Load more trigger
                if vm.hasMore {
                    ProgressView()
                        .onAppear { vm.loadMore() }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, prompt: "搜索 Host / URI / 内容")
        .onChange(of: searchText) { _, newValue in
            vm.keyword = newValue.isEmpty ? nil : newValue
            vm.loadFlows()
        }
        .onChange(of: protocolFilter) { _, newValue in
            vm.protocolFilter = newValue
            vm.loadFlows()
        }
        .onAppear {
            vm.loadFlows()
        }
        .refreshable {
            vm.refresh()
        }
    }
}
```

- [ ] **Step 2: Build, commit**

```bash
git add LocalPackages/KnotUI/Sources/KnotUI/Views/FlowList/FlowListView.swift
git commit -m "feat(ui): add FlowListView with search, filter, and infinite scroll"
```

---

## Post-Implementation Notes

- FlowListView is created but NOT yet wired into the app's navigation. The app entry point switch happens in Sub-project B2 (after detail views exist) or Sub-project C.
- The old SessionListView is preserved for now — it will be deleted in Sub-project C.
