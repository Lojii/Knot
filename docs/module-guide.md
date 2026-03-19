# Knot 模块详解

## 1. TunnelServices 模块

TunnelServices 是项目的核心引擎，包含网络代理、包捕获、协议编解码和数据存储全部功能。

### 1.1 Proxy — 代理服务器

代理服务器基于 SwiftNIO 实现，负责接收、解析并转发所有 HTTP/HTTPS/WebSocket 等应用层流量。

| 文件 | 职责 |
|------|------|
| `ProxyServer.swift` | 代理服务器主类，管理 EventLoopGroup、ServerBootstrap，绑定本地和 Wi-Fi 端口 |
| `ProtocolRouter.swift` | 连接首个 Handler，读取前 4 字节判断协议类型（HTTP/HTTPS/直接TLS），路由到对应 Pipeline |
| `HTTPCaptureHandler.swift` | HTTP/1.1 请求/响应捕获，连接真实服务器并中继数据 |
| `ConnectHandler.swift` | 处理 HTTP CONNECT 方法（HTTPS 隧道建立），决定是否进行 MITM 解密 |
| `MITMHandler.swift` | TLS 中间人处理，动态生成证书，执行 TLS 握手，根据 ALPN 切换到 H1/H2 |
| `HTTP2CaptureHandler.swift` | HTTP/2 多路复用流量捕获，每个 Stream 独立记录 |
| `WebSocketCaptureHandler.swift` | WebSocket 帧级捕获，记录 TEXT/BINARY/PING/PONG/CLOSE 帧 |
| `GRPCCaptureHandler.swift` | gRPC 调用捕获，解析 Length-Prefixed Message 帧格式 |
| `TunnelHandler.swift` | 非 MITM 模式的原始字节中继（加密连接透传） |
| `ResponseRelayHandler.swift` | 服务器响应中继回客户端，检测 WebSocket 升级 |
| `SOCKSProxyHandler.swift` | SOCKS4/5 代理协议支持 |
| `SessionRecorder.swift` | 会话记录桥接器，连接 NIO Handler 与新存储系统 |
| `SSLHandler.swift` | TLS/SSL 配置与上下文管理 |
| `BreakpointHandler.swift` | 请求/响应断点拦截，允许用户修改请求/响应 |
| `TrafficShapingHandler.swift` | 流量整形，模拟慢速网络 |
| `TimeoutHandler.swift` | 连接超时控制 |
| `IPFilterHandler.swift` | IP 地址过滤 |
| `RequestReplayer.swift` | 请求重放功能 |
| `OCSPChecker.swift` | OCSP 证书有效性检查 |

### 1.2 PacketCapture — IP 包捕获

负责 VPN 隧道层的 IP 包解析和 UDP 转发。

| 文件 | 职责 |
|------|------|
| `PacketCaptureEngine.swift` | 核心引擎（356 行），解析 IP 包，按协议分类处理，统计流量 |
| `IPPacketParser.swift` | IP 包二进制解析器（310 行），支持 IPv4/IPv6、TCP/UDP/ICMP 头部解析 |
| `UDPForwarder.swift` | UDP 包转发器，使用 Network.framework NWConnection，5秒超时 |
| `QUICMITMHandler.swift` | QUIC 协议 MITM 处理（使用 quiche 后端） |
| `LsquicMITMHandler.swift` | QUIC 协议 MITM 处理（使用 lsquic 后端） |

### 1.3 Codec — 协议编解码器

各种网络协议的解码器/格式化器。

| 文件 | 协议 | 解析内容 |
|------|------|---------|
| `DNSDecoder.swift` | DNS | RFC 1035 报文解析，支持 A/AAAA/CNAME/MX/NS/PTR/TXT/SOA/SRV/HTTPS 记录，域名压缩指针 |
| `QUICDecoder.swift` | QUIC | RFC 9000 包头解析，长头/短头区分，版本协商，连接 ID 提取 |
| `NTPDecoder.swift` | NTP | 时间同步协议解析 |
| `MQTTDecoder.swift` | MQTT | 消息队列协议解析（CONNECT/PUBLISH/SUBSCRIBE 等） |
| `RedisDecoder.swift` | Redis | RESP 协议解析 |
| `MemcacheDecoder.swift` | Memcache | 文本/二进制协议解析 |
| `SMTPDecoder.swift` | SMTP | 邮件传输协议解析 |
| `STOMPDecoder.swift` | STOMP | 简单文本面向消息协议解析 |
| `HAProxyDecoder.swift` | HAProxy | HAProxy Protocol V1/V2 解析 |
| `XMLFormatter.swift` | XML | XML 格式化美化输出 |

### 1.4 Storage — 存储层

新设计的多数据库存储架构（详见 [storage-design.md](storage-design.md)）。

#### 核心管理
| 文件 | 职责 |
|------|------|
| `DatabaseManager.swift` | 全局数据库连接管理器（单例），管理 catalog.db 和 per-task 数据库组 |
| `TaskDatabaseGroup.swift` | 每任务数据库组，包含 5 个数据库和 5 个串行写入队列 |
| `PathManager.swift` | 集中管理所有文件路径（数据库、Payload、日志） |
| `BatchWriter.swift` | 批量写入器，减少数据库事务开销 |
| `DecodeScheduler.swift` | 后台解码调度器 |
| `FlowIdGenerator.swift` | Flow ID 生成器 |
| `TaskStatsSync.swift` | 任务统计数据同步 |

#### Schema（数据库 DDL）
| 文件 | 数据库 | 包含表 |
|------|--------|--------|
| `CatalogSchema.swift` | catalog.db | capture_task, rule, breakpoint |
| `ProtocolSchema.swift` | proto.db | flow |
| `TransportSchema.swift` | transport.db | （传输层包记录） |
| `ConnectionSchema.swift` | connection.db | tcp_connection, quic_connection, quic_stream |
| `DecodedSchema.swift` | decoded.db | decoded_entry |
| `StateSchema.swift` | state.db | （流状态跟踪） |

#### DAO（数据访问对象）
| 文件 | 操作目标 | 主要方法 |
|------|---------|---------|
| `CatalogDAO.swift` | capture_task, rule, breakpoint | CRUD 操作 |
| `FlowDAO.swift` | flow | insert, update, find, query（分页+过滤） |
| `FlowDAO+Count.swift` | flow | 按协议统计计数 |
| `TcpConnectionDAO.swift` | tcp_connection | insertOrUpdate |
| `QuicConnectionDAO.swift` | quic_connection | QUIC 连接记录 |
| `QuicStreamDAO.swift` | quic_stream | QUIC 流记录 |
| `DecodedEntryDAO.swift` | decoded_entry | 解码内容存取 |
| `PacketDAO.swift` | packet | 原始包数据 |
| `TaskStatsDAO.swift` | capture_task | 统计数据更新 |
| `ModifyLogDAO.swift` | modify_log | 修改历史记录 |

#### Model（数据模型）
| 文件 | 说明 |
|------|------|
| `FlowRecord.swift` | 协议无关的流记录（flow_id, protocol, host, 时序, 搜索键, metadata JSON） |
| `ConnectionRecord.swift` | TCP 连接记录（源/目的 IP:Port, TLS SNI, 时序） |
| `QuicConnectionRecord.swift` | QUIC 连接记录 |
| `QuicStreamRecord.swift` | QUIC 流记录 |
| `DecodedEntry.swift` | 解码条目（解压后的消息体） |
| `ModifyLogEntry.swift` | 修改日志条目 |
| `PacketRow.swift` | 原始包行记录 |

#### Protocol（协议记录器）
| 文件 | 协议 | 职责 |
|------|------|------|
| `ProtocolRecorder.swift` | 通用 | 协议记录器基类/接口 |
| `HTTPRecorder.swift` | HTTP/HTTPS | 记录请求头/响应头/Body/时序，构建 FlowRecord |
| `DNSRecorder.swift` | DNS | 解析 DNS 报文并记录 |
| `GRPCRecorder.swift` | gRPC | 解析 gRPC 消息并记录 |
| `WebSocketRecorder.swift` | WebSocket | 记录帧序列 |

#### Payload（载荷存储）
| 文件 | 职责 |
|------|------|
| `PayloadWriter.swift` | 流式写入请求/响应 Body 到磁盘文件 |
| `PayloadReader.swift` | 从磁盘文件读取 Payload 数据 |
| `PayloadDecoder.swift` | Payload 解码（解压缩、编码转换） |
| `DecompressStream.swift` | 流式解压缩（gzip/deflate/brotli/zstd） |
| `TextAccumulator.swift` | 文本 Payload 累积器 |

### 1.5 Config — 配置

| 文件 | 职责 |
|------|------|
| `ProxyConfig.swift` | 集中配置：App Group ID、代理端口、VPN 地址、QUIC 后端、SSL 超时、数据库参数 |
| `CertStore.swift` | 证书存储管理，CA 证书/私钥加载 |
| `CertGenerator.swift` | 动态 X.509 证书生成器 |

### 1.6 其他

| 文件 | 职责 |
|------|------|
| `CaptureTask.swift` | 抓包任务核心模型，管理任务生命周期、证书加载、规则关联 |
| `MitmService.swift` | MITM 服务入口，协调 PacketCaptureEngine 和 ProxyServer |
| `AppNotification.swift` | 应用通知 |
| `NetworkInfo.swift` | 网络信息获取（Wi-Fi IP 等） |
| `SwiftyJSON.swift` | JSON 工具 |
| `Rule.swift` | 规则枚举定义（匹配策略、规则类型） |

---

## 2. KnotCore 模块

提供跨平台共享的核心协议和数据模型。

| 文件 | 职责 |
|------|------|
| `TunnelServiceProtocol.swift` | 隧道服务协议：startCapture/stopCapture/installExtension 等 |
| `CertificateServiceProtocol.swift` | 证书服务协议：安装/导出/信任状态 |
| `ExportService.swift` | 数据导出服务 |
| `ServiceContainer.swift` | 依赖注入容器（register/resolve 模式） |
| `TunnelStatus.swift` | 隧道状态枚举：disconnected/connecting/connected/disconnecting/error |
| `CertTrustStatus.swift` | 证书信任状态枚举：notInstalled/installed/untrusted/trusted |
| `Log.swift` | 日志工具 |

---

## 3. KnotUI 模块

SwiftUI 用户界面层（详见 [ui-guide.md](ui-guide.md)）。

### 3.1 App — 应用导航
| 文件 | 职责 |
|------|------|
| `RootView.swift` | 根视图，适配 iOS/macOS 不同布局 |
| `PrimaryPageView.swift` | 主页面切换器（仪表盘、流列表、规则等） |
| `DetailPageView.swift` | 详情页面路由 |
| `PageSwitcher.swift` | 页面切换逻辑 |
| `NavigationState.swift` | 导航状态管理（@Observable） |

### 3.2 Views — 页面视图
| 目录/文件 | 页面 |
|-----------|------|
| `Dashboard/DashboardView.swift` | 仪表盘主页（VPN 状态、代理配置、当前任务、历史） |
| `FlowList/FlowListView.swift` | 流列表（协议过滤、搜索、分页加载） |
| `FlowDetail/HTTPDetailView.swift` | HTTP 请求/响应详情（Overview/Request/Response 标签页） |
| `FlowDetail/DNSDetailView.swift` | DNS 查询详情 |
| `FlowDetail/WebSocketDetailView.swift` | WebSocket 帧时间线 |
| `FlowDetail/GRPCDetailView.swift` | gRPC 调用详情 |
| `FlowDetail/FlowDetailRouter.swift` | 根据协议类型路由到对应详情视图 |
| `Rule/RuleListView.swift` | 规则列表管理 |
| `Rule/RuleDetailView.swift` | 规则详情编辑 |
| `Certificate/CertificateView.swift` | CA 证书管理（安装/导出/信任状态） |
| `History/HistoryTaskView.swift` | 历史抓包任务列表 |
| `Settings/SettingsView.swift` | 设置页面 |

### 3.3 Components — 可复用组件
| 组件 | 用途 |
|------|------|
| `CurrentTaskView` | 当前运行任务卡片（流量统计、拦截数） |
| `HistoryTaskCell` | 历史任务列表单元格 |
| `FlowCell` | 流列表单元格（协议标签、主机名、状态码） |
| `ProtocolBadge` | 协议类型标签（HTTP/HTTPS/DNS/WS 等） |
| `ProtocolFilterBar` | 协议过滤栏 |
| `SearchBar` | 搜索栏 |
| `TimingWaterfallView` | 连接时序瀑布图 |
| `MessageBubble` | WebSocket 消息气泡 |
| `CertStatusCard` | 证书状态卡片 |
| `StateCardView` | 状态统计卡片 |
| `ProxyConfigView` | 代理配置视图 |
| `ExportMenu` | 导出菜单 |
| `RuleCell` | 规则列表单元格 |
| `RuleMatchRow` | 规则匹配条件行 |
| `FocusTagsView` | 焦点标签视图 |
| `EditToolbar` | 编辑工具栏 |
| `PlaceholderView` | 占位视图 |

### 3.4 ViewModels — 视图模型
| 文件 | 职责 |
|------|------|
| `AppState.swift` | 全局应用状态（@Observable）：VPN 状态、当前任务、证书状态 |
| `FlowListViewModel.swift` | 流列表数据管理：分页加载（每页 50 条）、协议过滤、搜索 |
| `RuleViewModel.swift` | 规则管理 |
| `CertificateViewModel.swift` | 证书操作 |
| `WebSocketDetailViewModel.swift` | WebSocket 详情数据 |

---

## 4. SwiftQuiche / SwiftLsquic 模块

QUIC 协议的 Swift 封装，提供两种可选后端：

### SwiftQuiche（Cloudflare quiche）
| 文件 | 职责 |
|------|------|
| `QuicheConnection.swift` | quiche 连接封装，管理 QUIC 握手、流读写、连接状态 |

### SwiftLsquic（LiteSpeed lsquic）
| 文件 | 职责 |
|------|------|
| `LsquicEngine.swift` | lsquic 引擎封装，管理引擎实例和事件循环 |

两个包均依赖预编译的 xcframework（仅支持 iOS ARM64），通过 `ProxyConfig.HTTP3.backend` 配置选择使用哪个后端。

---

## 5. 平台特定代码

### iOS
| 文件 | 职责 |
|------|------|
| `KnotApp-iOS/iOSApp.swift` | iOS 应用入口，初始化存储、注册服务 |
| `KnotApp-iOS/iOSTunnelService.swift` | 管理 NETunnelProviderManager，启动/停止 VPN |
| `KnotApp-iOS/iOSCertificateService.swift` | iOS 证书安装流程 |
| `PacketTunnel-iOS/PacketTunnelProvider.swift` | 网络扩展入口，启动 MitmService |

### macOS
| 文件 | 职责 |
|------|------|
| `KnotApp-macOS/macOSApp.swift` | macOS 应用入口 |
| `KnotApp-macOS/macOSTunnelService.swift` | macOS 隧道/代理服务 |
| `KnotApp-macOS/macOSCertificateService.swift` | macOS 证书安装流程 |
| `SystemExtension-macOS/MacPacketTunnelProvider.swift` | macOS 系统扩展入口 |
