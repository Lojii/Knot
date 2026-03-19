# Knot 存储层设计

## 1. 设计理念

### 旧架构的问题
- 单一 `nio.db` 数据库，所有数据混在一起
- 基于 ActiveSQLite/ASModel ORM，依赖重且不灵活
- Session 模型过度耦合 HTTP 协议，难以扩展
- 网络扩展和主应用共享数据库时存在锁竞争
- 无法支持大文件流式写入

### 新架构目标
- **任务隔离**: 每个抓包任务独立数据库组，互不干扰
- **协议无关**: 统一 FlowRecord 模型，通过 metadata JSON 扩展
- **高并发**: WAL 模式 + 串行写入队列，无锁竞争
- **流式存储**: 大 Payload 文件化，小 Payload 内联 BLOB
- **可扩展**: 新增协议无需修改 Schema

## 2. 数据库架构

```
┌─────────────────────────────────────────────────────────┐
│                  catalog.db (全局数据库)                   │
│  ┌─────────────────┬──────────┬──────────────┐          │
│  │  capture_task   │   rule   │  breakpoint  │          │
│  └─────────────────┴──────────┴──────────────┘          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│           Per-Task Database Group (按需打开)              │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ transport.db │  │  proto.db    │  │  decoded.db  │   │
│  │ TCP/UDP 包   │  │ 应用层流记录  │  │ 解码内容     │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐                      │
│  │  state.db    │  │connection.db │                      │
│  │ 流状态       │  │ 连接元数据   │                      │
│  └──────────────┘  └──────────────┘                      │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │ payloads/ 目录                                    │    │
│  │  ├── raw/        (原始请求/响应 Body)              │    │
│  │  ├── decoded/    (解码后的 Body)                   │    │
│  │  └── modified/   (用户修改后的版本)                │    │
│  └──────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## 3. Schema 定义

### 3.1 catalog.db — 全局目录

```sql
-- 抓包任务表
CREATE TABLE capture_task (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    created_at  REAL NOT NULL,           -- TimeInterval (秒)
    started_at  REAL,
    stopped_at  REAL,
    status      TEXT DEFAULT 'created',  -- created/running/stopped/error
    rule_id     INTEGER,
    ssl_enabled INTEGER DEFAULT 1,       -- 是否启用 HTTPS 解密
    local_ip    TEXT,
    local_port  INTEGER DEFAULT 8034,
    local_enabled INTEGER DEFAULT 1,
    wifi_ip     TEXT,
    wifi_port   INTEGER DEFAULT 8034,
    wifi_enabled INTEGER DEFAULT 0,
    flow_count  INTEGER DEFAULT 0,       -- 统计: 总流数
    upload_bytes INTEGER DEFAULT 0,      -- 统计: 上传总字节
    download_bytes INTEGER DEFAULT 0,    -- 统计: 下载总字节
    note        TEXT,
    extra       TEXT                     -- JSON 扩展字段
);

-- 过滤规则表
CREATE TABLE rule (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    name              TEXT NOT NULL,
    default_strategy  TEXT DEFAULT 'proxy',  -- proxy/direct/reject
    blacklist_enabled INTEGER DEFAULT 0,
    config            TEXT,                  -- JSON: 规则配置
    created_at        REAL NOT NULL,
    author            TEXT,
    note              TEXT
);

-- 断点表
CREATE TABLE breakpoint (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    enabled         INTEGER DEFAULT 1,
    match_phase     TEXT DEFAULT 'request',  -- request/response/both
    match_protocol  TEXT DEFAULT 'HTTP',
    match_pattern   TEXT NOT NULL,            -- 匹配模式 (正则/通配符)
    action          TEXT DEFAULT 'pause',     -- pause/modify/script
    script_ref      TEXT,                     -- 脚本文件引用
    priority        INTEGER DEFAULT 0,
    created_at      REAL NOT NULL,
    note            TEXT
);
```

### 3.2 proto.db — 协议流记录

```sql
-- 统一流记录表（核心表）
CREATE TABLE flow (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id         TEXT NOT NULL UNIQUE,     -- 全局唯一流 ID
    protocol        TEXT NOT NULL,            -- HTTP/HTTPS/DNS/WebSocket/gRPC/MQTT/...
    host            TEXT,
    port            INTEGER,

    -- 时序字段
    started_at      REAL NOT NULL,            -- 流开始时间
    ended_at        REAL,                     -- 流结束时间
    duration_ms     INTEGER,                  -- 持续时间 (毫秒)
    connect_at      REAL,                     -- TCP 连接发起
    connected_at    REAL,                     -- TCP 连接建立
    tls_done_at     REAL,                     -- TLS 握手完成
    req_end_at      REAL,                     -- 请求发送完成
    rsp_start_at    REAL,                     -- 响应开始接收

    -- 流量统计
    upload_bytes    INTEGER DEFAULT 0,
    download_bytes  INTEGER DEFAULT 0,

    -- 状态
    status          TEXT DEFAULT 'active',    -- active/completed/error
    error_message   TEXT,
    summary         TEXT,

    -- 协议语义搜索键 (每个协议定义不同含义)
    search_key1     TEXT,  -- HTTP: method    | DNS: queryType  | gRPC: "POST"
    search_key2     TEXT,  -- HTTP: uri       | DNS: queryName  | gRPC: servicePath
    search_key3     TEXT,  -- HTTP: status    | DNS: rcode      | gRPC: grpcStatus
    search_key4     TEXT,  -- HTTP: contentType

    -- 协议扩展数据 (JSON)
    metadata        TEXT,  -- { headers, encoding, grpc_service, frames, ... }

    -- Payload 引用
    req_payload_ref TEXT,  -- "payloads/raw/{flowId}_req.bin"
    rsp_payload_ref TEXT,  -- "payloads/raw/{flowId}_rsp.bin"

    -- 标记
    is_intercepted  INTEGER DEFAULT 0,
    is_modified     INTEGER DEFAULT 0,
    tags            TEXT                      -- 用户标签 (逗号分隔)
);

-- 索引
CREATE INDEX idx_flow_protocol   ON flow(protocol);
CREATE INDEX idx_flow_host       ON flow(host);
CREATE INDEX idx_flow_started_at ON flow(started_at);
CREATE INDEX idx_flow_status     ON flow(status);
CREATE INDEX idx_flow_key1       ON flow(search_key1);
CREATE INDEX idx_flow_key2       ON flow(search_key2);
CREATE INDEX idx_flow_key3       ON flow(search_key3);
```

### 3.3 connection.db — 连接元数据

```sql
-- TCP 连接表
CREATE TABLE tcp_connection (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id   TEXT NOT NULL UNIQUE,
    src_ip          TEXT,
    src_port        INTEGER,
    dst_ip          TEXT,
    dst_port        INTEGER,
    tls_sni         TEXT,                    -- TLS SNI 主机名
    tls_version     TEXT,                    -- TLS 版本
    tls_cipher      TEXT,                    -- TLS 密码套件
    alpn            TEXT,                    -- ALPN 协商结果
    started_at      REAL,
    connected_at    REAL,
    closed_at       REAL,
    close_reason    TEXT,                    -- normal/reset/timeout/error
    upload_bytes    INTEGER DEFAULT 0,
    download_bytes  INTEGER DEFAULT 0
);

-- QUIC 连接表
CREATE TABLE quic_connection (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id   TEXT NOT NULL UNIQUE,
    src_ip          TEXT,
    src_port        INTEGER,
    dst_ip          TEXT,
    dst_port        INTEGER,
    quic_version    TEXT,
    dcid            TEXT,                    -- Destination Connection ID
    scid            TEXT,                    -- Source Connection ID
    alpn            TEXT,
    started_at      REAL,
    closed_at       REAL,
    close_reason    TEXT
);

-- QUIC 流表
CREATE TABLE quic_stream (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    connection_id   TEXT NOT NULL,
    stream_id       INTEGER NOT NULL,
    direction       TEXT,                    -- bidi/uni
    started_at      REAL,
    closed_at       REAL,
    upload_bytes    INTEGER DEFAULT 0,
    download_bytes  INTEGER DEFAULT 0,
    FOREIGN KEY (connection_id) REFERENCES quic_connection(connection_id)
);
```

### 3.4 decoded.db — 解码内容

```sql
-- 解码条目表
CREATE TABLE decoded_entry (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id         TEXT NOT NULL,
    phase           TEXT NOT NULL,           -- request/response
    encoding        TEXT,                    -- gzip/deflate/brotli/zstd/identity
    original_size   INTEGER,
    decoded_size    INTEGER,
    content_type    TEXT,                    -- text/html, application/json, ...
    text_content    TEXT,                    -- 解码后的文本内容 (可搜索)
    binary_ref      TEXT,                    -- 二进制内容文件引用
    created_at      REAL NOT NULL
);

CREATE INDEX idx_decoded_flow_id ON decoded_entry(flow_id);
```

## 4. 核心组件

### 4.1 DatabaseManager（数据库管理器）

```swift
// 单例，管理所有数据库连接
class DatabaseManager {
    static let shared = DatabaseManager()

    let catalogDB: Connection           // 始终打开的全局数据库

    // 按需打开/关闭的任务数据库组
    func openTask(_ taskId: String) -> TaskDatabaseGroup
    func closeTask(_ taskId: String)    // 引用计数 -1

    // 初始化时:
    // 1. 创建目录结构
    // 2. 打开 catalog.db
    // 3. 执行 CatalogSchema.create()
    // 4. 配置 PRAGMA (WAL, cache_size, journal_size_limit)
}
```

### 4.2 TaskDatabaseGroup（任务数据库组）

```swift
// 捆绑一个任务的所有数据库和写入队列
class TaskDatabaseGroup {
    let taskId: String
    let transport: Connection     // transport.db
    let proto: Connection         // proto.db (protocol 是 Swift 关键字)
    let decoded: Connection       // decoded.db
    let state: Connection         // state.db
    let connection: Connection    // connection.db

    // 5 个串行写入队列 (避免 SQLite BUSY)
    let transportWriteQueue: DispatchQueue
    let protoWriteQueue: DispatchQueue
    let decodedWriteQueue: DispatchQueue
    let stateWriteQueue: DispatchQueue
    let connectionWriteQueue: DispatchQueue

    // 引用计数
    var refCount: Int

    // PRAGMA 配置 (根据进程类型调整)
    static func configurePragmas(_ db: Connection, profile: Profile)
    // mainApp: cache_size=2MB, journal_size_limit=4MB
    // packetTunnel: cache_size=512KB, journal_size_limit=1MB
}
```

### 4.3 PathManager（路径管理器）

```swift
// 集中管理所有文件路径
struct PathManager {
    static let containerURL: URL  // App Group 共享容器

    // 数据库路径
    static func catalogDBPath() -> String
    static func taskDirectory(taskId: String) -> URL
    static func transportDBPath(taskId: String) -> String
    static func protoDBPath(taskId: String) -> String
    // ...

    // Payload 路径
    static func payloadDirectory(taskId: String) -> URL
    static func rawPayloadPath(taskId: String, flowId: String, phase: String) -> URL
    // phase: "req" / "rsp"
    // 路径: tasks/{taskId}/payloads/raw/{flowId}_{phase}.bin
}
```

### 4.4 PayloadWriter / PayloadReader

```swift
// 流式写入 Payload 到磁盘
class PayloadWriter {
    let fileURL: URL
    private var fileHandle: FileHandle?

    func open()                  // 创建/打开文件
    func write(_ data: Data)     // 追加写入
    func close()                 // 关闭文件句柄
    var bytesWritten: Int64      // 已写入字节数
}

// 读取 Payload
class PayloadReader {
    static func read(url: URL) -> Data?
    static func readStream(url: URL, chunkSize: Int) -> AsyncStream<Data>
}
```

## 5. DAO 层设计

所有 DAO 采用静态 enum 模式（命名空间，无实例化）：

```swift
enum FlowDAO {
    // 插入
    static func insert(db: Connection, record: FlowRecord) throws

    // 更新
    static func update(db: Connection, flowId: String, ...) throws

    // 查询单条
    static func find(db: Connection, flowId: String) -> FlowRecord?

    // 分页查询（支持过滤）
    static func query(
        db: Connection,
        protocol: String? = nil,
        host: String? = nil,
        searchText: String? = nil,
        offset: Int = 0,
        limit: Int = 50
    ) -> [FlowRecord]

    // 协议统计
    static func countByProtocol(db: Connection) -> [String: Int]
}

enum CatalogDAO {
    // CaptureTask CRUD
    static func insertTask(db: Connection, ...) throws -> Int64
    static func findTask(db: Connection, id: Int64) -> CaptureTaskRecord?
    static func findAllTasks(db: Connection) -> [CaptureTaskRecord]
    static func updateTask(db: Connection, id: Int64, ...) throws

    // Rule CRUD
    static func insertRule(db: Connection, ...) throws -> Int64
    static func findRule(db: Connection, id: Int64) -> RuleRecord?
    static func findAllRules(db: Connection) -> [RuleRecord]
    static func deleteRule(db: Connection, id: Int64) throws
}
```

## 6. 协议记录器（ProtocolRecorder）

每种应用层协议有对应的记录器，负责将 NIO Handler 中的事件转化为 FlowRecord：

```swift
protocol ProtocolRecording {
    func recordRequestHead(...)
    func recordRequestBody(_ data: ByteBuffer)
    func recordRequestEnd()
    func recordResponseHead(...)
    func recordResponseBody(_ data: ByteBuffer)
    func recordResponseEnd()
    func buildFlowRecord() -> FlowRecord
}

// HTTP 记录器
class HTTPRecorder: ProtocolRecording {
    var method: String
    var uri: String
    var host: String
    var requestHeaders: [(String, String)]
    var responseStatus: Int
    var responseHeaders: [(String, String)]
    var timing: TimingInfo

    func buildFlowRecord() -> FlowRecord {
        FlowRecord(
            flowId: flowId,
            protocol: isHTTPS ? "HTTPS" : "HTTP",
            host: host,
            searchKey1: method,      // GET/POST/PUT/...
            searchKey2: uri,         // /api/users
            searchKey3: "\(responseStatus)",  // 200/404/500
            searchKey4: contentType, // application/json
            metadata: buildMetadataJSON(),
            reqPayloadRef: reqPayloadPath,
            rspPayloadRef: rspPayloadPath,
            ...
        )
    }
}

// DNS 记录器
class DNSRecorder: ProtocolRecording {
    // searchKey1: queryType ("A"/"AAAA"/...)
    // searchKey2: queryName ("www.example.com")
    // searchKey3: responseCode ("NOERROR"/"NXDOMAIN"/...)
}

// WebSocket 记录器
class WebSocketRecorder: ProtocolRecording {
    // searchKey2: path ("/ws/chat")
    // metadata: { frames: [...], total_messages: N }
}
```

## 7. 写入流程

### 高并发写入保证

```
NIO EventLoop 线程 (多个)
    │
    │ Handler 回调 (channelRead 等)
    │ → SessionRecorder.record*()
    │ → ProtocolRecorder.build*()
    ↓
dbGroup.protoWriteQueue.async {
    │ FlowDAO.insert(dbGroup.proto, flowRecord)
    │ // 串行执行，避免 SQLite BUSY
}

dbGroup.connectionWriteQueue.async {
    │ TcpConnectionDAO.insertOrUpdate(dbGroup.connection, ...)
}

dbGroup.decodedWriteQueue.async {
    │ DecodedEntryDAO.insert(dbGroup.decoded, ...)
}
```

### 批量写入优化

```swift
class BatchWriter {
    private var pendingFlows: [FlowRecord] = []
    private let batchSize = 50
    private let flushInterval: TimeInterval = 1.0

    func enqueue(_ record: FlowRecord) {
        pendingFlows.append(record)
        if pendingFlows.count >= batchSize {
            flush()
        }
    }

    func flush() {
        let batch = pendingFlows
        pendingFlows = []
        dbGroup.protoWriteQueue.async {
            try? db.transaction {
                for record in batch {
                    FlowDAO.insert(db: db, record: record)
                }
            }
        }
    }
}
```

## 8. SQLite PRAGMA 配置

```sql
-- WAL 模式: 支持并发读写
PRAGMA journal_mode = WAL;

-- 主应用配置 (读取为主)
PRAGMA cache_size = -2048;          -- 2MB 缓存
PRAGMA journal_size_limit = 4194304; -- 4MB WAL 文件限制

-- 网络扩展配置 (写入为主，内存受限)
PRAGMA cache_size = -512;           -- 512KB 缓存
PRAGMA journal_size_limit = 1048576; -- 1MB WAL 文件限制

-- 通用配置
PRAGMA synchronous = NORMAL;        -- 平衡性能与安全
PRAGMA temp_store = MEMORY;         -- 临时表使用内存
PRAGMA mmap_size = 268435456;       -- 256MB 内存映射 (主应用)
```

## 9. 文件系统布局

```
{App Group Container}/
├── catalog.db                              # 全局目录数据库
├── catalog.db-wal                          # WAL 日志
├── catalog.db-shm                          # 共享内存
│
├── Cert/                                   # CA 证书目录
│   ├── ca.pem                              # CA 证书
│   └── ca-key.pem                          # CA 私钥
│
├── tunnel_logs/                            # 隧道扩展日志
│
└── tasks/                                  # 任务数据目录
    ├── {taskId-1}/                         # 任务 1
    │   ├── transport.db                    # 传输层数据
    │   ├── proto.db                        # 协议层流记录
    │   ├── decoded.db                      # 解码内容
    │   ├── state.db                        # 流状态
    │   ├── connection.db                   # 连接元数据
    │   └── payloads/
    │       ├── raw/
    │       │   ├── {flowId1}_req.bin       # 请求 Body
    │       │   ├── {flowId1}_rsp.bin       # 响应 Body
    │       │   ├── {flowId2}_req.bin
    │       │   └── ...
    │       ├── decoded/                    # 解码后版本
    │       └── modified/                   # 用户修改版本
    │
    ├── {taskId-2}/                         # 任务 2
    │   └── ...
    └── ...
```

## 10. 数据迁移

### LegacyMigrator

从旧的 `nio.db`（ActiveSQLite）迁移到新架构：

```swift
enum LegacyMigrator {
    static func migrateIfNeeded() {
        // 1. 检测是否存在旧数据库
        guard FileManager.default.fileExists(atPath: legacyDBPath) else { return }

        // 2. 打开旧数据库
        let legacyDB = try Connection(legacyDBPath)

        // 3. 遍历旧 Session 表
        for row in legacyDB.prepare("SELECT * FROM Session") {
            // 4. 转换为 FlowRecord
            let flowRecord = convertSessionToFlow(row)

            // 5. 写入新数据库
            FlowDAO.insert(db: newProtoDb, record: flowRecord)
        }

        // 6. 时间戳修正 (旧数据可能是毫秒)
        // createdAtMs > 1_000_000_000_000 → 除以 1000 转为秒
    }
}
```
