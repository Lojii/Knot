# Body 高级查看器

## 基本信息

| 字段 | 值 |
|------|---|
| 功能编号 | P3-05 |
| 所属阶段 | Phase 3 |
| 优先级 | P1 |
| 状态 | ✅ 已完成 |
| 关联文件 | `lib/widgets/body_viewer.dart`, `lib/widgets/json_viewer.dart` |

## 功能描述

BodyViewer 是一个通用的 HTTP body 查看组件，支持三种显示模式切换：Pretty（智能格式化）、Raw（原始文本）、Hex（十六进制）。Pretty 模式根据 Content-Type 自动选择最佳显示方式：JSON 语法高亮、XML/HTML 自动缩进、图片预览等。

## 用户操作流程

1. 在请求详情的 Body Tab 中查看请求/响应 body
2. 默认 Pretty 模式 → 根据内容类型自动格式化
3. 点击 "Raw" → 查看原始未格式化的文本
4. 点击 "Hex" → 查看十六进制转储
5. 文本内容均可选择复制

## 界面设计

### 模式切换 Toggle
```
[Pretty] [Raw] [Hex]
```
- 三个 Chip 按钮横排
- 选中态: 蓝色背景+蓝色边框+蓝色文字
- 未选中: 透明背景+灰色边框

### Pretty 模式
根据 Content-Type 自动判断:

1. **图片** (content-type 包含 "image/"): 尝试 Base64 解码显示 Image.memory，失败则显示文字描述
2. **JSON** (content-type 包含 "json" 或内容以 `{`/`[` 开头): 语法高亮显示
   - Key: 蓝色（暗色模式 #82AAFF，亮色模式 #1565C0）
   - String: 绿色（暗色模式 #C3E88D，亮色模式 #2E7D32）
   - Number: 橙色（暗色模式 #F78C6C，亮色模式 #E65100）
   - Boolean/null: 紫色（暗色模式 #C792EA，亮色模式 #6A1B9A）
   - 使用 JsonEncoder.withIndent('  ') 格式化
3. **XML/HTML** (content-type 包含 "xml" 或 "html"): 自动缩进（基于标签解析）
4. **其他**: 原始文本 SelectableText

### Raw 模式
- 直接 SelectableText 显示原始内容
- JetBrains Mono 等宽字体

### Hex 模式
- 经典 hex dump 格式:
  ```
  00000000  48 54 54 50 2f 31 2e 31  20 32 30 30 20 4f 4b 0d  |HTTP/1.1 200 OK.|
  ```
- 三列: 偏移量(8位16进制) + 十六进制(每行16字节，左右各8字节) + ASCII (不可打印字符显示 `.`)
- 性能限制: 最多显示前 4096 字节，超出显示 "... truncated at 4096 bytes (total: {n})"

## 技术实现

### 前端（Flutter）
- **BodyViewer**: StatefulWidget，管理 `_viewMode` 状态
- **_SyntaxText**: StatelessWidget，JSON 语法高亮
  - 使用正则匹配: key("...":), string("..."), number(\d+\.?\d*), bool/null
  - 通过 SelectableText.rich(TextSpan) 渲染多色文本
- **_indentXml()**: 简单 XML 缩进器，按标签匹配调整缩进级别
- **_hexView()**: UTF-8 编码 → 每 16 字节一行，格式化输出

### JSON Viewer (`widgets/json_viewer.dart`)
- 独立的简单 JSON 格式化组件
- jsonDecode + JsonEncoder.withIndent('  ') + SelectableText

## 边界条件与异常处理

- body 为空时显示 "(empty)"（灰色 hintColor）
- JSON 解析失败时降级为原始文本
- 图片 Base64 解码失败时显示文字描述
- Hex 模式截断到 4KB 防止性能问题
- XML 缩进为尽力而为（best-effort），复杂嵌套可能不完美

## Todo

- [ ] JSON 大文件性能问题（regex 全文扫描）
- [ ] 缺少搜索/高亮功能
- [ ] 缺少行号显示
- [ ] 缺少折叠/展开 JSON 节点的交互
- [ ] 缺少 "复制全部" 按钮
- [ ] 缺少 "保存到文件" 功能
- [ ] 图片预览仅支持 Base64 编码，不支持二进制 body
- [ ] Hex 模式的 4KB 截断限制应可配置
- [ ] 缺少 Form URL-encoded 解析展示
- [ ] 缺少 Multipart form-data 解析展示
