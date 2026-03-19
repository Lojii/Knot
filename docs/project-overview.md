# Knot 项目总览

## 1. 项目简介

**Knot** 是一款 iOS/macOS 双平台网络抓包工具，采用 MITM（中间人攻击）技术实现 HTTP/HTTPS 流量的拦截与解析。项目使用 Swift 编写，基于 SwiftNIO 异步网络框架，支持多种网络协议的捕获与分析。

### 核心定位
- 纯粹的网络抓包工具（非科学上网/代理转发工具）
- 支持 HTTP/HTTPS、HTTP/2、WebSocket、gRPC、DNS、QUIC/HTTP3 等多协议
- 支持局域网内其他设备流量抓取
- 提供完整的流量解析、导出、规则过滤功能

### 技术栈
| 技术 | 用途 |
|------|------|
| Swift 5.9 | 主要开发语言 |
| SwiftNIO | 异步网络框架（代理服务器核心） |
| NIOHTTP1/NIOHTTP2 | HTTP/1.1 和 HTTP/2 协议处理 |
| NIOSSL | TLS/SSL 加密解密 |
| NIOWebSocket | WebSocket 协议处理 |
| swift-certificates | X.509 证书动态生成 |
| swift-crypto | 加密算法（RSA-2048） |
| SQLite.swift | 数据库存储 |
| SwiftUI | 用户界面（iOS 17+ / macOS 14+） |
| NetworkExtension | VPN 隧道（iOS 包捕获） |
| CocoaAsyncSocket | UDP 套接字 |
| quiche / lsquic | QUIC 协议支持 |

## 2. 平台支持

| 平台 | 最低版本 | 抓包方式 |
|------|---------|---------|
| iOS | 17.0+ | NetworkExtension (PacketTunnel VPN) |
| macOS | 14.0+ | System Extension / 本地代理 |

## 3. 项目目录结构

```
Knot-storage-redesign/
├── KnotApp-iOS/                    # iOS 应用入口
│   ├── iOSApp.swift                # @main 入口
│   ├── iOSTunnelService.swift      # iOS 隧道服务（NETunnelProviderManager）
│   ├── iOSCertificateService.swift # iOS 证书安装服务
│   └── Assets.xcassets/            # 应用资源
│
├── KnotApp-macOS/                  # macOS 应用入口
│   ├── macOSApp.swift              # @main 入口
│   ├── macOSTunnelService.swift    # macOS 隧道/代理服务
│   └── macOSCertificateService.swift
│
├── PacketTunnel-iOS/               # iOS 网络扩展（VPN 隧道）
│   ├── PacketTunnelProvider.swift  # NEPacketTunnelProvider 实现
│   └── Info.plist
│
├── SystemExtension-macOS/          # macOS 系统扩展
│   ├── MacPacketTunnelProvider.swift
│   └── main.swift
│
├── LocalPackages/                  # 本地 Swift Package 模块
│   ├── KnotUI/                     # UI 层（SwiftUI 视图与组件）
│   ├── KnotCore/                   # 核心层（服务协议与数据模型）
│   ├── TunnelServices/             # 服务层（网络、代理、存储、编解码）
│   ├── SwiftQuiche/                # QUIC 协议封装（Cloudflare quiche）
│   └── SwiftLsquic/                # QUIC 协议封装（LiteSpeed lsquic）
│
├── Frameworks/                     # 预编译 xcframework
│   ├── CQuiche.xcframework         # quiche C 库（仅 iOS）
│   └── CLsquic.xcframework         # lsquic C 库（仅 iOS）
│
├── Lib/                            # 日志库（AxLogger）
├── Scripts/                        # QUIC 框架构建脚本
├── CA/                             # CA 证书文件
├── Http/                           # HTTP 相关 UI 资源
├── screenshots/                    # 功能截图
│
├── docs/                           # 项目文档
│   ├── project-overview.md         # ← 本文件
│   ├── architecture.md             # 架构设计详解
│   ├── module-guide.md             # 模块详解
│   ├── packet-capture-flow.md      # 各协议抓包流程
│   ├── storage-design.md           # 存储层设计
│   ├── ui-guide.md                 # UI 层说明
│   ├── known-issues.md             # 已知问题
│   ├── proxy-architecture.md       # 代理架构（已有）
│   └── features/                   # 功能特性文档（已有）
│
├── Knot.xcodeproj/                 # Xcode 项目配置
├── README.md                       # 项目 README
└── LICENSE                         # 开源协议
```

## 4. 已实现功能

### 流量捕获
- HTTP/HTTPS 流量抓取与解密
- HTTP/2 多路复用流量捕获
- WebSocket 双向帧捕获
- gRPC 服务调用捕获
- DNS 查询与响应解析
- QUIC/HTTP3 流量捕获（实验性）
- TCP/UDP/ICMP 传输层数据包记录

### 流量分析
- 请求/响应头部完整解析
- Body 内容解码（gzip、deflate、brotli、zstd）
- Protobuf 消息解码
- XML 格式化
- 连接时序瀑布图（Timing Waterfall）

### 规则与过滤
- 自定义过滤规则配置
- IP 黑白名单
- 协议类型过滤
- 关键字搜索

### 流量修改
- 请求/响应断点注入（Breakpoint）
- 请求重放（Replay）
- 流量整形（Traffic Shaping）

### 数据管理
- 多格式导出（PCAP 等）
- 历史任务管理
- CA 证书安装与导出

### 其他
- 中英文国际化
- SOCKS 代理支持
- 局域网设备抓包
- SSL/OCSP 证书验证
- 超时控制

## 5. 当前分支状态

**分支**: `feature/storage-redesign`

项目正在进行重大的存储层重构：
1. 从 ActiveSQLite（已删除）迁移到 SQLite.swift
2. 从单一数据库迁移到多数据库架构（每个抓包任务独立数据库组）
3. 从旧 Session/Rule 模型迁移到新的 FlowRecord/RuleRecord 模型
4. UI 层从 UIKit 迁移到 SwiftUI
5. 整体架构从单体迁移到模块化 Swift Package 结构

## 6. 构建与运行

### 前置要求
- Xcode 15+（支持 Swift 5.9）
- Apple 开发者账号（需要 Network Extension 权限）
- 真机设备（iOS 模拟器不支持 VPN 隧道）

### 构建步骤
1. 打开 `Knot.xcodeproj`
2. 选择 `KnotApp-iOS` 或 `KnotApp-macOS` target
3. 配置开发团队和 Bundle Identifier
4. 确保 Network Extension、App Groups 等 entitlements 正确配置
5. 使用真机运行

### App Group 标识
```
group.Lojii.NIO1901
```

## 7. 依赖关系图

```
KnotApp-iOS / KnotApp-macOS
    │
    ├── KnotUI (SwiftUI 视图层)
    │     ├── KnotCore (核心服务协议)
    │     │     └── TunnelServices (网络/存储/编解码)
    │     └── TunnelServices
    │
    └── PacketTunnel-iOS / SystemExtension-macOS
          └── TunnelServices

TunnelServices 外部依赖:
    ├── SwiftNIO, NIOHTTP1, NIOHTTP2, NIOSSL, NIOWebSocket, NIOExtras
    ├── swift-crypto, swift-certificates, swift-asn1
    ├── SQLite.swift
    ├── CocoaAsyncSocket
    ├── SwiftQuiche (iOS only)
    └── SwiftLsquic (iOS only)
```
