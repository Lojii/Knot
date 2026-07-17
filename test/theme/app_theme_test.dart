import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knot/theme/app_theme.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Disable network fetching for google_fonts in tests
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  group('AppTheme.parseHex', () {
    test('parses 6-digit hex string', () {
      final color = AppTheme.parseHex('#FF0000');
      expect(color, const Color(0xFFFF0000));
    });

    test('parses 6-digit hex string lowercase', () {
      final color = AppTheme.parseHex('#34c759');
      expect(color, const Color(0xFF34C759));
    });

    test('parses 8-digit hex string (RRGGBBAA)', () {
      // #007AFF14 => R=00 G=7A B=FF A=14
      final color = AppTheme.parseHex('#007AFF14');
      // Flutter Color is 0xAARRGGBB, so alpha=0x14, R=0x00, G=0x7A, B=0xFF
      expect(color, const Color(0x14007AFF));
    });

    test('returns fallback Color on invalid input', () {
      final color = AppTheme.parseHex('notacolor', fallback: 0xFFABCDEF);
      expect(color, const Color(0xFFABCDEF));
    });

    test('returns default fallback (black) on invalid input with no fallback', () {
      final color = AppTheme.parseHex('bad');
      expect(color, const Color(0xFF000000));
    });

    test('parses "transparent" keyword', () {
      final color = AppTheme.parseHex('transparent');
      expect(color, Colors.transparent);
    });

    test('returns fallback on empty string', () {
      final color = AppTheme.parseHex('', fallback: 0xFF112233);
      expect(color, const Color(0xFF112233));
    });
  });

  group('AppTheme.loadFromJson', () {
    test('parses valid JSON and sets scaffoldBackgroundColor', () {
      const json = '''
      {
        "light": {
          "colors": {
            "scaffold": "#AABBCC",
            "surface": "#FFFFFF",
            "divider": "#D1D1D6",
            "primary": "#007AFF",
            "textPrimary": "#1D1D1F",
            "textSecondary": "#86868B",
            "method": {"GET":"#34C759","POST":"#FF9F0A","PUT":"#007AFF","DELETE":"#FF3B30","PATCH":"#AF52DE","default":"#8E8E93"},
            "status": {"2xx":"#34C759","3xx":"#007AFF","4xx":"#FF9F0A","5xx":"#FF3B30","default":"#8E8E93"},
            "protocol": {"HTTP":"#007AFF","HTTPS":"#34C759","H2":"#FF9F0A","WS":"#AF52DE","WSS":"#FF3B30"},
            "connection": {"connected":"#34C759","connecting":"#FF9F0A","disconnected":"#FF3B30"},
            "timing": {"connect":"#FF9F0A","tls":"#AF52DE","request":"#007AFF","ttfb":"#34C759","response":"#30D158"},
            "syntax": {"key":"#0A2463","string":"#2E7D32","number":"#E65100","boolean":"#6A1B9A"}
          },
          "toolbar": {"gradient":{"start":"#FAFAFA","end":"#EBEBEB"},"borderWidth":0.5},
          "table": {"headerGradient":{"start":"#F4F4F5","end":"#EAEAEB"},"selectedBackground":"#007AFF14","selectedIndicatorWidth":2,"selectedIndicatorColor":"#007AFF"},
          "tree": {"selectedBackground":"#007AFF","selectedText":"#FFFFFF","selectedRadius":5},
          "filterChip": {"activeBackground":"#007AFF1F","activeBorder":"transparent","activeText":"#007AFF","inactiveBackground":"transparent","inactiveBorder":"#D1D1D6"},
          "detailTab": {"activeBackground":"#E8E8ED","activeText":"#1D1D1F","inactiveText":"#86868B","radius":5}
        },
        "dark": {
          "colors": {
            "scaffold": "#1C1C1E",
            "surface": "#2C2C2E",
            "divider": "#38383A",
            "primary": "#0A84FF",
            "textPrimary": "#F5F5F7",
            "textSecondary": "#98989D",
            "method": {"GET":"#30D158","POST":"#FF9F0A","PUT":"#0A84FF","DELETE":"#FF453A","PATCH":"#BF5AF2","default":"#8E8E93"},
            "status": {"2xx":"#30D158","3xx":"#0A84FF","4xx":"#FF9F0A","5xx":"#FF453A","default":"#8E8E93"},
            "protocol": {"HTTP":"#0A84FF","HTTPS":"#30D158","H2":"#FF9F0A","WS":"#BF5AF2","WSS":"#FF453A"},
            "connection": {"connected":"#30D158","connecting":"#FF9F0A","disconnected":"#FF453A"},
            "timing": {"connect":"#FF9F0A","tls":"#BF5AF2","request":"#0A84FF","ttfb":"#30D158","response":"#34C759"},
            "syntax": {"key":"#82AAFF","string":"#C3E88D","number":"#F78C6C","boolean":"#C792EA"}
          },
          "toolbar": {"gradient":{"start":"#2C2C2E","end":"#232325"},"borderWidth":0.5},
          "table": {"headerGradient":{"start":"#2C2C2E","end":"#262628"},"selectedBackground":"#0A84FF1F","selectedIndicatorWidth":2,"selectedIndicatorColor":"#0A84FF"},
          "tree": {"selectedBackground":"#0A84FF","selectedText":"#FFFFFF","selectedRadius":5},
          "filterChip": {"activeBackground":"#0A84FF26","activeBorder":"transparent","activeText":"#0A84FF","inactiveBackground":"transparent","inactiveBorder":"#38383A"},
          "detailTab": {"activeBackground":"#38383A","activeText":"#F5F5F7","inactiveText":"#98989D","radius":5}
        },
        "sizing": {
          "globalBarHeight":38,"toolbarHeight":38,"filterBarHeight":34,"statusBarHeight":26,
          "tableRowHeight":26,"tableHeaderHeight":28,"detailTabHeight":28,"treeDefaultWidth":220,
          "macOSTrafficLightWidth":78,"iconSize":16,"iconButtonSize":22,"connectionDotSize":6,
          "searchFieldWidth":240,"searchFieldHeight":28
        },
        "spacing": {"xs":4,"sm":8,"md":12,"lg":16,"xl":24},
        "fontSize": {"xs":10,"sm":11,"md":12,"lg":13,"xl":14},
        "fontFamily": {"ui":"Inter","mono":"JetBrains Mono","uiLetterSpacing":-0.2},
        "radius": {"sm":4,"md":6,"lg":8,"popup":10}
      }
      ''';

      AppTheme.loadFromJson(json);

      // Verify scaffold color from JSON was parsed (check parsed config, not ThemeData which uses GoogleFonts)
      expect(AppTheme.lightMode.colors.scaffold, const Color(0xFFAABBCC));

      // Verify spacing
      expect(AppTheme.spacing.xs, 4.0);
      expect(AppTheme.spacing.sm, 8.0);
      expect(AppTheme.spacing.md, 12.0);
      expect(AppTheme.spacing.lg, 16.0);
      expect(AppTheme.spacing.xl, 24.0);

      // Verify sizing
      expect(AppTheme.sizing.globalBarHeight, 38.0);
      expect(AppTheme.sizing.tableRowHeight, 26.0);
      expect(AppTheme.sizing.treeDefaultWidth, 220.0);
      expect(AppTheme.sizing.iconSize, 16.0);

      // Verify radius
      expect(AppTheme.radius.sm, 4.0);
      expect(AppTheme.radius.md, 6.0);
      expect(AppTheme.radius.lg, 8.0);
      expect(AppTheme.radius.popup, 10.0);

      // Verify fontConfig
      expect(AppTheme.fontConfig.ui, 'Inter');
      expect(AppTheme.fontConfig.mono, 'JetBrains Mono');
      expect(AppTheme.fontConfig.uiLetterSpacing, -0.2);
    });

    test('falls back to defaults on invalid JSON', () {
      AppTheme.loadFromJson('{ invalid json }');

      // After invalid JSON, should have defaults
      expect(AppTheme.spacing.xs, 4.0);
      expect(AppTheme.spacing.sm, 8.0);
      expect(AppTheme.sizing.globalBarHeight, 38.0);
      expect(AppTheme.radius.sm, 4.0);
      expect(AppTheme.fontConfig.ui, 'Inter');

      // Dark scaffold should be the hardcoded default (check parsed config, not ThemeData)
      expect(AppTheme.darkMode.colors.scaffold, const Color(0xFF1C1C1E));
    });
  });

  group('AppTheme method colors', () {
    test('defaults define colors for all HTTP methods plus fallback', () {
      AppTheme.loadFromJson('invalid'); // reset to defaults
      for (final mode in [AppTheme.lightMode, AppTheme.darkMode]) {
        for (final m in ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'default']) {
          expect(mode.colors.method[m], isNotNull, reason: 'missing $m');
        }
      }
    });

    test('method map is keyed by uppercase names', () {
      AppTheme.loadFromJson('invalid'); // reset to defaults
      // methodColorOf uppercases its input before the lookup
      expect(AppTheme.lightMode.colors.method['get'], isNull);
      expect(AppTheme.lightMode.colors.method['GET'], isNotNull);
    });
  });

  group('AppTheme status colors', () {
    test('light mode defaults', () {
      AppTheme.loadFromJson('invalid'); // reset to defaults
      final status = AppTheme.lightMode.colors.status;
      expect(status['2xx'], AppTheme.parseHex('#34C759'));
      expect(status['3xx'], AppTheme.parseHex('#007AFF'));
      expect(status['4xx'], AppTheme.parseHex('#FF9F0A'));
      expect(status['5xx'], AppTheme.parseHex('#FF3B30'));
      expect(status['default'], AppTheme.parseHex('#8E8E93'));
    });

    test('dark mode defaults', () {
      AppTheme.loadFromJson('invalid'); // reset to defaults
      final status = AppTheme.darkMode.colors.status;
      expect(status['2xx'], AppTheme.parseHex('#30D158'));
      expect(status['3xx'], AppTheme.parseHex('#0A84FF'));
      expect(status['4xx'], AppTheme.parseHex('#FF9F0A'));
      expect(status['5xx'], AppTheme.parseHex('#FF453A'));
      expect(status['default'], AppTheme.parseHex('#8E8E93'));
    });
  });

  group('AppTheme semantic colors and xxl font size', () {
    test('new semantic colors have defaults', () {
      AppTheme.loadFromJson('invalid'); // reset to defaults
      expect(AppTheme.lightMode.colors.favorite, const Color(0xFFFFC107));
      expect(AppTheme.lightMode.colors.diffAdded, const Color(0xFF34C759));
      expect(AppTheme.lightMode.colors.diffRemoved, const Color(0xFFFF3B30));
      expect(AppTheme.darkMode.colors.diffAdded, const Color(0xFF30D158));
    });

    test('fontSize has xxl tier', () {
      AppTheme.loadFromJson('invalid'); // reset to defaults
      expect(AppTheme.fontSize.xxl, 20.0);
    });

    test('loadFromJson without new keys falls back to defaults for them', () {
      final jsonString = File('assets/theme.json').readAsStringSync();
      AppTheme.loadFromJson(jsonString);
      expect(AppTheme.lightMode.colors.favorite, const Color(0xFFFFC107));
      expect(AppTheme.fontSize.xxl, 20.0);

      AppTheme.loadFromJson('invalid'); // reset to defaults
    });
  });
}
