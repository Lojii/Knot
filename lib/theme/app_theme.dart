import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================
// Data classes
// ============================================================

class ThemeColors {
  final Color scaffold;
  final Color surface;
  final Color divider;
  final Color primary;
  final Color textPrimary;
  final Color textSecondary;
  final Map<String, Color> method;
  final Map<String, Color> status;
  final Map<String, Color> protocol;
  final Color statusConnected;
  final Color statusConnecting;
  final Color statusDisconnected;
  final Color timingConnect;
  final Color timingTLS;
  final Color timingRequest;
  final Color timingTTFB;
  final Color timingResponse;
  final Color syntaxKeyColor;
  final Color syntaxStringColor;
  final Color syntaxNumberColor;
  final Color syntaxBoolColor;

  const ThemeColors({
    required this.scaffold,
    required this.surface,
    required this.divider,
    required this.primary,
    required this.textPrimary,
    required this.textSecondary,
    required this.method,
    required this.status,
    required this.protocol,
    required this.statusConnected,
    required this.statusConnecting,
    required this.statusDisconnected,
    required this.timingConnect,
    required this.timingTLS,
    required this.timingRequest,
    required this.timingTTFB,
    required this.timingResponse,
    required this.syntaxKeyColor,
    required this.syntaxStringColor,
    required this.syntaxNumberColor,
    required this.syntaxBoolColor,
  });
}

class ToolbarConfig {
  final Color gradientStart;
  final Color gradientEnd;
  final double borderWidth;

  const ToolbarConfig({
    required this.gradientStart,
    required this.gradientEnd,
    required this.borderWidth,
  });
}

class TableConfig {
  final Color headerGradientStart;
  final Color headerGradientEnd;
  final Color selectedBackground;
  final Color selectedIndicatorColor;
  final double selectedIndicatorWidth;

  const TableConfig({
    required this.headerGradientStart,
    required this.headerGradientEnd,
    required this.selectedBackground,
    required this.selectedIndicatorColor,
    required this.selectedIndicatorWidth,
  });
}

class TreeConfig {
  final Color selectedBackground;
  final Color selectedText;
  final double selectedRadius;

  const TreeConfig({
    required this.selectedBackground,
    required this.selectedText,
    required this.selectedRadius,
  });
}

class FilterChipConfig {
  final Color activeBackground;
  final Color activeBorder;
  final Color activeText;
  final Color inactiveBackground;
  final Color inactiveBorder;

  const FilterChipConfig({
    required this.activeBackground,
    required this.activeBorder,
    required this.activeText,
    required this.inactiveBackground,
    required this.inactiveBorder,
  });
}

class DetailTabConfig {
  final Color activeBackground;
  final Color activeText;
  final Color inactiveText;
  final double radius;

  const DetailTabConfig({
    required this.activeBackground,
    required this.activeText,
    required this.inactiveText,
    required this.radius,
  });
}

class ModeColors {
  final ThemeColors colors;
  final ToolbarConfig toolbar;
  final TableConfig table;
  final TreeConfig tree;
  final FilterChipConfig filterChip;
  final DetailTabConfig detailTab;

  const ModeColors({
    required this.colors,
    required this.toolbar,
    required this.table,
    required this.tree,
    required this.filterChip,
    required this.detailTab,
  });
}

class SpacingConfig {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  const SpacingConfig({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });
}

class SizingConfig {
  final double globalBarHeight;
  final double toolbarHeight;
  final double filterBarHeight;
  final double statusBarHeight;
  final double tableRowHeight;
  final double tableHeaderHeight;
  final double detailTabHeight;
  final double treeDefaultWidth;
  final double macOSTrafficLightWidth;
  final double iconSize;
  final double iconButtonSize;
  final double connectionDotSize;
  final double searchFieldWidth;
  final double searchFieldHeight;

  const SizingConfig({
    required this.globalBarHeight,
    required this.toolbarHeight,
    required this.filterBarHeight,
    required this.statusBarHeight,
    required this.tableRowHeight,
    required this.tableHeaderHeight,
    required this.detailTabHeight,
    required this.treeDefaultWidth,
    required this.macOSTrafficLightWidth,
    required this.iconSize,
    required this.iconButtonSize,
    required this.connectionDotSize,
    required this.searchFieldWidth,
    required this.searchFieldHeight,
  });
}

class FontConfig {
  final String ui;
  final String mono;
  final double uiLetterSpacing;

  const FontConfig({
    required this.ui,
    required this.mono,
    required this.uiLetterSpacing,
  });
}

class RadiusConfig {
  final double sm;
  final double md;
  final double lg;
  final double popup;

  const RadiusConfig({
    required this.sm,
    required this.md,
    required this.lg,
    required this.popup,
  });
}

class FontSizeConfig {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  const FontSizeConfig({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });
}

// ============================================================
// Hardcoded defaults
// ============================================================

ModeColors _defaultLightMode() {
  return ModeColors(
    colors: ThemeColors(
      scaffold: const Color(0xFFF5F5F7),
      surface: const Color(0xFFFFFFFF),
      divider: const Color(0xFFD1D1D6),
      primary: const Color(0xFF007AFF),
      textPrimary: const Color(0xFF1D1D1F),
      textSecondary: const Color(0xFF86868B),
      method: {
        'GET': const Color(0xFF34C759),
        'POST': const Color(0xFFFF9F0A),
        'PUT': const Color(0xFF007AFF),
        'DELETE': const Color(0xFFFF3B30),
        'PATCH': const Color(0xFFAF52DE),
        'default': const Color(0xFF8E8E93),
      },
      status: {
        '2xx': const Color(0xFF34C759),
        '3xx': const Color(0xFF007AFF),
        '4xx': const Color(0xFFFF9F0A),
        '5xx': const Color(0xFFFF3B30),
        'default': const Color(0xFF8E8E93),
      },
      protocol: {
        'HTTP': const Color(0xFF007AFF),
        'HTTPS': const Color(0xFF34C759),
        'H2': const Color(0xFFFF9F0A),
        'WS': const Color(0xFFAF52DE),
        'WSS': const Color(0xFFFF3B30),
      },
      statusConnected: const Color(0xFF34C759),
      statusConnecting: const Color(0xFFFF9F0A),
      statusDisconnected: const Color(0xFFFF3B30),
      timingConnect: const Color(0xFFFF9F0A),
      timingTLS: const Color(0xFFAF52DE),
      timingRequest: const Color(0xFF007AFF),
      timingTTFB: const Color(0xFF34C759),
      timingResponse: const Color(0xFF30D158),
      syntaxKeyColor: const Color(0xFF0A2463),
      syntaxStringColor: const Color(0xFF2E7D32),
      syntaxNumberColor: const Color(0xFFE65100),
      syntaxBoolColor: const Color(0xFF6A1B9A),
    ),
    toolbar: const ToolbarConfig(
      gradientStart: Color(0xFFFAFAFA),
      gradientEnd: Color(0xFFEBEBEB),
      borderWidth: 0.5,
    ),
    table: const TableConfig(
      headerGradientStart: Color(0xFFF4F4F5),
      headerGradientEnd: Color(0xFFEAEAEB),
      selectedBackground: Color(0x14007AFF),
      selectedIndicatorColor: Color(0xFF007AFF),
      selectedIndicatorWidth: 2.0,
    ),
    tree: const TreeConfig(
      selectedBackground: Color(0xFFE8E8ED),
      selectedText: Color(0xFF1D1D1F),
      selectedRadius: 5.0,
    ),
    filterChip: const FilterChipConfig(
      activeBackground: Color(0x1F007AFF),
      activeBorder: Colors.transparent,
      activeText: Color(0xFF007AFF),
      inactiveBackground: Colors.transparent,
      inactiveBorder: Color(0xFFD1D1D6),
    ),
    detailTab: const DetailTabConfig(
      activeBackground: Color(0xFFE8E8ED),
      activeText: Color(0xFF1D1D1F),
      inactiveText: Color(0xFF86868B),
      radius: 5.0,
    ),
  );
}

ModeColors _defaultDarkMode() {
  return ModeColors(
    colors: ThemeColors(
      scaffold: const Color(0xFF1C1C1E),
      surface: const Color(0xFF2C2C2E),
      divider: const Color(0xFF38383A),
      primary: const Color(0xFF0A84FF),
      textPrimary: const Color(0xFFF5F5F7),
      textSecondary: const Color(0xFF98989D),
      method: {
        'GET': const Color(0xFF30D158),
        'POST': const Color(0xFFFF9F0A),
        'PUT': const Color(0xFF0A84FF),
        'DELETE': const Color(0xFFFF453A),
        'PATCH': const Color(0xFFBF5AF2),
        'default': const Color(0xFF8E8E93),
      },
      status: {
        '2xx': const Color(0xFF30D158),
        '3xx': const Color(0xFF0A84FF),
        '4xx': const Color(0xFFFF9F0A),
        '5xx': const Color(0xFFFF453A),
        'default': const Color(0xFF8E8E93),
      },
      protocol: {
        'HTTP': const Color(0xFF0A84FF),
        'HTTPS': const Color(0xFF30D158),
        'H2': const Color(0xFFFF9F0A),
        'WS': const Color(0xFFBF5AF2),
        'WSS': const Color(0xFFFF453A),
      },
      statusConnected: const Color(0xFF30D158),
      statusConnecting: const Color(0xFFFF9F0A),
      statusDisconnected: const Color(0xFFFF453A),
      timingConnect: const Color(0xFFFF9F0A),
      timingTLS: const Color(0xFFBF5AF2),
      timingRequest: const Color(0xFF0A84FF),
      timingTTFB: const Color(0xFF30D158),
      timingResponse: const Color(0xFF34C759),
      syntaxKeyColor: const Color(0xFF82AAFF),
      syntaxStringColor: const Color(0xFFC3E88D),
      syntaxNumberColor: const Color(0xFFF78C6C),
      syntaxBoolColor: const Color(0xFFC792EA),
    ),
    toolbar: const ToolbarConfig(
      gradientStart: Color(0xFF2C2C2E),
      gradientEnd: Color(0xFF232325),
      borderWidth: 0.5,
    ),
    table: const TableConfig(
      headerGradientStart: Color(0xFF2C2C2E),
      headerGradientEnd: Color(0xFF262628),
      selectedBackground: Color(0x1F0A84FF),
      selectedIndicatorColor: Color(0xFF0A84FF),
      selectedIndicatorWidth: 2.0,
    ),
    tree: const TreeConfig(
      selectedBackground: Color(0xFF38383A),
      selectedText: Color(0xFFE5E5EA),
      selectedRadius: 5.0,
    ),
    filterChip: const FilterChipConfig(
      activeBackground: Color(0x260A84FF),
      activeBorder: Colors.transparent,
      activeText: Color(0xFF0A84FF),
      inactiveBackground: Colors.transparent,
      inactiveBorder: Color(0xFF38383A),
    ),
    detailTab: const DetailTabConfig(
      activeBackground: Color(0xFF38383A),
      activeText: Color(0xFFF5F5F7),
      inactiveText: Color(0xFF98989D),
      radius: 5.0,
    ),
  );
}

const SpacingConfig _defaultSpacing = SpacingConfig(
  xs: 4.0, sm: 8.0, md: 12.0, lg: 16.0, xl: 24.0,
);

const SizingConfig _defaultSizing = SizingConfig(
  globalBarHeight: 38.0,
  toolbarHeight: 38.0,
  filterBarHeight: 34.0,
  statusBarHeight: 26.0,
  tableRowHeight: 26.0,
  tableHeaderHeight: 28.0,
  detailTabHeight: 28.0,
  treeDefaultWidth: 220.0,
  macOSTrafficLightWidth: 78.0,
  iconSize: 16.0,
  iconButtonSize: 22.0,
  connectionDotSize: 6.0,
  searchFieldWidth: 240.0,
  searchFieldHeight: 28.0,
);

const FontConfig _defaultFontConfig = FontConfig(
  ui: 'Inter',
  mono: 'JetBrains Mono',
  uiLetterSpacing: -0.2,
);

const RadiusConfig _defaultRadius = RadiusConfig(
  sm: 4.0, md: 6.0, lg: 8.0, popup: 10.0,
);

const FontSizeConfig _defaultFontSize = FontSizeConfig(
  xs: 10.0, sm: 11.0, md: 12.0, lg: 13.0, xl: 14.0,
);

// ============================================================
// AppTheme singleton
// ============================================================

class AppTheme {
  AppTheme._();

  // Singleton state
  static ModeColors _light = _defaultLightMode();
  static ModeColors _dark = _defaultDarkMode();
  static SpacingConfig _spacing = _defaultSpacing;
  static SizingConfig _sizing = _defaultSizing;
  static FontConfig _fontConfig = _defaultFontConfig;
  static RadiusConfig _radius = _defaultRadius;
  static FontSizeConfig _fontSize = _defaultFontSize;

  // ============ Static getters ============

  static SpacingConfig get spacing => _spacing;
  static SizingConfig get sizing => _sizing;
  static RadiusConfig get radius => _radius;
  static FontConfig get fontConfig => _fontConfig;
  static FontSizeConfig get fontSize => _fontSize;

  /// Direct access to parsed light/dark mode config (useful in tests).
  static ModeColors get lightMode => _light;
  static ModeColors get darkMode => _dark;

  // ============ parseHex ============

  /// Parse "#RRGGBB" or "#RRGGBBAA" hex strings to Color.
  /// Also handles "transparent". Returns fallback Color on invalid input.
  static Color parseHex(String hex, {int fallback = 0xFF000000}) {
    if (hex == 'transparent') return Colors.transparent;
    if (!hex.startsWith('#')) return Color(fallback);
    final raw = hex.substring(1).toUpperCase();
    if (raw.length == 6) {
      final value = int.tryParse(raw, radix: 16);
      if (value == null) return Color(fallback);
      return Color(0xFF000000 | value);
    } else if (raw.length == 8) {
      // Format: RRGGBBAA — convert to Flutter's 0xAARRGGBB
      final value = int.tryParse(raw, radix: 16);
      if (value == null) return Color(fallback);
      final r = (value >> 24) & 0xFF;
      final g = (value >> 16) & 0xFF;
      final b = (value >> 8) & 0xFF;
      final a = value & 0xFF;
      return Color((a << 24) | (r << 16) | (g << 8) | b);
    }
    return Color(fallback);
  }

  // ============ loadFromJson ============

  static void loadFromJson(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      _light = _parseModeColors(data['light'] as Map<String, dynamic>);
      _dark = _parseModeColors(data['dark'] as Map<String, dynamic>);
      _spacing = _parseSpacing(data['spacing'] as Map<String, dynamic>);
      _sizing = _parseSizing(data['sizing'] as Map<String, dynamic>);
      _fontConfig = _parseFontConfig(data['fontFamily'] as Map<String, dynamic>);
      _radius = _parseRadius(data['radius'] as Map<String, dynamic>);
      _fontSize = _parseFontSize(data['fontSize'] as Map<String, dynamic>);
    } catch (_) {
      _light = _defaultLightMode();
      _dark = _defaultDarkMode();
      _spacing = _defaultSpacing;
      _sizing = _defaultSizing;
      _fontConfig = _defaultFontConfig;
      _radius = _defaultRadius;
      _fontSize = _defaultFontSize;
    }
  }

  static Future<void> loadFromAsset() async {
    final jsonString = await rootBundle.loadString('assets/theme.json');
    loadFromJson(jsonString);
  }

  // ============ Brightness-aware accessors ============

  static ModeColors mode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }

  static ThemeColors colors(BuildContext context) => mode(context).colors;

  // ============ Convenience methods ============

  /// Context-aware method color.
  static Color methodColorOf(BuildContext context, String method) {
    final key = method.toUpperCase();
    final c = colors(context);
    return c.method[key] ?? c.method['default']!;
  }

  /// Context-aware status color.
  static Color statusColorOf(BuildContext context, int code) {
    final statusMap = colors(context).status;
    if (code >= 500) return statusMap['5xx']!;
    if (code >= 400) return statusMap['4xx']!;
    if (code >= 300) return statusMap['3xx']!;
    if (code >= 200) return statusMap['2xx']!;
    return statusMap['default']!;
  }

  static Color syntaxKey(BuildContext context) => colors(context).syntaxKeyColor;
  static Color syntaxString(BuildContext context) => colors(context).syntaxStringColor;
  static Color syntaxNumber(BuildContext context) => colors(context).syntaxNumberColor;
  static Color syntaxBool(BuildContext context) => colors(context).syntaxBoolColor;

  static TextStyle monoStyle(BuildContext context, {double? fontSize, Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize ?? _fontSize.sm,
      color: color ?? Theme.of(context).textTheme.bodyMedium?.color,
      height: 1.5,
    );
  }

  static TextStyle mono(BuildContext context) => monoStyle(context);

  // ============ ThemeData builders ============

  static ThemeData light() {
    final c = _light.colors;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: c.primary,
        surface: c.surface,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: c.scaffold,
      dividerColor: c.divider,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
    );
  }

  static ThemeData dark() {
    final c = _dark.colors;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: c.primary,
        surface: c.surface,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: c.scaffold,
      dividerColor: c.divider,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
    );
  }

  // ============ Private parsers ============

  static ModeColors _parseModeColors(Map<String, dynamic> m) {
    final colorsMap = m['colors'] as Map<String, dynamic>;
    final toolbarMap = m['toolbar'] as Map<String, dynamic>;
    final tableMap = m['table'] as Map<String, dynamic>;
    final treeMap = m['tree'] as Map<String, dynamic>;
    final chipMap = m['filterChip'] as Map<String, dynamic>;
    final tabMap = m['detailTab'] as Map<String, dynamic>;

    return ModeColors(
      colors: _parseThemeColors(colorsMap),
      toolbar: _parseToolbarConfig(toolbarMap),
      table: _parseTableConfig(tableMap),
      tree: _parseTreeConfig(treeMap),
      filterChip: _parseFilterChipConfig(chipMap),
      detailTab: _parseDetailTabConfig(tabMap),
    );
  }

  static ThemeColors _parseThemeColors(Map<String, dynamic> m) {
    Map<String, Color> colorMap(Map<String, dynamic> raw) =>
        raw.map((k, v) => MapEntry(k, parseHex(v as String)));

    final conn = m['connection'] as Map<String, dynamic>;
    final timing = m['timing'] as Map<String, dynamic>;
    final syntax = m['syntax'] as Map<String, dynamic>;

    return ThemeColors(
      scaffold: parseHex(m['scaffold'] as String),
      surface: parseHex(m['surface'] as String),
      divider: parseHex(m['divider'] as String),
      primary: parseHex(m['primary'] as String),
      textPrimary: parseHex(m['textPrimary'] as String),
      textSecondary: parseHex(m['textSecondary'] as String),
      method: colorMap(m['method'] as Map<String, dynamic>),
      status: colorMap(m['status'] as Map<String, dynamic>),
      protocol: colorMap(m['protocol'] as Map<String, dynamic>),
      statusConnected: parseHex(conn['connected'] as String),
      statusConnecting: parseHex(conn['connecting'] as String),
      statusDisconnected: parseHex(conn['disconnected'] as String),
      timingConnect: parseHex(timing['connect'] as String),
      timingTLS: parseHex(timing['tls'] as String),
      timingRequest: parseHex(timing['request'] as String),
      timingTTFB: parseHex(timing['ttfb'] as String),
      timingResponse: parseHex(timing['response'] as String),
      syntaxKeyColor: parseHex(syntax['key'] as String),
      syntaxStringColor: parseHex(syntax['string'] as String),
      syntaxNumberColor: parseHex(syntax['number'] as String),
      syntaxBoolColor: parseHex(syntax['boolean'] as String),
    );
  }

  static ToolbarConfig _parseToolbarConfig(Map<String, dynamic> m) {
    final gradient = m['gradient'] as Map<String, dynamic>;
    return ToolbarConfig(
      gradientStart: parseHex(gradient['start'] as String),
      gradientEnd: parseHex(gradient['end'] as String),
      borderWidth: (m['borderWidth'] as num).toDouble(),
    );
  }

  static TableConfig _parseTableConfig(Map<String, dynamic> m) {
    final hg = m['headerGradient'] as Map<String, dynamic>;
    return TableConfig(
      headerGradientStart: parseHex(hg['start'] as String),
      headerGradientEnd: parseHex(hg['end'] as String),
      selectedBackground: parseHex(m['selectedBackground'] as String),
      selectedIndicatorColor: parseHex(m['selectedIndicatorColor'] as String),
      selectedIndicatorWidth: (m['selectedIndicatorWidth'] as num).toDouble(),
    );
  }

  static TreeConfig _parseTreeConfig(Map<String, dynamic> m) {
    return TreeConfig(
      selectedBackground: parseHex(m['selectedBackground'] as String),
      selectedText: parseHex(m['selectedText'] as String),
      selectedRadius: (m['selectedRadius'] as num).toDouble(),
    );
  }

  static FilterChipConfig _parseFilterChipConfig(Map<String, dynamic> m) {
    return FilterChipConfig(
      activeBackground: parseHex(m['activeBackground'] as String),
      activeBorder: parseHex(m['activeBorder'] as String),
      activeText: parseHex(m['activeText'] as String),
      inactiveBackground: parseHex(m['inactiveBackground'] as String),
      inactiveBorder: parseHex(m['inactiveBorder'] as String),
    );
  }

  static DetailTabConfig _parseDetailTabConfig(Map<String, dynamic> m) {
    return DetailTabConfig(
      activeBackground: parseHex(m['activeBackground'] as String),
      activeText: parseHex(m['activeText'] as String),
      inactiveText: parseHex(m['inactiveText'] as String),
      radius: (m['radius'] as num).toDouble(),
    );
  }

  static SpacingConfig _parseSpacing(Map<String, dynamic> m) {
    return SpacingConfig(
      xs: (m['xs'] as num).toDouble(),
      sm: (m['sm'] as num).toDouble(),
      md: (m['md'] as num).toDouble(),
      lg: (m['lg'] as num).toDouble(),
      xl: (m['xl'] as num).toDouble(),
    );
  }

  static SizingConfig _parseSizing(Map<String, dynamic> m) {
    return SizingConfig(
      globalBarHeight: (m['globalBarHeight'] as num).toDouble(),
      toolbarHeight: (m['toolbarHeight'] as num).toDouble(),
      filterBarHeight: (m['filterBarHeight'] as num).toDouble(),
      statusBarHeight: (m['statusBarHeight'] as num).toDouble(),
      tableRowHeight: (m['tableRowHeight'] as num).toDouble(),
      tableHeaderHeight: (m['tableHeaderHeight'] as num).toDouble(),
      detailTabHeight: (m['detailTabHeight'] as num).toDouble(),
      treeDefaultWidth: (m['treeDefaultWidth'] as num).toDouble(),
      macOSTrafficLightWidth: (m['macOSTrafficLightWidth'] as num).toDouble(),
      iconSize: (m['iconSize'] as num).toDouble(),
      iconButtonSize: (m['iconButtonSize'] as num).toDouble(),
      connectionDotSize: (m['connectionDotSize'] as num).toDouble(),
      searchFieldWidth: (m['searchFieldWidth'] as num).toDouble(),
      searchFieldHeight: (m['searchFieldHeight'] as num).toDouble(),
    );
  }

  static FontConfig _parseFontConfig(Map<String, dynamic> m) {
    return FontConfig(
      ui: m['ui'] as String,
      mono: m['mono'] as String,
      uiLetterSpacing: (m['uiLetterSpacing'] as num).toDouble(),
    );
  }

  static RadiusConfig _parseRadius(Map<String, dynamic> m) {
    return RadiusConfig(
      sm: (m['sm'] as num).toDouble(),
      md: (m['md'] as num).toDouble(),
      lg: (m['lg'] as num).toDouble(),
      popup: (m['popup'] as num).toDouble(),
    );
  }

  static FontSizeConfig _parseFontSize(Map<String, dynamic> m) {
    return FontSizeConfig(
      xs: (m['xs'] as num).toDouble(),
      sm: (m['sm'] as num).toDouble(),
      md: (m['md'] as num).toDouble(),
      lg: (m['lg'] as num).toDouble(),
      xl: (m['xl'] as num).toDouble(),
    );
  }
}
