import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Simple code viewer with syntax highlighting and line numbers.
/// Uses custom regex-based highlighter (no external dependency issues).
class CodeViewer extends StatelessWidget {
  final Uint8List bytes;
  final String language;
  final bool formatJson;

  const CodeViewer({
    super.key,
    required this.bytes,
    this.language = 'text',
    this.formatJson = true,
  });

  String get _text {
    String raw;
    try { raw = utf8.decode(bytes); } catch (_) { raw = latin1.decode(bytes); }
    if (language == 'json' && formatJson) {
      try {
        final obj = jsonDecode(raw);
        return const JsonEncoder.withIndent('  ').convert(obj);
      } catch (_) {}
    }
    if (language == 'xml' || language == 'html') {
      return _indentXml(raw);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final lines = text.split('\n');
    final style = AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.sm);
    final lineNumColor = AppTheme.colors(context).textSecondary;

    return SelectableText.rich(
      TextSpan(
        children: [
          for (int i = 0; i < lines.length; i++) ...[
            // Line number
            TextSpan(
              text: '${(i + 1).toString().padLeft(4)} ',
              style: style.copyWith(color: lineNumColor),
            ),
            // Highlighted content
            ..._highlightLine(context, lines[i], style),
            const TextSpan(text: '\n'),
          ],
        ],
      ),
    );
  }

  List<TextSpan> _highlightLine(BuildContext context, String line, TextStyle base) {
    switch (language) {
      case 'json':
        return _highlightJson(context, line, base);
      case 'html':
      case 'xml':
        return _highlightMarkup(context, line, base);
      case 'css':
        return _highlightCss(context, line, base);
      case 'javascript':
        return _highlightJs(context, line, base);
      default:
        return [TextSpan(text: line, style: base)];
    }
  }

  // ── JSON highlighting ──

  List<TextSpan> _highlightJson(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    final re = RegExp(r'("(?:\\.|[^"\\])*")\s*:|("(?:\\.|[^"\\])*")|(\b-?\d+\.?\d*(?:[eE][+-]?\d+)?\b)|(\btrue\b|\bfalse\b|\bnull\b)');
    int last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start), style: base));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(color: AppTheme.syntaxKey(context))));
        spans.add(TextSpan(text: ':', style: base));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(color: AppTheme.syntaxString(context))));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(color: AppTheme.syntaxNumber(context))));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(color: AppTheme.syntaxBool(context))));
      }
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: base));
    return spans.isEmpty ? [TextSpan(text: line, style: base)] : spans;
  }

  // ── HTML/XML highlighting ──

  List<TextSpan> _highlightMarkup(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    final re = RegExp(r'(</?[a-zA-Z][a-zA-Z0-9:-]*)|(\s[a-zA-Z:-]+=)("[^"]*"|' "'[^']*'" r')|(/>|>|<!--.*?-->)');
    int last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start), style: base));
      final txt = m.group(0)!;
      if (txt.startsWith('<')) {
        spans.add(TextSpan(text: txt, style: base.copyWith(color: AppTheme.syntaxKey(context))));
      } else if (txt.startsWith('"') || txt.startsWith("'")) {
        spans.add(TextSpan(text: txt, style: base.copyWith(color: AppTheme.syntaxString(context))));
      } else if (txt.contains('=')) {
        spans.add(TextSpan(text: txt, style: base.copyWith(color: AppTheme.syntaxBool(context))));
      } else {
        spans.add(TextSpan(text: txt, style: base.copyWith(color: AppTheme.syntaxKey(context))));
      }
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: base));
    return spans.isEmpty ? [TextSpan(text: line, style: base)] : spans;
  }

  // ── CSS highlighting ──

  List<TextSpan> _highlightCss(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    final re = RegExp(r'(/\*.*?\*/)|([a-zA-Z-]+)\s*:|([#\w][^\s;{}"]+)');
    int last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start), style: base));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(color: AppTheme.syntaxBool(context))));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: '${m.group(2)}:', style: base.copyWith(color: AppTheme.syntaxKey(context))));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(color: AppTheme.syntaxString(context))));
      }
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: base));
    return spans.isEmpty ? [TextSpan(text: line, style: base)] : spans;
  }

  // ── JavaScript highlighting ──

  static const _jsKeywords = {'function','const','let','var','if','else','return','for','while',
    'class','new','this','import','export','from','async','await','try','catch','throw','switch','case','break','default'};

  List<TextSpan> _highlightJs(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    final re = RegExp(r'(//[^\n]*)|("(?:\\.|[^"\\])*"|' "'(?:\\\\.|[^'\\\\])*'" r'|`(?:\\.|[^`\\])*`)|(\b\d+\.?\d*\b)|(\btrue\b|\bfalse\b|\bnull\b|\bundefined\b)|(\b[a-zA-Z_$]\w*\b)');
    int last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start), style: base));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(color: AppTheme.syntaxBool(context))));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(color: AppTheme.syntaxString(context))));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(color: AppTheme.syntaxNumber(context))));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(color: AppTheme.syntaxBool(context))));
      } else if (m.group(5) != null) {
        final word = m.group(5)!;
        spans.add(TextSpan(text: word, style: _jsKeywords.contains(word)
            ? base.copyWith(color: AppTheme.syntaxKey(context)) : base));
      }
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: base));
    return spans.isEmpty ? [TextSpan(text: line, style: base)] : spans;
  }

  // ── XML indent ──

  static String _indentXml(String xml) {
    final buf = StringBuffer();
    int indent = 0;
    final re = RegExp(r'(<[^>]+>)');
    final parts = <String>[];
    int last = 0;
    for (final m in re.allMatches(xml)) {
      if (m.start > last) {
        final text = xml.substring(last, m.start).trim();
        if (text.isNotEmpty) parts.add(text);
      }
      parts.add(m.group(0)!);
      last = m.end;
    }
    if (last < xml.length) {
      final text = xml.substring(last).trim();
      if (text.isNotEmpty) parts.add(text);
    }
    for (final part in parts) {
      if (part.startsWith('</')) {
        indent = (indent - 1).clamp(0, 999);
        buf.writeln('${'  ' * indent}$part');
      } else if (part.startsWith('<') && !part.startsWith('<!') && !part.endsWith('/>') && !part.contains('</')) {
        buf.writeln('${'  ' * indent}$part');
        indent++;
      } else {
        buf.writeln('${'  ' * indent}$part');
      }
    }
    return buf.toString().trimRight();
  }
}
