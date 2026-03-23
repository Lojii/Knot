# Diff 对比工具

## 基本信息

| 字段 | 值 |
|------|---|
| 功能编号 | P5-03 |
| 所属阶段 | Phase 5 |
| 优先级 | P2 |
| 状态 | ✅ 已完成 |
| 关联文件 | `lib/pages/tools/diff_page.dart` |

## 功能描述

Diff 对比工具允许用户选择两条已捕获的流量，并排（Side-by-Side）展示它们的差异。比较内容包括请求行、状态码、请求头、响应头和响应 body。差异行用颜色高亮标注（左侧红色表示删除/不同，右侧绿色表示新增/不同）。

## 用户操作流程

1. 点击 GlobalBar → Tools 菜单 → "Diff Tool"
2. 进入流量选择页面
3. 从下拉菜单中选择 Flow A 和 Flow B
4. 点击 "Compare" 按钮
5. 加载两条流量的详情和 body
6. 并排展示差异，差异行高亮标注
7. 点击 "Change Flows" 重新选择

## 界面设计

### 选择页面
```
┌──────────────────────────────────────┐
│ Diff Tool                            │
│ Select two flows to compare.         │
│                                      │
│ Flow A: [▾ GET api.example.com/v1/.. │
│ Flow B: [▾ POST api.example.com/v2.. │
│                                      │
│ [Compare]                            │
└──────────────────────────────────────┘
```

- 标题 + 说明文字
- 两个 DropdownButton（isExpanded），显示 "{method} {host}{uri} [{status}]"
- 无流量时显示提示 "No flows available. Capture some traffic first."
- Compare 按钮: FilledButton，两个 flow 都选择后可点击

### 对比视图
```
┌────────── Header ──────────────────────────────┐
│ 🔀 Diff Comparison         [Change Flows]       │
├──────────────────┬─────────────────────────────┤
│    Flow A        │        Flow B               │
├──────────────────┼─────────────────────────────┤
│ Request          │ Request                      │
│ GET /api/v1/users│ GET /api/v1/users            │
│ Status           │ Status                       │
│🟥 200 (HTTPS)    │🟩 201 (HTTPS)                │
│ Request Headers  │ Request Headers              │
│ Accept: */*      │ Accept: */*                  │
│🟥 Auth: Bearer..  │🟩 Auth: Token..              │
│ Response Headers │ Response Headers             │
│ ...              │ ...                          │
│ Body             │ Body                         │
│🟥 {"id":1}       │🟩 {"id":2}                   │
└──────────────────┴─────────────────────────────┘
```

### 差异高亮规则
- 同一位置（index）的行内容不同 → 高亮
- 左侧 (Flow A): 红色背景 (alpha 8%) + 红色文字 (red.shade700)
- 右侧 (Flow B): 绿色背景 (alpha 8%) + 绿色文字 (green.shade700)
- 内容相同的行: 无特殊颜色
- 一侧多出的行（index 越界）: 视为差异

### 比较分区
每侧按以下分区展示:
1. **Request**: "{method} {uri}"
2. **Status**: "{status} ({protocol})"
3. **Request Headers**: 按字母序排列，跳过伪头 (:开头)
4. **Response Headers**: 同上
5. **Body**: 响应 body 按行分割

### 分区标题
- surfaceContainerHighest 背景
- labelMedium 粗体文字

## 技术实现

### 前端（Flutter）
- **DiffPage**: StatefulWidget，管理 flowA/flowB/detailA/detailB/bodyA/bodyB/isLoading
- **_loadAndCompare()**: 并行加载两条流量的 detail + body
  - Future.wait([getFlowDetail x2, getPayload x2])
  - catchError 处理 body 加载失败
- **_buildSections()**: 将 flow + detail + body 拆分为 5 个 _DiffSection
  - Headers 排序后比较（保证顺序一致性）
- **_DiffColumn**: ListView.builder 渲染各 section 及其 lines
- **_FlowDropdown**: DropdownButton 展示流量选择

### 后端（Swift/KnotWebService）
- 依赖 API: getFlowDetail + getPayload（preview 模式）

## 边界条件与异常处理

- 无流量时显示提示文字
- 加载失败时 SnackBar 提示
- body 加载失败时使用空字符串（catchError）
- body 为空时显示 "(empty)"
- 两个 DropdownButton 可以选择同一条流量（自己与自己比较，无差异）

## Todo

- [ ] 缺少行级别的精确 diff 算法（当前仅按 index 对齐比较）
- [ ] 缺少字符级 diff 高亮
- [ ] Header 排序后按 index 对比可能不准确（key 不同时错位比较）
- [ ] 缺少同步滚动（左右两侧独立滚动）
- [ ] 缺少展开/折叠 section
- [ ] 缺少差异统计（N 处不同）
- [ ] 缺少 JSON 结构化 diff（按 key path 比较）
- [ ] 缺少导出 diff 报告
- [ ] Body 按行分割可能对 minified JSON 无效（全在一行）
