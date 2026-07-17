# UI 全局打磨与共享组件库实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 6 个共享 UI 组件（AppToast / Hoverable / AppButton / AppTextField / AppTabBar / EmptyState），补充主题语义色，然后逐页替换重复实现、修复硬编码颜色、补齐交互反馈、理清信息层级。

**Architecture:** Flutter macOS 桌面应用，GetX 状态管理（`Obx`/`Get.find`），i18n 用 GetX `.tr`（键定义在 `lib/i18n/translations.dart`）。主题系统集中在 `lib/theme/app_theme.dart`（单例 `AppTheme`，可被 `assets/theme.json` 覆盖，解析失败整体回退硬编码默认值）。新组件全部放 `lib/widgets/common/`，只从 `AppTheme` 取值，零新依赖。

**Tech Stack:** Flutter 3.44 / Dart，GetX，flutter_test（widget test）。

**Spec:** `docs/superpowers/specs/2026-07-17-ui-polish-component-library-design.md`

---

## 实施须知（每个任务开始前先读这一节）

- 工作目录：`/Users/aa123/Documents/000/未命名/Knot`，分支 `feature/flutter-ui`。
- 所有命令在项目根目录运行。`flutter` 在 PATH 中（3.44.0 stable）。
- 主题取值惯例：`AppTheme.colors(context)` 返回当前亮/暗模式的 `ThemeColors`；`AppTheme.spacing / sizing / radius / fontSize` 是静态配置；`AppTheme.mode(context).detailTab / filterChip / table / tree` 是分区配置。**新代码禁止写死颜色/字号/间距**，一律走这些入口。
- Widget test 惯例参考现有 `test/widgets/connection_indicator_test.dart`。新组件不直接用 GoogleFonts，测试无需字体 mock。
- i18n：用户可见的新字符串必须加到 `lib/i18n/translations.dart` 的 `enUS` 和 `zhCN` 两个 map。本计划尽量复用现有键（`detail.curl_copied`、`toolbar.start/stop`、`empty.*`）；可能需要新增的键在 Task 9（`action.close`）和 Task 13（IconButton tooltip），各任务内有具体说明。
- 每个任务末尾都要跑 `flutter analyze`（期望 `No issues found!`）与 `flutter test`（期望全绿），然后 commit。commit message 末尾加：
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## 文件结构总览

**新建：**

| 文件 | 职责 |
|---|---|
| `lib/widgets/common/app_toast.dart` | Overlay 浮动提示 `showAppToast()` |
| `lib/widgets/common/hoverable.dart` | hover/pressed/光标包装器 |
| `lib/widgets/common/app_button.dart` | 统一按钮（primary/secondary/destructive） |
| `lib/widgets/common/app_text_field.dart` | 统一输入框 |
| `lib/widgets/common/app_tab_bar.dart` | 统一分段式 Tab |
| `lib/widgets/common/empty_state.dart` | 统一空状态 |
| `test/widgets/common/*_test.dart` | 上述组件的 widget test（6 个文件） |

**修改：** `lib/theme/app_theme.dart`、`assets/theme.json`、capture 7 个文件、compose/history/settings、tools 6 个文件、`lib/pages/capture/capture_page.dart`、`lib/pages/capture/tree_panel.dart`。

**删除：** `lib/widgets/json_viewer.dart`、`test/widgets/json_viewer_test.dart`。

---

### Task 1: 主题补充（语义色 + xxl 字号）

**Files:**
- Modify: `lib/theme/app_theme.dart`
- Modify: `assets/theme.json`
- Test: `test/theme/app_theme_test.dart`（追加用例）

- [ ] **Step 1: 写失败测试**

在 `test/theme/app_theme_test.dart` 的主 `group` 内追加：

```dart
test('new semantic colors have defaults', () {
  expect(AppTheme.lightMode.colors.favorite, const Color(0xFFFFC107));
  expect(AppTheme.lightMode.colors.diffAdded, const Color(0xFF34C759));
  expect(AppTheme.lightMode.colors.diffRemoved, const Color(0xFFFF3B30));
  expect(AppTheme.darkMode.colors.diffAdded, const Color(0xFF30D158));
});

test('fontSize has xxl tier', () {
  expect(AppTheme.fontSize.xxl, 20.0);
});

test('loadFromJson without new keys falls back to defaults for them', () {
  // 用 assets/theme.json 现有内容（不含新键）加载，不应触发整体回退
  final jsonString = File('assets/theme.json').readAsStringSync();
  AppTheme.loadFromJson(jsonString);
  expect(AppTheme.lightMode.colors.favorite, const Color(0xFFFFC107));
  expect(AppTheme.fontSize.xxl, 20.0);
});
```

文件顶部若无 `import 'dart:io';` 则添加。注意：该测试文件里若已有 `setUp`/`tearDown` 重置逻辑，跟随现有写法；最后一个测试结束后调用 `AppTheme.loadFromJson('invalid')` 恢复默认（现有 fallback 行为）以免污染其他用例——若现有测试已有类似恢复模式则照抄。

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: 编译错误 `favorite/diffAdded/diffRemoved/xxl isn't defined`（属于预期失败）

- [ ] **Step 3: 实现主题字段**

`lib/theme/app_theme.dart` 修改四处：

(a) `ThemeColors` 类（约 :11-57）新增 3 个字段，加入构造函数（**带默认值，非 required**，避免破坏既有调用）：

```dart
  final Color favorite;
  final Color diffAdded;
  final Color diffRemoved;
```

```dart
    this.favorite = const Color(0xFFFFC107),
    this.diffAdded = const Color(0xFF34C759),
    this.diffRemoved = const Color(0xFFFF3B30),
```

(b) `_defaultDarkMode()`（约 :320）的 `ThemeColors(` 中显式传暗色值：

```dart
      favorite: const Color(0xFFFFD60A),
      diffAdded: const Color(0xFF30D158),
      diffRemoved: const Color(0xFFFF453A),
```

(c) `FontSizeConfig`（约 :223-237）新增 `final double xxl;`，构造函数加 `this.xxl = 20.0,`（同样带默认值）；`_defaultFontSize`（约 :428）加 `xxl: 20.0`。

(d) 解析器改为**可选解析**（新键缺失时用默认值，不抛异常）：

`_parseThemeColors`（约 :617）的 `return ThemeColors(` 中追加：

```dart
      favorite: m['favorite'] != null ? parseHex(m['favorite'] as String) : const Color(0xFFFFC107),
      diffAdded: m['diffAdded'] != null ? parseHex(m['diffAdded'] as String) : const Color(0xFF34C759),
      diffRemoved: m['diffRemoved'] != null ? parseHex(m['diffRemoved'] as String) : const Color(0xFFFF3B30),
```

`_parseFontSize`（约 :743）追加：

```dart
      xxl: m['xxl'] != null ? (m['xxl'] as num).toDouble() : 20.0,
```

注意：可选解析导致 dark 模式下 JSON 未定义新键时会落到 light 默认值——可接受（这些色在明暗下均可读），如需精确可在 `assets/theme.json` 显式写值（下一步就写）。

(e) `assets/theme.json`：`light.colors` 内加 `"favorite": "#FFC107", "diffAdded": "#34C759", "diffRemoved": "#FF3B30"`；`dark.colors` 内加 `"favorite": "#FFD60A", "diffAdded": "#30D158", "diffRemoved": "#FF453A"`；`fontSize` 加 `"xxl": 20`。改完用 `python3 -m json.tool assets/theme.json > /dev/null && echo OK` 校验 JSON 合法。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: 全部 PASS

- [ ] **Step 5: 全量检查并提交**

```bash
flutter analyze && flutter test
git add lib/theme/app_theme.dart assets/theme.json test/theme/app_theme_test.dart
git commit -m "feat(theme): add favorite/diffAdded/diffRemoved colors and xxl font size"
```

---

### Task 2: AppToast 组件

**Files:**
- Create: `lib/widgets/common/app_toast.dart`
- Test: `test/widgets/common/app_toast_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/app_toast.dart';

void main() {
  testWidgets('showAppToast displays message and auto-dismisses', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showAppToast(context, 'Copied!'),
            child: const Text('go'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Copied!'), findsOneWidget);

    // 2 秒后自动消失
    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.text('Copied!'), findsNothing);
  });

  testWidgets('second toast replaces the first', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) { ctx = c; return const SizedBox(); })),
    ));
    showAppToast(ctx, 'first');
    await tester.pump();
    showAppToast(ctx, 'second');
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
  });
}
```

注：package 名以 `pubspec.yaml` 的 `name:` 为准（现有测试 import 前缀照抄，若是 `package:knot/...` 之外的名字则替换）。

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/widgets/common/app_toast_test.dart`
Expected: 编译失败（文件不存在）

- [ ] **Step 3: 实现**

`lib/widgets/common/app_toast.dart` 完整内容：

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

OverlayEntry? _activeToast;
Timer? _dismissTimer;

/// 全局浮动提示：复制/导出/保存成功后的轻量反馈。
/// 基于 Overlay，不依赖 ScaffoldMessenger；约 2 秒自动消失；新提示替换旧提示。
void showAppToast(BuildContext context, String message,
    {IconData icon = Icons.check_circle_outline}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  _dismissTimer?.cancel();
  _activeToast?.remove();
  _activeToast = null;

  final entry = OverlayEntry(
    builder: (ctx) {
      final colors = AppTheme.colors(ctx);
      return Positioned(
        bottom: 48,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing.lg,
                  vertical: AppTheme.spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius.popup),
                  border: Border.all(color: colors.divider, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: AppTheme.sizing.iconSize, color: colors.primary),
                    SizedBox(width: AppTheme.spacing.sm),
                    Text(message,
                        style: TextStyle(
                          fontSize: AppTheme.fontSize.md,
                          color: colors.textPrimary,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  _activeToast = entry;
  overlay.insert(entry);
  _dismissTimer = Timer(const Duration(seconds: 2), () {
    if (_activeToast == entry) {
      entry.remove();
      _activeToast = null;
    }
  });
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widgets/common/app_toast_test.dart`
Expected: PASS ×2

- [ ] **Step 5: 提交**

```bash
flutter analyze && git add lib/widgets/common/app_toast.dart test/widgets/common/app_toast_test.dart
git commit -m "feat(widgets): add AppToast overlay notification"
```

---

### Task 3: Hoverable 组件

**Files:**
- Create: `lib/widgets/common/hoverable.dart`
- Test: `test/widgets/common/hoverable_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/hoverable.dart';

void main() {
  testWidgets('builder receives hover state and onTap fires', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Hoverable(
          onTap: () => tapped = true,
          builder: (context, hovered) => Container(
            width: 60,
            height: 24,
            color: hovered ? Colors.blue : Colors.transparent,
            child: Text(hovered ? 'hover' : 'idle'),
          ),
        ),
      ),
    ));

    expect(find.text('idle'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Hoverable)));
    await tester.pump();
    expect(find.text('hover'), findsOneWidget);

    await tester.tap(find.byType(Hoverable));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/widgets/common/hoverable_test.dart` → 编译失败

- [ ] **Step 3: 实现**

`lib/widgets/common/hoverable.dart` 完整内容：

```dart
import 'package:flutter/material.dart';

/// 自定义可点击区域的 hover/光标包装器。
/// 解决 GestureDetector 无悬停反馈的问题：builder 拿到 hovered 状态自行渲染。
class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final MouseCursor cursor;

  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapUp,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过** → PASS

- [ ] **Step 5: 提交**

```bash
flutter analyze && git add lib/widgets/common/hoverable.dart test/widgets/common/hoverable_test.dart
git commit -m "feat(widgets): add Hoverable wrapper for hover feedback"
```

---

### Task 4: AppButton 组件

**Files:**
- Create: `lib/widgets/common/app_button.dart`
- Test: `test/widgets/common/app_button_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/app_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('renders label and fires onPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(wrap(AppButton(
      label: 'Save',
      onPressed: () => pressed = true,
    )));
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(pressed, isTrue);
  });

  testWidgets('disabled button renders at reduced opacity', (tester) async {
    await tester.pumpWidget(wrap(const AppButton(
      label: 'Save',
      onPressed: null,
    )));
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Save'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0.4);
  });

  testWidgets('shows tooltip and icon', (tester) async {
    await tester.pumpWidget(wrap(const AppButton(
      label: 'Start',
      icon: Icons.play_arrow,
      tooltip: 'Start capture',
      onPressed: null,
    )));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败** → 编译失败

- [ ] **Step 3: 实现**

`lib/widgets/common/app_button.dart` 完整内容：

```dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'hoverable.dart';

enum AppButtonVariant { primary, secondary, destructive }

/// 统一按钮。primary=实心主色（主操作）；secondary=描边（普通操作）；
/// destructive=红色文字（删除/清空）。内建 hover/pressed/光标/tooltip。
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final String? tooltip;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.secondary,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final enabled = onPressed != null;

    Widget button = Hoverable(
      onTap: onPressed,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) {
        final hover = hovered && enabled;
        final (Color bg, Color fg, Border? border) = switch (variant) {
          AppButtonVariant.primary => (
              hover ? colors.primary.withValues(alpha: 0.85) : colors.primary,
              Colors.white, // 有色底上的前景色，明暗模式均适用（刻意例外）
              null,
            ),
          AppButtonVariant.secondary => (
              hover ? colors.divider.withValues(alpha: 0.35) : Colors.transparent,
              colors.textPrimary,
              Border.all(color: colors.divider, width: 0.5),
            ),
          AppButtonVariant.destructive => (
              hover ? colors.diffRemoved.withValues(alpha: 0.12) : Colors.transparent,
              colors.diffRemoved,
              Border.all(color: colors.divider, width: 0.5),
            ),
        };

        return Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            height: AppTheme.sizing.searchFieldHeight,
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
            decoration: BoxDecoration(
              color: bg,
              border: border,
              borderRadius: BorderRadius.circular(AppTheme.radius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppTheme.sizing.iconSize, color: fg),
                  SizedBox(width: AppTheme.spacing.xs),
                ],
                Text(label,
                    style: TextStyle(fontSize: AppTheme.fontSize.md, color: fg)),
              ],
            ),
          ),
        );
      },
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }
    return button;
  }
}
```

- [ ] **Step 4: 运行测试确认通过** → PASS ×3

- [ ] **Step 5: 提交**

```bash
flutter analyze && git add lib/widgets/common/app_button.dart test/widgets/common/app_button_test.dart
git commit -m "feat(widgets): add AppButton with variants and hover feedback"
```

---

### Task 5: AppTextField 组件

**Files:**
- Create: `lib/widgets/common/app_text_field.dart`
- Test: `test/widgets/common/app_text_field_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/app_text_field.dart';

void main() {
  testWidgets('renders hint, forwards onChanged', (tester) async {
    String? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTextField(hintText: 'Search...', onChanged: (v) => changed = v),
      ),
    ));
    expect(find.text('Search...'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abc');
    expect(changed, 'abc');
  });
}
```

- [ ] **Step 2: 运行确认失败** → 编译失败

- [ ] **Step 3: 实现**

`lib/widgets/common/app_text_field.dart` 完整内容：

```dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 统一输入框：isDense、radius.md 圆角、divider 边框、聚焦主色边框。
/// 取代各页手写的 InputDecoration。
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final int maxLines;

  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.maxLines = 1,
  });

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius.md),
        borderSide: BorderSide(color: color, width: 0.5),
      );

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLines: maxLines,
      style: TextStyle(fontSize: AppTheme.fontSize.md),
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffix: suffix,
        isDense: true,
        filled: true,
        fillColor: colors.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacing.sm,
          vertical: AppTheme.spacing.sm,
        ),
        border: _border(colors.divider),
        enabledBorder: _border(colors.divider),
        focusedBorder: _border(colors.primary),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过** → PASS

- [ ] **Step 5: 提交**

```bash
flutter analyze && git add lib/widgets/common/app_text_field.dart test/widgets/common/app_text_field_test.dart
git commit -m "feat(widgets): add AppTextField with unified decoration"
```

---

### Task 6: AppTabBar 组件

**Files:**
- Create: `lib/widgets/common/app_tab_bar.dart`
- Test: `test/widgets/common/app_tab_bar_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/app_tab_bar.dart';

void main() {
  testWidgets('renders tabs, highlights active, fires onChanged', (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTabBar(
          tabs: const ['List', 'Waterfall'],
          activeIndex: 0,
          onChanged: (i) => selected = i,
        ),
      ),
    ));
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Waterfall'), findsOneWidget);
    await tester.tap(find.text('Waterfall'));
    expect(selected, 1);
  });

  testWidgets('renders optional leading label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTabBar(
          tabs: const ['Headers', 'Body'],
          activeIndex: 0,
          onChanged: (_) {},
          label: 'REQUEST',
        ),
      ),
    ));
    expect(find.text('REQUEST'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败** → 编译失败

- [ ] **Step 3: 实现**

`lib/widgets/common/app_tab_bar.dart` 完整内容：

```dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'hoverable.dart';

/// 统一分段式 Tab（macOS segmented control 观感）。
/// 选中项 = detailTab.activeBackground 胶囊；未选中 hover 时浅背景。
/// 可选 [label] 在最左侧显示分组标签（如 REQUEST / RESPONSE）。
class AppTabBar extends StatelessWidget {
  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final String? label;
  final double? fontSize;

  const AppTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
    this.label,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final detailTab = AppTheme.mode(context).detailTab;
    final size = fontSize ?? AppTheme.fontSize.sm;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!,
              style: TextStyle(
                fontSize: AppTheme.fontSize.xs,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppTheme.colors(context).textSecondary,
              )),
          SizedBox(width: AppTheme.spacing.sm),
        ],
        ...List.generate(tabs.length, (i) {
          final isActive = activeIndex == i;
          return Padding(
            padding: EdgeInsets.only(right: i < tabs.length - 1 ? 2 : 0),
            child: Hoverable(
              onTap: () => onChanged(i),
              builder: (context, hovered) => Container(
                padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.md, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? detailTab.activeBackground
                      : hovered
                          ? detailTab.activeBackground.withValues(alpha: 0.5)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(detailTab.radius),
                ),
                child: Text(tabs[i],
                    style: TextStyle(
                      fontSize: size,
                      fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                      color: isActive
                          ? detailTab.activeText
                          : detailTab.inactiveText,
                    )),
              ),
            ),
          );
        }),
      ],
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过** → PASS ×2

- [ ] **Step 5: 提交**

```bash
flutter analyze && git add lib/widgets/common/app_tab_bar.dart test/widgets/common/app_tab_bar_test.dart
git commit -m "feat(widgets): add AppTabBar segmented control"
```

---

### Task 7: EmptyState 组件

**Files:**
- Create: `lib/widgets/common/empty_state.dart`
- Test: `test/widgets/common/empty_state_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/common/empty_state.dart';

void main() {
  testWidgets('renders icon, title, description and action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.inbox,
          title: 'No requests',
          description: 'Start capturing to see traffic',
          action: TextButton(onPressed: () {}, child: const Text('Start')),
        ),
      ),
    ));
    expect(find.byIcon(Icons.inbox), findsOneWidget);
    expect(find.text('No requests'), findsOneWidget);
    expect(find.text('Start capturing to see traffic'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('description and action are optional', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EmptyState(icon: Icons.inbox, title: 'Empty')),
    ));
    expect(find.text('Empty'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败** → 编译失败

- [ ] **Step 3: 实现**

`lib/widgets/common/empty_state.dart` 完整内容（以 `map_local_page.dart:56-79` 现有精致版为基准）：

```dart
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 统一空状态：图标 + 标题 + 可选描述 + 可选操作。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colors.textSecondary.withValues(alpha: 0.6)),
          SizedBox(height: AppTheme.spacing.sm),
          Text(title,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AppTheme.fontSize.md,
                fontWeight: FontWeight.w500,
              )),
          if (description != null) ...[
            SizedBox(height: AppTheme.spacing.xs),
            Text(description!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary.withValues(alpha: 0.8),
                  fontSize: AppTheme.fontSize.sm,
                )),
          ],
          if (action != null) ...[
            SizedBox(height: AppTheme.spacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过** → PASS ×2

- [ ] **Step 5: 提交**

```bash
flutter analyze && git add lib/widgets/common/empty_state.dart test/widgets/common/empty_state_test.dart
git commit -m "feat(widgets): add EmptyState component"
```

---

### Task 8: 死代码清理 + status_bar 复用 ConnectionIndicator

**Files:**
- Delete: `lib/widgets/json_viewer.dart`、`test/widgets/json_viewer_test.dart`
- Modify: `lib/pages/capture/status_bar.dart`

- [ ] **Step 1: 删除死代码**

```bash
git rm lib/widgets/json_viewer.dart test/widgets/json_viewer_test.dart
```

- [ ] **Step 2: status_bar 复用 ConnectionIndicator**

`lib/pages/capture/status_bar.dart`：`ConnectionIndicator` 组件（`lib/widgets/connection_indicator.dart`）渲染「圆点 + 状态文字」，而 status_bar 目前只要圆点还手写了 switch。改法：

(a) 添加 import：`import '../../widgets/connection_indicator.dart';`

(b) 删除 :37-41 的 `dotColor` switch 和 :44-45 的手写圆点 Container + SizedBox，替换为：

```dart
            ConnectionIndicator(status: wsStatus),
            _sep(context),
```

即 Row 的 children 开头变为 `ConnectionIndicator(status: wsStatus), _sep(context), _item(context, 'Listening on :...'), ...`。`themeColors` 变量仍被下载/上传速度文字使用，保留。视觉变化：圆点旁多出状态文字（connected/connecting/disconnected 的 i18n 文案）——这是设计允许的增强。

- [ ] **Step 3: 验证并提交**

```bash
flutter analyze && flutter test
git add -A && git commit -m "refactor: remove dead JsonViewer, reuse ConnectionIndicator in status bar"
```

---

### Task 9: capture 主页 — global_bar

**Files:**
- Modify: `lib/pages/capture/global_bar.dart`

改动全部围绕审计定位。每处改完保持 `flutter analyze` 干净。

- [ ] **Step 1: Start/Stop 按钮加 tooltip + hover（:347-372 `_StartStopButton`）**

用 `Hoverable` + `Tooltip` 重写 build（import `../../widgets/common/hoverable.dart`）：

```dart
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final capturing = taskCtrl.isCapturing.value;
      final color = capturing
          ? AppTheme.methodColorOf(context, 'DELETE')
          : AppTheme.methodColorOf(context, 'GET');
      return Tooltip(
        message: capturing ? 'toolbar.stop'.tr : 'toolbar.start'.tr,
        waitDuration: const Duration(milliseconds: 500),
        child: Hoverable(
          onTap: () => taskCtrl.toggleCapture(),
          builder: (context, hovered) => Container(
            width: AppTheme.sizing.iconButtonSize,
            height: AppTheme.sizing.iconButtonSize,
            decoration: BoxDecoration(
              color: hovered ? color.withValues(alpha: 0.85) : color,
              borderRadius: BorderRadius.circular(AppTheme.radius.md),
            ),
            child: Icon(
              capturing ? Icons.stop : Icons.play_arrow,
              size: 14,
              color: Colors.white, // 有色底上的前景色（刻意例外）
            ),
          ),
        ),
      );
    });
  }
```

（`toolbar.start`/`toolbar.stop` 键已存在于 translations.dart。圆角 5 → `AppTheme.radius.md`=6。）

- [ ] **Step 2: TabChip hover + 抓包红点用主题色 + 关闭按钮反馈（:173-239）**

(a) `_TabChip.build` 里最外层 `GestureDetector` 换成 `Hoverable`（onTap/onSecondaryTapUp 参数直接搬），Container 的 `color` 改为：

```dart
          color: isActive
              ? colors.surface
              : hovered
                  ? colors.surface.withValues(alpha: 0.5)
                  : Colors.transparent,
```

(b) :210 `color: Colors.red` → `color: AppTheme.colors(context).statusDisconnected`（该 Container 的 decoration 因此去掉 `const`）。

(c) :229-235 关闭按钮：外面包 `Tooltip(message: 'tab.close'.tr, waitDuration: const Duration(milliseconds: 500), child: ...)`，`GestureDetector` 换成 `Hoverable`，builder 返回：

```dart
                      Icon(Icons.close, size: 12,
                          color: hovered ? colors.textPrimary : colors.textSecondary),
```

- [ ] **Step 3: 删除确认按钮红色语义化（:321）**

`TextButton.styleFrom(foregroundColor: Colors.red)` → `TextButton.styleFrom(foregroundColor: AppTheme.colors(ctx).diffRemoved)`。

- [ ] **Step 4: 设置弹窗关闭按钮补 tooltip（:135-139）**

`IconButton` 加 `tooltip: 'action.close'.tr,`。检查 translations.dart 是否已有 `action.close`；若无，在 enUS 加 `'action.close': 'Close',`、zhCN 加 `'action.close': '关闭',`。

- [ ] **Step 5: Import HAR 对话框输入框换 AppTextField（:591-597）**

`TextField(controller: controller, decoration: InputDecoration(hintText: ..., labelText: ...))` → `AppTextField(controller: controller, hintText: 'import.har_path_hint'.tr, labelText: 'import.har_path_label'.tr)`（import `../../widgets/common/app_text_field.dart`）。

- [ ] **Step 6: 验证并提交**

```bash
flutter analyze && flutter test
git add -A && git commit -m "feat(capture): global bar polish — hover states, tooltips, theme colors"
```

---

### Task 10: capture 主页 — flow_table + capture_page（复制反馈 + 信息层级 + 空状态）

**Files:**
- Modify: `lib/pages/capture/flow_table.dart`
- Modify: `lib/pages/capture/capture_page.dart`
- Modify: `lib/i18n/translations.dart`（如需）

- [ ] **Step 1: 复制 cURL 后弹 toast**

(a) `flow_table.dart:347-349`（右键菜单 `.then` 回调内）：

```dart
      } else if (value == 'curl') {
        final curl = "curl -X ${flow.method} '${flow.protocol.toLowerCase()}://${flow.host}${flow.uri}'";
        Clipboard.setData(ClipboardData(text: curl));
        showAppToast(context, 'detail.curl_copied'.tr);
      }
```

import `../../widgets/common/app_toast.dart`。`detail.curl_copied` 键已存在。

(b) `capture_page.dart:195-206`（`CopyAsCurlIntent` 回调）：`Clipboard.setData(...)` 后加同样一行 `showAppToast(context, 'detail.curl_copied'.tr);`。该回调在 `Actions` 内，确认作用域里有 `context`（`build` 的 context 可用；若回调签名拿不到 context，用 `Builder` 内的 context 或把 `showAppToast` 调用放到能拿到 context 的层级——`CallbackAction` 的 onInvoke 在 build 作用域内定义，直接引用外层 `context` 即可）。

- [ ] **Step 2: 表格行信息层级（:228-254 `_buildRow`）**

- host 列（:231-232）：style 加 `fontWeight: FontWeight.w500`。
- time（:246-247）、duration（:249-251）、size（:253-254）三列：style 加 `color: AppTheme.colors(context).textSecondary`。
- 其余列不动（method/status 已有彩色，protocol/uri 保持默认）。

- [ ] **Step 3: 表头字重（:174-177 `_headerCell`）**

`fontWeight: FontWeight.bold` → `FontWeight.w600`，并加 `color: AppTheme.colors(context).textSecondary`。注意 `_headerCell` 签名没有 context——它是 `_FlowTableState` 的方法，State 有 `this.context` 可直接用 `AppTheme.colors(context)`。

- [ ] **Step 4: 空状态升级（:100-110）**

`Center(child: Text('empty.no_requests'.tr, ...))` → `EmptyState(icon: Icons.inbox_outlined, title: 'empty.no_requests'.tr, description: 'home.start_hint'.tr)`（两个键都已存在；import `../../widgets/common/empty_state.dart`）。

- [ ] **Step 5: 颜色标签描边修正（:533）**

`_ColorSubmenu` 里 `Border.all(color: Colors.white24)` → `Border.all(color: AppTheme.colors(context).divider)`。

- [ ] **Step 6: 验证并提交**

```bash
flutter analyze && flutter test
git add -A && git commit -m "feat(capture): copy-curl toast, flow table hierarchy, empty state"
```

---

### Task 11: capture 主页 — content_panel / flow_detail_panel / filter_bar（Tab 统一 + chip 反馈）

**Files:**
- Modify: `lib/pages/capture/content_panel.dart`
- Modify: `lib/pages/capture/flow_detail_panel.dart`
- Modify: `lib/pages/capture/filter_bar.dart`

- [ ] **Step 1: content_panel Tab 换 AppTabBar（:53-84）**

`Row(children: List.generate(tabs.length, ...))` 整块替换为：

```dart
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppTabBar(
                tabs: tabs,
                activeIndex: activeTab,
                onChanged: panelCtrl.switchTab,
              ),
            ),
```

删除不再使用的 `detailTab` 局部变量（:17）。TCP 占位空状态（:22-38）换成 `EmptyState(icon: Icons.dns_outlined, title: 'tab.tcp_coming_soon'.tr)`。

- [ ] **Step 2: flow_detail_panel 两处 Tab 换 AppTabBar**

(a) `_tabButton`（:137-163）及其调用处（:121-131）：Obx 内 Row 替换为：

```dart
            return AppTabBar(
              tabs: ['detail.data'.tr, 'detail.details'.tr],
              activeIndex: active,
              onChanged: panelCtrl.switchTab,
              fontSize: AppTheme.fontSize.xs,
            );
```

删除 `_tabButton` 方法和 build 里不再使用的 `detailTab` 变量。

(b) `_SubTabBar`（:298-362）：保留类与签名（label/tabs/activeIndex/onTap），内部 Obx 的 Row 替换为：

```dart
        return AppTabBar(
          tabs: tabs,
          activeIndex: activeIndex.value,
          onChanged: onTap,
          label: label,
          fontSize: AppTheme.fontSize.xs,
        );
```

删除类内不再使用的 `detailTab` 变量。

(c) :806 附近的 `fontSize: 10` → `AppTheme.fontSize.xs`；:103/:106 的 `EdgeInsets.symmetric(horizontal: 5, vertical: 1)` → `EdgeInsets.symmetric(horizontal: AppTheme.spacing.xs, vertical: 1)`、`BorderRadius.circular(3)` → `BorderRadius.circular(AppTheme.radius.sm)`。

- [ ] **Step 3: filter_bar chip 加 hover + 光标（:203-226 `_chip`）**

`GestureDetector` → `Hoverable`，Container `color` 改为：

```dart
            color: isActive
                ? chipConfig.activeBackground
                : hovered
                    ? chipConfig.activeBackground.withValues(alpha: 0.4)
                    : chipConfig.inactiveBackground,
```

- [ ] **Step 4: filter_bar 搜索框换 AppTextField（:156-196）**

`TextField` 整块换成 `AppTextField`，传 `controller: _searchController, focusNode: widget.searchFocusNode, hintText: 'toolbar.search'.tr, prefixIcon: const Icon(Icons.search, size: 16), onChanged: (v) { setState(() {}); tableCtrl.search(v); }`，`suffix` 传原来的 ⌘F 提示 Text（searchExpanded 时）。原 InputDecoration 使用 `radius.md`、聚焦主色边框与 AppTextField 默认一致，视觉不变。

- [ ] **Step 5: 验证并提交**

```bash
flutter analyze && flutter test
git add -A && git commit -m "feat(capture): unify tabs with AppTabBar, filter chip hover, search field"
```

---

### Task 12: capture 主页 — tree_panel / waterfall_tab / dashboard_tab

**Files:**
- Modify: `lib/pages/capture/tree_panel.dart`
- Modify: `lib/pages/capture/waterfall_tab.dart`
- Modify: `lib/pages/capture/dashboard_tab.dart`

- [ ] **Step 1: tree_panel 星标色 + 空状态**

- :398 `const Color(0xFFFFC107)` → `AppTheme.colors(context).favorite`（去掉相应 const）。
- :47 附近的一行灰字空状态 → `EmptyState(icon: Icons.account_tree_outlined, title: <原文案>)`（保留原 i18n 键）。

- [ ] **Step 2: waterfall_tab 空状态（:316 附近）**

一行灰字 → `EmptyState(icon: Icons.waterfall_chart, title: <原文案>)`。canvas 内部 14 色调色板与 `fontSize: 9/8` **不动**（spec 明确不做）。

- [ ] **Step 3: dashboard_tab 字号与颜色**

- :114 `fontSize: 18` 与 :160 `fontSize: 20` → `AppTheme.fontSize.xxl`（两处统一为 20，视觉差异 +2px 可接受）。
- :131 `color: Colors.white`（饼图 title 文字，画在彩色扇区上）→ 保留但加注释 `// 有色扇区上的前景色（刻意例外）`。
- :124/:142 `Text('empty.no_data'.tr)` 空状态保持行内形式（图表区域太小不适合 48px 图标版），但加 `style: TextStyle(color: AppTheme.colors(context).textSecondary, fontSize: AppTheme.fontSize.sm)`；若无法取到 context 则用 Builder 包裹。

- [ ] **Step 4: 验证并提交**

```bash
flutter analyze && flutter test
git add -A && git commit -m "feat(capture): tree/waterfall/dashboard polish — theme colors, empty states"
```

---

### Task 13: compose_page + history_page

**Files:**
- Modify: `lib/pages/compose/compose_page.dart`
- Modify: `lib/pages/history/history_page.dart`

- [ ] **Step 1: compose body tabs 换 AppTabBar（:404-436）**

`_buildBodyTabs` 整个方法体替换为：

```dart
  Widget _buildBodyTabs(ThemeData theme) {
    final labels = ['tab.raw'.tr, 'tab.json'.tr, 'tab.form'.tr];
    return AppTabBar(
      tabs: labels,
      activeIndex: _bodyTab,
      onChanged: (i) => setState(() => _bodyTab = i),
    );
  }
```

（compose 原本带边框的 tab 样式改为与全应用一致的胶囊样式——spec 明确统一。）

- [ ] **Step 2: compose 其余控件**

通读 `compose_page.dart`，将手写 `InputDecoration` 的 TextField（URL 输入 :378 附近、key-value 编辑器 :459/:477 附近等）换成 `AppTextField`（保留各自 controller/hint/onChanged）；Send 等主操作 `ElevatedButton` → `AppButton(variant: AppButtonVariant.primary, ...)`；普通 `TextButton` → `AppButton`（secondary）。若某处 TextField 有 AppTextField 未覆盖的参数（如 keyboardType、expands），保留原样并继续。

- [ ] **Step 3: history_page 颜色与空状态**

- :128/:144 `Colors.red` → `AppTheme.colors(context).diffRemoved`（删除按钮语义）。
- :211-212 `Colors.white` / `Colors.black.withAlpha(30)`：查看上下文——若是彩色底上的前景/遮罩则保留加注释，否则映射主题色。
- :301 同上处理。
- :266 一行灰字空状态 → `EmptyState(icon: Icons.history, title: <原 i18n 文案>)`。
- 各 `IconButton` 补 `tooltip:`（用已有 i18n 键如 `action.delete`；缺键则在 translations.dart 补 enUS/zhCN）。

- [ ] **Step 4: 验证并提交**

```bash
flutter analyze && flutter test
git add -A && git commit -m "feat(pages): compose and history polish — unified controls"
```

注意：`test/pages/compose_test.dart` 若断言了旧控件类型（如 `find.byType(ElevatedButton)`），同步更新断言为 `AppButton`。

---

### Task 14: tools 五页 + settings

**Files:**
- Modify: `lib/pages/tools/map_local_page.dart`、`map_remote_page.dart`、`breakpoint_page.dart`、`breakpoint_dialog.dart`、`allow_block_page.dart`、`diff_page.dart`
- Modify: `lib/pages/settings/settings_page.dart`

- [ ] **Step 1: 四个 tools 页空状态换 EmptyState**

`map_local_page.dart:55-80`、`map_remote_page.dart:63` 附近、`breakpoint_page.dart:63` 附近的手写「图标+标题+描述」Column → `EmptyState(icon: <原图标>, title: <原标题>.tr, description: <原描述>.tr)`；`allow_block_page.dart:124` 附近是一行文字空状态，同样升级为 `EmptyState`（图标选 `Icons.filter_list`）。

- [ ] **Step 2: tools 页按钮/输入框统一**

各页「添加规则」等 `TextButton.icon(style: TextButton.styleFrom(minimumSize...))` → `AppButton(icon: ..., label: ..., onPressed: ...)`（主操作用 primary）；对话框内手写 InputDecoration 的 TextField → `AppTextField`；删除按钮 → `AppButton(variant: AppButtonVariant.destructive)` 或 IconButton 加 tooltip。`diff_page.dart` 唯一的 `FilledButton` → `AppButton(variant: AppButtonVariant.primary)`。

- [ ] **Step 3: 硬编码颜色映射**

- `breakpoint_dialog.dart:69` `Colors.orange` → `AppTheme.colors(context).statusConnecting`；:167 `Colors.red` → `.diffRemoved`；:183 `Colors.green` → `.diffAdded`；:184 `Colors.white` → 若为彩色底前景则保留加注释。
- `diff_page.dart:309-317`：`Colors.red.withValues(...)` / `Colors.green.withValues(...)` / `Colors.red.shade700` → `AppTheme.colors(context).diffRemoved.withValues(alpha: <原值>)` / `.diffAdded.withValues(...)` / `.diffRemoved`。
- `allow_block_page.dart` 的 Material `TabBar`（两个模式切换）→ `AppTabBar`。注意该页目前是无状态的 `DefaultTabController` + `TabBar` + `TabBarView`，没有现成的 index 状态：需改为 `StatefulWidget`，用 `int _tabIndex` + `AppTabBar(activeIndex: _tabIndex, onChanged: (i) => setState(...))` + `IndexedStack` 替代 `DefaultTabController`/`TabBarView`，页面内其余逻辑不变。

- [ ] **Step 4: settings_page 证书状态色（:62-64, :82）**

```dart
            final colors = AppTheme.colors(context);
            final (icon, color, label) = switch (status) {
              CertStatus.trusted => (Icons.verified, colors.statusConnected, 'settings.cert_trusted'.tr),
              CertStatus.installed => (Icons.warning_amber, colors.statusConnecting, 'settings.cert_installed'.tr),
              CertStatus.none => (Icons.cancel_outlined, colors.statusDisconnected, 'settings.cert_not_installed'.tr),
              CertStatus.checking => (Icons.hourglass_empty, theme.hintColor, 'settings.cert_checking'.tr),
            };
```

:82 `const Icon(Icons.check_circle, color: Color(0xFF34C759), size: 18)` → `Icon(Icons.check_circle, color: colors.statusConnected, size: 18)`。设置页的 `SegmentedButton`（主题切换）保留——它就是 macOS 风格，无需替换。安装/导出 `TextButton.icon` → `AppButton`。

注意：`test/pages/diff_test.dart` 若断言 FilledButton/颜色，同步更新。

- [ ] **Step 5: 验证并提交**

```bash
flutter analyze && flutter test
git add -A && git commit -m "feat(tools,settings): unified components, theme colors, empty states"
```

---

### Task 15: 收尾验证

**Files:** 无新改动（除非发现问题）

- [ ] **Step 1: 全量静态检查与测试**

```bash
flutter analyze          # 期望 No issues found!
flutter test             # 期望全部通过
```

- [ ] **Step 2: 残留硬编码扫描**

```bash
grep -rn "Colors\.red\|Colors\.green\|Colors\.orange\|Colors\.white24\|Color(0xFF34C759)\|Color(0xFFFF9F0A)\|Color(0xFFFF3B30)\|Color(0xFFFFC107)" lib/pages/ lib/widgets/common/
```

期望：仅剩带「刻意例外」注释的 `Colors.white`（有色底前景）；waterfall_tab canvas 调色板不在扫描范围（spec 排除）。发现漏网就地修复。

- [ ] **Step 3: 真机运行人工验收**

```bash
flutter run -d macos
```

检查清单（光/暗两套主题各过一遍，Settings → Theme 切换）：
1. 工具栏 Start/Stop hover 变色、tooltip 出现；tab chip hover 有浅背景；tab 关闭 X hover 变色。
2. 右键流量行 → Copy as cURL → 屏幕下方出现 toast 并 2 秒消失；快捷键复制同样有 toast。
3. List/Waterfall/Dashboard tab、详情 Data/Details tab、REQUEST/RESPONSE 子 tab 观感一致，未选中项 hover 有反馈。
4. 流量表格：host 加粗可辨，time/duration/size 呈灰色次要观感。
5. 无任务时流量表 / 域名树 / 历史页显示图标式空状态。
6. Compose body tabs、tools 页按钮与输入框和主界面观感一致。
7. 设置页证书状态色随主题正常显示。

- [ ] **Step 4: 修复发现的问题并提交**

发现问题就地修复，跑 analyze + test，然后：

```bash
git add -A && git commit -m "fix: post-verification UI polish fixes"
```

（若无问题，此步跳过。）

---

## 完成后

按 superpowers:finishing-a-development-branch 流程决定合并方式（当前分支 `feature/flutter-ui`，主分支 `master`）。
