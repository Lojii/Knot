# Knot 架构设计详解

## 1. 总体架构

Knot 采用分层模块化架构，通过 Swift Package Manager 将代码组织为多个独立包：

```
┌─────────────────────────────────────────────────────────────┐
│                    应用层 (App Layer)                         │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │ KnotApp-iOS  │  │ KnotApp-macOS │  │ PacketTunnel-iOS │  │
│  │  (SwiftUI)   │  │  (SwiftUI)    │  │ (NE Extension)   │  │
│  └──────┬───────┘  └───────┬───────┘  └────────┬─────────┘  │
│         │                  │                    │             │
├─────────┼──────────────────┼────────────────────┼─────────────┤
│         │          UI 层 (Presentation)         │             │
│         │    ┌─────────────────────────┐        │             │
│         └────┤        KnotUI          ├────────┘             │
│              │  Views / Components /   │                      │
│              │  ViewModels (SwiftUI)   │                      │
│              └───────────┬─────────────┘                      │
│                          │                                    │
├──────────────────────────┼────────────────────────────────────┤
│                   核心层 (Core Layer)                          │
│              ┌───────────┴─────────────┐                      │
│              │       KnotCore          │                      │
│              │ ServiceContainer /      │                      │
│              │ Protocols / Models      │                      │
│              └───────────┬─────────────┘                      │
│                          │                                    │
├──────────────────────────┼────────────────────────────────────┤
│                   服务层 (Service Layer)                       │
│              ┌───────────┴─────────────┐                      │
│              │     TunnelServices      │                      │
│              │                         │                      │
│              │  ┌─────────────────┐    │                      │
│              │  │   Proxy 代理    │    │                      │
│              │  │  HTTP/HTTPS/WS  │    │                      │
│              │  │  H2/gRPC/QUIC   │    │                      │
│              │  └────────┬────────┘    │                      │
│              │           │             │                      │
│              │  ┌────────┴────────┐    │                      │
│              │  │  Storage 存储   │    │                      │
│              │  │  DB/DAO/Payload │    │                      │
│              │  └─────────────────┘    │                      │
│              │                         │                      │
│              │  ┌─────────────────┐    │                      │
│              │  │  Codec 编解码   │    │                      │
│              │  │  DNS/NTP/MQTT.. │    │                      │
│              │  └─────────────────┘    │                      │
│              │                         │                      │
│              │  ┌─────────────────┐    │                      │
│              │  │ PacketCapture   │    │                      │
│              │  │ IP包解析/转发    │    │                      │
│              │  └─────────────────┘    │                      │
│              └─────────────────────────┘                      │
│                                                               │
├───────────────────────────────────────────────────────────────┤
│                   外部依赖层                                    │
│  SwiftNIO │ NIOSSL │ SQLite.swift │ swift-crypto │ quiche    │
└───────────────────────────────────────────────────────────────┘
```

## 2. 双数据通路架构

Knot 采用两条独立的数据通路同时工作：

### 通路一：VPN 隧道（传输层）
```
设备所有网络流量
    ↓
NEPacketTunnelProvider (iOS 网络扩展)
    ↓
PacketCaptureEngine (IP 包解析)
    ├── TCP 包 → transport.db 记录
    ├── UDP 包 → UDPForwarder 转发 + 解码
    │   ├── DNS (端口 53) → DNSDecoder
    │   ├── NTP (端口 123) → NTPDecoder
    │   ├── QUIC (端口 443) → QUICDecoder
    │   └── 其他 → 原始记录
    └── ICMP → transport.db 记录
    ↓
TCP 流量重定向到本地代理 (127.0.0.1:8034)
```

### 通路二：代理服务器（应用层）
```
TCP 连接到达本地代理
    ↓
ProxyServer (SwiftNIO Bootstrap)
    ↓
ProtocolRouter (协议检测，读取前4字节)
    ├── HTTP 明文 → HTTPCaptureHandler
    ├── CONNECT → ConnectHandler → MITMHandler (HTTPS 解密)
    │   ├── ALPN=h2 → HTTP2CaptureHandler
    │   └── ALPN=http/1.1 → HTTPCaptureHandler
    │       └── 检测 WebSocket 升级 → WebSocketCaptureHandler
    └── 直接 TLS → TunnelHandler (透传中继)
    ↓
SessionRecorder + ProtocolRecorder
    ↓
proto.db / connection.db / decoded.db / payloads/
```

### 两条通路的关联
- VPN 隧道捕获所有 IP 包，记录传输层信息（源/目的 IP:Port、包大小、时间戳）
- 代理服务器解析应用层协议，记录详细的请求/响应内容
- 两条通路通过 `flow_id` 关联，形成完整的从传输层到应用层的数据视图

## 3. 代理服务器线程模型

```
ProxyServer
├── masterGroup: MultiThreadedEventLoopGroup
│   └── 线程数 = CPU 核心数
│   └── 职责: 接受新连接 (ServerBootstrap)
│
├── workerGroup: MultiThreadedEventLoopGroup
│   └── 线程数 = CPU 核心数 × 3
│   └── 职责: 处理连接上的 I/O 事件
│
└── 每个连接的 Handler Pipeline（在 worker 线程上执行）:
    ProtocolRouter
    → [协议检测]
    → HTTPRequestDecoder / NIOSSLServerHandler / ...
    → HTTPCaptureHandler / HTTP2CaptureHandler / ...
    → ResponseRelayHandler (中继响应)
```

## 4. MITM（中间人）TLS 解密机制

```
客户端                     Knot 代理                      目标服务器
  │                          │                              │
  │── HTTP CONNECT host:443 →│                              │
  │                          │                              │
  │←─ 200 Connection Est. ──│                              │
  │                          │                              │
  │── TLS ClientHello ──────→│                              │
  │   (包含 SNI: host)       │                              │
  │                          │── 动态生成 host 的证书 ──→    │
  │                          │   (CA 签名, SHA256-RSA-2048)  │
  │                          │                              │
  │←─ TLS ServerHello ──────│   (使用动态证书)              │
  │   (Knot 的假证书)        │                              │
  │                          │                              │
  │── TLS 握手完成 ─────────→│                              │
  │   (客户端信任 CA)        │                              │
  │                          │──────── TLS 连接 ───────────→│
  │                          │   (真正的服务器证书)          │
  │                          │                              │
  │== 明文 HTTP 请求 ========│== 重新加密转发 ==============│
  │                          │                              │
  │                     [解密并记录]                         │
  │                     [请求头/Body/时序]                   │
  │                          │                              │
  │== 明文 HTTP 响应 ========│== 解密并记录 ================│
```

### ALPN 协商与协议切换

TLS 握手时通过 ALPN（Application-Layer Protocol Negotiation）确定上层协议：

```
ALPN 协商结果:
├── "h2" (HTTP/2)
│   └── 切换到 HTTP2CaptureHandler
│       └── NIOHTTP2Handler + HTTP2StreamMultiplexer
│       └── 每个 Stream 独立的 H2StreamCaptureHandler
│
├── "http/1.1" (HTTP/1.1)
│   └── 切换到 HTTPCaptureHandler
│       └── 检测 WebSocket Upgrade
│           └── 101 → WebSocketCaptureHandler
│
└── 未协商 / 其他
    └── 按 HTTP/1.1 处理
```

## 5. 证书管理架构

```
CertStore (证书存储)
├── CA 根证书 (x509CACert)
│   └── 存储在 App Group 共享容器
│   └── 用户需手动安装并信任
│
├── CA 私钥 (rsaSigningKey)
│   └── RSA-2048
│   └── 用于签发动态证书
│
├── 服务器私钥 (rsaKey)
│   └── 所有动态证书共用
│
└── ThreadSafeCertPool (线程安全缓存)
    └── [hostname: NIOSSLCertificate]
    └── NSLock 保护并发访问
    └── 避免重复生成

CertGenerator (证书生成器)
├── 输入: 主机名, CA证书, CA私钥
├── X.509 v3 证书
│   ├── 有效期: 1年
│   ├── 签名算法: SHA256withRSA
│   ├── SAN 扩展: 主机名
│   └── DER 编码 → NIOSSLCertificate
└── 输出: 用于该主机的 TLS 服务器证书
```

## 6. 服务注入架构

采用 ServiceContainer 模式实现平台差异化：

```swift
// KnotCore 定义协议
protocol TunnelServiceProtocol {
    func startCapture(config: ProxyConfig) async throws
    func stopCapture() async throws
    var statusPublisher: AnyPublisher<TunnelStatus, Never> { get }
}

protocol CertificateServiceProtocol {
    func installCACert() async throws
    func exportCACert() -> Data?
    var trustStatus: CertTrustStatus { get }
}

// iOS 平台实现
ServiceContainer.shared.register(TunnelServiceProtocol.self,
    instance: iOSTunnelService())  // 使用 NETunnelProviderManager

// macOS 平台实现
ServiceContainer.shared.register(TunnelServiceProtocol.self,
    instance: macOSTunnelService())  // 使用 System Extension 或本地代理

// UI 层解析使用
let tunnelService = ServiceContainer.shared.resolve(TunnelServiceProtocol.self)
```

## 7. 并发模型

### SwiftNIO EventLoop（网络层）
- 所有网络 I/O 在 EventLoop 线程上执行
- Handler 之间通过 ChannelPipeline 传递事件
- 禁止在 EventLoop 上执行阻塞操作

### DispatchQueue（存储层）
- 每个数据库使用独立的串行队列（避免 SQLite BUSY 错误）
- 5 个写入队列: transport / proto / decoded / state / connection
- 读操作可在任意线程（SQLite WAL 模式支持并发读）

### 引用计数（资源管理）
```
DatabaseManager.openTask(taskId)
    → TaskDatabaseGroup 引用计数 +1
    → 首次打开时创建连接

DatabaseManager.closeTask(taskId)
    → 引用计数 -1
    → 引用计数 = 0 时关闭所有连接并释放
```

## 8. 网络配置

```
VPN 隧道配置:
├── IPv4 地址: 192.169.89.1/24
├── IPv6 地址: fd00::1/64
├── MTU: 1500
├── DNS: 8.8.8.8, 8.8.4.4
├── 排除路由: 127.0.0.0/8, 192.168.0.0/16, 10.0.0.0/8
└── 全部流量路由到隧道

代理服务器配置:
├── 本地代理: 127.0.0.1:8034
├── Wi-Fi 代理: [动态IP]:8034（可配置端口）
├── TCP_NODELAY: 启用
├── 连接超时: 10秒
└── TLS 握手超时: 10秒

QUIC 配置 (实验性):
├── 后端: quiche (Cloudflare) 或 lsquic (LiteSpeed)
├── 最大并发会话: 20
├── 空闲超时: 30秒
└── 默认关闭 (HTTP3.enabled = false)
```

## 9. App Group 数据共享

iOS 上主应用和网络扩展运行在不同进程中，通过 App Group 共享数据：

```
App Group: group.Lojii.NIO1901
    │
    ├── catalog.db          ← 两个进程共享（WAL 模式并发安全）
    ├── Cert/               ← CA 证书文件
    └── tasks/
        └── {taskId}/       ← 每个抓包任务的数据
            ├── *.db        ← 网络扩展写入，主应用读取
            └── payloads/   ← 请求/响应 Body 文件
```

网络扩展进程负责：
- 运行 VPN 隧道
- 运行代理服务器
- 写入数据库和 Payload 文件

主应用进程负责：
- 管理抓包任务（启动/停止）
- 读取并展示抓包数据
- 管理规则和证书
