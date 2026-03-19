# Knot 已知问题

本文档记录项目中发现的问题，按严重程度排序。

---

## 严重问题 (Critical)

### 1. 时间戳单位不一致 — HistoryTaskCell 日期显示错误

**文件**: `LocalPackages/KnotUI/Sources/KnotUI/Components/HistoryTaskCell.swift:34`

**问题**: 时间戳被错误地除以 1000：
```swift
let date = Date(timeIntervalSince1970: ts / 1000)
```

**原因**: `CaptureTask.creatTime` 存储的是 `TimeInterval`（秒级），不是毫秒。在 `CaptureTask.swift:114,117,157` 中，时间戳通过 `Date().timeIntervalSince1970` 获取（返回秒）。

**影响**: 历史任务显示的日期会是 1970 年附近的错误日期。

**修复建议**:
```swift
let date = Date(timeIntervalSince1970: ts)  // 移除 / 1000
```

---

## 重要问题 (Major)

### 2. fatalError 导致应用崩溃

**文件**:
- `LocalPackages/TunnelServices/Sources/TunnelServices/HttpService/HTTPServer.swift:76,99`
- `LocalPackages/TunnelServices/Sources/TunnelServices/HttpService/HTTPServerHandler.swift:213`
- `LocalPackages/TunnelServices/Sources/TunnelServices/MitmService.swift:458`

**问题**: 网络绑定失败时使用 `fatalError()` 直接崩溃：
```swift
fatalError("HTTPServer(Wifi):Address was unable to bind:\(wifiIP):\(self.defaultPort)")
```

**影响**: 如果端口被占用或 IP 不可用，整个网络扩展进程会崩溃，用户体验极差。

**修复建议**: 替换为 `throw` 错误或记录日志后优雅降级。

### 3. DatabaseManager 强制解包导致崩溃风险

**文件**: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/DatabaseManager.swift`

**问题**: 多处使用 `try!` 强制解包：
```swift
try! FileManager.default.createDirectory(...)
catalogDB = try! Connection(...)
try! TaskDatabaseGroup.configurePragmas(...)
```

**影响**: 任何数据库初始化失败（磁盘满、权限问题）都会导致应用崩溃。

**修复建议**: 改为 `do-catch` 并提供错误恢复机制或用户提示。

### 4. 数据迁移可能静默失败

**文件**: `LocalPackages/TunnelServices/Sources/TunnelServices/Storage/Migration/LegacyMigrator.swift`

**问题**: 从旧 ActiveSQLite 数据库迁移时，错误处理不充分。旧的 `nio.db` 如果存在但格式不兼容，可能导致数据丢失。

**修复建议**: 添加迁移前备份和详细的错误日志。

---

## 中等问题 (Moderate)

### 5. 残留注释代码

**文件**: `LocalPackages/TunnelServices/Sources/TunnelServices/Handler/ChannelWatchHandler.swift:29-30,40-41`

**问题**: 包含注释掉的 NSNumber 旧代码：
```swift
// self.proxyContext.task.uploadTraffic = NSNumber(value: ...)
```

**影响**: 代码整洁性问题，不影响运行。

**修复建议**: 清理所有注释掉的旧代码。

### 6. 时间戳格式不统一

**相关文件**:
- `CaptureTask.swift` — 使用秒级 TimeInterval
- `HistoryTaskCell.swift` — 假设毫秒（见问题 #1）
- `LegacyMigrator.swift:81` — 通过阈值判断毫秒还是秒：
  ```swift
  createdAtMs > 1_000_000_000_000 ? createdAtMs / 1000.0 : createdAtMs
  ```

**问题**: 项目中没有统一的时间戳约定，不同模块假设不同。

**修复建议**: 制定并执行统一标准（建议全部使用秒级 TimeInterval），在文档中明确说明。

### 7. SessionRecorder 仍有旧 Session API 引用

**文件**: `LocalPackages/TunnelServices/Sources/TunnelServices/Proxy/SessionRecorder.swift:16,20`

**问题**: 包含 TODO 注释和对旧 session API 的引用，表明迁移尚未完成。

**修复建议**: 完成从 ProxySession 到新 ProtocolRecorder 系统的迁移。

---

## 轻微问题 (Minor)

### 8. 空协议实现

**文件**: `LocalPackages/TunnelServices/Sources/TunnelServices/CaptureTask.swift:340-342`

```swift
extension CaptureTask: GCDAsyncUdpSocketDelegate {
}
```

**问题**: 空的协议实现。如果 `GCDAsyncUdpSocketDelegate` 有可选方法（Objective-C @optional），这是合法的。但如果是 Swift 协议，则可能缺少必要方法。

### 9. TODO 标记未解决

项目中存在多处 TODO 注释，表明功能未完成：

| 文件 | 描述 |
|------|------|
| `SessionRecorder.swift` | 旧 session API 迁移 |
| `MitmService.swift:295,307` | 发送更新信息的逻辑 |
| 多个 Handler 文件 | 请求/响应修改功能 |

### 10. README.md 内容过时

**文件**: `README.md`

**问题**:
- 仍提到 `pod install`（项目已迁移到 Swift Package Manager）
- 未提及 macOS 支持
- 未反映当前的模块化架构
- 截图链接可能失效（外部图床）

**修复建议**: 更新 README 以反映当前项目状态。

---

## 架构改进建议

### A. 错误处理标准化
当前混用 `try!`、`fatalError`、`try?` 静默忽略等模式。建议：
- 网络层: 所有错误通过 NIO promise/future 传播
- 存储层: `throws` 并由调用方处理
- UI 层: 显示用户友好的错误提示

### B. 日志体系完善
建议为各层建立统一的日志级别：
- `error`: 崩溃/数据丢失风险
- `warning`: 可恢复但异常的情况
- `info`: 关键生命周期事件
- `debug`: 开发调试信息

### C. 测试覆盖
当前测试目录存在但测试内容有限：
- `KnotApp-iOSTests/` — 需要补充
- `KnotApp-iOSUITests/` — 需要补充
- `KnotApp-macOSTests/` — 需要补充
- `KnotTests/` — NIO 相关测试

建议优先为以下模块添加单元测试：
1. DAO 层（FlowDAO、CatalogDAO）— 数据正确性
2. 编解码器（DNSDecoder、QUICDecoder）— 协议解析正确性
3. IPPacketParser — 二进制解析正确性
4. PathManager — 路径生成正确性

---

## 问题统计

| 严重程度 | 数量 | 类型 |
|---------|------|------|
| Critical | 1 | 时间戳显示错误 |
| Major | 3 | fatalError 崩溃、数据库强制解包、迁移风险 |
| Moderate | 3 | 残留代码、时间戳不统一、迁移未完成 |
| Minor | 3 | 空协议、TODO 未解决、README 过时 |
| **总计** | **10** | |
