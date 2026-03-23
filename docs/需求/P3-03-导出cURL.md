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

## Todo

- [ ] body 应嵌入实际请求内容（需加载 request payload）
- [ ] 缺少 --compressed 标志（gzip/br/deflate）
- [ ] 缺少 --insecure 选项（自签名证书场景）
- [ ] 快捷键 Cmd+C 与系统复制冲突，应使用不同快捷键或条件判断
- [ ] 缺少导出为其他格式（fetch/axios/python requests）
- [ ] 多行格式在 Windows 上应使用 `^` 而非 `\`
