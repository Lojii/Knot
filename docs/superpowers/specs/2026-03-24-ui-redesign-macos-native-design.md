# Knot UI Redesign — macOS Native Style

**Date:** 2026-03-24
**Status:** Approved
**Scope:** Full visual redesign, zero logic changes

## Goal

Transform the Knot UI from generic Material 3 to a polished macOS-native aesthetic inspired by Proxyman. Compact density, system-following light/dark themes, JSON-driven theme configuration.

## Design Decisions

- **Style direction:** macOS Native (Apple HIG-aligned)
- **Density:** Compact (power-user optimized)
- **Theme mode:** Follow system (both light and dark polished)
- **Theme storage:** External `assets/theme.json` file, parsed at startup by `AppTheme`

## Architecture: JSON-Driven Theme

### File: `assets/theme.json`

All visual tokens live in a single JSON file. `AppTheme` reads this at app startup and exposes parsed values. Changing the theme means editing this JSON — no Dart code changes needed.

### JSON Schema

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

### AppTheme Rewrite

`AppTheme` becomes a JSON-driven singleton:

1. On app startup, load `assets/theme.json` via `rootBundle`
2. Parse into a structured `ThemeConfig` object
3. Expose typed getters: `AppTheme.colors.primary`, `AppTheme.sizing.toolbarHeight`, etc.
4. `AppTheme.light()` and `AppTheme.dark()` build `ThemeData` from parsed config
5. All existing `AppTheme.xxx` call sites migrate to the new getter paths

Fallback: if JSON parsing fails, use hardcoded defaults (current values) so the app never breaks.

## Component Visual Spec

### GlobalBar (38px)
- Linear gradient background (toolbar gradient from JSON)
- 0.5px hairline bottom border (divider color)
- Icons: 16px, outlined style (consider CupertinoIcons where appropriate)
- Task name: `fontWeight: w500`
- Connection dot: 6px

### Toolbar (38px)
- Same gradient background + 0.5px bottom border
- Play/Stop button: 22x22 rounded rect (radius 5px), filled green/red + white icon
- Clear button: 22x22 rounded rect, light gray background
- Search field: white/surface fill, 0.5px border, 6px radius, 28px height

### FilterBar (34px)
- Chips: no border when active, use `activeBackground` from JSON
- Inactive: transparent fill + thin border
- Remove "Proto:" / "Status:" text labels — use section grouping by spacing instead

### FlowTable
- Header: gradient background from JSON
- Row height: 26px, no alternating colors
- Selected row: tinted background + 2px left indicator bar (primary color)
- Method text: `fontWeight: w600`
- Status code: colored text (no badge)
- Hover: subtle background tint

### TreePanel
- Selected item: rounded rect highlight (radius 5px), primary fill, white text
- Section headers: uppercase, `letterSpacing: 0.5`, 8px font, secondary text color
- Simplify expansion indicator to chevron

### FlowDetailPanel
- Replace Material TabBar with segmented-control style: selected tab gets rounded rect background, no underline indicator
- Section titles: `w600`, secondary text color
- Key-value tables: tighter spacing, monospace values

### StatusBar (26px)
- Gradient background matching toolbar
- Separator: `·` (middle dot) instead of `|`
- Connection dot: 6px + status text

## Files Changed

### Modified
- `lib/theme/app_theme.dart` — rewrite as JSON-driven theme loader
- `lib/main.dart` — async theme loading at startup
- `lib/pages/capture/global_bar.dart` — gradient, icon style, spacing
- `lib/pages/capture/toolbar.dart` — gradient, button style, search field
- `lib/pages/capture/filter_bar.dart` — chip style
- `lib/pages/capture/flow_table.dart` — header gradient, selection style, hover
- `lib/pages/capture/tree_panel.dart` — selection highlight, section headers
- `lib/pages/capture/flow_detail_panel.dart` — tab style, section titles
- `lib/pages/capture/status_bar.dart` — gradient, separator, dot
- `lib/pages/capture/content_panel.dart` — minor tab style alignment
- `lib/pages/capture/waterfall_tab.dart` — timing colors from JSON
- `lib/pages/capture/dashboard_tab.dart` — chart colors from JSON
- `lib/widgets/connection_indicator.dart` — dot size, colors from JSON
- `lib/widgets/key_value_table.dart` — tighter spacing, mono values
- `lib/widgets/json_viewer.dart` — syntax colors from JSON
- `lib/widgets/body_viewer.dart` — style alignment
- `lib/widgets/waterfall_bar.dart` — timing colors from JSON

### New
- `assets/theme.json` — theme configuration file

### Not Changed
- `lib/controllers/**` — no logic changes
- `lib/models/**` — no data model changes
- `lib/api/**` — no API changes
- `lib/utils/**` — no utility changes
- `lib/pages/compose/**` — visual pass deferred (lower priority)
- `lib/pages/history/**` — visual pass deferred
- `lib/pages/settings/**` — visual pass deferred
- `lib/pages/tools/**` — visual pass deferred

## Testing

- **Unit test:** JSON parsing, hex color conversion, fallback to defaults on invalid JSON
- **Manual verification:** Both light and dark themes on macOS Retina display
- **Regression:** Ensure all existing functionality unchanged (controllers, API, navigation)

## Risks

- `google_fonts` Inter renders slightly differently from SF Pro — acceptable
- 0.5px borders on non-Retina may round to 1px — Flutter handles well on Retina
- JSON loading is async — need splash or sync asset pre-load to avoid flash
