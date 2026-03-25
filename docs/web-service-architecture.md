# Web Service 架构方案

## 核心原则

**同一时刻只有一个 KnotWebServer 实例运行。谁活着谁起服务。**

同一套 `KnotWebServer` 代码，根据运行环境在不同进程中实例化。主 App 和 Network Extension 不会同时运行 Web 服务。

---

## 各平台架构

### macOS

```
┌───────────────────────────────┐
│ Flutter App (主进程)            │
│  └─ KnotServer (子进程)         │
│      ├─ KnotWebServer (API)    │  ← 唯一 Web 服务
│      └─ ProxyServer (抓包)     │  ← 按需启动
│                                │
│  Flutter UI 连 localhost:PORT  │
└───────────────────────────────┘
```

macOS 没有 Network Extension 的限制。KnotServer 作为子进程常驻，主 App 始终是纯客户端。

### iOS

iOS 的 Network Extension 只在 VPN 开启时运行，关闭即停止。主 App 也可能随时被系统回收。因此需要动态决定由谁来提供 Web 服务。

#### VPN 开启（抓包中）

```
┌──────────────────┐       ┌──────────────────────────┐
│ 主 App (如果在前台) │       │ Network Extension         │
│                   │       │                           │
│ 纯客户端，不起服务  │──────→│ KnotWebServer ← 权威服务   │
│ 连 Extension 端口  │       │ ProxyServer (MITM 抓包)    │
│                   │       │ SQLite 写入 (App Group)    │
└──────────────────┘       └──────────────────────────┘
        ↑                            ↑
   局域网浏览器                   局域网浏览器
   也连 Extension 端口            直接连
```

- Extension 是数据权威方（正在写入）
- 主 App 如果在前台，作为客户端连接 Extension 的 Web API
- 主 App 被杀了也不影响 Extension 和浏览器

#### VPN 关闭（查看历史）

```
┌──────────────────────┐
│ 主 App                │
│                       │
│ KnotWebServer ← 服务  │  ← 主 App 自己起 Web 服务
│ 只读模式，无抓包能力   │
│ SQLite 只读 (App Group)│
└──────────────────────┘
        ↑
   局域网浏览器
   连主 App 端口
```

- Extension 不运行
- 主 App 启动 KnotWebServer 提供历史查询
- 数据库只读，不会有写入冲突

---

## 切换协议

主 App 和 Extension 通过 **App Group 共享文件** + **Darwin Notification** 协调谁来起 Web 服务。

### 共享状态文件

路径: `App Group Container/web-service-state.json`

```json
{
  "provider": "extension",
  "port": 9090,
  "pid": 12345,
  "startedAt": 1711360000
}
```

| 字段 | 说明 |
|------|------|
| `provider` | `"extension"` 或 `"app"`，当前谁在提供服务 |
| `port` | Web 服务绑定的端口 |
| `pid` | 进程 ID（用于判断是否还活着） |
| `startedAt` | 启动时间戳 |

### Darwin Notification 事件

| 通知名 | 发送方 | 含义 |
|--------|--------|------|
| `com.knot.webservice.started` | 任意 | "我启动了 Web 服务" |
| `com.knot.webservice.stopped` | 任意 | "我停了 Web 服务" |

### 状态机

```
主 App 启动:
  1. 读 web-service-state.json
  2. if provider == "extension" && 进程还活着:
       → 连 extension 端口，不起服务
  3. else:
       → 自己起 KnotWebServer
       → 写 state.json (provider: "app", port, pid)
       → 发 Darwin Notification: started

Extension 启动 (VPN 开启):
  1. 读 web-service-state.json
  2. if provider == "app":
       → 发 Darwin Notification: stopped (通知主 App 关服务)
       → 等待主 App 关闭 (或超时 2s 后强制继续)
  3. 起 KnotWebServer
  4. 写 state.json (provider: "extension", port, pid)
  5. 发 Darwin Notification: started

Extension 停止 (VPN 关闭):
  1. 删除或清空 state.json
  2. 发 Darwin Notification: stopped

主 App 收到 started 通知:
  → 如果自己在跑 Web 服务: 关闭它
  → 读 state.json 获取新端口
  → 重新连接

主 App 收到 stopped 通知:
  → 如果需要 (用户还在看 App): 自己起 KnotWebServer
  → 写 state.json
```

---

## 数据库并发安全

SQLite 在 App Group 共享目录中。

| 场景 | Extension | 主 App | 安全性 |
|------|-----------|--------|--------|
| 抓包中 | 读写 | 只读 (连 Extension API) | 安全：主 App 不直接操作 DB |
| 未抓包 | 不运行 | 只读 | 安全：单进程访问 |
| 切换瞬间 | 正在停 | 正在起 | 安全：通过 Darwin Notification 排序 |

主 App 的 Web 服务在只读模式下运行时，打开 SQLite 连接使用 `readonly: true`，避免任何意外写入。

---

## 端口策略

- Extension 和主 App 使用**相同的首选端口** (如 9090)
- 同一时刻只有一个在跑，不会冲突
- 绑定失败时自动递增端口 (已有 `PortAllocator.bindWithRetry`)
- 实际端口写入 `web-service-state.json`，客户端从中读取

---

## 代码复用

```
KnotWebService (Swift Package)
├── KnotWebServer.swift      ← 完全复用，不改一行
├── HTTPRouter.swift         ← 完全复用
├── Routes/                  ← 完全复用
│   ├── TaskRoutes.swift
│   ├── FlowRoutes.swift
│   └── ...
└── Server/
    └── WebSocketHandler.swift ← 完全复用

调用方只需:
  let server = KnotWebServer(preferredPort: 9090)
  let port = try server.start()
```

不管是主 App 还是 Extension，实例化 `KnotWebServer` 的代码完全相同。区别只在于：
- **何时启动**: 由上述状态机决定
- **数据库路径**: 都是 App Group 目录，一样
- **是否有 ProxyServer**: Extension 有，主 App 没有

---

## 各端实现清单

### iOS Network Extension (PacketTunnel)

```swift
// PacketTunnelProvider.swift

override func startTunnel(options: ..., completionHandler: ...) {
    // 1. 启动抓包
    let task = CaptureTask(...)
    proxyServer.start(task: task)

    // 2. 启动 Web 服务
    let webServer = KnotWebServer(preferredPort: 9090)
    let port = try webServer.start()

    // 3. 写状态文件
    WebServiceState.write(provider: .extension, port: port)

    // 4. 通知主 App
    DarwinNotificationCenter.post("com.knot.webservice.started")
}

override func stopTunnel(with reason: ..., completionHandler: ...) {
    proxyServer.stop()
    webServer.stop()
    WebServiceState.clear()
    DarwinNotificationCenter.post("com.knot.webservice.stopped")
}
```

### iOS 主 App (Flutter - Swift 侧)

```swift
// AppDelegate.swift 或 MethodChannel handler

func ensureWebService() {
    if let state = WebServiceState.read(),
       state.provider == "extension",
       state.isProcessAlive {
        // Extension 在跑，用它的端口
        self.apiPort = state.port
        return
    }

    // Extension 没跑，自己起
    let server = KnotWebServer(preferredPort: 9090)
    let port = try server.start()
    WebServiceState.write(provider: .app, port: port)
    self.apiPort = port
}

// 监听 Darwin Notification
func onWebServiceStarted() {
    // Extension 起来了，关掉自己的
    selfWebServer?.stop()
    let state = WebServiceState.read()
    self.apiPort = state?.port ?? 9090
    // 通知 Flutter 端口变了
}

func onWebServiceStopped() {
    // Extension 停了，自己顶上
    ensureWebService()
}
```

### macOS (当前架构，不变)

```swift
// main.swift (KnotServer 子进程)
let webServer = KnotWebServer(preferredPort: 9090)
let port = try webServer.start()
// 子进程生命周期跟随主 App，不需要切换协议
```

---

## 总结

| 问题 | 方案 |
|------|------|
| 同时跑两个 Web 服务？ | 不会。状态机保证同一时刻只有一个 |
| 端口冲突？ | 不会。同一时刻只有一个进程绑端口 |
| 数据一致性？ | 保证。写入只发生在 Extension 抓包时，主 App 只读 |
| Extension 停了怎么办？ | 主 App 自动接管，起 Web 服务提供历史查询 |
| 代码重复？ | 没有。`KnotWebServer` 是独立 Swift Package，两端复用 |
| 局域网浏览器？ | 连当前活着的那个端口（从 state.json 获取） |
