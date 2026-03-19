# Knot UI 层说明

## 1. 技术方案

- **框架**: SwiftUI（iOS 17+ / macOS 14+）
- **状态管理**: @Observable 宏（Observation 框架）
- **导航**: NavigationSplitView（iPad/macOS 双栏）+ NavigationStack（iPhone 单栏）
- **架构模式**: MVVM（View + ViewModel + DAO 直接访问）

## 2. 导航架构

### 页面枚举

```swift
// 主页面（左侧/底部导航）
enum PrimaryPage {
    case dashboard              // 仪表盘（首页）
    case flowList(taskId: String) // 流列表（指定任务）
    case ruleList               // 规则列表
    case certificate            // 证书管理
    case historyTask            // 历史任务
    case settings               // 设置
}

// 详情页（右侧/推入导航）
enum DetailDestination {
    case flowList               // 流列表
    case flowDetail(FlowRecord) // 流详情
    case ruleDetail(RuleRecord) // 规则详情
    case ruleAdd                // 新增规则
    case settingCertificate     // 证书设置
    case settingAbout           // 关于
    case settingWeb(URL)        // 内嵌网页
}
```

### 布局适配

```
iOS (Compact):
┌──────────────────┐
│   Navigation     │
│   Stack          │
│                  │
│   Primary Page   │
│   → Detail Page  │
│   → Sub Detail   │
│                  │
└──────────────────┘

iPad / macOS (Regular):
┌────────┬─────────────────┐
│ Side   │                 │
│ Bar    │   Detail View   │
│        │                 │
│ ─────  │   (Navigation   │
│ Dash   │    Stack)       │
│ Flows  │                 │
│ Rules  │                 │
│ Cert   │                 │
│ ...    │                 │
└────────┴─────────────────┘
```

## 3. 核心页面说明

### 3.1 DashboardView — 仪表盘

应用主页，显示当前抓包状态和快速操作入口。

```
┌─────────────────────────────────┐
│  VPN 状态指示器                  │
│  [●] 已连接 / [○] 已断开        │
├─────────────────────────────────┤
│  代理配置 (ProxyConfigView)      │
│  本地: 127.0.0.1:8034           │
│  Wi-Fi: 192.168.1.5:8034       │
├─────────────────────────────────┤
│  当前任务 (CurrentTaskView)      │
│  ┌───────────────────────────┐  │
│  │ 任务名称         运行中    │  │
│  │ ↑ 1.2 MB  ↓ 5.8 MB       │  │
│  │ 拦截: 234 条              │  │
│  │          [查看详情 →]      │  │
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│  最近任务                       │
│  ┌───────────────────────────┐  │
│  │ HistoryTaskCell × N       │  │
│  │ 2026-03-19 14:30  (128条) │  │
│  │ 2026-03-18 09:15  (56条)  │  │
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│  [开始抓包] / [停止抓包]         │
└─────────────────────────────────┘
```

**数据来源**:
- VPN 状态: `AppState.vpnStatus`（TunnelServiceProtocol 推送）
- 当前任务: `CatalogDAO.findAllTasks(db: catalogDB)` 取最新
- 统计数据: `CaptureTask.interceptCount`, `uploadTraffic`, `downloadFlow`

### 3.2 FlowListView — 流列表

显示指定抓包任务的所有捕获流，支持过滤和搜索。

```
┌─────────────────────────────────┐
│  搜索栏 (SearchBar)              │
│  [🔍 搜索主机名、URI、状态码...]  │
├─────────────────────────────────┤
│  协议过滤栏 (ProtocolFilterBar)  │
│  [全部] [HTTP] [HTTPS] [DNS]    │
│  [WS] [gRPC] [其他]             │
│  HTTP: 128  DNS: 45  WS: 12    │
├─────────────────────────────────┤
│  流列表 (LazyVStack)            │
│  ┌───────────────────────────┐  │
│  │ FlowCell                  │  │
│  │ [HTTPS] GET api.example.com │
│  │ /v1/users         200 OK  │  │
│  │ 14:30:25    ↓2.1KB        │  │
│  ├───────────────────────────┤  │
│  │ [DNS] A www.google.com    │  │
│  │ → 142.250.80.4   NOERROR │  │
│  │ 14:30:24                  │  │
│  ├───────────────────────────┤  │
│  │ [WS] /ws/notifications    │  │
│  │ 42 messages    连接中      │  │
│  │ 14:28:00                  │  │
│  └───────────────────────────┘  │
│        [加载更多...]             │
└─────────────────────────────────┘
```

**数据来源**:
- `FlowListViewModel` 管理分页加载
- `FlowDAO.query(db: dbGroup.proto, protocol: filter, searchText: keyword, offset: page*50, limit: 50)`
- `FlowDAO.countByProtocol(db: dbGroup.proto)` 获取各协议计数

**分页策略**:
- 每页 50 条
- 滚动到底部自动加载下一页
- 协议过滤和搜索重置分页

### 3.3 FlowDetailRouter — 流详情路由

根据协议类型路由到对应的详情视图：

```swift
struct FlowDetailRouter: View {
    let flow: FlowRecord

    var body: some View {
        switch flow.protocolName {
        case "HTTP", "HTTPS":
            HTTPDetailView(flow: flow)
        case "DNS":
            DNSDetailView(flow: flow)
        case "WebSocket":
            WebSocketDetailView(flow: flow)
        case "gRPC":
            GRPCDetailView(flow: flow)
        default:
            GenericFlowDetailView(flow: flow)
        }
    }
}
```

### 3.4 HTTPDetailView — HTTP 详情

HTTP/HTTPS 请求的详细信息，包含三个标签页。

```
┌─────────────────────────────────┐
│  [Overview] [Request] [Response]│
├─────────────────────────────────┤
│                                 │
│  === Overview 标签页 ===         │
│  URL: https://api.example.com   │
│       /v1/users?page=1          │
│  Method: GET                    │
│  Status: 200 OK                │
│  Protocol: HTTP/1.1             │
│                                 │
│  时序瀑布图 (TimingWaterfallView)│
│  DNS    ████░░░░░░░░  12ms     │
│  TCP    ░░░░████░░░░  25ms     │
│  TLS    ░░░░░░░░████  45ms     │
│  Request ░░░░░░░░░░██  5ms     │
│  Response░░░░░░░░░░░█  3ms     │
│  Total: 90ms                   │
│                                 │
│  === Request 标签页 ===          │
│  Headers:                       │
│  Host: api.example.com          │
│  Accept: application/json       │
│  Authorization: Bearer xxx...   │
│                                 │
│  Body: (PayloadReader 加载)      │
│  { "page": 1, "limit": 20 }    │
│                                 │
│  === Response 标签页 ===         │
│  Headers:                       │
│  Content-Type: application/json │
│  Content-Encoding: gzip         │
│                                 │
│  Body: (解压后展示)              │
│  { "users": [...], "total": 42 }│
│                                 │
└─────────────────────────────────┘
```

**数据来源**:
- 头部信息: `FlowRecord.metadata` (JSON 解析)
- 时序数据: `FlowRecord.connectAt/connectedAt/tlsDoneAt/reqEndAt/rspStartAt`
- Body 内容: `PayloadReader.read(url: flowRecord.reqPayloadRef/rspPayloadRef)`
- 解压: `PayloadDecoder.decode()` (gzip/deflate/brotli)

### 3.5 DNSDetailView — DNS 详情

```
┌─────────────────────────────────┐
│  查询信息                       │
│  域名: www.example.com          │
│  类型: A                        │
│  ID: 12345                      │
├─────────────────────────────────┤
│  响应码: NOERROR                │
├─────────────────────────────────┤
│  Answer Records                 │
│  ┌───────────────────────────┐  │
│  │ www.example.com  A        │  │
│  │ 93.184.216.34    TTL:300  │  │
│  ├───────────────────────────┤  │
│  │ www.example.com  AAAA     │  │
│  │ 2606:2800:220:1::         │  │
│  │ TTL:300                   │  │
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│  Authority Records (如果有)      │
│  Additional Records (如果有)     │
└─────────────────────────────────┘
```

### 3.6 WebSocketDetailView — WebSocket 详情

```
┌─────────────────────────────────┐
│  连接信息                       │
│  URL: wss://example.com/ws/chat │
│  状态: 连接中 / 已关闭          │
│  消息总数: 42                    │
├─────────────────────────────────┤
│  消息时间线 (MessageBubble)      │
│                                 │
│  14:30:25 →                     │
│  ┌──────────────────────┐       │
│  │ {"type":"subscribe"} │       │
│  └──────────────────────┘       │
│                                 │
│       ← 14:30:25               │
│       ┌──────────────────────┐  │
│       │ {"type":"ack"}       │  │
│       └──────────────────────┘  │
│                                 │
│  14:30:30 →                     │
│  ┌──────────────────────┐       │
│  │ {"type":"message",   │       │
│  │  "data":"hello"}     │       │
│  └──────────────────────┘       │
│                                 │
│  [PING] 14:30:35               │
│  [PONG] 14:30:35               │
│                                 │
└─────────────────────────────────┘
```

### 3.7 RuleListView — 规则管理

```
┌─────────────────────────────────┐
│  规则列表            [+ 新增]    │
├─────────────────────────────────┤
│  ┌───────────────────────────┐  │
│  │ ★ Knot(Default)           │  │
│  │   策略: proxy | 黑名单:关  │  │
│  ├───────────────────────────┤  │
│  │   我的规则                │  │
│  │   策略: direct | 黑名单:开 │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**数据来源**: `CatalogDAO.findAllRules(db: catalogDB)`

### 3.8 CertificateView — 证书管理

```
┌─────────────────────────────────┐
│  CA 证书状态                     │
│  ┌───────────────────────────┐  │
│  │ CertStatusCard            │  │
│  │ 状态: ✓ 已信任 / ⚠ 未安装  │  │
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│  [安装 CA 证书]                 │
│  [导出 CA 证书]                 │
├─────────────────────────────────┤
│  安装说明:                      │
│  1. 点击安装，在设置中允许描述文件│
│  2. 设置 → 通用 → 关于 → 证书   │
│     信任设置 → 启用完全信任       │
└─────────────────────────────────┘
```

## 4. ViewModel 详解

### 4.1 AppState — 全局应用状态

```swift
@Observable
class AppState {
    var vpnStatus: TunnelStatus = .disconnected
    var currentTask: CaptureTask?
    var certificateStatus: CertTrustStatus = .notInstalled
    var networkType: String = "Wi-Fi"
    var activeRuleId: Int64?

    // 由 TunnelServiceProtocol 推送状态更新
    // UI 通过 @Environment 或直接注入获取
}
```

### 4.2 FlowListViewModel — 流列表数据管理

```swift
@Observable
class FlowListViewModel {
    var flows: [FlowRecord] = []
    var protocolCounts: [String: Int] = [:]
    var selectedProtocol: String? = nil
    var searchText: String = ""
    var isLoading: Bool = false
    var hasMore: Bool = true

    private let dbGroup: TaskDatabaseGroup
    private let pageSize = 50
    private var currentPage = 0

    func loadInitial() {
        currentPage = 0
        flows = FlowDAO.query(
            db: dbGroup.proto,
            protocol: selectedProtocol,
            searchText: searchText.isEmpty ? nil : searchText,
            offset: 0,
            limit: pageSize
        )
        protocolCounts = FlowDAO.countByProtocol(db: dbGroup.proto)
        hasMore = flows.count == pageSize
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        currentPage += 1
        let newFlows = FlowDAO.query(
            db: dbGroup.proto,
            protocol: selectedProtocol,
            searchText: searchText.isEmpty ? nil : searchText,
            offset: currentPage * pageSize,
            limit: pageSize
        )
        flows.append(contentsOf: newFlows)
        hasMore = newFlows.count == pageSize
        isLoading = false
    }

    func filterByProtocol(_ protocol: String?) {
        selectedProtocol = `protocol`
        loadInitial()
    }

    func search(_ text: String) {
        searchText = text
        loadInitial()
    }
}
```

## 5. 可复用组件说明

### 5.1 TimingWaterfallView — 时序瀑布图

展示 HTTP 请求的各阶段耗时：

```swift
struct TimingWaterfallView: View {
    let flow: FlowRecord

    // 时间阶段:
    // DNS Lookup:   started_at → connect_at
    // TCP Connect:  connect_at → connected_at
    // TLS Handshake: connected_at → tls_done_at
    // Request Send:  tls_done_at → req_end_at
    // Server Wait:   req_end_at → rsp_start_at
    // Response Receive: rsp_start_at → ended_at

    // 每个阶段用不同颜色的水平条表示
    // 宽度按比例缩放
}
```

### 5.2 ProtocolBadge — 协议标签

```swift
struct ProtocolBadge: View {
    let protocol: String

    // 不同协议使用不同颜色:
    // HTTP  → 蓝色
    // HTTPS → 绿色
    // DNS   → 橙色
    // WS    → 紫色
    // gRPC  → 红色
    // 其他  → 灰色
}
```

### 5.3 FlowCell — 流列表单元格

```swift
struct FlowCell: View {
    let flow: FlowRecord

    // 布局:
    // [ProtocolBadge] [Method] host
    // search_key2 (URI/path)    [status]
    // timestamp           [download_bytes]
}
```

## 6. 数据流总结

```
存储层                    ViewModel               View
──────                   ─────────              ────
catalog.db
  ├─ capture_task  ──→  AppState.currentTask ──→ DashboardView
  └─ rule          ──→  RuleViewModel        ──→ RuleListView

TaskDatabaseGroup
  ├─ proto.db
  │  └─ flow       ──→  FlowListViewModel   ──→ FlowListView
  │                     .flows                    └→ FlowCell
  │                     .protocolCounts            └→ ProtocolFilterBar
  │                                               └→ FlowDetailRouter
  │                                                   ├→ HTTPDetailView
  │                                                   ├→ DNSDetailView
  │                                                   ├→ WebSocketDetailView
  │                                                   └→ GRPCDetailView
  │
  ├─ connection.db ──→  HTTPDetailView       ──→ TimingWaterfallView
  │
  ├─ decoded.db    ──→  HTTPDetailView       ──→ Body 文本展示
  │
  └─ payloads/
     └─ raw/       ──→  PayloadReader        ──→ Body 原始数据展示
```
