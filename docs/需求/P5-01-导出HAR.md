# 导出 HAR

## 基本信息

| 字段 | 值 |
|------|---|
| 功能编号 | P5-01 |
| 所属阶段 | Phase 5 |
| 优先级 | P1 |
| 状态 | ✅ 已完成 |
| 关联文件 | `lib/utils/har_export.dart`, `lib/pages/capture/global_bar.dart` |

## 功能描述

将当前抓包任务的所有流量导出为 HAR (HTTP Archive) 1.2 格式的 JSON 文件。HAR 是一种通用的 HTTP 抓包数据交换格式，可以被 Chrome DevTools、Charles、Proxyman 等工具导入查看。

## 用户操作流程

1. 点击 GlobalBar → Tools 菜单 → "Export HAR"
2. SnackBar 提示 "Exporting HAR..."
3. 后台逐条加载流量详情和响应 body
4. 导出完成 → SnackBar 提示 "HAR exported to {path}"
5. 文件保存到桌面: `~/Desktop/knot-export-{timestamp}.har`

## 界面设计

- 触发入口: Tools 菜单中 "Export HAR"（upload_file 图标）
- 反馈:
  - 进行中: SnackBar "Exporting HAR..."
  - 成功: SnackBar "HAR exported to /Users/.../Desktop/knot-export-xxx.har"（4s 显示）
  - 失败: SnackBar "Export failed: {error}"
  - 无流量: SnackBar "No flows to export"

## 技术实现

### HarExport 类 (`utils/har_export.dart`)

#### fromFlows(flows, api, taskId, {bodySizeLimit})
1. 遍历所有 FlowSummary
2. 对每条流量调用 api.getFlowDetail() 加载详情
3. 构建 HAR entry（失败时降级为 minimal entry）
4. 组装 HAR 1.2 JSON 结构

#### HAR 结构
```json
{
  "log": {
    "version": "1.2",
    "creator": {"name": "Knot", "version": "1.0.0"},
    "entries": [...]
  }
}
```

#### 每个 Entry 包含
- **startedDateTime**: ISO 8601 UTC 格式
- **time**: 总耗时 ms
- **request**: method / url / httpVersion / headers / queryString / bodySize
- **response**: status / statusText / httpVersion / headers / content(size/mimeType/text) / bodySize
- **timings**: connect / ssl / send / wait / receive（毫秒，无数据时 -1）

#### URL 构建
- scheme: HTTPS/H2 → https, 其他 → http
- port: 80/443 不显示，其他显示
- fullUrl = scheme://host:port/uri

#### Headers 处理
- 跳过伪头部（`:` 开头的 HTTP/2 伪头）
- 格式化为 `[{name, value}, ...]`

#### Query String 解析
- 从 URI 中 `?` 后的部分解析
- Uri.splitQueryString() 提取键值对

#### Body 加载
- 仅在 downloadBytes <= bodySizeLimit (默认 1MB) 时加载
- 使用 preview 模式: api.getPayload(direction: 'response', preview: true)
- 加载失败时忽略（不阻塞导出）

#### Timings 计算
- connect: connectedAt - connectAt
- ssl: tlsDoneAt - connectedAt（无 TLS 时 -1）
- send: reqEndAt - tlsDoneAt (或 connectedAt)
- wait: rspStartAt - reqEndAt
- receive: endedAt - rspStartAt

#### writeToDesktop(harJson)
- 输出路径: `$HOME/Desktop/knot-export-{timestamp}.har`
- 使用 dart:io File.writeAsString

### 后端（Swift/KnotWebService）
- 依赖 API: getFlowDetail + getPayload

## 边界条件与异常处理

- 无流量时 SnackBar 提示 "No flows to export"
- taskId 为 null 时不导出
- 单条流量加载失败时降级为 minimal entry（仅包含 summary 信息，timings 全为 -1）
- 大 body (>1MB) 不加载（避免内存问题）
- 导出文件写入失败时 catch 报错

## Proxyman 参考

### 功能对标

Proxyman 的 Export 功能，位于 File → Export 菜单中。支持导出为 HAR 格式和 Proxyman 自有格式。

### Proxyman 界面布局描述

Proxyman 的导出功能：
- **File → Export → HAR**：导出为 HAR 1.2 格式
- **File → Export → Proxyman**：导出为 .proxyman 格式（Proxyman 专有格式，保留更多元数据）
- **导出选择**：可选择导出全部请求或仅选中的请求
- **文件选择器**：使用 macOS 标准 NSSavePanel，用户自选保存位置和文件名
- **导出完成提示**：macOS 通知或状态栏提示
- **导入 Charles Session**：支持导入 .chls 格式的 Charles Session 文件
- **HAR 导出内容**：完整的请求和响应信息，包括 headers、body、timings

### 参考截图

| 截图 | 说明 |
|------|------|
| （文字描述）Proxyman File → Export 菜单 | File 菜单中 Export 子菜单包含 "HTTP Archive (.har)" 和 "Proxyman (.proxyman)" 两个选项。点击后弹出 macOS 标准文件保存对话框 |

### 布局优缺点分析

**优点：**
- 使用 macOS 标准文件保存对话框，用户可自选保存位置
- 支持两种格式（HAR + Proxyman 自有格式）
- 支持选择性导出（全部或仅选中）
- 导出内容完整，包含请求和响应 body

**缺点：**
- 大量请求导出时缺少进度条
- 不支持压缩导出

### Knot 与 Proxyman 差异

| 对比点 | Proxyman | Knot |
|--------|----------|------|
| 保存位置 | macOS 文件选择器 | 固定保存到桌面 |
| 导出格式 | HAR + .proxyman | 仅 HAR |
| 选择性导出 | 全部或仅选中 | 仅全部导出 |
| Request body | 包含 | 不包含 |
| 进度提示 | 无明确进度条 | SnackBar "Exporting..." |
| 大 body 处理 | 完整导出 | 超过 1MB 跳过 |

### Knot 中尚未实现的 Proxyman 功能

- **文件保存对话框**: 使用系统文件选择器让用户自选保存位置
- **选择性导出**: 仅导出选中或过滤后的请求
- **Request body 导出**: 导出请求 body（当前仅导出响应 body）
- **自有格式导出**: 类似 .proxyman 的自有格式，保留更多元数据
- **导出进度条**: 大量请求导出时显示进度
- **导入 Charles Session**: 支持 .chls 格式导入

## Todo

- [ ] 大量流量导出时无进度条
- [ ] 缺少文件保存位置选择（当前固定桌面）
- [ ] 缺少选择性导出（仅导出选中/过滤后的流量）
- [ ] request body 未导出（仅导出 response body）
- [ ] 缺少压缩选项（HAR 文件可能很大）
- [ ] statusText 映射不完整（仅覆盖常见状态码）
- [ ] 串行加载 detail 较慢，应改为并发或批量 API
