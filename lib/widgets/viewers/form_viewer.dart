import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../key_value_table.dart';
import '../../theme/app_theme.dart';

/// Viewer for application/x-www-form-urlencoded bodies.
class FormViewer extends StatelessWidget {
  final Uint8List bytes;

  const FormViewer({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    String text;
    try { text = utf8.decode(bytes); } catch (_) { text = latin1.decode(bytes); }

    final pairs = Uri.splitQueryString(text);
    if (pairs.isEmpty) {
      return SelectableText(text, style: AppTheme.mono(context));
    }

    final entries = pairs.entries.map((e) => (
      Uri.decodeComponent(e.key),
      Uri.decodeComponent(e.value),
    )).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(AppTheme.spacing.sm),
      child: KeyValueTable(entries: entries),
    );
  }
}
