# 各协议抓包流程详解

本文档详细描述 Knot 对各种网络协议的抓包过程，包括从数据包捕获到存储展示的完整链路。

---

## 1. 整体抓包流程概览

```
用户点击"开始抓包"
    ↓
TunnelService.startCapture()
    ↓
NETunnelProviderManager.startVPNTunnel()  (iOS)
    ↓
PacketTunnelProvider.startTunnel()
    ↓
MitmService.prepare()
├── 创建/复用 CaptureTask
├── 加载 CA 证书和私钥
├── 初始化 DatabaseManager
└── 打开 TaskDatabaseGroup
    ↓
MitmService.run()
├── 启动 PacketCaptureEngine（VPN 隧道）
└── 启动 ProxyServer（本地代理 + Wi-Fi 代理）
    ↓
设备所有网络流量被路由到 VPN 隧道
    ↓
PacketCaptureEngine 解析 IP 包 → 记录传输层
TCP 流量重定向到代理服务器 → 解析应用层
```

---

## 2. HTTP 明文抓包流程

### 数据流
```
客户端 App
    │
    │ HTTP GET /api/data HTTP/1.1
    │ Host: example.com
    ↓
PacketCaptureEngine
    │ 解析 IP/TCP 头部
    │ 记录: srcIP:srcPort → dstIP:80
    │ 重定向 TCP 到 127.0.0.1:8034
    ↓
ProxyServer (NIO Bootstrap)
    ↓
ProtocolRouter.channelRead()
    │ 读取前 4 字节: "GET "
    │ 识别为 HTTP 协议
    │ 构建 HTTP Pipeline:
    │   HTTPRequestDecoder
    │   HTTPResponseEncoder
    │   HTTPServerPipelineHandler
    │   HTTPCaptureHandler
    ↓
HTTPCaptureHandler.channelRead(.head)
    │ 提取: method=GET, uri=/api/data, host=example.com
    │ 创建 SessionRecorder
    │ → HTTPRecorder.recordRequestHead(method, uri, headers)
    │ → PayloadWriter 准备写入请求 Body
    │
    │ 建立到 example.com:80 的 TCP 连接
    │ (ClientBootstrap → workerGroup)
    ↓
HTTPCaptureHandler.channelRead(.body)
    │ → PayloadWriter.write(bodyData) → {flowId}_req.bin
    ↓
HTTPCaptureHandler.channelRead(.end)
    │ → HTTPRecorder.recordRequestEnd(timestamp)
    │ 转发完整请求到 example.com
    ↓
ResponseRelayHandler.channelRead(.head)
    │ 状态码: 200 OK
    │ → HTTPRecorder.recordResponseHead(status, headers)
    ↓
ResponseRelayHandler.channelRead(.body)
    │ → PayloadWriter.write(bodyData) → {flowId}_rsp.bin
    │ 同时中继给客户端
    ↓
ResponseRelayHandler.channelRead(.end)
    │ → HTTPRecorder.recordResponseEnd()
    │ → HTTPRecorder.buildFlowRecord() 构建 FlowRecord:
    │     flow_id: 唯一标识
    │     protocol: "HTTP"
    │     host: "example.com"
    │     search_key1: "GET" (method)
    │     search_key2: "/api/data" (uri)
    │     search_key3: "200" (status)
    │     search_key4: "application/json" (contentType)
    │     metadata: { headers, encoding, ... } (JSON)
    │     req_payload_ref: "payloads/raw/{flowId}_req.bin"
    │     rsp_payload_ref: "payloads/raw/{flowId}_rsp.bin"
    │     timing: connectAt, connectedAt, reqEndAt, rspStartAt, endedAt
    │
    │ → FlowDAO.insert(dbGroup.proto, flowRecord)
    │ → TcpConnectionDAO.insertOrUpdate(dbGroup.connection, ...)
    ↓
客户端收到 HTTP 响应
```

### 存储结果
```
proto.db:
  flow 表: { flow_id, protocol="HTTP", host="example.com",
             search_key1="GET", search_key2="/api/data",
             search_key3="200", upload_bytes=128, download_bytes=4096, ... }

connection.db:
  tcp_connection 表: { src_ip, src_port, dst_ip="93.184.216.34", dst_port=80, ... }

payloads/raw/:
  {flowId}_req.bin  → 请求 Body (如果有)
  {flowId}_rsp.bin  → 响应 Body (JSON 数据)
```

---

## 3. HTTPS 抓包流程（MITM 解密）

### 数据流
```
客户端 App
    │
    │ 目标: https://api.example.com/v1/users
    │
    ↓ TCP 连接到 api.example.com:443
PacketCaptureEngine
    │ 重定向到 127.0.0.1:8034
    ↓
ProtocolRouter.channelRead()
    │ 读取前 4 字节: "CONN" (CONNECT 方法)
    │ 构建 HTTP Pipeline → ConnectHandler
    ↓
ConnectHandler.channelRead(.head)
    │ 请求: CONNECT api.example.com:443 HTTP/1.1
    │ 发送: HTTP/1.1 200 Connection Established
    │ 移除 HTTP 编解码器
    │
    │ 判断: sslEnable=1 → MITM 模式
    │ 添加 MITMHandler 到 Pipeline
    ↓
MITMHandler.channelRead()
    │ 收到 TLS ClientHello
    │ 验证: 首字节=0x16(Handshake), 版本≤0x03
    │
    │ ① 从 ClientHello 提取 SNI: api.example.com
    │
    │ ② 查找/生成证书:
    │    CertGenerator.generateCert(
    │      host: "api.example.com",
    │      caKey: rsaSigningKey,    // CA 私钥
    │      caCert: x509CACert      // CA 证书
    │    )
    │    → X.509 v3 证书:
    │      Subject: api.example.com
    │      SAN: api.example.com
    │      Issuer: Knot CA
    │      Validity: 1 年
    │      Signature: SHA256withRSA
    │    → 缓存到 ThreadSafeCertPool
    │
    │ ③ 创建 NIOSSLServerHandler:
    │    - 证书: 动态生成的 api.example.com 证书
    │    - 私钥: rsaKey
    │    - ALPN: ["h2", "http/1.1"]
    │
    │ ④ 与客户端完成 TLS 握手
    ↓
ApplicationProtocolNegotiationHandler
    │ ALPN 结果: "http/1.1" (或 "h2")
    │
    ├── "http/1.1" → 添加 HTTPCaptureHandler
    │   （后续流程同 HTTP 明文，但额外记录 TLS 信息）
    │   protocol = "HTTPS"
    │   tls_done_at = TLS 握手完成时间
    │
    └── "h2" → 添加 HTTP2CaptureBuilder
        （见下文 HTTP/2 流程）
    ↓
HTTPCaptureHandler（HTTPS 模式）
    │ 此时数据已解密为明文 HTTP
    │
    │ 同时建立到 api.example.com:443 的真正 TLS 连接
    │ (使用真实服务器证书验证)
    │
    │ 记录解密后的请求/响应内容（同 HTTP 流程）
    │ FlowRecord.protocol = "HTTPS"
    │ 额外记录: tls_done_at, sni
    ↓
客户端收到解密→重加密的响应
```

### MITM 不生效的情况
```
ConnectHandler 判断:
├── sslEnable=0 → TunnelHandler（原始字节中继，不解密）
├── 规则匹配到白名单 → TunnelHandler
└── 证书固定（Certificate Pinning）→ 客户端拒绝 Knot 的假证书
    → 连接失败，记录错误到 FlowRecord.error_message
```

---

## 4. HTTP/2 抓包流程

### 数据流
```
TLS 握手完成，ALPN 协商结果 = "h2"
    ↓
HTTP2CaptureBuilder
    │ 构建 HTTP/2 Pipeline:
    │   NIOHTTP2Handler (解析 HTTP/2 帧)
    │   HTTP2StreamMultiplexer (多路复用)
    ↓
每个 HTTP/2 Stream（并行）:
    ↓
HTTP2FramePayloadToHTTP1ServerCodec
    │ 将 HTTP/2 帧转换为 HTTP/1.1 格式
    │ (HEADERS 帧 → HTTPRequestHead)
    │ (DATA 帧 → HTTPRequestBody)
    ↓
H2StreamCaptureHandler
    │ 为每个 Stream 创建独立的 HTTPRecorder
    │ 记录: :method, :path, :authority, :scheme
    │
    │ 检测 gRPC:
    │   if content-type starts with "application/grpc"
    │   → 标记 protocol = "gRPC"
    │   → GRPCCaptureHandler 接管
    │
    │ → FlowRecord:
    │     protocol: "HTTPS" (或 "gRPC")
    │     metadata: { "h2_stream_id": streamId, ... }
    ↓
每个 Stream 独立写入 FlowDAO
```

### HTTP/2 特殊处理
- 多个 Stream 共享同一个 TCP 连接，但每个 Stream 有独立的 FlowRecord
- 服务器推送（Server Push）作为独立 Stream 捕获
- HEADERS 帧包含 :method, :path, :authority 伪头部
- DATA 帧累积为请求/响应 Body

---

## 5. WebSocket 抓包流程

### 数据流
```
HTTP/1.1 请求阶段（在 HTTPCaptureHandler 中）:
    │
    │ 客户端发送:
    │   GET /ws/chat HTTP/1.1
    │   Connection: upgrade
    │   Upgrade: websocket
    │   Sec-WebSocket-Key: xxx
    │
    │ HTTPCaptureHandler 检测到 WebSocket Upgrade
    │ 设置 WebSocketUpgradeInterceptor
    │
    │ 转发请求到服务器
    ↓
服务器响应:
    │ HTTP/1.1 101 Switching Protocols
    │ Upgrade: websocket
    │ Connection: Upgrade
    │ Sec-WebSocket-Accept: yyy
    ↓
WebSocketUpgradeInterceptor.onUpgrade()
    │ 101 确认 → 协议切换
    │
    │ 移除 HTTP 编解码器
    │ 添加 WebSocket Pipeline:
    │   WebSocketFrameDecoder (客户端方向)
    │   WebSocketFrameEncoder (服务器方向)
    │   WebSocketCaptureHandler
    ↓
WebSocketCaptureHandler
    │
    │ ┌─── 客户端 → 服务器 ───┐
    │ │ WebSocketFrameLogger  │  → 记录帧
    │ │ WebSocketForwarder    │  → 解除掩码并转发
    │ └───────────────────────┘
    │
    │ ┌─── 服务器 → 客户端 ───┐
    │ │ WebSocketFrameLogger  │  → 记录帧
    │ │ WebSocketForwarder    │  → 转发
    │ └───────────────────────┘
    ↓
每个帧记录:
    │ [2026-03-19T10:30:45Z] [FIN] [TEXT] [128B] [→] {"type":"message","data":"hello"}
    │ [2026-03-19T10:30:45Z] [FIN] [TEXT] [64B]  [←] {"type":"ack","id":42}
    │ [2026-03-19T10:30:50Z] [FIN] [PING] [0B]   [→]
    │ [2026-03-19T10:30:50Z] [FIN] [PONG] [0B]   [←]
    │
    │ → WebSocketRecorder 累积所有帧
    │ → FlowRecord:
    │     protocol: "WebSocket"
    │     host: "example.com"
    │     search_key2: "/ws/chat" (uri)
    │     metadata: { frames: [...], total_messages: N }
    ↓
连接关闭时写入数据库
```

### WebSocket 帧类型
| 操作码 | 类型 | 说明 |
|--------|------|------|
| 0x1 | TEXT | 文本数据（UTF-8） |
| 0x2 | BINARY | 二进制数据 |
| 0x8 | CLOSE | 关闭连接 |
| 0x9 | PING | 心跳请求 |
| 0xA | PONG | 心跳响应 |
| 0x0 | CONTINUATION | 分片续传 |

---

## 6. gRPC 抓包流程

### 数据流
```
HTTP/2 Stream 中检测到 gRPC:
    │ content-type: application/grpc
    │ :path: /myservice.MyService/MyMethod
    ↓
GRPCCaptureHandler
    │
    │ gRPC 消息采用 Length-Prefixed Message 帧格式:
    │ ┌───────────────────────────────────────────┐
    │ │ Compressed (1 byte) │ Length (4 bytes, BE) │
    │ ├────────────────────────────────────────────┤
    │ │        Protobuf Message (N bytes)          │
    │ └────────────────────────────────────────────┘
    │
    │ 解析步骤:
    │ ① 读取 1 字节压缩标志 (0=未压缩, 1=gzip)
    │ ② 读取 4 字节消息长度 (大端序)
    │ ③ 读取 N 字节 Protobuf 消息体
    │ ④ 如果压缩: gzip 解压
    │ ⑤ 尝试 Protobuf 基础解码 (field/wire type)
    │ ⑥ 解码失败则回退到 hex dump
    ↓
GRPCRecorder
    │ → FlowRecord:
    │     protocol: "gRPC"
    │     host: "api.example.com"
    │     search_key1: "POST" (gRPC always POST)
    │     search_key2: "/myservice.MyService/MyMethod"
    │     metadata: {
    │       "grpc_service": "myservice.MyService",
    │       "grpc_method": "MyMethod",
    │       "grpc_status": "0",
    │       "messages": [...]
    │     }
    ↓
FlowDAO.insert(dbGroup.proto, flowRecord)
```

### gRPC 特殊处理
- gRPC 运行在 HTTP/2 之上，必须先完成 MITM TLS 解密
- Unary 调用：1 个请求消息 + 1 个响应消息
- Server Streaming：1 个请求 + N 个响应消息
- Client Streaming：N 个请求 + 1 个响应消息
- Bidirectional Streaming：N 个请求 + M 个响应消息
- Trailers 帧包含 grpc-status 和 grpc-message

---

## 7. DNS 抓包流程

### 数据流
```
设备发起 DNS 查询
    ↓
PacketCaptureEngine
    │ 解析 IP/UDP 头部
    │ 检测: dst_port = 53 → DNS 协议
    ↓
UDPForwarder
    │ 创建 NWConnection 到 DNS 服务器 (8.8.8.8:53)
    │ 发送原始 DNS 查询数据
    │ 等待响应 (5 秒超时)
    ↓
DNSDecoder.decode(queryData)
    │
    │ DNS 报文结构 (RFC 1035):
    │ ┌──────────────────────────────┐
    │ │ Header (12 bytes)            │
    │ │  ID (2B), Flags (2B),        │
    │ │  QDCount, ANCount,           │
    │ │  NSCount, ARCount (各2B)     │
    │ ├──────────────────────────────┤
    │ │ Questions Section            │
    │ │  QNAME (域名, 变长)           │
    │ │  QTYPE (2B), QCLASS (2B)    │
    │ ├──────────────────────────────┤
    │ │ Answer Section               │
    │ │  NAME, TYPE, CLASS, TTL,     │
    │ │  RDLENGTH, RDATA             │
    │ ├──────────────────────────────┤
    │ │ Authority Section            │
    │ │ Additional Section           │
    │ └──────────────────────────────┘
    │
    │ 域名解析（支持压缩指针）:
    │   03 77 77 77 07 65 78 61 6D 70 6C 65 03 63 6F 6D 00
    │   →  w  w  w     e  x  a  m  p  l  e     c  o  m
    │   → "www.example.com"
    │
    │ 记录类型解析:
    │   A (1)     → IPv4 地址 (4B)
    │   AAAA (28) → IPv6 地址 (16B)
    │   CNAME (5) → 别名域名
    │   MX (15)   → 邮件服务器 (优先级 + 域名)
    │   TXT (16)  → 文本记录
    │   NS (2)    → 名称服务器
    │   SOA (6)   → 权威记录
    │   SRV (33)  → 服务记录 (优先级, 权重, 端口, 目标)
    │   PTR (12)  → 反向解析
    │   HTTPS (65)→ HTTPS 服务绑定
    ↓
DNSRecorder
    │ → FlowRecord:
    │     protocol: "DNS"
    │     host: "www.example.com" (查询域名)
    │     search_key1: "A" (查询类型)
    │     search_key2: "www.example.com" (查询名)
    │     search_key3: "NOERROR" (响应码)
    │     metadata: {
    │       "query_id": 12345,
    │       "questions": [{ "name": "www.example.com", "type": "A" }],
    │       "answers": [
    │         { "name": "www.example.com", "type": "A",
    │           "ttl": 300, "data": "93.184.216.34" }
    │       ],
    │       "response_code": "NOERROR"
    │     }
    ↓
FlowDAO.insert(dbGroup.proto, flowRecord)
```

### DNS-over-HTTPS (DoH) 处理
```
DoH 请求通过 HTTPS 抓包流程捕获:
    │ POST https://dns.google/dns-query
    │ Content-Type: application/dns-message
    │
    │ HTTPRecorder 检测到 content-type = "application/dns-message"
    │ → 调用 DNSDecoder 解析 Body
    │ → 额外生成 DNS FlowRecord
```

### DNS 响应码
| 码值 | 名称 | 含义 |
|------|------|------|
| 0 | NOERROR | 查询成功 |
| 1 | FORMERR | 格式错误 |
| 2 | SERVFAIL | 服务器失败 |
| 3 | NXDOMAIN | 域名不存在 |
| 4 | NOTIMP | 未实现 |
| 5 | REFUSED | 拒绝 |

---

## 8. QUIC/HTTP3 抓包流程（实验性）

### 数据流
```
设备发起 QUIC 连接 (UDP 端口 443)
    ↓
PacketCaptureEngine
    │ 解析 IP/UDP 头部
    │ 检测: dst_port = 443 + UDP → 可能是 QUIC
    ↓
QUICDecoder.decode()
    │
    │ QUIC 包头解析 (RFC 9000):
    │
    │ 首字节判断:
    │ ├── bit 7 = 1 → 长头部 (Long Header)
    │ │   ┌──────────────────────────────────┐
    │ │   │ Header Form (1) │ Fixed (1)      │
    │ │   │ Long Packet Type (2) │ ...        │
    │ │   ├──────────────────────────────────┤
    │ │   │ Version (4B)                      │
    │ │   │ DCID Length (1B) │ DCID (N bytes) │
    │ │   │ SCID Length (1B) │ SCID (N bytes) │
    │ │   │ Type-specific payload...          │
    │ │   └──────────────────────────────────┘
    │ │   类型:
    │ │   ├── 0x00: Initial (握手开始)
    │ │   ├── 0x01: 0-RTT (早期数据)
    │ │   ├── 0x02: Handshake (握手)
    │ │   └── 0x03: Retry (重试)
    │ │
    │ └── bit 7 = 0 → 短头部 (Short Header)
    │     ┌──────────────────────────────────┐
    │     │ Header Form (0) │ ...            │
    │     ├──────────────────────────────────┤
    │     │ DCID (N bytes, 长度已知)          │
    │     │ Encrypted payload...             │
    │     └──────────────────────────────────┘
    ↓
QUICMITMHandler (如果启用 HTTP/3 MITM)
    │
    │ 双 quiche 连接架构:
    │ ┌─────────┐     ┌──────────────┐     ┌─────────┐
    │ │ Client  │ ←→ │ Knot Proxy   │ ←→ │ Server  │
    │ │ (App)   │     │ quiche conn1 │     │ (Real)  │
    │ │         │     │ quiche conn2 │     │         │
    │ └─────────┘     └──────────────┘     └─────────┘
    │
    │ conn1: 与客户端的 QUIC 连接 (使用动态证书)
    │ conn2: 与服务器的 QUIC 连接 (使用真实证书)
    │
    │ 解密后按 HTTP/3 Stream 记录:
    │ → HTTPRecorder (h3 variant)
    │ → FlowRecord:
    │     protocol: "HTTP3"
    │     metadata: { "quic_version": "1", "connection_id": "..." }
    ↓
FlowDAO.insert() + QuicConnectionDAO + QuicStreamDAO
```

### QUIC 限制
- HTTP/3 MITM 默认关闭（`ProxyConfig.HTTP3.enabled = false`）
- 最大 20 个并发 QUIC 会话
- xcframework 仅支持 iOS ARM64
- quiche 和 lsquic 两个后端可选，通过配置切换

---

## 9. TCP 传输层记录

### 数据流
```
所有 TCP 数据包通过 VPN 隧道:
    ↓
PacketCaptureEngine.processPacket()
    │
    │ IPv4/IPv6 头部解析:
    │ ├── 版本 (4/6)
    │ ├── 源 IP / 目的 IP
    │ ├── 协议号 (6=TCP, 17=UDP, 1=ICMP)
    │ └── 总长度
    │
    │ TCP 头部解析 (IPPacketParser):
    │ ┌──────────────────────────────────────┐
    │ │ Source Port (2B) │ Dest Port (2B)     │
    │ │ Sequence Number (4B)                  │
    │ │ Acknowledgment Number (4B)            │
    │ │ Data Offset (4b) │ Flags (6b)         │
    │ │ Window Size (2B) │ Checksum (2B)      │
    │ └──────────────────────────────────────┘
    │
    │ TCP 标志位:
    │ ├── SYN  → 连接建立（三次握手）
    │ ├── ACK  → 确认
    │ ├── FIN  → 连接关闭
    │ ├── RST  → 连接重置
    │ ├── PSH  → 数据推送
    │ └── URG  → 紧急数据
    │
    │ 端口识别应用层协议:
    │ ├── 80    → HTTP
    │ ├── 443   → HTTPS / QUIC
    │ ├── 53    → DNS (TCP)
    │ ├── 6379  → Redis
    │ ├── 3306  → MySQL
    │ ├── 27017 → MongoDB
    │ ├── 1883  → MQTT
    │ └── 其他  → 通用 TCP
    ↓
transport.db 记录:
    │ src_ip, src_port, dst_ip, dst_port
    │ packet_size, direction, timestamp
    │ tcp_flags, seq_num, ack_num
```

---

## 10. UDP 传输层记录

### 数据流
```
UDP 数据包通过 VPN 隧道:
    ↓
PacketCaptureEngine.processPacket()
    │
    │ UDP 头部解析:
    │ ┌──────────────────────────────────┐
    │ │ Source Port (2B) │ Dest Port (2B) │
    │ │ Length (2B) │ Checksum (2B)       │
    │ └──────────────────────────────────┘
    │
    │ 端口识别:
    │ ├── 53    → DNS → DNSDecoder + UDPForwarder
    │ ├── 123   → NTP → NTPDecoder
    │ ├── 443   → QUIC → QUICDecoder
    │ ├── 5353  → mDNS (Bonjour)
    │ ├── 67/68 → DHCP
    │ └── 5060  → SIP
    ↓
UDPForwarder.forward()
    │ 创建 NWConnection → 目标地址:端口
    │ 发送数据
    │ 接收响应 (5秒超时)
    │ IPPacketBuilder 构建响应包
    │ → 写回 VPN 隧道
```

---

## 11. MQTT 协议抓包

### 数据流
```
MQTT 连接 (TCP 端口 1883/8883):
    ↓
HTTPCaptureHandler 或 TunnelHandler
    ↓
MQTTDecoder.decode()
    │
    │ MQTT 固定头部:
    │ ┌─────────────────────────┐
    │ │ Packet Type (4b)        │
    │ │ Flags (4b)              │
    │ │ Remaining Length (1-4B) │ (变长编码)
    │ └─────────────────────────┘
    │
    │ 消息类型:
    │ ├── CONNECT (1)    → 连接请求
    │ ├── CONNACK (2)    → 连接确认
    │ ├── PUBLISH (3)    → 发布消息 (Topic + Payload)
    │ ├── PUBACK (4)     → 发布确认
    │ ├── SUBSCRIBE (8)  → 订阅主题
    │ ├── SUBACK (9)     → 订阅确认
    │ ├── UNSUBSCRIBE (10) → 取消订阅
    │ ├── PINGREQ (12)   → 心跳请求
    │ ├── PINGRESP (13)  → 心跳响应
    │ └── DISCONNECT (14) → 断开连接
    ↓
FlowRecord:
    protocol: "MQTT"
    metadata: { "client_id": "...", "topic": "...", "qos": 1, ... }
```

---

## 12. Redis 协议抓包

### 数据流
```
Redis 连接 (TCP 端口 6379):
    ↓
RedisDecoder.decode()
    │
    │ RESP (Redis Serialization Protocol):
    │ ├── "+" → Simple String    (+OK\r\n)
    │ ├── "-" → Error            (-ERR unknown command\r\n)
    │ ├── ":" → Integer          (:1000\r\n)
    │ ├── "$" → Bulk String      ($6\r\nfoobar\r\n)
    │ ├── "*" → Array            (*2\r\n$3\r\nGET\r\n$5\r\nmykey\r\n)
    │ └── 二进制安全，\r\n 分隔
    │
    │ 示例解析:
    │ 客户端: *3\r\n$3\r\nSET\r\n$5\r\nmykey\r\n$7\r\nmyvalue\r\n
    │ → SET mykey myvalue
    │
    │ 服务器: +OK\r\n
    │ → OK
    ↓
FlowRecord:
    protocol: "Redis"
    metadata: { "command": "SET", "key": "mykey", ... }
```

---

## 13. NTP 协议抓包

### 数据流
```
NTP 查询 (UDP 端口 123):
    ↓
NTPDecoder.decode()
    │
    │ NTP 报文 (48 字节固定):
    │ ┌────────────────────────────────────┐
    │ │ LI (2b) │ VN (3b) │ Mode (3b)     │
    │ │ Stratum (1B) │ Poll (1B)           │
    │ │ Precision (1B)                     │
    │ │ Root Delay (4B)                    │
    │ │ Root Dispersion (4B)               │
    │ │ Reference ID (4B)                  │
    │ │ Reference Timestamp (8B)           │
    │ │ Originate Timestamp (8B)           │
    │ │ Receive Timestamp (8B)             │
    │ │ Transmit Timestamp (8B)            │
    │ └────────────────────────────────────┘
    │
    │ Mode: 3=Client, 4=Server, 5=Broadcast
    ↓
FlowRecord:
    protocol: "NTP"
    metadata: { "stratum": 2, "mode": "server", "offset_ms": 12.5, ... }
```

---

## 14. 数据存储总结

所有协议的抓包数据最终存储在统一的 FlowRecord 结构中：

```
FlowRecord (统一数据模型)
├── flow_id           → 唯一标识（所有协议通用）
├── protocol          → "HTTP"/"HTTPS"/"DNS"/"WebSocket"/"gRPC"/"MQTT"/"Redis"/...
├── host              → 目标主机
├── port              → 目标端口
├── started_at        → 开始时间
├── ended_at          → 结束时间
├── duration_ms       → 持续时间
├── upload_bytes      → 上传字节数
├── download_bytes    → 下载字节数
├── status            → 状态（success/error/...）
├── search_key1~4     → 协议语义搜索键（每个协议定义不同）
│   HTTP:  method / uri / statusCode / contentType
│   DNS:   queryType / queryName / responseCode / -
│   gRPC:  "POST" / servicePath / grpcStatus / -
│   WS:    "WS" / path / - / -
├── metadata (JSON)   → 协议特定扩展数据
├── req_payload_ref   → 请求体文件引用
├── rsp_payload_ref   → 响应体文件引用
└── timing 字段       → 连接各阶段时间戳
```
