# 导入 HAR

## 基本信息

| 字段 | 值 |
|------|---|
| 功能编号 | P5-02 |
| 所属阶段 | Phase 5 |
| 优先级 | P1 |
| 状态 | ✅ 已完成 |
| 关联文件 | `lib/utils/har_import.dart`, `lib/pages/capture/global_bar.dart` |

## 功能描述

从 HAR (HTTP Archive) 1.2 格式的 JSON 文件中导入流量记录，将其显示在当前的流量列表中。导入的流量以 "imported-" 前缀的 flowId 标识，与实时抓包的流量区分。支持从其他抓包工具（Chrome DevTools、Charles 等）导出的 HAR 文件。

## 用户操作流程

1. 点击 GlobalBar → Tools 菜单 → "Import HAR"
2. 弹出路径输入对话框
3. 输入 HAR 文件的完整路径（如 `/Users/xxx/Desktop/export.har`）
4. 点击 "Import"
5. 解析成功 → SnackBar "Imported {N} requests from HAR file"
6. 导入的流量插入到流量列表顶部

## 界面设计

### 导入对话框
```
┌──────────────────────────────┐
│ Import HAR                   │
│                              │
│ HAR file path                │
│ [/path/to/file.har        ] │
│                              │
│         [Cancel]  [Import]   │
└──────────────────────────────┘
```
- 标题: "Import HAR"
- 输入框: hint "/path/to/file.har", label "HAR file path"
- 按钮: "Cancel" + "Import"

### 反馈
- 成功: SnackBar "Imported {N} requests from HAR file"（3s）
- 失败: SnackBar "Import failed: {error}"

## 技术实现

### HarImport 类 (`utils/har_import.dart`)

#### parse(String jsonContent) → List<FlowSummary>
1. jsonDecode 解析 HAR JSON
2. 遍历 log.entries
3. 每个 entry 转换为 FlowSummary（失败则跳过）

#### importFromFile(String path) → List<FlowSummary>
- 读取文件内容 → 调用 parse

#### _entryToFlowSummary(entry, index) → FlowSummary
字段映射:
| HAR 字段 | FlowSummary 字段 |
|----------|-----------------|
| request.method | method (searchKey1) |
| request.url → Uri.parse | host / port / uri (searchKey2) |
| response.status | status / statusCode (searchKey3) |
| response.content.mimeType | contentType (searchKey4) |
| response.bodySize | downloadBytes |
| request.bodySize | uploadBytes |
| startedDateTime | startedAt (epoch 秒) |
| time | endedAt = startedAt + time/1000 |
| timings (sum of positive values) | durationMs |

#### flowId 生成
- 格式: `imported-{index}-{startedAt}`
- 例如: `imported-0-1711000000`

#### 协议判断
- httpVersion 含 "h2"/"http/2" → "H2"
- scheme "https" → "HTTPS"
- 其他 → "HTTP"

#### Duration 计算
- 累加 timings 中所有正值（connect/ssl/send/wait/receive）
- 全部为 -1 时使用 entry.time

### 导入流程（GlobalBar）
1. showDialog 获取文件路径
2. HarImport.importFromFile(path) 解析
3. 逐条 flowCtrl.flows.insert(0, flow) 插入列表顶部
4. 更新 flowCtrl.total

### 后端（Swift/KnotWebService）
- 纯前端操作，不涉及后端

## 边界条件与异常处理

- 文件不存在时抛出 "File not found: {path}"
- JSON 解析失败时捕获异常
- 单条 entry 格式异常时跳过（不影响其他 entry）
- URL 解析失败时 host/port/path 使用默认值
- startedDateTime 解析失败时使用当前时间
- 路径为空时不执行导入

## Proxyman 参考

### 功能对标

Proxyman 的 File → Open 功能，支持导入 HAR 文件、Proxyman 文件和 Charles Session 文件。

### Proxyman 界面布局描述

Proxyman 的导入功能：
- **File → Open（⌘O）**：使用 macOS 标准 NSOpenPanel 文件选择器
- **支持格式**：
  - .har（HAR 1.2 格式）
  - .proxyman（Proxyman 自有格式）
  - .chls（Charles Session 格式）
- **导入方式**：导入后创建新的 Session 窗口/Tab，不与当前 Session 混合
- **File → Open Recent**：显示最近打开的文件列表
- **拖放支持**：支持将文件直接拖放到应用窗口中导入
- **导入后展示**：完整的流量列表+详情，与实时抓包的数据展示方式一致

### 参考截图

| 截图 | 说明 |
|------|------|
| （文字描述）Proxyman File → Open | macOS 标准文件选择对话框，过滤器显示支持的文件类型（.har、.proxyman、.chls）。可以导航文件系统选择文件 |

### 布局优缺点分析

**优点：**
- 使用 macOS 标准文件选择器，用户体验一致
- 支持多种格式（HAR + Proxyman + Charles）
- 导入创建新 Session，不污染当前数据
- 支持拖放导入
- 导入后可查看完整详情

**缺点：**
- 大 HAR 文件导入可能较慢
- 不同格式的信息完整度不同

### Knot 与 Proxyman 差异

| 对比点 | Proxyman | Knot |
|--------|----------|------|
| 文件选择 | macOS 标准文件选择器 | 手动输入路径对话框 |
| 支持格式 | HAR + .proxyman + .chls | 仅 HAR |
| 导入方式 | 创建新 Session | 插入当前列表顶部 |
| 拖放 | 支持 | 不支持 |
| 详情查看 | 完整详情可查看 | 无法查看详情（无 detail 数据） |
| 进度提示 | 有 | 无 |
| Open Recent | 支持 | 不支持 |

### Knot 中尚未实现的 Proxyman 功能

- **文件选择器**: 使用系统文件选择对话框代替手动输入路径
- **拖放导入**: 将文件拖放到窗口中导入
- **导入 Charles Session**: 支持 .chls 格式
- **创建新任务**: 导入时创建新 Task 而非混入当前列表
- **完整详情**: 导入的流量应可查看详情
- **导入进度**: 大文件导入时显示进度
- **格式验证**: 验证 HAR 文件版本和完整性

## Todo

- [ ] 缺少文件选择器（当前需手动输入路径）
- [ ] 缺少拖放导入
- [ ] 导入的流量无法查看详情（无 detail 数据）
- [ ] 导入不会创建新 task，直接混入当前列表
- [ ] 缺少导入预览（先显示摘要再确认导入）
- [ ] 缺少进度指示（大 HAR 文件解析可能耗时）
- [ ] 缺少 HAR 格式验证（如 version 检查）
- [ ] 导入后 total 计数可能不准确（简单累加，未去重）
