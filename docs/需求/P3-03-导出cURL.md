# 导出 cURL

## 基本信息

| 字段 | 值 |
|------|---|
| 功能编号 | P3-03 |
| 所属阶段 | Phase 3 |
| 优先级 | P1 |
| 状态 | ✅ 已完成 |
| 关联文件 | `lib/utils/curl_export.dart`, `lib/pages/capture/flow_detail_panel.dart`, `lib/pages/capture/flow_table.dart`, `lib/pages/capture/capture_page.dart` |

## 功能描述

将选中的 HTTP 请求导出为可执行的 cURL 命令，复制到系统剪贴板。支持三种触发方式：详情面板按钮、右键上下文菜单、键盘快捷键 Cmd+C。生成的命令包含 method、URL、请求头，POST/PUT/PATCH 请求包含 body 占位符。

## 用户操作流程

### 方式一: 详情面板按钮
1. 选中某条流量 → 详情面板展开
2. 点击顶部 "Copy as cURL" 按钮
3. SnackBar 提示 "cURL command copied to clipboard"

### 方式二: 右键菜单
1. 在 FlowTable 中右键某行
2. 弹出上下文菜单 → 点击 "Copy as cURL"
3. cURL 命令复制到剪贴板

### 方式三: 键盘快捷键
1. 选中某条流量后按 Cmd+C
2. 基于 FlowSummary 的信息生成简化 cURL 并复制

## 界面设计

- 详情面板: TextButton.icon（copy 图标 + "Copy as cURL" 文字, 11px）
- 右键菜单: PopupMenuItem（copy 图标 + "Copy as cURL" 文字）
- SnackBar 反馈: "cURL command copied to clipboard"，2s 显示

## 技术实现

### CurlExport 类 (`utils/curl_export.dart`)
`fromFlowDetail(Map<String, dynamic> raw)`:

1. 从 raw 中提取 method / uri / host / protocol / port
2. 构建完整 URL: `{scheme}://{host}{:port}{uri}`
   - scheme: HTTPS/H2 协议用 https，其余用 http
   - port: 80/443 不显示，其余显示
3. 构建 cURL 部分:
   - `curl` 命令
   - `-X '{METHOD}'`（GET 除外）
   - `'{URL}'`
   - `-H '{name: value}'`（跳过伪头 `:` 开头的）
   - `--data '<request body>'`（POST/PUT/PATCH）
4. 各部分用 ` \\\n  ` 换行连接
5. 单引号使用 `'\''` 转义

### 快捷键简化版
Cmd+C 绑定在 CopyAsCurlIntent 中，使用 FlowSummary 直接构建简化版:
```
curl -X {method} '{protocol}://{host}{uri}'
```
不包含请求头（因为 summary 中无 headers 数据）。

### 后端（Swift/KnotWebService）
- 详情面板版本依赖已加载的 FlowDetail.raw 中的 metadata.requestHeaders

## 边界条件与异常处理

- 未选中流量时 Cmd+C 不执行任何操作
- detail 未加载时使用空 headers（仅生成 method + URL）
- body 内容未实际嵌入（使用占位符 `<request body>`）

## Proxyman 参考

### 功能对标

Proxyman 的 Copy as cURL 功能，位于右键上下文菜单中。

### Proxyman 界面布局描述

Proxyman 导出 cURL 的方式：
- **右键菜单**：在 Flow List 中右键选中请求 → "Copy as cURL"
- **菜单栏**：Edit → Copy as cURL（⌘⇧C）
- **生成的 cURL 包含**：完整的 method、URL、所有请求头（-H）、请求 body（--data / --data-binary）、--compressed 标志（如有 gzip）
- 生成的命令完整可直接在终端执行，包含实际 body 内容
- 支持多选请求批量复制为多条 cURL 命令

### 参考截图

| 截图 | 说明 |
|------|------|
| （文字描述）Proxyman 右键菜单 | 右键请求行弹出菜单，包含 "Copy as cURL" 选项（⌘⇧C），菜单还包含 Repeat、Compose、Add to Diff Pool、Map Local/Remote 等其他操作 |

### 布局优缺点分析

**优点：**
- 生成的 cURL 包含完整的请求信息（含实际 body）
- 使用独立快捷键 ⌘⇧C，不与系统复制冲突
- 支持 --compressed 标志
- 支持批量复制

**缺点：**
- 仅支持 cURL 格式，不支持其他语言格式

### Knot 与 Proxyman 差异

| 对比点 | Proxyman | Knot |
|--------|----------|------|
| 快捷键 | ⌘⇧C（不冲突） | ⌘C（与系统复制冲突） |
| body 内容 | 包含实际 body | 占位符 `<request body>` |
| --compressed | 自动添加 | 未实现 |
| 批量复制 | 支持多选 | 仅单条 |
| 触发方式 | 右键菜单 + 菜单栏 + 快捷键 | 右键菜单 + 详情按钮 + 快捷键 |
| 其他格式 | 仅 cURL | 仅 cURL |

### Knot 中尚未实现的 Proxyman 功能

- **实际 body 嵌入**: Proxyman 的 cURL 包含完整请求 body，Knot 使用占位符
- **--compressed 标志**: 当请求使用 gzip/br/deflate 时自动添加
- **批量复制**: 多选请求批量生成 cURL
- **不冲突的快捷键**: 使用 ⌘⇧C 避免与系统复制冲突

## Todo

- [ ] body 应嵌入实际请求内容（需加载 request payload）
- [ ] 缺少 --compressed 标志（gzip/br/deflate）
- [ ] 缺少 --insecure 选项（自签名证书场景）
- [ ] 快捷键 Cmd+C 与系统复制冲突，应使用不同快捷键或条件判断
- [ ] 缺少导出为其他格式（fetch/axios/python requests）
- [ ] 多行格式在 Windows 上应使用 `^` 而非 `\`
