# 多协议记录器、UI 切换与旧代码清理设计

## 概述

在数据库存储系统重设计（Phase 1）完成后，本设计覆盖剩余三个子项目：

1. **Sub-project A**：扩展 ProtocolRecorder，支持 WebSocket、DNS、gRPC、HTTP/2
2. **Sub-project B**：UI 层全面切换到新存储系统 + 各协议专属详情视图
3. **Sub-project C**：移除 ActiveSQLite 框架、旧模型和旧 UI

依赖顺序：A → B1 → B2 → C

**前置条件**：`feature/storage-redesign` 分支已完成，包含完整的多数据库架构、FlowDAO、PayloadWriter/Reader、DecodeScheduler、HTTPRecorder 及 SessionRecorder 双写集成。

---

## Sub-project A：ProtocolRecorder 扩展

### 设计决策

| 协议 | Recorder 策略 | Flow protocol 值 | decoded.db 使用 |
|------|-------------|------------------|----------------|
| HTTP/2 | 复用 HTTPRecorder，加 protocolOverride 参数 | `"H2"` | 同 HTTP（req/rsp 各一条） |
| WebSocket | 新建 WebSocketRecorder | `"WS"` / `"WSS"` | 每帧一条，sequence 递增 |
| DNS | 新建 DNSRecorder | `"DNS"` | 不使用（数据全在 metadata） |
| gRPC | 新建 GRPCRecorder | `"gRPC"` | 每 message 一条，sequence 递增 |

### WebSocketRecorder

WebSocket 连接 = 一个 Flow，帧数据实时写入 decoded.db。

**protocol.db flow 表**：

```
flow_id: "ws_0001"
protocol: "WS" (或 "WSS")
host: "ws.example.com"
summary: "↑12 ↓34 frames"
search_key1: "wss"          (scheme)
search_key2: "/chat"        (uri)
search_key3: "46"           (total frames)
search_key4: "1000"         (close code)
metadata: {
    "upgradeReqHeaders": [...],
    "upgradeRspHeaders": [...],
    "subprotocol": "graphql-ws",
    "extensions": "permessage-deflate"
}
```

**decoded.db decoded_entry 表**（每帧一条记录）：

```
flow_id: "ws_0001", direction: 0, sequence: 0   ← 客户端发出的第1帧
decoded_type: "text"
search_text: "{"type":"subscribe","id":"1"}"
inline_data: (≤4KB 内联)

flow_id: "ws_0001", direction: 1, sequence: 0   ← 服务器返回的第1帧
decoded_type: "text"
search_text: "{"type":"data","id":"1",...}"

flow_id: "ws_0001", direction: 0, sequence: 1   ← 客户端第2帧
...
```

**帧数据存储策略**：
- TEXT 帧 ≤ 4KB → `inline_data` 内联 + `search_text` 可搜索
- TEXT 帧 > 4KB → 文件存储 `payloads/raw/{flowId}_frame_{dir}_{seq}.bin`
- BINARY 帧 → 文件存储，`search_text = nil`
- PING/PONG/CLOSE → 仅记录 decoded_entry 元数据，不存载荷
- `decoded_type` 值：`"text"`, `"binary"`, `"ping"`, `"pong"`, `"close"`, `"continuation"`

**帧序号**：客户端和服务端各自独立递增 sequence。`direction=0`（客户端→服务器）从 0 起，`direction=1`（服务器→客户端）从 0 起。UI 展示时按 `decoded_at` 时间戳交错排列。

**生命周期**：WebSocketRecorder 不在 init 时插入 protocol.db，而是先在内存中积累元数据，关闭时才插入。但帧数据实时写入 decoded.db（帧可能很多，不能全在内存中积累）。

### DNSRecorder

DNS 是短生命周期的请求/响应模式，每次查询 = 一个 Flow。

**protocol.db flow 表**：

```
flow_id: "dns_0001"
protocol: "DNS"
host: "example.com"          (查询域名)
port: 53 (UDP) 或 443 (DoH)
summary: "A example.com → 93.184.216.34"
search_key1: "A"             (queryType)
search_key2: "example.com"   (domain)
search_key3: "93.184.216.34" (firstAnswer)
search_key4: "NOERROR"       (responseCode)
metadata: {
    "transport": "udp",       ← 或 "doh"
    "id": 1234,
    "opcode": 0,
    "isRecursionDesired": true,
    "questions": [
        {"name": "example.com", "type": "A", "class": "IN"}
    ],
    "answers": [
        {"name": "example.com", "type": "A", "ttl": 300, "data": "93.184.216.34"}
    ],
    "authorities": [...],
    "additionals": [...],
    "httpFlowId": "http_0042"  ← 仅 DoH，关联回原始 HTTP 请求
}
```

**DNS 不需要 decoded.db 和 payload 文件**——所有数据都在 metadata JSON 中（DNS 消息通常 < 1KB）。

**两条路径的集成**：

```
UDP DNS 路径:
PacketCaptureEngine → UDPForwarder → DNSDecoder.parse()
    → DNSRecorder.recordQuery(message:)
    → DNSRecorder.recordResponse(message:)
    → FlowDAO.insert() 到 protocol.db
    metadata.transport = "udp"

DoH 路径:
HTTPCaptureHandler → 检测 content-type: application/dns-message
    → DNSDecoder.parse(body)
    → 创建独立 DNS Flow（除了原本的 HTTP Flow）
    → FlowDAO.insert() 到 protocol.db
    metadata.transport = "doh"
    metadata.httpFlowId = "原始 HTTP Flow 的 flowId"
```

DoH 会产生两条 Flow：一条 HTTP Flow（记录 HTTP 层面），一条 DNS Flow（记录 DNS 语义）。通过 `httpFlowId` 从 DNS Flow 跳转到原始 HTTP 请求。

### HTTP/2（复用 HTTPRecorder）

不新建 Recorder 类。在 HTTPRecorder 中增加可选参数：

```swift
public class HTTPRecorder: ProtocolRecorder {
    private var protocolOverride: String?
    private var extraMetadata: [String: Any]

    public init(flowId: String, host: String, port: Int,
                protocolOverride: String? = nil, extraMetadata: [String: Any] = [:])

    public func buildFlowRecord() -> FlowRecord {
        var record = FlowRecord(...)
        record.protocolName = protocolOverride ?? Self.protocolName
        record.metadata.merge(extraMetadata) { _, new in new }
        return record
    }
}
```

`HTTP2CaptureHandler` 创建 recorder 时传 `protocolOverride: "H2", extraMetadata: ["streamId": streamId]`。

### GRPCRecorder

gRPC 是 HTTP/2 上的特殊协议，需要独立 Flow 类型。

**protocol.db flow 表**：

```
flow_id: "grpc_0001"
protocol: "gRPC"
host: "api.example.com"
summary: "UserService/GetUser → OK"
search_key1: "GetUser"       (method)
search_key2: "UserService"   (service)
search_key3: "0"             (grpc status code)
search_key4: "OK"            (grpc status message)
metadata: {
    "httpVersion": "HTTP/2",
    "streamId": 5,
    "grpcEncoding": "identity",
    "path": "/UserService/GetUser",
    "reqHeaders": [...],
    "rspHeaders": [...],
    "trailers": [...]
}
```

**decoded.db**：每个 gRPC message 一条记录，streaming RPC 用 sequence 递增。

### Handler 集成方式

**WebSocketCaptureHandler**：

```
WebSocketUpgradeInterceptor 检测 101 →
    创建 WebSocketRecorder(flowId, host, uri)
    记录 upgrade headers 到 metadata
    → WebSocketFrameLogger 每帧调用:
        recorder.recordFrame(direction, opcode, payload, timestamp)
        → 写入 decoded.db (inline 或文件)
    → 连接关闭时:
        recorder.recordClosed(closeCode)
        → FlowDAO.insert() 到 protocol.db
```

**HTTP2CaptureHandler**：

创建 HTTPRecorder 时传 `protocolOverride: "H2"` + `extraMetadata: ["streamId": N]`。检测到 gRPC 时改为创建 GRPCRecorder。

**HTTPCaptureHandler（DoH 检测）**：

在 `recordResponseEnd()` 中，检测 `content-type == "application/dns-message"`，读取响应 body，`DNSDecoder.parse()`，创建独立 DNS Flow。

**UDPForwarder（UDP DNS）**：

收到 DNS 请求/响应对 → `DNSRecorder.recordQuery()` + `recordResponse()` → `FlowDAO.insert()`。

### 新增/修改文件

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `Storage/Protocol/WebSocketRecorder.swift` | WS 帧记录 + Flow 构建 |
| 新建 | `Storage/Protocol/DNSRecorder.swift` | DNS 查询/响应 + transport 标记 |
| 新建 | `Storage/Protocol/GRPCRecorder.swift` | gRPC message 记录 |
| 修改 | `Storage/Protocol/HTTPRecorder.swift` | 加 protocolOverride + extraMetadata |
| 修改 | `Proxy/WebSocketCaptureHandler.swift` | 集成 WebSocketRecorder |
| 修改 | `Proxy/HTTP2CaptureHandler.swift` | 传 H2 参数 + gRPC 路由 |
| 修改 | `Proxy/GRPCCaptureHandler.swift` | 集成 GRPCRecorder |
| 修改 | `Proxy/HTTPCaptureHandler.swift` | DoH 检测 + DNS Flow 创建 |
| 修改 | `PacketCapture/UDPForwarder.swift` | UDP DNS → DNSRecorder |
| 新建 | 测试文件 × 3 | WebSocket/DNS/gRPC Recorder 测试 |

---

## Sub-project B1：数据源切换 + 统一 Flow 列表

### FlowListViewModel

```swift
class FlowListViewModel: ObservableObject {
    @Published var flows: [FlowRecord] = []
    @Published var isLoading = false

    var taskId: Int64
    var protocolFilter: String?       // nil=全部, "HTTP", "WS", "DNS", "gRPC"
    var hostContains: String?
    var keyword: String?
    var pageIndex: Int = 0
    let pageSize: Int = 50

    func loadFlows()    // FlowDAO.query(db:protocolFilter:hostContains:offset:limit:)
    func loadMore()     // pageIndex += 1, append results
    func refresh()      // pageIndex = 0, reload
}
```

### FlowCell — 多协议统一 Cell

共享布局框架，各协议展示不同的图标和摘要：

```
┌──────────────────────────────────────────────────┐
│ [协议图标]  host                        [时间戳] │
│ [方法/类型]  summary                    [状态]   │
│             ↑1.2KB  ↓45.3KB            [耗时]   │
└──────────────────────────────────────────────────┘
```

| 协议 | 图标 | 徽章 | 状态区 |
|------|------|------|--------|
| HTTP/H2 | `globe` | 方法(GET/POST)彩色 | 状态码彩色(2xx绿/4xx橙/5xx红) |
| WS/WSS | `arrow.up.arrow.down` | `WS` 紫色 | `↑12 ↓34` 帧数 |
| DNS | `magnifyingglass` | `A`/`AAAA` 蓝色 | 首条 answer 或 NXDOMAIN |
| gRPC | `arrow.triangle.branch` | `gRPC` 橙色 | gRPC status |

实现：一个 `FlowCell` view，根据 `flow.protocolName` 用 `switch` 选择不同的 badge 和 status view。

### 协议筛选栏

列表顶部水平滚动的 protocol filter chip：

```
[ 全部 ] [ HTTP (123) ] [ WS (5) ] [ DNS (45) ] [ gRPC (8) ]
```

计数来自 `FlowDAO.countByProtocol(db:)` — GROUP BY protocol 查询。

### 搜索

两层搜索：
1. **protocol.db**：host、searchKey2(uri)、summary 模糊匹配 — 快速
2. **decoded.db FTS**：全文搜索 body 内容 — 仅在用户开启"搜索内容"时触发

### 过渡方式

新建 `FlowListView` / `FlowCell` / `FlowListViewModel`，不修改旧 SessionListView。在 App 入口切换 NavigationLink 到新视图。

### 新增文件

| 文件 | 说明 |
|------|------|
| `KnotUI/ViewModels/FlowListViewModel.swift` | 数据加载 + 筛选分页 |
| `KnotUI/Views/FlowList/FlowListView.swift` | 统一列表 + 协议筛选栏 |
| `KnotUI/Components/FlowCell.swift` | 多协议统一 Cell |
| `KnotUI/Components/ProtocolBadge.swift` | 协议图标 + 方法徽章 |
| `TunnelServices/Storage/DAO/FlowDAO+Count.swift` | countByProtocol 查询 |

---

## Sub-project B2：协议专属详情视图

### FlowDetailRouter

```swift
struct FlowDetailRouter: View {
    let flow: FlowRecord
    let dbGroup: TaskDatabaseGroup

    var body: some View {
        switch flow.protocolName {
        case "HTTP", "HTTPS", "H2":
            HTTPDetailView(flow: flow, dbGroup: dbGroup)
        case "WS", "WSS":
            WebSocketDetailView(flow: flow, dbGroup: dbGroup)
        case "DNS":
            DNSDetailView(flow: flow)
        case "gRPC":
            GRPCDetailView(flow: flow, dbGroup: dbGroup)
        default:
            GenericFlowDetailView(flow: flow)
        }
    }
}
```

### HTTPDetailView

保持现有 3-tab 布局（Request / Response / Overview），数据源切换：

- **Headers** → `flow.metadata["reqHeaders"]` / `["rspHeaders"]`（JSON 解析）
- **Body** → `DecodedEntryDAO.find(db:flowId:direction:)` → inline_data 或文件流式读取
- **Overview / Timing** → 瀑布图组件，数据来自 `flow.connectAt`, `flow.connectedAt`, `flow.tlsDoneAt`, `flow.reqEndAt`, `flow.rspStartAt`, `flow.endedAt`

```
Timing 瀑布图:
  DNS     ██░░░░░░░░░  12ms
  Connect ░░██░░░░░░░  8ms
  TLS     ░░░░██░░░░░  15ms
  Request ░░░░░░█░░░░  2ms
  TTFB    ░░░░░░░██░░  45ms
  Response░░░░░░░░░██  120ms
```

### WebSocketDetailView — 对话式帧视图

```
┌─────────────────────────────────────────┐
│  WebSocket  ws.example.com/chat         │
│  ↑12 frames  ↓34 frames  Duration: 5m  │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────┐                │
│  │ {"type":"subscribe"} │  ← 客户端(右)  │
│  └─────────────────────┘     10:23:01   │
│                                         │
│         ┌─────────────────────┐         │
│  (左) → │ {"type":"data",...}  │         │
│         └─────────────────────┘         │
│         10:23:01.05                     │
│                                         │
│  ── CLOSE (1000: Normal) ──             │
└─────────────────────────────────────────┘
```

**实现要点**：
- 数据来源：`DecodedEntryDAO` 查询所有 entries，按 `decoded_at` 排序
- 分页加载：初始加载最近 50 帧，上滑加载更多
- 气泡布局：`direction=0`（客户端）靠右绿色，`direction=1`（服务端）靠左灰色
- TEXT 帧展示文本内容（可折叠长文本），BINARY 帧展示 `[Binary: 1.2KB]`
- PING/PONG 显示为时间轴小标记，CLOSE 显示为分割线 + close code

### DNSDetailView — Q&A 格式

```
┌─────────────────────────────────────────┐
│  DNS Query  (UDP)           12ms        │
├─────────────────────────────────────────┤
│  Question                               │
│  ┌─────────────────────────────────┐    │
│  │ A   example.com          IN     │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Answers                                │
│  ┌─────────────────────────────────┐    │
│  │ A   example.com   TTL=300      │    │
│  │     → 93.184.216.34            │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ── Response: NOERROR ──                │
│  Transport: UDP  │  Server: 8.8.8.8     │
└─────────────────────────────────────────┘
```

数据全部来自 `flow.metadata` JSON。DoH 类型额外显示"查看 HTTP 请求"链接（通过 `metadata.httpFlowId`）。

### GRPCDetailView

3-tab 布局（Request / Response / Headers），Request/Response tab 内可能有多个 message（streaming RPC），用 sequence 区分：

```
Request tab:
  Message #0
  ┌──────────────────────────────┐
  │ {"userId": "123", ...}       │
  └──────────────────────────────┘

Response tab (streaming):
  Message #0
  ┌──────────────────────────────┐
  │ {"name": "Alice", ...}       │
  └──────────────────────────────┘
  Message #1
  ┌──────────────────────────────┐
  │ {"name": "Bob", ...}         │
  └──────────────────────────────┘

Headers tab:
  Request Headers / Response Headers / Trailers
```

### 新增文件

| 文件 | 说明 |
|------|------|
| `KnotUI/Views/FlowDetail/FlowDetailRouter.swift` | 按 protocol 路由 |
| `KnotUI/Views/FlowDetail/HTTPDetailView.swift` | HTTP/H2 详情 |
| `KnotUI/Views/FlowDetail/WebSocketDetailView.swift` | 对话帧视图 |
| `KnotUI/ViewModels/WebSocketDetailViewModel.swift` | 帧分页加载 |
| `KnotUI/Views/FlowDetail/DNSDetailView.swift` | DNS Q&A 视图 |
| `KnotUI/Views/FlowDetail/GRPCDetailView.swift` | gRPC message 视图 |
| `KnotUI/Views/FlowDetail/GenericFlowDetailView.swift` | 未知协议兜底 |
| `KnotUI/Components/TimingWaterfallView.swift` | HTTP timing 瀑布图 |
| `KnotUI/Components/MessageBubble.swift` | WS/gRPC 消息气泡 |

---

## Sub-project C：清理旧代码

### 前置条件

Sub-project B 全部完成后，UI 已完全切换到新 FlowDAO，旧代码无调用者。

### 提取非数据库逻辑

`CaptureTask.swift` 中的证书管理和 `Rule.swift` 中的规则匹配逻辑不能直接删除，需先提取：

- **CertManager.swift**（新建）：从 CaptureTask 提取 `loadCACert()`, `certPool`, `x509CACert`, `rsaSigningKey` 等证书管理逻辑
- **RuleEngine.swift**（新建）：从 Rule 提取 `configParse()`, `matching(host:uri:target:)`, 策略枚举(DIRECT/REJECT/COPY)等规则解析和匹配逻辑。Rule 数据通过 `CatalogDAO` 读取。

### 执行顺序

```
Step 1: 提取非数据库逻辑
        → 新建 CertManager.swift
        → 新建 RuleEngine.swift
        → 各 Handler 改为引用新类

Step 2: 移除 SessionRecorder 中旧写入路径
        → 各 Handler 直接使用 ProtocolRecorder

Step 3: 移除 MitmService 中的 ASConfigration 调用
        → 替换为 DatabaseManager 初始化

Step 4: 删除旧模型 (Session.swift, CaptureTask.swift, Rule.swift)

Step 5: 删除旧 UI 组件 (SessionListView 等 7 个文件)

Step 6: 删除 ActiveSQLite 框架 (12 个文件)

Step 7: 全量编译验证 + 测试
```

每一步之后保证项目可编译。

### 删除文件清单

**旧模型（3 文件）**：
- `Session.swift` (485 行)
- `CaptureTask.swift` (366 行)
- `Rule/Rule.swift` (543 行)

**旧 UI（7 文件）**：
- `KnotUI/Views/SessionList/SessionListView.swift`
- `KnotUI/Views/SessionDetail/SessionDetailView.swift`
- `KnotUI/ViewModels/SessionListViewModel.swift`
- `KnotUI/Components/SessionCell.swift`
- `KnotUI/Components/SessionOverviewSection.swift`
- `KnotUI/Components/SessionHeaderList.swift`
- `KnotUI/Components/SessionBodyPreview.swift`

**ActiveSQLite 框架（12 文件）**：
- `ActiveSQLite/ASModel.swift`
- `ActiveSQLite/ASProtocol.swift`
- `ActiveSQLite/ASProtocol+Save.swift`
- `ActiveSQLite/ASProtocol+Query.swift`
- `ActiveSQLite/ASProtocol+Schame.swift`
- `ActiveSQLite/ASProtocol+introspection.swift`
- `ActiveSQLite/ASConfigration.swift`
- `ActiveSQLite/ASError.swift`
- `ActiveSQLite/ASLogger.swift`
- `ActiveSQLite/ASUtils.swift`
- `ActiveSQLite/Types.swift`
- `ActiveSQLite/ActiveSQLite.swift`

---

## 全景汇总

| Sub-project | 范围 | 新建文件 | 修改文件 | 删除文件 |
|------------|------|---------|---------|---------|
| A: ProtocolRecorder 扩展 | WS/DNS/gRPC/H2 记录器 + Handler 集成 | ~6 | ~5 | 0 |
| B1: 数据源切换 + 统一列表 | FlowListView + FlowCell + 筛选 | ~5 | ~2 | 0 |
| B2: 协议专属详情视图 | HTTP/WS/DNS/gRPC 详情 | ~9 | 0 | 0 |
| C: 清理旧代码 | 提取逻辑 + 移除旧模型/UI/ORM | ~2 | ~3 | ~22 |
