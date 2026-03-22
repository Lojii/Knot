import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BodyViewer extends StatelessWidget {
  final String body;
  final String contentType;
  final String label;

  const BodyViewer({
    super.key,
    required this.body,
    this.contentType = '',
    this.label = '',
  });

  @override
  Widget build(BuildContext context) {
    if (body.isEmpty) {
      return const Text('(empty)', style: TextStyle(color: Colors.grey, fontSize: 11));
    }

    // Image detection
    if (_isImage(contentType)) {
      return _imagePreview(context);
    }

    // JSON detection
    if (_isJson(contentType) || _looksLikeJson(body)) {
      return _jsonView(context);
    }

    // Default: raw text
    return SelectableText(body, style: AppTheme.mono(context));
  }

  Widget _jsonView(BuildContext context) {
    try {
      final obj = jsonDecode(body);
      final pretty = const JsonEncoder.withIndent('  ').convert(obj);
      return _SyntaxText(text: pretty, language: 'json');
    } catch (_) {
      return SelectableText(body, style: AppTheme.mono(context));
    }
  }

  Widget _imagePreview(BuildContext context) {
    // Try to decode base64 or show placeholder
    try {
      final bytes = base64Decode(body);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image Preview ($contentType)', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Cannot preview image')),
        ],
      );
    } catch (_) {
      return Text('Image ($contentType) — ${body.length} bytes', style: const TextStyle(fontSize: 11));
    }
  }

  bool _isImage(String ct) => ct.contains('image/');
  bool _isJson(String ct) => ct.contains('json');
  bool _looksLikeJson(String s) {
    final trimmed = s.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }
}

/// Simple syntax-colored text (no external dependency).
/// Colors JSON keys, strings, numbers, booleans differently.
class _SyntaxText extends StatelessWidget {
  final String text;
  final String language;
  const _SyntaxText({required this.text, required this.language});

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.mono(context);
    if (language != 'json') {
      return SelectableText(text, style: style);
    }
    return SelectableText.rich(
      _colorizeJson(text, style),
    );
  }

  TextSpan _colorizeJson(String json, TextStyle base) {
    final spans = <TextSpan>[];
    final re = RegExp(r'("(?:\\.|[^"\\])*")\s*:|("(?:\\.|[^"\\])*")|(\b\d+\.?\d*\b)|(\btrue\b|\bfalse\b|\bnull\b)');

    int lastEnd = 0;
    for (final m in re.allMatches(json)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: json.substring(lastEnd, m.start), style: base));
      }
      if (m.group(1) != null) {
        // JSON key
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(color: Colors.blue)));
        spans.add(TextSpan(text: ':', style: base));
      } else if (m.group(2) != null) {
        // String value
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(color: Colors.green)));
      } else if (m.group(3) != null) {
        // Number
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(color: Colors.orange)));
      } else if (m.group(4) != null) {
        // Boolean/null
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(color: Colors.purple)));
      }
      lastEnd = m.end;
    }
    if (lastEnd < json.length) {
      spans.add(TextSpan(text: json.substring(lastEnd), style: base));
    }
    return TextSpan(children: spans);
  }
}
