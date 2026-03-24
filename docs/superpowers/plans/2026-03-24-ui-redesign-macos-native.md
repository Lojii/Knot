# Knot UI Redesign — macOS Native Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Knot's UI from generic Material 3 to a polished macOS-native aesthetic with all styling driven by an external JSON theme file.

**Architecture:** Create `assets/theme.json` containing all visual tokens. Rewrite `AppTheme` as a singleton that loads and parses this JSON at startup, exposing typed getters. Then migrate each UI component to read from the new theme system and apply the macOS-native visual spec.

**Tech Stack:** Flutter, Dart, GetX, google_fonts, fl_chart, multi_split_view

**Spec:** `docs/superpowers/specs/2026-03-24-ui-redesign-macos-native-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `assets/theme.json` | All visual tokens (colors, sizing, spacing, fonts, radii, component-specific styles) for light & dark themes | Create |
| `pubspec.yaml` | Register `assets/theme.json` as a Flutter asset | Modify |
| `lib/theme/app_theme.dart` | JSON-driven theme singleton: load, parse, expose typed getters, build `ThemeData` | Rewrite |
| `lib/main.dart` | Async theme initialization before `runApp` | Modify |
| `test/theme/app_theme_test.dart` | Unit tests for JSON parsing, hex conversion, fallback defaults | Create |
| `lib/pages/capture/global_bar.dart` | Gradient toolbar, icon style, connection dot | Modify |
| `lib/pages/capture/toolbar.dart` | Gradient, rounded button style, search field | Modify |
| `lib/pages/capture/filter_bar.dart` | Chip style, remove labels | Modify |
| `lib/pages/capture/flow_table.dart` | Header gradient, selection indicator, hover | Modify |
| `lib/pages/capture/tree_panel.dart` | Selection highlight, section headers, chevron | Modify |
| `lib/pages/capture/flow_detail_panel.dart` | Segmented tab style, section titles | Modify |
| `lib/pages/capture/status_bar.dart` | Gradient, middle dot separator, dot size | Modify |
| `lib/pages/capture/content_panel.dart` | Tab style alignment | Modify |
| `lib/pages/capture/capture_page.dart` | Minor scaffold background | Modify |
| `lib/pages/capture/waterfall_tab.dart` | Timing colors from theme | Modify |
| `lib/pages/capture/dashboard_tab.dart` | Chart colors, card style from theme | Modify |
| `lib/widgets/connection_indicator.dart` | Dot size 6px, colors from theme | Modify |
| `lib/widgets/key_value_table.dart` | Tighter spacing | Modify |
| `lib/widgets/json_viewer.dart` | Syntax colors from theme | Modify |
| `lib/widgets/body_viewer.dart` | Mode toggle style from theme | Modify |
| `lib/widgets/waterfall_bar.dart` | Timing colors from theme | Modify |

---

### Task 1: Create `assets/theme.json` and register in pubspec

**Files:**
- Create: `assets/theme.json`
- Modify: `pubspec.yaml:59-64`

- [ ] **Step 1: Create `assets/` directory**

Run: `mkdir -p assets`

- [ ] **Step 2: Create `assets/theme.json`**

Write the full JSON from the spec. Both `light` and `dark` theme blocks, plus shared `sizing`, `spacing`, `fontSize`, `fontFamily`, and `radius` sections.

```json
{
  "light": {
    "colors": {
      "scaffold": "#F5F5F7",
      "surface": "#FFFFFF",
      "divider": "#D1D1D6",
      "primary": "#007AFF",
      "textPrimary": "#1D1D1F",
      "textSecondary": "#86868B",
      "method": {
        "GET": "#34C759",
        "POST": "#FF9F0A",
        "PUT": "#007AFF",
        "DELETE": "#FF3B30",
        "PATCH": "#AF52DE",
        "default": "#8E8E93"
      },
      "status": {
        "2xx": "#34C759",
        "3xx": "#007AFF",
        "4xx": "#FF9F0A",
        "5xx": "#FF3B30",
        "default": "#8E8E93"
      },
      "protocol": {
        "HTTP": "#007AFF",
        "HTTPS": "#34C759",
        "H2": "#FF9F0A",
        "WS": "#AF52DE",
        "WSS": "#FF3B30"
      },
      "connection": {
        "connected": "#34C759",
        "connecting": "#FF9F0A",
        "disconnected": "#FF3B30"
      },
      "timing": {
        "connect": "#FF9F0A",
        "tls": "#AF52DE",
        "request": "#007AFF",
        "ttfb": "#34C759",
        "response": "#30D158"
      },
      "syntax": {
        "key": "#0A2463",
        "string": "#2E7D32",
        "number": "#E65100",
        "boolean": "#6A1B9A"
      }
    },
    "toolbar": {
      "gradient": { "start": "#FAFAFA", "end": "#EBEBEB" },
      "borderWidth": 0.5
    },
    "table": {
      "headerGradient": { "start": "#F4F4F5", "end": "#EAEAEB" },
      "selectedBackground": "#007AFF14",
      "selectedIndicatorWidth": 2,
      "selectedIndicatorColor": "#007AFF"
    },
    "tree": {
      "selectedBackground": "#007AFF",
      "selectedText": "#FFFFFF",
      "selectedRadius": 5
    },
    "filterChip": {
      "activeBackground": "#007AFF1F",
      "activeBorder": "transparent",
      "activeText": "#007AFF",
      "inactiveBackground": "transparent",
      "inactiveBorder": "#D1D1D6"
    },
    "detailTab": {
      "activeBackground": "#E8E8ED",
      "activeText": "#1D1D1F",
      "inactiveText": "#86868B",
      "radius": 5
    }
  },
  "dark": {
    "colors": {
      "scaffold": "#1C1C1E",
      "surface": "#2C2C2E",
      "divider": "#38383A",
      "primary": "#0A84FF",
      "textPrimary": "#F5F5F7",
      "textSecondary": "#98989D",
      "method": {
        "GET": "#30D158",
        "POST": "#FF9F0A",
        "PUT": "#0A84FF",
        "DELETE": "#FF453A",
        "PATCH": "#BF5AF2",
        "default": "#8E8E93"
      },
      "status": {
        "2xx": "#30D158",
        "3xx": "#0A84FF",
        "4xx": "#FF9F0A",
        "5xx": "#FF453A",
        "default": "#8E8E93"
      },
      "protocol": {
        "HTTP": "#0A84FF",
        "HTTPS": "#30D158",
        "H2": "#FF9F0A",
        "WS": "#BF5AF2",
        "WSS": "#FF453A"
      },
      "connection": {
        "connected": "#30D158",
        "connecting": "#FF9F0A",
        "disconnected": "#FF453A"
      },
      "timing": {
        "connect": "#FF9F0A",
        "tls": "#BF5AF2",
        "request": "#0A84FF",
        "ttfb": "#30D158",
        "response": "#34C759"
      },
      "syntax": {
        "key": "#82AAFF",
        "string": "#C3E88D",
        "number": "#F78C6C",
        "boolean": "#C792EA"
      }
    },
    "toolbar": {
      "gradient": { "start": "#2C2C2E", "end": "#232325" },
      "borderWidth": 0.5
    },
    "table": {
      "headerGradient": { "start": "#2C2C2E", "end": "#262628" },
      "selectedBackground": "#0A84FF1F",
      "selectedIndicatorWidth": 2,
      "selectedIndicatorColor": "#0A84FF"
    },
    "tree": {
      "selectedBackground": "#0A84FF",
      "selectedText": "#FFFFFF",
      "selectedRadius": 5
    },
    "filterChip": {
      "activeBackground": "#0A84FF26",
      "activeBorder": "transparent",
      "activeText": "#0A84FF",
      "inactiveBackground": "transparent",
      "inactiveBorder": "#38383A"
    },
    "detailTab": {
      "activeBackground": "#38383A",
      "activeText": "#F5F5F7",
      "inactiveText": "#98989D",
      "radius": 5
    }
  },
  "sizing": {
    "globalBarHeight": 38,
    "toolbarHeight": 38,
    "filterBarHeight": 34,
    "statusBarHeight": 26,
    "tableRowHeight": 26,
    "tableHeaderHeight": 28,
    "detailTabHeight": 28,
    "treeDefaultWidth": 220,
    "macOSTrafficLightWidth": 78,
    "iconSize": 16,
    "iconButtonSize": 22,
    "connectionDotSize": 6,
    "searchFieldWidth": 240,
    "searchFieldHeight": 28
  },
  "spacing": {
    "xs": 4,
    "sm": 8,
    "md": 12,
    "lg": 16,
    "xl": 24
  },
  "fontSize": {
    "xs": 10,
    "sm": 11,
    "md": 12,
    "lg": 13,
    "xl": 14
  },
  "fontFamily": {
    "ui": "Inter",
    "mono": "JetBrains Mono",
    "uiLetterSpacing": -0.2
  },
  "radius": {
    "sm": 4,
    "md": 6,
    "lg": 8,
    "popup": 10
  }
}
```

- [ ] **Step 3: Register asset in `pubspec.yaml`**

In `pubspec.yaml`, under the `flutter:` section, add the assets key:

```yaml
flutter:
  uses-material-design: true

  assets:
    - assets/theme.json
```

- [ ] **Step 4: Verify asset loads**

Run: `flutter pub get`
Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add assets/theme.json pubspec.yaml
git commit -m "feat: add theme.json asset with macOS-native color tokens"
```

---

### Task 2: Rewrite `AppTheme` as JSON-driven singleton

**Files:**
- Rewrite: `lib/theme/app_theme.dart`
- Create: `test/theme/app_theme_test.dart`

- [ ] **Step 1: Write failing tests for theme loading**

Create `test/theme/app_theme_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/theme/app_theme.dart';

void main() {
  group('AppTheme hex parsing', () {
    test('parseHex parses 6-digit hex', () {
      final color = AppTheme.parseHex('#007AFF');
      expect(color.value, 0xFF007AFF);
    });

    test('parseHex parses 8-digit hex with alpha', () {
      final color = AppTheme.parseHex('#007AFF14');
      expect(color.value, 0x14007AFF);
    });

    test('parseHex returns fallback for invalid input', () {
      final color = AppTheme.parseHex('not-a-color', fallback: 0xFFFF0000);
      expect(color.value, 0xFFFF0000);
    });

    test('parseHex handles transparent keyword', () {
      final color = AppTheme.parseHex('transparent');
      expect(color, const Color(0x00000000));
    });
  });

  group('AppTheme JSON loading', () {
    test('loadFromJson parses valid JSON string', () {
      const json = '''
      {
        "light": {
          "colors": {
            "scaffold": "#F5F5F7",
            "surface": "#FFFFFF",
            "divider": "#D1D1D6",
            "primary": "#007AFF",
            "textPrimary": "#1D1D1F",
            "textSecondary": "#86868B",
            "method": { "GET": "#34C759", "default": "#8E8E93" },
            "status": { "2xx": "#34C759", "default": "#8E8E93" },
            "protocol": { "HTTP": "#007AFF" },
            "connection": { "connected": "#34C759", "connecting": "#FF9F0A", "disconnected": "#FF3B30" },
            "timing": { "connect": "#FF9F0A", "tls": "#AF52DE", "request": "#007AFF", "ttfb": "#34C759", "response": "#30D158" },
            "syntax": { "key": "#0A2463", "string": "#2E7D32", "number": "#E65100", "boolean": "#6A1B9A" }
          },
          "toolbar": { "gradient": { "start": "#FAFAFA", "end": "#EBEBEB" }, "borderWidth": 0.5 },
          "table": { "headerGradient": { "start": "#F4F4F5", "end": "#EAEAEB" }, "selectedBackground": "#007AFF14", "selectedIndicatorWidth": 2, "selectedIndicatorColor": "#007AFF" },
          "tree": { "selectedBackground": "#007AFF", "selectedText": "#FFFFFF", "selectedRadius": 5 },
          "filterChip": { "activeBackground": "#007AFF1F", "activeBorder": "transparent", "activeText": "#007AFF", "inactiveBackground": "transparent", "inactiveBorder": "#D1D1D6" },
          "detailTab": { "activeBackground": "#E8E8ED", "activeText": "#1D1D1F", "inactiveText": "#86868B", "radius": 5 }
        },
        "dark": {
          "colors": {
            "scaffold": "#1C1C1E",
            "surface": "#2C2C2E",
            "divider": "#38383A",
            "primary": "#0A84FF",
            "textPrimary": "#F5F5F7",
            "textSecondary": "#98989D",
            "method": { "GET": "#30D158", "default": "#8E8E93" },
            "status": { "2xx": "#30D158", "default": "#8E8E93" },
            "protocol": { "HTTP": "#0A84FF" },
            "connection": { "connected": "#30D158", "connecting": "#FF9F0A", "disconnected": "#FF453A" },
            "timing": { "connect": "#FF9F0A", "tls": "#BF5AF2", "request": "#0A84FF", "ttfb": "#30D158", "response": "#34C759" },
            "syntax": { "key": "#82AAFF", "string": "#C3E88D", "number": "#F78C6C", "boolean": "#C792EA" }
          },
          "toolbar": { "gradient": { "start": "#2C2C2E", "end": "#232325" }, "borderWidth": 0.5 },
          "table": { "headerGradient": { "start": "#2C2C2E", "end": "#262628" }, "selectedBackground": "#0A84FF1F", "selectedIndicatorWidth": 2, "selectedIndicatorColor": "#0A84FF" },
          "tree": { "selectedBackground": "#0A84FF", "selectedText": "#FFFFFF", "selectedRadius": 5 },
          "filterChip": { "activeBackground": "#0A84FF26", "activeBorder": "transparent", "activeText": "#0A84FF", "inactiveBackground": "transparent", "inactiveBorder": "#38383A" },
          "detailTab": { "activeBackground": "#38383A", "activeText": "#F5F5F7", "inactiveText": "#98989D", "radius": 5 }
        },
        "sizing": { "globalBarHeight": 38, "toolbarHeight": 38, "filterBarHeight": 34, "statusBarHeight": 26, "tableRowHeight": 26, "tableHeaderHeight": 28, "detailTabHeight": 28, "treeDefaultWidth": 220, "macOSTrafficLightWidth": 78, "iconSize": 16, "iconButtonSize": 22, "connectionDotSize": 6, "searchFieldWidth": 240, "searchFieldHeight": 28 },
        "spacing": { "xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24 },
        "fontSize": { "xs": 10, "sm": 11, "md": 12, "lg": 13, "xl": 14 },
        "fontFamily": { "ui": "Inter", "mono": "JetBrains Mono", "uiLetterSpacing": -0.2 },
        "radius": { "sm": 4, "md": 6, "lg": 8, "popup": 10 }
      }
      ''';

      AppTheme.loadFromJson(json);

      // Verify light theme colors
      expect(AppTheme.light().scaffoldBackgroundColor, AppTheme.parseHex('#F5F5F7'));
      expect(AppTheme.spacing.sm, 8.0);
      expect(AppTheme.sizing.toolbarHeight, 38.0);
      expect(AppTheme.radius.md, 6.0);
      expect(AppTheme.fontConfig.ui, 'Inter');
    });

    test('loadFromJson falls back to defaults on invalid JSON', () {
      AppTheme.loadFromJson('not valid json');

      // Should still work with defaults
      expect(AppTheme.spacing.sm, 8.0);
      expect(AppTheme.sizing.toolbarHeight, 38.0);
    });
  });

  group('AppTheme color accessors', () {
    setUp(() {
      // Reset to defaults
      AppTheme.loadFromJson('{}');
    });

    test('methodColor returns correct color for GET', () {
      final color = AppTheme.methodColor('GET');
      expect(color, isNotNull);
    });

    test('statusColor returns correct color for 200', () {
      final color = AppTheme.statusColor(200);
      expect(color, isNotNull);
    });

    test('statusColor returns default for unknown codes', () {
      final color = AppTheme.statusColor(100);
      expect(color, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: FAIL (AppTheme.parseHex, AppTheme.loadFromJson, etc. don't exist yet)

- [ ] **Step 3: Rewrite `lib/theme/app_theme.dart`**

Complete rewrite. The new `AppTheme` must:
- Expose a static `parseHex(String hex, {int fallback})` method
- Expose a static `loadFromJson(String jsonString)` that parses and stores config
- Expose a static `loadFromAsset()` that reads `assets/theme.json` via `rootBundle`
- Expose typed getters: `AppTheme.spacing`, `AppTheme.sizing`, `AppTheme.radius`, `AppTheme.fontConfig`
- Expose brightness-aware color getters: `AppTheme.colors(BuildContext)` returns the light or dark color set based on current theme
- Keep `AppTheme.light()` and `AppTheme.dark()` returning `ThemeData`
- Keep convenience methods: `methodColor(String)`, `statusColor(int)`, `monoStyle(context)`, `syntaxKey(context)`, etc.
- Provide hardcoded fallback defaults matching current values if JSON is missing/invalid

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ========== Data classes ==========

class ThemeColors {
  final Color scaffold, surface, divider, primary, textPrimary, textSecondary;
  final Map<String, Color> method, status, protocol;
  final Color connConnected, connConnecting, connDisconnected;
  final Color timingConnect, timingTls, timingRequest, timingTtfb, timingResponse;
  final Color syntaxKey, syntaxString, syntaxNumber, syntaxBoolean;

  const ThemeColors({
    required this.scaffold, required this.surface, required this.divider,
    required this.primary, required this.textPrimary, required this.textSecondary,
    required this.method, required this.status, required this.protocol,
    required this.connConnected, required this.connConnecting, required this.connDisconnected,
    required this.timingConnect, required this.timingTls, required this.timingRequest,
    required this.timingTtfb, required this.timingResponse,
    required this.syntaxKey, required this.syntaxString, required this.syntaxNumber,
    required this.syntaxBoolean,
  });
}

class ToolbarConfig {
  final Color gradientStart, gradientEnd;
  final double borderWidth;
  const ToolbarConfig({required this.gradientStart, required this.gradientEnd, required this.borderWidth});
}

class TableConfig {
  final Color headerGradientStart, headerGradientEnd;
  final Color selectedBackground, selectedIndicatorColor;
  final double selectedIndicatorWidth;
  const TableConfig({required this.headerGradientStart, required this.headerGradientEnd,
    required this.selectedBackground, required this.selectedIndicatorColor, required this.selectedIndicatorWidth});
}

class TreeConfig {
  final Color selectedBackground, selectedText;
  final double selectedRadius;
  const TreeConfig({required this.selectedBackground, required this.selectedText, required this.selectedRadius});
}

class FilterChipConfig {
  final Color activeBackground, activeBorder, activeText;
  final Color inactiveBackground, inactiveBorder;
  const FilterChipConfig({required this.activeBackground, required this.activeBorder, required this.activeText,
    required this.inactiveBackground, required this.inactiveBorder});
}

class DetailTabConfig {
  final Color activeBackground, activeText, inactiveText;
  final double radius;
  const DetailTabConfig({required this.activeBackground, required this.activeText, required this.inactiveText, required this.radius});
}

class ModeColors {
  final ThemeColors colors;
  final ToolbarConfig toolbar;
  final TableConfig table;
  final TreeConfig tree;
  final FilterChipConfig filterChip;
  final DetailTabConfig detailTab;
  const ModeColors({required this.colors, required this.toolbar, required this.table,
    required this.tree, required this.filterChip, required this.detailTab});
}

class SpacingConfig {
  final double xs, sm, md, lg, xl;
  const SpacingConfig({required this.xs, required this.sm, required this.md, required this.lg, required this.xl});
}

class SizingConfig {
  final double globalBarHeight, toolbarHeight, filterBarHeight, statusBarHeight;
  final double tableRowHeight, tableHeaderHeight, detailTabHeight;
  final double treeDefaultWidth, macOSTrafficLightWidth;
  final double iconSize, iconButtonSize, connectionDotSize;
  final double searchFieldWidth, searchFieldHeight;
  const SizingConfig({
    required this.globalBarHeight, required this.toolbarHeight, required this.filterBarHeight,
    required this.statusBarHeight, required this.tableRowHeight, required this.tableHeaderHeight,
    required this.detailTabHeight, required this.treeDefaultWidth, required this.macOSTrafficLightWidth,
    required this.iconSize, required this.iconButtonSize, required this.connectionDotSize,
    required this.searchFieldWidth, required this.searchFieldHeight,
  });
}

class FontConfig {
  final String ui, mono;
  final double uiLetterSpacing;
  const FontConfig({required this.ui, required this.mono, required this.uiLetterSpacing});
}

class RadiusConfig {
  final double sm, md, lg, popup;
  const RadiusConfig({required this.sm, required this.md, required this.lg, required this.popup});
}

class FontSizeConfig {
  final double xs, sm, md, lg, xl;
  const FontSizeConfig({required this.xs, required this.sm, required this.md, required this.lg, required this.xl});
}

// ========== AppTheme singleton ==========

class AppTheme {
  AppTheme._();

  static late ModeColors _light;
  static late ModeColors _dark;
  static late SpacingConfig spacing;
  static late SizingConfig sizing;
  static late FontConfig fontConfig;
  static late RadiusConfig radius;
  static late FontSizeConfig fontSize;

  static bool _initialized = false;

  // --- Hex parsing ---

  static Color parseHex(String hex, {int fallback = 0xFF000000}) {
    if (hex == 'transparent') return const Color(0x00000000);
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) {
      final value = int.tryParse('FF$hex', radix: 16);
      return Color(value ?? fallback);
    }
    if (hex.length == 8) {
      // Format: RRGGBBAA -> need to convert to AARRGGBB
      final rr = hex.substring(0, 2);
      final gg = hex.substring(2, 4);
      final bb = hex.substring(4, 6);
      final aa = hex.substring(6, 8);
      final value = int.tryParse('$aa$rr$gg$bb', radix: 16);
      return Color(value ?? fallback);
    }
    return Color(fallback);
  }

  // --- Loading ---

  static Future<void> loadFromAsset() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/theme.json');
      loadFromJson(jsonStr);
    } catch (_) {
      _loadDefaults();
    }
  }

  static void loadFromJson(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      _light = _parseModeColors(map['light'] as Map<String, dynamic>? ?? {}, Brightness.light);
      _dark = _parseModeColors(map['dark'] as Map<String, dynamic>? ?? {}, Brightness.dark);
      spacing = _parseSpacing(map['spacing'] as Map<String, dynamic>? ?? {});
      sizing = _parseSizing(map['sizing'] as Map<String, dynamic>? ?? {});
      fontConfig = _parseFontConfig(map['fontFamily'] as Map<String, dynamic>? ?? {});
      radius = _parseRadius(map['radius'] as Map<String, dynamic>? ?? {});
      fontSize = _parseFontSize(map['fontSize'] as Map<String, dynamic>? ?? {});
      _initialized = true;
    } catch (_) {
      _loadDefaults();
    }
  }

  static void _loadDefaults() {
    // Hardcoded fallbacks matching the spec defaults
    _light = _parseModeColors({}, Brightness.light);
    _dark = _parseModeColors({}, Brightness.dark);
    spacing = _parseSpacing({});
    sizing = _parseSizing({});
    fontConfig = _parseFontConfig({});
    radius = _parseRadius({});
    fontSize = _parseFontSize({});
    _initialized = true;
  }

  // --- Brightness-aware accessors ---

  static ModeColors mode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static ThemeColors colors(BuildContext context) => mode(context).colors;

  // --- Convenience color accessors ---

  static Color methodColor(String method) {
    // Use light as fallback for non-context calls
    final m = (_initialized ? _light : _parseModeColors({}, Brightness.light)).colors.method;
    return m[method.toUpperCase()] ?? m['default'] ?? const Color(0xFF8E8E93);
  }

  static Color methodColorOf(BuildContext context, String method) {
    final m = colors(context).method;
    return m[method.toUpperCase()] ?? m['default'] ?? const Color(0xFF8E8E93);
  }

  static Color statusColor(int code) {
    final s = (_initialized ? _light : _parseModeColors({}, Brightness.light)).colors.status;
    if (code >= 500) return s['5xx'] ?? const Color(0xFFFF3B30);
    if (code >= 400) return s['4xx'] ?? const Color(0xFFFF9F0A);
    if (code >= 300) return s['3xx'] ?? const Color(0xFF007AFF);
    if (code >= 200) return s['2xx'] ?? const Color(0xFF34C759);
    return s['default'] ?? const Color(0xFF8E8E93);
  }

  static Color statusColorOf(BuildContext context, int code) {
    final s = colors(context).status;
    if (code >= 500) return s['5xx'] ?? const Color(0xFFFF3B30);
    if (code >= 400) return s['4xx'] ?? const Color(0xFFFF9F0A);
    if (code >= 300) return s['3xx'] ?? const Color(0xFF007AFF);
    if (code >= 200) return s['2xx'] ?? const Color(0xFF34C759);
    return s['default'] ?? const Color(0xFF8E8E93);
  }

  // --- Syntax colors (context-aware) ---

  static Color syntaxKey(BuildContext context) => colors(context).syntaxKey;
  static Color syntaxString(BuildContext context) => colors(context).syntaxString;
  static Color syntaxNumber(BuildContext context) => colors(context).syntaxNumber;
  static Color syntaxBool(BuildContext context) => colors(context).syntaxBoolean;

  // --- Font helpers ---

  static TextStyle monoStyle(BuildContext context, {double? fs, Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fs ?? fontSize.sm,
      color: color ?? colors(context).textPrimary,
      height: 1.5,
    );
  }

  static TextStyle mono(BuildContext context) => monoStyle(context);

  // --- ThemeData builders ---

  static ThemeData light() {
    if (!_initialized) _loadDefaults();
    final c = _light.colors;
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    return base.copyWith(
      scaffoldBackgroundColor: c.scaffold,
      dividerColor: c.divider,
      colorScheme: ColorScheme.light(
        primary: c.primary,
        surface: c.surface,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
    );
  }

  static ThemeData dark() {
    if (!_initialized) _loadDefaults();
    final c = _dark.colors;
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    return base.copyWith(
      scaffoldBackgroundColor: c.scaffold,
      dividerColor: c.divider,
      colorScheme: ColorScheme.dark(
        primary: c.primary,
        surface: c.surface,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
    );
  }

  // --- Internal parsing helpers ---

  static Color _c(Map<String, dynamic> m, String key, String fallbackHex) =>
      parseHex((m[key] as String?) ?? fallbackHex);

  static double _d(Map<String, dynamic> m, String key, double fallback) =>
      (m[key] as num?)?.toDouble() ?? fallback;

  static Map<String, Color> _colorMap(Map<String, dynamic> m, Map<String, String> defaults) {
    final result = <String, Color>{};
    for (final e in defaults.entries) {
      result[e.key] = parseHex((m[e.key] as String?) ?? e.value);
    }
    return result;
  }

  static ModeColors _parseModeColors(Map<String, dynamic> json, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final c = json['colors'] as Map<String, dynamic>? ?? {};
    final tb = json['toolbar'] as Map<String, dynamic>? ?? {};
    final tbGrad = tb['gradient'] as Map<String, dynamic>? ?? {};
    final tbl = json['table'] as Map<String, dynamic>? ?? {};
    final tblGrad = tbl['headerGradient'] as Map<String, dynamic>? ?? {};
    final tr = json['tree'] as Map<String, dynamic>? ?? {};
    final fc = json['filterChip'] as Map<String, dynamic>? ?? {};
    final dt = json['detailTab'] as Map<String, dynamic>? ?? {};
    final conn = c['connection'] as Map<String, dynamic>? ?? {};
    final timing = c['timing'] as Map<String, dynamic>? ?? {};
    final syntax = c['syntax'] as Map<String, dynamic>? ?? {};

    return ModeColors(
      colors: ThemeColors(
        scaffold: _c(c, 'scaffold', isLight ? '#F5F5F7' : '#1C1C1E'),
        surface: _c(c, 'surface', isLight ? '#FFFFFF' : '#2C2C2E'),
        divider: _c(c, 'divider', isLight ? '#D1D1D6' : '#38383A'),
        primary: _c(c, 'primary', isLight ? '#007AFF' : '#0A84FF'),
        textPrimary: _c(c, 'textPrimary', isLight ? '#1D1D1F' : '#F5F5F7'),
        textSecondary: _c(c, 'textSecondary', isLight ? '#86868B' : '#98989D'),
        method: _colorMap(c['method'] as Map<String, dynamic>? ?? {}, {
          'GET': isLight ? '#34C759' : '#30D158',
          'POST': '#FF9F0A',
          'PUT': isLight ? '#007AFF' : '#0A84FF',
          'DELETE': isLight ? '#FF3B30' : '#FF453A',
          'PATCH': isLight ? '#AF52DE' : '#BF5AF2',
          'default': '#8E8E93',
        }),
        status: _colorMap(c['status'] as Map<String, dynamic>? ?? {}, {
          '2xx': isLight ? '#34C759' : '#30D158',
          '3xx': isLight ? '#007AFF' : '#0A84FF',
          '4xx': '#FF9F0A',
          '5xx': isLight ? '#FF3B30' : '#FF453A',
          'default': '#8E8E93',
        }),
        protocol: _colorMap(c['protocol'] as Map<String, dynamic>? ?? {}, {
          'HTTP': isLight ? '#007AFF' : '#0A84FF',
          'HTTPS': isLight ? '#34C759' : '#30D158',
          'H2': '#FF9F0A',
          'WS': isLight ? '#AF52DE' : '#BF5AF2',
          'WSS': isLight ? '#FF3B30' : '#FF453A',
        }),
        connConnected: _c(conn, 'connected', isLight ? '#34C759' : '#30D158'),
        connConnecting: _c(conn, 'connecting', '#FF9F0A'),
        connDisconnected: _c(conn, 'disconnected', isLight ? '#FF3B30' : '#FF453A'),
        timingConnect: _c(timing, 'connect', '#FF9F0A'),
        timingTls: _c(timing, 'tls', isLight ? '#AF52DE' : '#BF5AF2'),
        timingRequest: _c(timing, 'request', isLight ? '#007AFF' : '#0A84FF'),
        timingTtfb: _c(timing, 'ttfb', isLight ? '#34C759' : '#30D158'),
        timingResponse: _c(timing, 'response', isLight ? '#30D158' : '#34C759'),
        syntaxKey: _c(syntax, 'key', isLight ? '#0A2463' : '#82AAFF'),
        syntaxString: _c(syntax, 'string', isLight ? '#2E7D32' : '#C3E88D'),
        syntaxNumber: _c(syntax, 'number', isLight ? '#E65100' : '#F78C6C'),
        syntaxBoolean: _c(syntax, 'boolean', isLight ? '#6A1B9A' : '#C792EA'),
      ),
      toolbar: ToolbarConfig(
        gradientStart: _c(tbGrad, 'start', isLight ? '#FAFAFA' : '#2C2C2E'),
        gradientEnd: _c(tbGrad, 'end', isLight ? '#EBEBEB' : '#232325'),
        borderWidth: _d(tb, 'borderWidth', 0.5),
      ),
      table: TableConfig(
        headerGradientStart: _c(tblGrad, 'start', isLight ? '#F4F4F5' : '#2C2C2E'),
        headerGradientEnd: _c(tblGrad, 'end', isLight ? '#EAEAEB' : '#262628'),
        selectedBackground: _c(tbl, 'selectedBackground', isLight ? '#007AFF14' : '#0A84FF1F'),
        selectedIndicatorColor: _c(tbl, 'selectedIndicatorColor', isLight ? '#007AFF' : '#0A84FF'),
        selectedIndicatorWidth: _d(tbl, 'selectedIndicatorWidth', 2),
      ),
      tree: TreeConfig(
        selectedBackground: _c(tr, 'selectedBackground', isLight ? '#007AFF' : '#0A84FF'),
        selectedText: _c(tr, 'selectedText', '#FFFFFF'),
        selectedRadius: _d(tr, 'selectedRadius', 5),
      ),
      filterChip: FilterChipConfig(
        activeBackground: _c(fc, 'activeBackground', isLight ? '#007AFF1F' : '#0A84FF26'),
        activeBorder: _c(fc, 'activeBorder', 'transparent'),
        activeText: _c(fc, 'activeText', isLight ? '#007AFF' : '#0A84FF'),
        inactiveBackground: _c(fc, 'inactiveBackground', 'transparent'),
        inactiveBorder: _c(fc, 'inactiveBorder', isLight ? '#D1D1D6' : '#38383A'),
      ),
      detailTab: DetailTabConfig(
        activeBackground: _c(dt, 'activeBackground', isLight ? '#E8E8ED' : '#38383A'),
        activeText: _c(dt, 'activeText', isLight ? '#1D1D1F' : '#F5F5F7'),
        inactiveText: _c(dt, 'inactiveText', isLight ? '#86868B' : '#98989D'),
        radius: _d(dt, 'radius', 5),
      ),
    );
  }

  static SpacingConfig _parseSpacing(Map<String, dynamic> m) => SpacingConfig(
    xs: _d(m, 'xs', 4), sm: _d(m, 'sm', 8), md: _d(m, 'md', 12), lg: _d(m, 'lg', 16), xl: _d(m, 'xl', 24),
  );

  static SizingConfig _parseSizing(Map<String, dynamic> m) => SizingConfig(
    globalBarHeight: _d(m, 'globalBarHeight', 38),
    toolbarHeight: _d(m, 'toolbarHeight', 38),
    filterBarHeight: _d(m, 'filterBarHeight', 34),
    statusBarHeight: _d(m, 'statusBarHeight', 26),
    tableRowHeight: _d(m, 'tableRowHeight', 26),
    tableHeaderHeight: _d(m, 'tableHeaderHeight', 28),
    detailTabHeight: _d(m, 'detailTabHeight', 28),
    treeDefaultWidth: _d(m, 'treeDefaultWidth', 220),
    macOSTrafficLightWidth: _d(m, 'macOSTrafficLightWidth', 78),
    iconSize: _d(m, 'iconSize', 16),
    iconButtonSize: _d(m, 'iconButtonSize', 22),
    connectionDotSize: _d(m, 'connectionDotSize', 6),
    searchFieldWidth: _d(m, 'searchFieldWidth', 240),
    searchFieldHeight: _d(m, 'searchFieldHeight', 28),
  );

  static FontConfig _parseFontConfig(Map<String, dynamic> m) => FontConfig(
    ui: (m['ui'] as String?) ?? 'Inter',
    mono: (m['mono'] as String?) ?? 'JetBrains Mono',
    uiLetterSpacing: _d(m, 'uiLetterSpacing', -0.2),
  );

  static RadiusConfig _parseRadius(Map<String, dynamic> m) => RadiusConfig(
    sm: _d(m, 'sm', 4), md: _d(m, 'md', 6), lg: _d(m, 'lg', 8), popup: _d(m, 'popup', 10),
  );

  static FontSizeConfig _parseFontSize(Map<String, dynamic> m) => FontSizeConfig(
    xs: _d(m, 'xs', 10), sm: _d(m, 'sm', 11), md: _d(m, 'md', 12), lg: _d(m, 'lg', 13), xl: _d(m, 'xl', 14),
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/theme/app_theme.dart test/theme/app_theme_test.dart
git commit -m "feat: rewrite AppTheme as JSON-driven singleton with typed getters"
```

---

### Task 3: Update `main.dart` for async theme loading

**Files:**
- Modify: `lib/main.dart:20-40`

- [ ] **Step 1: Add async theme loading before `runApp`**

In `main()`, after `WidgetsFlutterBinding.ensureInitialized();` and before `Get.put(...)`, add:

```dart
await AppTheme.loadFromAsset();
```

The function signature must change from `void main() async` (already async, so just add the call).

- [ ] **Step 2: Verify app still compiles**

Run: `flutter build macos --debug 2>&1 | tail -5`
Expected: build succeeds (or at least no theme-related errors)

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: load theme.json at app startup"
```

---

### Task 4: Migrate all old `AppTheme.xxxConst` call sites

This task updates every file that references old `AppTheme` static constants to use the new API. The old constants (`AppTheme.spacingXS`, `AppTheme.fontSizeSM`, `AppTheme.radiusMD`, `AppTheme.globalBarHeight`, `AppTheme.methodGet`, `AppTheme.statusConnected`, `AppTheme.timingConnect`, `AppTheme.protocolColors`, etc.) are replaced with the new paths.

**Files:** All files under `lib/pages/` and `lib/widgets/` that import `app_theme.dart`.

**Migration mapping:**

| Old | New |
|-----|-----|
| `AppTheme.spacingXS` | `AppTheme.spacing.xs` |
| `AppTheme.spacingSM` | `AppTheme.spacing.sm` |
| `AppTheme.spacingMD` | `AppTheme.spacing.md` |
| `AppTheme.spacingLG` | `AppTheme.spacing.lg` |
| `AppTheme.spacingXL` | `AppTheme.spacing.xl` |
| `AppTheme.fontSizeXS` | `AppTheme.fontSize.xs` |
| `AppTheme.fontSizeSM` | `AppTheme.fontSize.sm` |
| `AppTheme.fontSizeMD` | `AppTheme.fontSize.md` |
| `AppTheme.fontSizeLG` | `AppTheme.fontSize.lg` |
| `AppTheme.fontSizeXL` | `AppTheme.fontSize.xl` |
| `AppTheme.radiusSM` | `AppTheme.radius.sm` |
| `AppTheme.radiusMD` | `AppTheme.radius.md` |
| `AppTheme.radiusLG` | `AppTheme.radius.lg` |
| `AppTheme.globalBarHeight` | `AppTheme.sizing.globalBarHeight` |
| `AppTheme.toolbarHeight` | `AppTheme.sizing.toolbarHeight` |
| `AppTheme.filterBarHeight` | `AppTheme.sizing.filterBarHeight` |
| `AppTheme.statusBarHeight` | `AppTheme.sizing.statusBarHeight` |
| `AppTheme.tableRowHeight` | `AppTheme.sizing.tableRowHeight` |
| `AppTheme.tableHeaderHeight` | `AppTheme.sizing.tableHeaderHeight` |
| `AppTheme.detailTabHeight` | `AppTheme.sizing.detailTabHeight` |
| `AppTheme.treeDefaultWidth` | `AppTheme.sizing.treeDefaultWidth` |
| `AppTheme.macOSTrafficLightWidth` | `AppTheme.sizing.macOSTrafficLightWidth` |
| `AppTheme.methodGet` / `methodColor(m)` | `AppTheme.methodColorOf(context, m)` (context-aware) or `AppTheme.methodColor(m)` (static) |
| `AppTheme.statusColor(code)` | `AppTheme.statusColorOf(context, code)` (context-aware) or `AppTheme.statusColor(code)` (static) |
| `AppTheme.statusConnected` | `AppTheme.colors(context).connConnected` |
| `AppTheme.statusConnecting` | `AppTheme.colors(context).connConnecting` |
| `AppTheme.statusDisconnected` | `AppTheme.colors(context).connDisconnected` |
| `AppTheme.timingConnect` | `AppTheme.colors(context).timingConnect` |
| `AppTheme.timingTLS` | `AppTheme.colors(context).timingTls` |
| `AppTheme.timingRequest` | `AppTheme.colors(context).timingRequest` |
| `AppTheme.timingTTFB` | `AppTheme.colors(context).timingTtfb` |
| `AppTheme.timingResponse` | `AppTheme.colors(context).timingResponse` |
| `AppTheme.protocolColors[x]` | `AppTheme.colors(context).protocol[x]` |
| `AppTheme.methodDefault` | `AppTheme.colors(context).method['default']` |

- [ ] **Step 1: Migrate all files that use old constants**

Go through each file that imports `app_theme.dart` and apply the mapping above. Key files:
- `lib/pages/capture/global_bar.dart`
- `lib/pages/capture/toolbar.dart`
- `lib/pages/capture/filter_bar.dart`
- `lib/pages/capture/flow_table.dart`
- `lib/pages/capture/tree_panel.dart`
- `lib/pages/capture/flow_detail_panel.dart`
- `lib/pages/capture/status_bar.dart`
- `lib/pages/capture/content_panel.dart`
- `lib/pages/capture/capture_page.dart`
- `lib/pages/capture/waterfall_tab.dart`
- `lib/pages/capture/dashboard_tab.dart`
- `lib/widgets/connection_indicator.dart`
- `lib/widgets/key_value_table.dart`
- `lib/widgets/json_viewer.dart`
- `lib/widgets/body_viewer.dart`
- `lib/widgets/waterfall_bar.dart`
- `lib/pages/compose/compose_page.dart`
- `lib/pages/history/history_page.dart`
- `lib/pages/settings/settings_page.dart`
- `lib/pages/tools/map_remote_page.dart`
- `lib/pages/tools/map_local_page.dart`
- `lib/pages/tools/allow_block_page.dart`
- `lib/pages/tools/breakpoint_page.dart`
- `lib/pages/tools/breakpoint_dialog.dart`
- `lib/pages/tools/diff_page.dart`

Note: For widgets that don't have `BuildContext` available (like `WaterfallBar`'s `CustomPainter`), pass colors as constructor params from the parent widget which does have context.

- [ ] **Step 2: Fix compilation errors**

Run: `flutter analyze`
Expected: no errors related to AppTheme (warnings OK for now)

- [ ] **Step 3: Run existing tests**

Run: `flutter test`
Expected: all existing tests still pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: migrate all AppTheme call sites to new JSON-driven API"
```

---

### Task 5: Apply macOS-native visual styles — GlobalBar & Toolbar

**Files:**
- Modify: `lib/pages/capture/global_bar.dart`
- Modify: `lib/pages/capture/toolbar.dart`

- [ ] **Step 1: Update GlobalBar**

Replace the `Container` decoration in `GlobalBar.build()` (line 30-35):

```dart
decoration: BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppTheme.mode(context).toolbar.gradientStart,
      AppTheme.mode(context).toolbar.gradientEnd,
    ],
  ),
  border: Border(
    bottom: BorderSide(
      color: AppTheme.colors(context).divider,
      width: AppTheme.mode(context).toolbar.borderWidth,
    ),
  ),
),
```

Update icon sizes to `AppTheme.sizing.iconSize` (16px). Update task name font weight to `w500`.

- [ ] **Step 2: Update Toolbar**

Same gradient decoration for the toolbar container. Style the play/stop button as a rounded rect:

```dart
Container(
  width: AppTheme.sizing.iconButtonSize,
  height: AppTheme.sizing.iconButtonSize,
  decoration: BoxDecoration(
    color: taskCtrl.isCapturing.value
        ? AppTheme.methodColorOf(context, 'DELETE')
        : AppTheme.methodColorOf(context, 'GET'),
    borderRadius: BorderRadius.circular(5),
  ),
  child: Icon(
    taskCtrl.isCapturing.value ? Icons.stop : Icons.play_arrow,
    size: 14,
    color: Colors.white,
  ),
)
```

Update search field: `AppTheme.sizing.searchFieldHeight` height, `AppTheme.sizing.searchFieldWidth` width, surface fill, 0.5px border, 6px radius.

- [ ] **Step 3: Verify visually**

Run: `flutter run -d macos`
Expected: gradient toolbars, rounded play button, refined search field

- [ ] **Step 4: Commit**

```bash
git add lib/pages/capture/global_bar.dart lib/pages/capture/toolbar.dart
git commit -m "feat: apply macOS-native gradient toolbars and button styles"
```

---

### Task 6: Apply macOS-native visual styles — FilterBar & StatusBar

**Files:**
- Modify: `lib/pages/capture/filter_bar.dart`
- Modify: `lib/pages/capture/status_bar.dart`

- [ ] **Step 1: Update FilterBar chips**

Remove the `Text('Proto: '...)` and `Text('Status: '...)` labels. Update chip decoration to use `AppTheme.mode(context).filterChip`:

```dart
decoration: BoxDecoration(
  color: active.contains(label)
      ? AppTheme.mode(context).filterChip.activeBackground
      : AppTheme.mode(context).filterChip.inactiveBackground,
  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
  border: Border.all(
    color: active.contains(label)
        ? AppTheme.mode(context).filterChip.activeBorder
        : AppTheme.mode(context).filterChip.inactiveBorder,
    width: 0.5,
  ),
),
```

- [ ] **Step 2: Update StatusBar**

Apply toolbar gradient background. Change separator from `|` to `·` (middle dot). Update connection dot to `AppTheme.sizing.connectionDotSize`.

- [ ] **Step 3: Verify visually**

Run app (`flutter run -d macos`). Check filter chips are borderless when active. Check status bar gradient and separators.

- [ ] **Step 4: Commit**

```bash
git add lib/pages/capture/filter_bar.dart lib/pages/capture/status_bar.dart
git commit -m "feat: apply macOS-native filter chips and status bar"
```

---

### Task 7: Apply macOS-native visual styles — FlowTable

**Files:**
- Modify: `lib/pages/capture/flow_table.dart`

- [ ] **Step 1: Update table header**

Replace `color: theme.colorScheme.surfaceContainerHigh` with gradient from `AppTheme.mode(context).table`:

```dart
decoration: BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppTheme.mode(context).table.headerGradientStart,
      AppTheme.mode(context).table.headerGradientEnd,
    ],
  ),
),
```

- [ ] **Step 2: Update selected row style**

In `_FlowRow`, replace the flat `color` with selection indicator:

```dart
Container(
  height: AppTheme.sizing.tableRowHeight,
  decoration: BoxDecoration(
    color: isSelected ? AppTheme.mode(context).table.selectedBackground : null,
    border: isSelected
        ? Border(left: BorderSide(
            color: AppTheme.mode(context).table.selectedIndicatorColor,
            width: AppTheme.mode(context).table.selectedIndicatorWidth,
          ))
        : null,
  ),
  // ... padding adjusted for indicator width when selected
)
```

- [ ] **Step 3: Update method text weight**

Change method text to `fontWeight: FontWeight.w600`.

- [ ] **Step 4: Verify visually**

Run app. Select a row — should see blue left indicator + tinted background. Header should have subtle gradient.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/capture/flow_table.dart
git commit -m "feat: apply macOS-native table header gradient and selection indicator"
```

---

### Task 8: Apply macOS-native visual styles — TreePanel

**Files:**
- Modify: `lib/pages/capture/tree_panel.dart`

- [ ] **Step 1: Update "All Domains" selection style**

Replace `ListTile` selected style with custom rounded rect:

```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 3),
  margin: EdgeInsets.symmetric(horizontal: AppTheme.spacing.xs),
  decoration: BoxDecoration(
    color: isSelected ? AppTheme.mode(context).tree.selectedBackground : null,
    borderRadius: BorderRadius.circular(AppTheme.mode(context).tree.selectedRadius),
  ),
  child: Text('All Domains',
    style: TextStyle(
      fontSize: AppTheme.fontSize.md,
      color: isSelected ? AppTheme.mode(context).tree.selectedText : null,
    ),
  ),
)
```

- [ ] **Step 2: Update section headers**

"Domains" and "Pinned" headers: uppercase, `letterSpacing: 0.5`, `fontSize: AppTheme.fontSize.xs`, secondary text color.

- [ ] **Step 3: Verify visually**

Run app. Selected domain should show blue rounded rect with white text. Section headers should be small uppercase.

- [ ] **Step 4: Commit**

```bash
git add lib/pages/capture/tree_panel.dart
git commit -m "feat: apply macOS-native tree panel selection and section headers"
```

---

### Task 9: Apply macOS-native visual styles — FlowDetailPanel & ContentPanel

**Files:**
- Modify: `lib/pages/capture/flow_detail_panel.dart`
- Modify: `lib/pages/capture/content_panel.dart`

- [ ] **Step 1: Replace Material TabBar in FlowDetailPanel**

Replace the standard `TabBar` with a custom segmented-control style using the `detailTab` config from theme:

```dart
// Replace TabBar with a Row of styled tab buttons
Container(
  height: AppTheme.sizing.detailTabHeight,
  padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
  child: Row(
    children: tabs.map((tab) {
      final isActive = currentIndex == tab.index;
      final dt = AppTheme.mode(context).detailTab;
      return GestureDetector(
        onTap: () => tabController.animateTo(tab.index),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 3),
          margin: EdgeInsets.only(right: AppTheme.spacing.xs),
          decoration: BoxDecoration(
            color: isActive ? dt.activeBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(dt.radius),
          ),
          child: Text(tab.label, style: TextStyle(
            fontSize: AppTheme.fontSize.sm,
            color: isActive ? dt.activeText : dt.inactiveText,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
          )),
        ),
      );
    }).toList(),
  ),
)
```

- [ ] **Step 2: Update section titles in detail tabs**

Change "Request Headers", "Response Body", etc. to use `fontWeight: FontWeight.w600` and `color: AppTheme.colors(context).textSecondary`.

- [ ] **Step 3: Apply same tab style to ContentPanel**

Update the List/Waterfall/Dashboard tabs in `content_panel.dart` to use the same segmented-control style.

- [ ] **Step 4: Verify visually**

Run app. Tabs should appear as rounded rect segments, not underlined Material tabs.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/capture/flow_detail_panel.dart lib/pages/capture/content_panel.dart
git commit -m "feat: apply macOS-native segmented tab controls"
```

---

### Task 10: Apply macOS-native visual styles — ConnectionIndicator & Widgets

**Files:**
- Modify: `lib/widgets/connection_indicator.dart`
- Modify: `lib/widgets/key_value_table.dart`
- Modify: `lib/widgets/body_viewer.dart`
- Modify: `lib/widgets/json_viewer.dart`

- [ ] **Step 1: Update ConnectionIndicator**

Change dot size from 8 to `AppTheme.sizing.connectionDotSize` (6px). Use context-aware colors:

```dart
final (color, label) = switch (status) {
  WsStatus.connected => (AppTheme.colors(context).connConnected, 'Connected'),
  WsStatus.connecting => (AppTheme.colors(context).connConnecting, 'Connecting...'),
  WsStatus.disconnected => (AppTheme.colors(context).connDisconnected, 'Disconnected'),
};
```

- [ ] **Step 2: Update KeyValueTable spacing**

Reduce vertical padding from 2 to 1. Ensure mono style uses theme-aware colors.

- [ ] **Step 3: Update BodyViewer mode toggle**

Use the `filterChip` config for Pretty/Raw/Hex toggles (same style as filter bar chips).

- [ ] **Step 4: Update JsonViewer syntax colors**

Already using `AppTheme.syntaxKey(context)` etc. — just verify these now pull from JSON config.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/connection_indicator.dart lib/widgets/key_value_table.dart lib/widgets/body_viewer.dart lib/widgets/json_viewer.dart
git commit -m "feat: apply macOS-native widget styles"
```

---

### Task 11: Apply macOS-native visual styles — Waterfall & Dashboard

**Files:**
- Modify: `lib/pages/capture/waterfall_tab.dart`
- Modify: `lib/pages/capture/dashboard_tab.dart`
- Modify: `lib/widgets/waterfall_bar.dart`

- [ ] **Step 1: Update WaterfallTab legend colors**

Replace `AppTheme.timingConnect` etc. with context-aware versions. Pass colors to `WaterfallBar` as constructor params since `CustomPainter` lacks `BuildContext`:

```dart
WaterfallBar(
  // ... existing params ...
  connectColor: AppTheme.colors(context).timingConnect,
  tlsColor: AppTheme.colors(context).timingTls,
  requestColor: AppTheme.colors(context).timingRequest,
  ttfbColor: AppTheme.colors(context).timingTtfb,
  responseColor: AppTheme.colors(context).timingResponse,
)
```

- [ ] **Step 2: Update WaterfallBar to accept color params**

Add color fields to `WaterfallBar` and `_WaterfallPainter`. Replace hardcoded `AppTheme.timingXxx` references in `paint()` with the passed-in colors.

- [ ] **Step 3: Update DashboardTab**

Update protocol chart colors: `AppTheme.colors(context).protocol[e.key]`. Update card decoration to use theme surface/divider. Update traffic stat colors.

- [ ] **Step 4: Verify visually**

Run app. Waterfall and dashboard should display correct colors in both light and dark modes.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/capture/waterfall_tab.dart lib/pages/capture/dashboard_tab.dart lib/widgets/waterfall_bar.dart
git commit -m "feat: apply macOS-native waterfall and dashboard colors"
```

---

### Task 12: Run full test suite and fix any failures

**Files:** Test files as needed

- [ ] **Step 1: Run full test suite**

Run: `flutter test`

- [ ] **Step 2: Fix any failing tests**

Common issues:
- Widget tests may fail if they were checking for specific Material colors
- Tests creating `AppTheme` values may need `AppTheme.loadFromJson('{}')` in `setUp()`

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Fix any errors (warnings acceptable).

- [ ] **Step 4: Commit fixes**

```bash
git add -A
git commit -m "fix: update tests for JSON-driven theme system"
```

---

### Task 13: Manual verification and final polish

- [ ] **Step 1: Test light mode**

Run: `flutter run -d macos`
System appearance: Light. Verify all components look correct.

- [ ] **Step 2: Test dark mode**

Switch system to dark mode. Verify all components adapt correctly.

- [ ] **Step 3: Test theme hot-swap**

Edit `assets/theme.json` (e.g., change primary color). Restart app. Verify new color takes effect.

- [ ] **Step 4: Fix any visual issues found during testing**

Address any misaligned elements, wrong colors, or missing gradient applications.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "polish: final visual adjustments for macOS-native theme"
```
