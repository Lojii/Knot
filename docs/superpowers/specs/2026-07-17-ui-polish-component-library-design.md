# UI 全局打磨与共享组件库设计

日期：2026-07-17
状态：已与用户确认

## 背景与目标

Knot 的 Flutter macOS 界面走仿 macOS 原生路线（Apple 系统色 + Inter 字体），已有集中的主题系统 `lib/theme/app_theme.dart`（支持 `assets/theme.json` 覆盖），但代码审计发现三类问题导致界面「不够友好、不够美观」：

1. **风格不统一**：Tab 栏有 5 种实现、按钮混用 4 种（TextButton / ElevatedButton / FilledButton / 自绘）、`InputDecoration` 手写 23 处、空状态两种风格并存；十几处硬编码颜色绕过主题（部分数值与主题定义完全相同）。
2. **交互反馈不足**：复制 cURL 无任何提示；全项目仅 3 个 tooltip；20+ 处可点击区域无 hover 高亮，部分连手型光标都没有。
3. **信息层级不清**：流量表格所有列同字号同字重同色，主次不分；核心页空状态只有一行灰字，而 tools 页反而有精致空状态。

目标：对标 Proxyman，把 macOS 原生观感做到位——统一控件、完善悬停/按下/操作反馈、理清信息层级。范围为全局（capture 主页 + compose / history / tools / settings）。

策略（用户已选定）：**先沉淀共享组件库，再逐页替换**，一次性解决风格统一与交互反馈，最小化后续维护成本。

## 第 1 部分：共享组件库（`lib/widgets/common/`）

新建 6 个组件，全部从 `AppTheme` 取值，不引入新依赖：

### 1. AppButton — 统一按钮
- 三种样式：`primary`（实心主色，主操作如 Start / Send）、`secondary`（描边/文字，普通操作）、`destructive`（红色语义，删除/清空）。
- 内建 hover 加深、pressed 反馈、`SystemMouseCursors.click`、可选 leading 图标、可选 `tooltip` 参数。
- 替换现有 TextButton / ElevatedButton / FilledButton / `_StartStopButton`（`global_bar.dart:347` 自绘）四种混用。

### 2. AppTextField — 统一输入框
- 封装重复手写的 23 处 `InputDecoration`：isDense、`radius.sm` 圆角、divider 色边框、聚焦时主色边框，高度对齐 `sizing.searchFieldHeight`。
- 支持可选前缀图标（搜索场景）、清除按钮。

### 3. AppTabBar — 统一分段式 Tab
- macOS segmented control 观感：选中项为 `detailTab.activeBackground` 圆角胶囊，未选中项 hover 时浅背景。
- 替换 5 种现有实现：`content_panel.dart` 的 tab、`flow_detail_panel.dart` 的 `_tabButton` 与 `_SubTabBar`、`compose_page.dart` 的 `_buildBodyTabs`、以及 settings / allow_block 的 Material `TabBar`。

### 4. EmptyState — 统一空状态
- 图标（48px、弱化色）+ 标题 + 描述 + 可选操作按钮，以 tools 页现有精致版（`map_local_page.dart:56-79`）为基准抽出。
- 核心页（流量表、域名树、历史、瀑布图、仪表盘）从「一行灰字」升级到该组件。

### 5. Hoverable — 轻量 hover 包装器
- 提供 hover 背景色、手型光标、pressed 不透明度反馈。
- 供 tab chip、filter chip、树节点、自定义可点击区域使用，解决「点了才知道能点」。

### 6. AppToast — 统一操作反馈
- `showAppToast(context, message, {icon})`：基于 `Overlay` 实现的浮动式紧凑提示，不依赖 `ScaffoldMessenger`（部分页面可能不在其之下），约 2 秒自动消失。
- 复制/导出/保存等操作后统一走它。

### 顺手清理
- 删除死代码 `lib/widgets/json_viewer.dart`（`lib/` 内无引用），连同其测试 `test/widgets/json_viewer_test.dart` 一并删除，否则 `flutter analyze` 会失败。
- `status_bar.dart` 改为复用现成的 `ConnectionIndicator`（当前手工重写了相同的圆点+状态色逻辑，`status_bar.dart:37-44`）。

### 主题补充
- 可映射到现有语义色的硬编码直接映射：如 `settings_page.dart:62-64` 证书状态色 → `colors.status` / `statusConnected` 系；`global_bar.dart:210,321` 的 `Colors.red` → 主题红。
- 确实缺位的新增进 `ThemeColors` 与 `theme.json` 解析：diff 增删色（`diff_page.dart:309-317`）、收藏星标色（`tree_panel.dart:398`）。`fontSize` 新增的 `xxl` 档同样纳入 `theme.json` 可覆盖范围。
- 解析沿用现有 fallback 机制：`theme.json` 缺字段或解析失败时回退硬编码默认值，旧配置不崩。

## 第 2 部分：逐页替换与体验修复

### 替换顺序（每页一个独立提交，随时可停）
1. **capture 主页**：global_bar、flow_table、tree_panel、flow_detail_panel、content_panel、filter_bar、status_bar——使用频率最高，优先。
2. **compose、history**。
3. **tools 五页（breakpoint / map_local / map_remote / allow_block / diff）+ settings**。

每页替换内容：按钮/输入框/Tab/空状态换成新组件；顺手修掉该页硬编码颜色、字号、圆角（映射到 `AppTheme`）。

### 交互反馈修复（随所在页一起改）
- 复制 cURL 后弹 AppToast「已复制到剪贴板」：`flow_table.dart:349`、`capture_page.dart:202`。
- 核心按钮补 tooltip：Start/Stop（含快捷键提示）、tab 关闭按钮、各页 IconButton。
- filter chip、tab chip、tab 关闭按钮补手型光标 + hover 高亮（Hoverable）。

### 信息层级修复
- **流量表格行**（`flow_table.dart:228-254`）：host 列改中等字重；time / duration / size 次要列改 `textSecondary` 色；method / status 保持现有彩色；表头文字加字重。
- **仪表盘统计大数字**（`dashboard_tab.dart:114,160`）：字号纳入主题（`fontSize` 增加 xxl 档）。
- 空状态统一后自带层级（图标弱化、标题主色、描述次要色）。

## 错误处理

纯 UI 层改动，不触碰 controller / api / 存储逻辑。`theme.json` 新增字段走现有 try-catch fallback，解析失败整体回退默认主题（与现状一致）。

## 测试与验证

- 每页改完跑 `flutter analyze` 与现有测试（`test/`）。
- 组件库为纯展示组件，为 AppButton / AppTabBar / EmptyState / AppToast 补基础 widget test（渲染、点击回调、hover 状态）。
- 全部完成后 `flutter run -d macos` 实际启动，逐页人工验证光/暗两套主题。

## 不做的事（YAGNI）

- 不引入新依赖、不换状态管理。
- 不动瀑布图 canvas 内部 14 色调色板（可争议项，本期保持现状）。
- 不做空状态引导/新手教程（用户未选该痛点）。
- 不重新设计页面布局与导航结构，只做控件统一与细节打磨。
