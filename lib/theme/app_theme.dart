import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized theme for the entire Knot app.
/// All colors, fonts, spacing, and sizing are defined here.
/// To change the look of the app, modify only this file.
class AppTheme {
  // ============ SPACING ============
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 12.0;
  static const double spacingLG = 16.0;
  static const double spacingXL = 24.0;

  // ============ SIZING ============
  static const double globalBarHeight = 38.0;
  static const double toolbarHeight = 38.0;
  static const double filterBarHeight = 34.0;
  static const double statusBarHeight = 26.0;
  static const double tableRowHeight = 26.0;
  static const double tableHeaderHeight = 28.0;
  static const double treeDefaultWidth = 220.0;
  static const double detailTabHeight = 28.0;
  static const double macOSTrafficLightWidth = 78.0;

  // ============ FONT SIZES ============
  static const double fontSizeXS = 10.0;
  static const double fontSizeSM = 11.0;
  static const double fontSizeMD = 12.0;
  static const double fontSizeLG = 13.0;
  static const double fontSizeXL = 14.0;

  // ============ BORDER RADIUS ============
  static const double radiusSM = 4.0;
  static const double radiusMD = 6.0;
  static const double radiusLG = 8.0;

  // ============ HTTP METHOD COLORS ============
  static const Color methodGet = Color(0xFF4CAF50);
  static const Color methodPost = Color(0xFFFF9800);
  static const Color methodPut = Color(0xFF2196F3);
  static const Color methodDelete = Color(0xFFF44336);
  static const Color methodPatch = Color(0xFF9C27B0);
  static const Color methodDefault = Color(0xFF9E9E9E);

  static Color methodColor(String method) => switch (method.toUpperCase()) {
    'GET' => methodGet,
    'POST' => methodPost,
    'PUT' => methodPut,
    'DELETE' => methodDelete,
    'PATCH' => methodPatch,
    _ => methodDefault,
  };

  // ============ STATUS CODE COLORS ============
  static Color statusColor(int code) {
    if (code >= 500) return const Color(0xFFF44336);
    if (code >= 400) return const Color(0xFFFF9800);
    if (code >= 300) return const Color(0xFF2196F3);
    if (code >= 200) return const Color(0xFF4CAF50);
    return const Color(0xFF9E9E9E);
  }

  // ============ PROTOCOL COLORS (for charts) ============
  static const Map<String, Color> protocolColors = {
    'HTTP': Color(0xFF42A5F5),
    'HTTPS': Color(0xFF66BB6A),
    'H2': Color(0xFFFFA726),
    'WS': Color(0xFFAB47BC),
    'WSS': Color(0xFFEF5350),
  };

  // ============ CONNECTION STATUS ============
  static const Color statusConnected = Color(0xFF4CAF50);
  static const Color statusConnecting = Color(0xFFFF9800);
  static const Color statusDisconnected = Color(0xFFF44336);

  // ============ WATERFALL TIMING COLORS ============
  static const Color timingConnect = Color(0xFFFF9800);
  static const Color timingTLS = Color(0xFF9C27B0);
  static const Color timingRequest = Color(0xFF2196F3);
  static const Color timingTTFB = Color(0xFF81C784);
  static const Color timingResponse = Color(0xFF4CAF50);

  // ============ SYNTAX HIGHLIGHTING ============
  static Color syntaxKey(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF82AAFF) : const Color(0xFF1565C0);
  static Color syntaxString(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFC3E88D) : const Color(0xFF2E7D32);
  static Color syntaxNumber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF78C6C) : const Color(0xFFE65100);
  static Color syntaxBool(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFC792EA) : const Color(0xFF6A1B9A);

  // ============ FONTS ============
  static TextStyle monoStyle(BuildContext context, {double? fontSize, Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize ?? fontSizeSM,
      color: color ?? Theme.of(context).textTheme.bodyMedium?.color,
      height: 1.5,
    );
  }

  static TextStyle mono(BuildContext context) => monoStyle(context);

  // ============ THEMES ============

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xFF1E88E5),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      dividerColor: const Color(0xFFE0E0E0),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF42A5F5),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF1E1E2E),
      dividerColor: const Color(0xFF2E2E3E),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
    );
  }
}
