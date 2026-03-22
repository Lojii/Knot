import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: Colors.blue,
    textTheme: GoogleFonts.interTextTheme(),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1a1a2e),
    colorSchemeSeed: Colors.blue,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  );

  static TextStyle mono(BuildContext context) => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    color: Theme.of(context).textTheme.bodyMedium?.color,
  );
}
