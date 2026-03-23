# Knot 产品需求文档 & 开发计划

> 参考 Proxyman 功能体系，结合 Knot 自身架构（Swift/NIO 抓包核心 + Flutter UI + KnotWebService API），规划完整的产品功能路线图。

---

## 一、功能清单总览

### 1. 基础抓包功能

| 编号 | 功能 | 描述 | Proxyman 参考 | Knot 现状 |
|------|------|------|--------------|-----------|
| B-01 | HTTP/HTTPS 抓包 | 拦截并解密 HTTP/HTTPS 请求，显示明文内容 | 核心功能 | ✅ 已实现 |
| B-02 | WebSocket 抓包 | 捕获 WebSocket 帧（文本/二进制），双向展示 | 核心功能 | ✅ 已实现 |
| B-03 | HTTP/2 抓包 | 捕获 H2 多路复用流，显示帧级别数据 | 核心功能 | ✅ 已实现 |
| B-04 | SSL 证书管理 | 生成/安装/信任 CA 证书，支持自定义证书 | SSL Proxying 页 | ⚠️ 部分（生成+MITM有，UI管理无） |
| B-05 | SSL 代理列表 | Include/Exclude 域名列表，控制哪些域名解密 | SSL Proxying List | ❌ 未实现 |
| B-06 | 请求详情查看 | Headers、Body、Query、Cookies、Timing、Connection、Certificate | 基础功能 | ⚠️ 部分（有Headers/Body/Timing/Connection，缺Query/Cookies/Certificate） |
| B-07 | 请求搜索与过滤 | 按URL/Header/Body/Status/Method/协议 组合过滤（AND/OR） | Multiple Filters | ⚠️ 部分（有协议和状态码过滤，缺高级组合过滤） |
| B-08 | 域名/App 分组树 | 左侧按域名或应用分组展示请求 | 左侧边栏 | ✅ 已实现（域名分组） |
| B-09 | 请求列表表格 | Method、Host、Path、Status、Size、Time 等列，可排序 | 主内容区 | ⚠️ 部分（有表格，缺排序） |
| B-10 | 颜色标记与备注 | 给请求添加颜色标签和文字备注 | Color Tag & Comment | ❌ 未实现 |
| B-11 | 收藏/置顶 | 置顶重要的域名或请求 | Pin & Favorite | ❌ 未实现 |

### 2. 高级调试工具

| 编号 | 功能 | 描述 | Proxyman 参考 | Knot 现状 |
|------|------|------|--------------|-----------|
| A-01 | Compose（构造请求） | 手动构造 HTTP 请求并发送，支持所有方法和自定义 Header/Body | Compose | ❌ 未实现 |
| A-02 | Repeat（重放请求） | 重新发送已捕获的请求，支持修改后重发 | Repeat | ❌ 未实现 |
| A-03 | Map Local（本地映射） | 将请求的响应映射到本地文件（JSON/HTML/图片等） | Map Local | ❌ 未实现 |
| A-04 | Map Remote（远程映射） | 将请求重定向到另一个服务器（修改协议/Host/Port/Path） | Map Remote | ❌ 未实现 |
| A-05 | Breakpoint（断点） | 拦截请求/响应，暂停并允许实时编辑后放行或中止 | Breakpoint | ❌ 未实现 |
| A-06 | Allow/Block List | 白名单/黑名单控制，只显示或屏蔽特定域名的流量 | Allow/Block List | ❌ 未实现 |
| A-07 | Scripting（脚本） | 用 JavaScript 编写脚本修改请求/响应（类似 mitmproxy 的 addon） | Scripting | ❌ 未实现 |
| A-08 | No Caching（禁用缓存） | 移除请求/响应中的缓存头，强制获取最新内容 | No Caching | ❌ 未实现 |
| A-09 | Diff（对比） | 并排对比两个请求/响应的差异（URL、Headers、Body） | Diff Tool | ❌ 未实现 |
| A-10 | Protobuf 解码 | 导入 .desc 文件解码 Protobuf 二进制为 JSON | Protobuf | ❌ 未实现 |
| A-11 | GraphQL 支持 | 按 Query Name 过滤/匹配，美化 Query，列表显示 Query Name | GraphQL | ❌ 未实现 |
| A-12 | Network Conditions（网络模拟） | 模拟慢速网络（3G/4G/丢包/延迟），测试弱网表现 | Network Conditions | ❌ 未实现 |
| A-13 | Reverse Proxy（反向代理） | 建立本地 Web 服务器透明转发到远端，用于不支持代理配置的客户端 | Reverse Proxy | ❌ 未实现 |
| A-14 | External Proxy（外部代理） | 链式代理，将流量转发到上游 HTTP/HTTPS/SOCKS 代理 | External Proxy | ❌ 未实现 |

### 3. 数据管理

| 编号 | 功能 | 描述 | Proxyman 参考 | Knot 现状 |
|------|------|------|--------------|-----------|
| D-01 | 历史任务管理 | 查看/切换/搜索/删除历史抓包任务 | Session 管理 | ✅ 已实现 |
| D-02 | 导出请求 | 导出为 cURL/HAR/Proxyman 格式 | Export | ❌ 未实现 |
| D-03 | 导入数据 | 导入 HAR/Charles/Proxyman 格式的抓包文件 | Import | ❌ 未实现 |
| D-04 | 批量清理 | 按条件批量删除请求记录 | Clear 功能 | ⚠️ 部分（有清空，缺按条件清理） |

### 4. 网络层功能

| 编号 | 功能 | 描述 | Proxyman 参考 | Knot 现状 |
|------|------|------|--------------|-----------|
| N-01 | TCP 连接视图 | 查看 TCP 连接详情（IP、端口、状态、TLS 信息、字节数） | Connection 信息 | ⚠️ 部分（数据有，UI 占位） |
| N-02 | UDP/QUIC 视图 | 查看 QUIC 连接和 UDP 数据包 | 无（Knot 特有） | ⚠️ 部分（引擎有，UI 占位） |
| N-03 | DNS 解析展示 | 显示 DNS 查询和解析结果 | 无 | ❌ 未实现 |

### 5. 平台与设备

| 编号 | 功能 | 描述 | Proxyman 参考 | Knot 现状 |
|------|------|------|--------------|-----------|
| P-01 | macOS 桌面 App | 原生 macOS 应用（Flutter） | macOS 原生 | ✅ 已实现 |
| P-02 | Web 版 | Flutter Web 编译嵌入 KnotWebService | 无 | ❌ 待实现（P3） |
| P-03 | iOS App | Flutter iOS 应用 + Network Extension | iOS 原生 | ❌ 待实现（P3） |
| P-04 | Windows/Linux | Flutter 桌面跨平台 | Electron 版 | ❌ 未来规划 |
| P-05 | Remote Device 支持 | iPhone/Android 设备通过代理连接抓包 | iOS/Android 设备支持 | ⚠️ 部分（代理可用，缺引导 UI） |
| P-06 | Access Control | 控制哪些远程设备可以连接代理 | Access Control | ❌ 未实现 |

### 6. UI/UX

| 编号 | 功能 | 描述 | Proxyman 参考 | Knot 现状 |
|------|------|------|--------------|-----------|
| U-01 | 深色/浅色主题 | 跟随系统或手动切换 | 主题支持 | ✅ 已实现 |
| U-02 | 状态看板 | CPU/内存/连接池/协议分布/流量统计 | 无（Knot 特有） | ✅ 已实现 |
| U-03 | 时序图（Waterfall） | Chrome DevTools 风格的请求时序图 | 无 | ✅ 已实现 |
| U-04 | 实时推送 | WebSocket 实时推送新请求到 UI | 无 | ✅ 已实现 |
| U-05 | 键盘快捷键 | 常用操作的快捷键绑定 | 丰富的快捷键 | ❌ 未实现 |
| U-06 | Body 高级查看器 | JSON 语法高亮、图片预览、Hex 视图、XML/HTML 格式化 | 多格式预览 | ⚠️ 部分（JSON 高亮有，缺 Hex/XML/图片） |
| U-07 | 请求编辑器 | Raw 格式编辑请求/响应（用于 Breakpoint/Compose） | Raw Editor | ❌ 未实现 |

---

## 二、开发阶段规划

### Phase 3：基础功能完善（当前优先）

> 完善抓包工具的基本体验，让日常使用流畅。

| 优先级 | 功能 | 编号 | 工作量 |
|--------|------|------|--------|
| P0 | 请求详情完善（Query/Cookies/Certificate Tab） | B-06 | 小 |
| P0 | 列排序（点击列头排序） | B-09 | 小 |
| P0 | SSL 代理列表（Include/Exclude 域名） | B-05 | 中 |
| P0 | 导出为 cURL | D-02 | 小 |
| P1 | 高级过滤器（多条件 AND/OR 组合） | B-07 | 中 |
| P1 | Body 高级查看器（Hex/XML/图片预览） | U-06 | 中 |
| P1 | 颜色标记与备注 | B-10 | 小 |
| P1 | 收藏/置顶域名 | B-11 | 小 |
| P1 | 键盘快捷键 | U-05 | 小 |
| P2 | TCP/UDP 连接视图完整 UI | N-01, N-02 | 中 |
| P2 | 证书管理 UI | B-04 | 中 |

### Phase 4：高级调试工具

> 对标 Proxyman 的核心调试能力。

| 优先级 | 功能 | 编号 | 工作量 |
|--------|------|------|--------|
| P0 | Compose（构造请求） | A-01 | 中 |
| P0 | Repeat（重放请求） | A-02 | 小 |
| P0 | Map Local（本地映射） | A-03 | 大 |
| P0 | Breakpoint（断点调试） | A-05 | 大 |
| P1 | Map Remote（远程映射） | A-04 | 中 |
| P1 | Allow/Block List | A-06 | 中 |
| P1 | No Caching | A-08 | 小 |
| P2 | Diff 对比 | A-09 | 中 |
| P2 | Scripting（JS 脚本引擎） | A-07 | 大 |
| P2 | Network Conditions（弱网模拟） | A-12 | 中 |

### Phase 5：协议扩展 & 数据互通

> 支持更多协议和数据格式。

| 优先级 | 功能 | 编号 | 工作量 |
|--------|------|------|--------|
| P0 | 导出 HAR 格式 | D-02 | 中 |
| P0 | 导入 HAR 格式 | D-03 | 中 |
| P1 | Protobuf 解码 | A-10 | 大 |
| P1 | GraphQL 支持 | A-11 | 中 |
| P2 | gRPC 增强展示 | - | 中 |
| P2 | DNS 解析展示 | N-03 | 中 |
| P2 | Reverse Proxy | A-13 | 大 |
| P2 | External Proxy（链式代理） | A-14 | 中 |

### Phase 6：跨平台 & 设备管理

> 扩展到更多平台和设备。

| 优先级 | 功能 | 编号 | 工作量 |
|--------|------|------|--------|
| P0 | Web 版（Flutter Web 嵌入） | P-02 | 中 |
| P0 | iOS App | P-03 | 大 |
| P1 | Remote Device 引导 UI（WiFi 代理配置引导） | P-05 | 中 |
| P1 | Access Control（设备访问控制） | P-06 | 小 |
| P2 | Windows 桌面版 | P-04 | 大 |
| P2 | Linux 桌面版 | P-04 | 中 |

---

## 三、功能详细描述

### B-05 SSL 代理列表

**目标：** 控制哪些域名/App 的 HTTPS 流量被解密。

**功能：**
- Include List：只解密列表中的域名（默认空 = 不解密任何）
- Exclude List：解密所有域名除了列表中的
- 支持通配符：`*.google.com`、`api.*.com`
- 右键请求 → 添加到 Include/Exclude List
- 支持按 App 过滤（macOS 可检测进程名）

**UI：**
- 菜单 Tools → SSL Proxying List
- 弹窗显示两个列表（Include/Exclude），支持增删改

---

### A-01 Compose（构造请求）

**目标：** 手动构造并发送 HTTP 请求，用于 API 测试。

**功能：**
- 选择 Method（GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS）
- 输入 URL
- 编辑 Headers（Key-Value 表格）
- 编辑 Body（Raw/JSON/Form/Binary）
- 编辑 Query Parameters
- 发送请求并查看响应
- 可从已捕获的请求直接打开 Compose（预填充数据）

**UI：**
- 独立页面或弹窗
- 左侧：请求编辑区
- 右侧：响应展示区

---

### A-02 Repeat（重放请求）

**目标：** 重新发送已捕获的请求。

**功能：**
- 右键请求 → Repeat
- 可选择重放次数（1/5/10/自定义）
- 重放结果显示在流量列表中
- 可先编辑再重放（Repeat & Edit → 打开 Compose）

---

### A-03 Map Local（本地映射）

**目标：** 用本地文件内容替代服务器响应。

**功能：**
- 创建规则：URL Pattern → 本地文件路径
- 支持通配符和正则匹配
- 可自定义响应状态码和 Headers
- 支持 JSON/HTML/JS/CSS/图片等格式
- 右键请求 → Map Local（自动生成规则）
- 规则可启用/禁用

**后端实现：**
- 在 TunnelServices 的 HTTPCaptureHandler 中拦截匹配请求
- 从本地文件读取内容构造响应
- 不转发到真实服务器

---

### A-05 Breakpoint（断点调试）

**目标：** 暂停请求/响应，实时编辑后决定放行或中止。

**功能：**
- 创建断点规则：URL Pattern + Request/Response/Both
- 命中断点时弹出编辑窗口
- 可编辑：URL、Method、Headers、Body、Status Code
- 三个操作：Execute（放行）、Cancel（跳过不修改）、Abort（返回 503）
- 支持超时自动放行

**后端实现：**
- 在 ResponseRelayHandler 和 HTTPCaptureHandler 中添加断点检查
- 命中时暂停 NIO pipeline，通过 WebSocket 通知 Flutter UI
- UI 编辑完成后通过 API 回传修改后的数据，恢复 pipeline

---

### A-09 Diff（对比工具）

**目标：** 并排对比两个请求/响应的差异。

**功能：**
- 选择两个请求 → Diff
- 对比：URL、Method、Status Code、Headers、Body
- 支持 Side-by-Side 和 Unified 两种视图
- 高亮差异行
- 支持导出 diff 文件

---

### A-12 Network Conditions（弱网模拟）

**目标：** 模拟各种网络条件，测试应用在弱网下的表现。

**功能：**
- 预设配置：WiFi / 4G / 3G / Edge / 100% Loss
- 自定义：上行/下行带宽、延迟、丢包率
- 按域名或全局生效
- 实时切换，立即生效

**后端实现：**
- 在 NIO pipeline 中添加 ThrottleHandler
- 根据配置延迟数据转发、随机丢包

---

## 四、当前已完成功能

| 模块 | 功能 | 状态 |
|------|------|------|
| 抓包引擎 | HTTP/1.1、HTTP/2、WebSocket、QUIC 抓包 | ✅ |
| 抓包引擎 | TLS MITM 动态证书生成 | ✅ |
| 抓包引擎 | 连接池复用（Keep-Alive + Pool） | ✅ |
| 抓包引擎 | 自动隧道回退（证书不信任时透传） | ✅ |
| 抓包引擎 | 防崩溃 + 自动重启 | ✅ |
| 存储层 | KnotStorage 独立模块（SQLite + 文件） | ✅ |
| 存储层 | 5 个数据库（transport/protocol/decoded/state/connection） | ✅ |
| 存储层 | StorageWriter 写入门面 | ✅ |
| API 层 | KnotWebService HTTP+WebSocket 服务 | ✅ |
| API 层 | REST API（tasks/flows/payload/stats） | ✅ |
| API 层 | WebSocket 实时推送（flow/metrics/stats） | ✅ |
| Flutter UI | macOS 桌面应用 | ✅ |
| Flutter UI | 全局栏 + 工具栏 + 过滤栏 + 状态栏 | ✅ |
| Flutter UI | 域名树 + 请求列表 + 请求详情（Headers/Body/Timing/Connection） | ✅ |
| Flutter UI | Waterfall 时序图 | ✅ |
| Flutter UI | Dashboard 状态看板 | ✅ |
| Flutter UI | 历史任务管理（查看/切换/搜索/编辑/删除/批量删除） | ✅ |
| Flutter UI | 设置页面 | ✅ |
| Flutter UI | 深色/浅色主题 + 集中式 Theme 系统 | ✅ |
| Flutter UI | JSON 语法高亮 Body 查看器 | ✅ |
| 测试 | Flutter 162 个测试 | ✅ |
| 测试 | KnotStorage 8 个测试 | ✅ |
| 测试 | TunnelServices 27 个集成测试 | ✅ |
| 测试 | 100 站点浏览器压测（77/100 通过，0 崩溃） | ✅ |
