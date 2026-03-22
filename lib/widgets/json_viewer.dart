import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class JsonViewer extends StatelessWidget {
  final String jsonString;
  const JsonViewer({super.key, required this.jsonString});

  @override
  Widget build(BuildContext context) {
    String formatted;
    try {
      final obj = jsonDecode(jsonString);
      formatted = const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      formatted = jsonString;
    }
    return SelectableText(formatted, style: AppTheme.mono(context));
  }
}
