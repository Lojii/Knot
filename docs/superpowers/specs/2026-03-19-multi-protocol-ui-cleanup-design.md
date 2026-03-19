# 多协议记录器、UI 切换与旧代码清理设计

## 概述

在数据库存储系统重设计（Phase 1）完成后，本设计覆盖剩余四个子项目：

1. **Sub-project A0**：新增 connection.db 连接层数据库（transport 与 protocol 之间的会话/连接层）
2. **Sub-project A**：扩展 ProtocolRecorder，支持 WebSocket、DNS、gRPC、HTTP/2、QUIC/HTTP3
3. **Sub-project B**：UI 层全面切换到新存储系统 + 各协议专属详情视图
4. **Sub-project C**：移除 ActiveSQLite 框架、旧模型和旧 UI

依赖顺序：A0 → A → B1 → B2 → C

**前置条件**：`feature/storage-redesign` 分支已完成，包含完整的多数据库架构、FlowDAO、PayloadWriter/Reader、DecodeScheduler、HTTPRecorder 及 SessionRecorder 双写集成。

---

## Sub-project A0：新增 connection.db 连接层

### 设计动机

原有 4 库架构中，transport.db 记录逐包数据，protocol.db 记录应用层请求。但 QUIC 这样的传输协议不属于任何一层——它运行在 UDP 之上，内建 TLS 和多路复用，承载 HTTP/3 请求。需要一个中间层来记录**连接/会话级**数据。

```
transport.db    → 原始包（IP/TCP/UDP 逐包记录）
    ↓
connection.db   → 连接/会话层（TCP 连接、QUIC 连接、QUIC 流）  ← 新增
    ↓
protocol.db     → 应用协议（HTTP/WS/DNS/gRPC/H3 请求级）
```

同时，state.db 中的 `connection` 表（TCP 连接状态）迁移到 connection.db 的 `tcp_connection` 表，state.db 只保留 `modify_log` + `task_stats`。

### Schema

```sql
-- TCP 连接
CREATE TABLE IF NOT EXISTS tcp_connection (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id         TEXT NOT NULL UNIQUE,
    src_ip          TEXT NOT NULL,
    src_port        INTEGER NOT NULL,
    dst_ip          TEXT NOT NULL,
    dst_port        INTEGER NOT NULL,
    state           TEXT NOT NULL DEFAULT 'open',
    started_at      REAL NOT NULL,
    established_at  REAL,
    closed_at       REAL,
    close_reason    TEXT NOT NULL DEFAULT '',
    tls_version     TEXT NOT NULL DEFAULT '',
    tls_cipher      TEXT NOT NULL DEFAULT '',
    tls_sni         TEXT NOT NULL DEFAULT '',
    server_cert     TEXT NOT NULL DEFAULT '',
    packets_in      INTEGER NOT NULL DEFAULT 0,
    packets_out     INTEGER NOT NULL DEFAULT 0,
    bytes_in        INTEGER NOT NULL DEFAULT 0,
    bytes_out       INTEGER NOT NULL DEFAULT 0
);

-- QUIC 连接
CREATE TABLE IF NOT EXISTS quic_connection (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id         TEXT NOT NULL UNIQUE,
    src_ip          TEXT NOT NULL,
    src_port        INTEGER NOT NULL,
    dst_ip          TEXT NOT NULL,
    dst_port        INTEGER NOT NULL,
    state           TEXT NOT NULL DEFAULT 'handshaking',
    started_at      REAL NOT NULL,
    established_at  REAL,
    closed_at       REAL,
    close_reason    TEXT NOT NULL DEFAULT '',
    version         TEXT NOT NULL DEFAULT '',
    dcid            TEXT NOT NULL DEFAULT '',
    scid            TEXT NOT NULL DEFAULT '',
    alpn            TEXT NOT NULL DEFAULT '',
    tls_cipher      TEXT NOT NULL DEFAULT '',
    tls_sni         TEXT NOT NULL DEFAULT '',
    server_cert     TEXT NOT NULL DEFAULT '',
    is_0rtt         INTEGER NOT NULL DEFAULT 0,
    packets_in      INTEGER NOT NULL DEFAULT 0,
    packets_out     INTEGER NOT NULL DEFAULT 0,
    bytes_in        INTEGER NOT NULL DEFAULT 0,
    bytes_out       INTEGER NOT NULL DEFAULT 0,
    streams_count   INTEGER NOT NULL DEFAULT 0
);

-- QUIC 流（多路复用）
CREATE TABLE IF NOT EXISTS quic_stream (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id   TEXT NOT NULL,
    stream_id       INTEGER NOT NULL,
    stream_type     TEXT NOT NULL DEFAULT '',
    state           TEXT NOT NULL DEFAULT 'open',
    started_at      REAL NOT NULL,
    closed_at       REAL,
    protocol_flow_id TEXT NOT NULL DEFAULT '',
    bytes_in        INTEGER NOT NULL DEFAULT 0,
    bytes_out       INTEGER NOT NULL DEFAULT 0,
    UNIQUE(connection_id, stream_id)
);

CREATE INDEX IF NOT EXISTS idx_tcp_conn_flow_id ON tcp_connection(flow_id);
CREATE INDEX IF NOT EXISTS idx_quic_conn_flow_id ON quic_connection(flow_id);
CREATE INDEX IF NOT EXISTS idx_quic_stream_conn ON quic_stream(connection_id);
CREATE INDEX IF NOT EXISTS idx_quic_stream_proto ON quic_stream(protocol_flow_id);
```

### 跨库关联

```
transport.db          connection.db              protocol.db
 Packet               tcp_connection              Flow (HTTP/WS)
 ┌──────┐   flow_id   ┌──────────────┐  conn_id  ┌──────────┐
 │packet │────────────→│tcp_connection│←──────────│HTTP Flow │
 │packet │            │              │           │          │
 └──────┘            └──────────────┘           └──────────┘

                       quic_connection             Flow (H3)
 ┌──────┐   flow_id   ┌──────────────┐           ┌──────────┐
 │packet │────────────→│quic_connection│          │H3 Flow   │
 │(UDP)  │            │              │           │          │
 └──────┘             ├──────────────┤  proto_id  │          │
                      │ quic_stream  │───────────→│(stream)  │
                      │ quic_stream  │───────────→│          │
                      └──────────────┘           └──────────┘
```

- `transport.db Packet.flow_id` → `connection.db tcp/quic_connection.flow_id`
- `protocol.db Flow.metadata.connectionId` → `connection.db tcp/quic_connection.flow_id`
- `quic_stream.protocol_flow_id` → `protocol.db Flow.flow_id`

### 对现有架构的改动

1. **TaskDatabaseGroup**：从 4 库变为 5 库，新增 `connection: Connection` + `connectionWriteQueue: DispatchQueue`
2. **新增 `ConnectionSchema.swift`**
3. **新增 DAO**：`TcpConnectionDAO.swift`、`QuicConnectionDAO.swift`、`QuicStreamDAO.swift`
4. **新增 Model**：`TcpConnectionRecord.swift`、`QuicConnectionRecord.swift`、`QuicStreamRecord.swift`
5. **state.db**：移除 `connection` 表（迁移到 connection.db），StateSchema 更新
6. **state.db ConnectionDAO**：删除（被 TcpConnectionDAO 替代）
7. **SessionRecorder 双写**：TCP 连接信息改写 connection.db 而非 state.db
8. **PathManager**：新增 `connectionDBPath(_:root:)` 方法
9. **PRAGMA 配置**：connection.db 同其他库一致

### 新增/修改文件

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `Storage/Schema/ConnectionSchema.swift` | tcp_connection + quic_connection + quic_stream DDL |
| 新建 | `Storage/DAO/TcpConnectionDAO.swift` | TCP 连接 CRUD |
| 新建 | `Storage/DAO/QuicConnectionDAO.swift` | QUIC 连接 CRUD |
| 新建 | `Storage/DAO/QuicStreamDAO.swift` | QUIC 流 CRUD |
| 新建 | `Storage/Model/TcpConnectionRecord.swift` | TCP 连接 model |
| 新建 | `Storage/Model/QuicConnectionRecord.swift` | QUIC 连接 model |
| 新建 | `Storage/Model/QuicStreamRecord.swift` | QUIC 流 model |
| 修改 | `Storage/TaskDatabaseGroup.swift` | 新增第 5 个库 connection |
| 修改 | `Storage/DatabaseManager.swift` | 适配 5 库 |
| 修改 | `Storage/Schema/StateSchema.swift` | 移除 connection 表 |
| 修改 | `Storage/DAO/ConnectionDAO.swift` | 删除（替换为 TcpConnectionDAO） |
| 修改 | `Storage/PathManager.swift` | 新增 connectionDBPath |
| 修改 | `Proxy/SessionRecorder.swift` | 连接信息写 connection.db |
| 新建 | 测试文件 | ConnectionSchema + DAO 测试 |

---

## Sub-project A：ProtocolRecorder 扩展

### 设计决策

| 协议 | Recorder 策略 | Flow protocol 值 | decoded.db 使用 |
|------|-------------|------------------|----------------|
| HTTP/2 | 复用 HTTPRecorder，加 protocolOverride 参数 | `"H2"` | 同 HTTP（req/rsp 各一条） |
| HTTP/3 | 复用 HTTPRecorder，protocolOverride="H3" | `"H3"` | 同 HTTP |
| WebSocket | 新建 WebSocketRecorder | `"WS"` / `"WSS"` | 每帧一条，sequence 递增 |
| DNS | 新建 DNSRecorder | `"DNS"` | 不使用（数据全在 metadata） |
| gRPC | 新建 GRPCRecorder | `"gRPC"` | 每 message 一条，sequence 递增 |
| QUIC | 不使用 ProtocolRecorder，直接写 connection.db | connection.db 记录 | 不使用 |

### WebSocketRecorder

WebSocket 连接 = 一个 Flow，帧数据实时写入 decoded.db。

**protocol.db flow 表**：

```
flow_id: "ws_0001"
protocol: "WS" (或 "WSS")
host: "ws.example.com"
summary: "↑12 ↓34 frames"
search_key1: "graphql-ws"   (subprotocol, 空则为 "")
search_key2: "/chat"        (uri)
search_key3: "46"           (total frames)
search_key4: "1000"         (close code)
注意：scheme 信息已由 protocol 字段（"WS"/"WSS"）承载，search_key1 用于 subprotocol 更有查询价值。
此映射覆盖先前 database-redesign spec 中的 WebSocket search_key 表，以本 spec 为准。
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

**生命周期**：WebSocketRecorder 在连接建立时立即插入一条 `status=inProgress` 的 Flow 记录到 protocol.db（避免崩溃导致 decoded.db 中帧数据成为孤儿）。帧数据实时写入 decoded.db。连接关闭时 UPDATE 该 Flow 记录（设置 endedAt、summary、status=completed、search_key3=帧总数、search_key4=closeCode）。

**大文件帧存储**：TEXT 帧 > 4KB 和 BINARY 帧不通过 PayloadWriter（它设计为单文件追加），而是直接使用 `FileManager.createFile` + `FileHandle` 写入单帧文件。大多数 WS 帧 ≤ 4KB，走 decoded.db 内联路径，无需文件 I/O。

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

### QUIC/HTTP3

**QUIC 连接**不通过 ProtocolRecorder，直接写 connection.db：

```
PacketCaptureEngine 检测 UDP:443 →
    QUICDecoder.parse() 提取包头 →
    QuicConnectionDAO.insertOrUpdate() 写 connection.db
    QuicStreamDAO.insert() 记录流创建
```

**HTTP/3 请求**复用 HTTPRecorder：

```
QUIC stream 上的 HTTP/3 帧 →
    HTTP3Handler 解析为 HTTP 语义 →
    HTTPRecorder(protocolOverride: "H3", extraMetadata: {
        "connectionId": quic_connection.flow_id,
        "streamId": quic_stream.stream_id,
        "quicVersion": "1"
    }) →
    FlowDAO.insert() 到 protocol.db
    同时 QuicStreamDAO.update(protocol_flow_id: h3FlowId)
```

**HTTP/3 的完整数据流**：

```
UDP 包到达
    ↓
transport.db: 记录 UDP packet
    ↓
QUICDecoder 解析 QUIC 包头
    ↓
connection.db: quic_connection（连接级元数据）
              + quic_stream（每个流）
    ↓
HTTP/3 Handler 解析 HTTP 语义
    ↓
protocol.db: Flow (protocol="H3")
             复用 HTTPRecorder (protocolOverride: "H3")
```

**注意**：项目已有 SwiftQuiche 和 SwiftLsquic 两个 QUIC 后端（iOS only）。HTTP/3 Handler 的具体实现取决于选用的后端，但 Recorder 层不关心——它只消费解析后的 HTTP 语义数据。

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

**HTTP2CaptureHandler（需要完整重构）**：

当前 `HTTP2CaptureHandler` 的 `H2StreamCaptureHandler` 和 `H2ResponseRelayHandler` 直接使用 `SessionRecorder`。需要完整重构：
1. `H2StreamCaptureHandler` 中的 `SessionRecorder` 替换为 `HTTPRecorder`（带 `protocolOverride: "H2"`, `extraMetadata: ["streamId": N]`）
2. gRPC 检测（`content-type: application/grpc*`）时，改为创建 `GRPCRecorder` 替代 HTTPRecorder
3. `H2ResponseRelayHandler` 中 recorder 引用类型从 `SessionRecorder` 改为 `ProtocolRecorder` 协议
4. `HTTP2CaptureBuilder` multiplexer 闭包中的 recorder 创建逻辑同步更新
5. 注意：当前代理对上游使用 HTTP/1.1（`applicationProtocols: ["http/1.1"]`），metadata 中应记录 `"upstreamVersion": "HTTP/1.1"` 以区分

这是 Sub-project A 中改动量最大的部分。

**HTTPCaptureHandler（DoH 检测）**：

在 `recordResponseEnd()` 中，检测 `content-type == "application/dns-message"`，读取响应 body，`DNSDecoder.parse()`，创建独立 DNS Flow。

**UDP DNS（跨进程问题）**：

`UDPForwarder` 运行在 PacketTunnel 扩展进程中，而 `FlowDAO` 和 `DatabaseManager` 运行在主 App 进程中。两者是不同进程，不能直接共享内存对象。

**解决方案：App Group 共享数据库 + 进程感知**：
- PacketTunnel 扩展进程中的 `DNSRecorder` 直接写入 App Group 目录下的 `protocol.db`（SQLite WAL 模式支持跨进程一写多读，只要不同时多写）
- PacketTunnel 使用 `PragmaProfile.packetTunnel`（低内存配置）
- 主 App 进程读取 `protocol.db` 时无需额外同步（WAL 模式允许并发读写）
- 注意：如果主 App 的 NIO Handler 也在写同一个 `protocol.db`，两个进程会竞争写锁。通过 `busy_timeout = 3000` 缓解，但高并发时仍可能阻塞。因此 UDP DNS 写入走 `BatchWriter`（100ms 窗口），减少锁竞争频率。

**替代方案（如果跨进程写锁成为瓶颈）**：
- 延迟 UDP DNS 记录——PacketTunnel 扩展仅将 DNS 数据写入共享文件（JSON lines），主 App 进程启动时或定期扫描该文件并导入 protocol.db。
- 这样 protocol.db 只有一个写者（主 App），但 DNS 数据延迟展示。

### 新增/修改文件

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `Storage/Protocol/WebSocketRecorder.swift` | WS 帧记录 + Flow 构建 |
| 新建 | `Storage/Protocol/DNSRecorder.swift` | DNS 查询/响应 + transport 标记 |
| 新建 | `Storage/Protocol/GRPCRecorder.swift` | gRPC message 记录 |
| 修改 | `Storage/Protocol/HTTPRecorder.swift` | 加 protocolOverride + extraMetadata |
| 修改 | `Proxy/WebSocketCaptureHandler.swift` | 集成 WebSocketRecorder |
| 修改 | `Proxy/HTTP2CaptureHandler.swift` | 传 H2 参数 + gRPC 路由 |
| 修改 | `Proxy/GRPCCaptureHandler.swift` | GRPCDecoder 工具方法供 GRPCRecorder 调用 |
| 修改 | `Proxy/HTTPCaptureHandler.swift` | DoH 检测 + DNS Flow 创建 |
| 修改 | `PacketCapture/UDPForwarder.swift` | UDP DNS → DNSRecorder |
| 修改 | `Storage/DAO/DecodedEntryDAO.swift` | 新增 findAll(db:flowId:offset:limit:) 分页查询 |
| 修改 | `Storage/DAO/FlowDAO.swift` | 新增 keyword 搜索参数 + FlowDAO.search() 方法 |
| 新建 | 测试文件 × 3 | WebSocket/DNS/gRPC Recorder 测试 |

---

## Sub-project B1：数据源切换 + 统一 Flow 列表

### FlowListViewModel

```swift
class FlowListViewModel: ObservableObject {
    @Published var flows: [FlowRecord] = []
    @Published var isLoading = false

    var taskId: Int64                // 数据库层使用 Int64；UI 导航层传入 String 时需转换
    var protocolFilter: String?       // nil=全部, "HTTP", "WS", "DNS", "gRPC"
    var hostContains: String?
    var keyword: String?              // 搜索 host + summary + searchKey2(uri)，需扩展 FlowDAO.query
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

Step 4: 删除旧 UI 组件 (SessionListView 等 7 个文件)
        → 先删 UI，因为 UI 引用了旧模型；先删模型会导致编译失败

Step 5: 删除旧模型 (Session.swift, CaptureTask.swift, Rule.swift)

Step 6: 删除 ActiveSQLite 框架 (12 个文件)
        → 最后删 ORM，因为旧模型依赖它

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

## 延迟协议

MQTT 的 search_key 映射已在先前 database-redesign spec 中预留，但本 spec 不覆盖其 Recorder 实现。MQTT 将在后续 spec 中单独设计（遵循相同的 ProtocolRecorder 模式）。

QUIC/HTTP3 已纳入本 spec（Sub-project A0 connection.db + Sub-project A HTTP3 Recorder）。

---

## 全景汇总

| Sub-project | 范围 | 新建文件 | 修改文件 | 删除文件 |
|------------|------|---------|---------|---------|
| A0: connection.db 连接层 | TCP/QUIC 连接数据库 + Schema + DAO + Model | ~8 | ~6 | ~1 |
| A: ProtocolRecorder 扩展 | WS/DNS/gRPC/H2/H3 记录器 + Handler 集成 | ~6 | ~7 | 0 |
| B1: 数据源切换 + 统一列表 | FlowListView + FlowCell + 筛选 | ~5 | ~2 | 0 |
| B2: 协议专属详情视图 | HTTP/WS/DNS/gRPC/QUIC 详情 | ~10 | 0 | 0 |
| C: 清理旧代码 | 提取逻辑 + 移除旧模型/UI/ORM | ~2 | ~3 | ~22 |
