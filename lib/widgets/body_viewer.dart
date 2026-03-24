import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum BodyViewMode { pretty, raw, hex }

class BodyViewer extends StatefulWidget {
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
  State<BodyViewer> createState() => _BodyViewerState();
}

class _BodyViewerState extends State<BodyViewer> {
  BodyViewMode _viewMode = BodyViewMode.pretty;

  @override
  Widget build(BuildContext context) {
    if (widget.body.isEmpty) {
      return Text('(empty)', style: TextStyle(
        color: Theme.of(context).hintColor,
        fontSize: AppTheme.fontSize.sm,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildModeToggle(context),
        SizedBox(height: AppTheme.spacing.xs),
        _buildBody(context),
      ],
    );
  }

  Widget _buildModeToggle(BuildContext context) {
    final filterChip = AppTheme.mode(context).filterChip;
    return Row(
      children: BodyViewMode.values.map((mode) {
        final isActive = _viewMode == mode;
        final label = switch (mode) {
          BodyViewMode.pretty => 'Pretty',
          BodyViewMode.raw => 'Raw',
          BodyViewMode.hex => 'Hex',
        };
        return Padding(
          padding: EdgeInsets.only(right: AppTheme.spacing.xs),
          child: GestureDetector(
            onTap: () => setState(() => _viewMode = mode),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.spacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: isActive
                    ? filterChip.activeBackground
                    : filterChip.inactiveBackground,
                borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                border: Border.all(
                  color: isActive
                      ? filterChip.activeBorder
                      : filterChip.inactiveBorder,
                  width: 0.5,
                ),
              ),
              child: Text(label, style: TextStyle(
                fontSize: AppTheme.fontSize.sm,
                color: isActive ? filterChip.activeText : null,
              )),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_viewMode) {
      case BodyViewMode.pretty:
        return _prettyView(context);
      case BodyViewMode.raw:
        return _rawView(context);
      case BodyViewMode.hex:
        return _hexView(context);
    }
  }

  Widget _prettyView(BuildContext context) {
    // Image detection
    if (_isImage(widget.contentType)) {
      return _imagePreview(context);
    }

    // JSON detection
    if (_isJson(widget.contentType) || _looksLikeJson(widget.body)) {
      return _jsonView(context);
    }

    // XML/HTML auto-indent
    if (_isXml(widget.contentType)) {
      return _xmlView(context);
    }

    // Default: raw text
    return SelectableText(widget.body, style: AppTheme.mono(context));
  }

  Widget _rawView(BuildContext context) {
    return SelectableText(
      widget.body,
      style: AppTheme.mono(context),
    );
  }

  Widget _hexView(BuildContext context) {
    final bytes = utf8.encode(widget.body);
    // Limit to first 4KB for performance
    final limit = math.min(bytes.length, 4096);
    final truncated = bytes.sublist(0, limit);

    final lines = <String>[];
    for (int offset = 0; offset < truncated.length; offset += 16) {
      final end = math.min(offset + 16, truncated.length);
      final chunk = truncated.sublist(offset, end);

      // Offset column
      final offsetStr = offset.toRadixString(16).padLeft(8, '0');

      // Hex bytes
      final hexParts = <String>[];
      for (int j = 0; j < 16; j++) {
        if (j < chunk.length) {
          hexParts.add(chunk[j].toRadixString(16).padLeft(2, '0'));
        } else {
          hexParts.add('  ');
        }
      }
      final hexLeft = hexParts.sublist(0, math.min(8, hexParts.length)).join(' ');
      final hexRight = hexParts.length > 8
          ? hexParts.sublist(8).join(' ')
          : '';
      final hexStr = '$hexLeft  $hexRight';

      // ASCII column
      final ascii = chunk.map((b) => (b >= 32 && b <= 126)
          ? String.fromCharCode(b)
          : '.').join();

      lines.add('$offsetStr  $hexStr  |$ascii|');
    }

    if (bytes.length > limit) {
      lines.add('... truncated at 4096 bytes (total: ${bytes.length})');
    }

    return SelectableText(
      lines.join('\n'),
      style: AppTheme.mono(context),
    );
  }

  Widget _jsonView(BuildContext context) {
    try {
      final obj = jsonDecode(widget.body);
      final pretty = const JsonEncoder.withIndent('  ').convert(obj);
      return _SyntaxText(text: pretty, language: 'json');
    } catch (_) {
      return SelectableText(widget.body, style: AppTheme.mono(context));
    }
  }

  Widget _xmlView(BuildContext context) {
    final formatted = _indentXml(widget.body);
    return SelectableText(formatted, style: AppTheme.mono(context));
  }

  Widget _imagePreview(BuildContext context) {
    // Try to decode base64 or show placeholder
    try {
      final bytes = base64Decode(widget.body);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image Preview (${widget.contentType})',
              style: TextStyle(fontSize: AppTheme.fontSize.sm)),
          SizedBox(height: AppTheme.spacing.sm),
          Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text('Cannot preview image')),
        ],
      );
    } catch (_) {
      return Text('Image (${widget.contentType}) \u2014 ${widget.body.length} bytes',
          style: TextStyle(fontSize: AppTheme.fontSize.sm));
    }
  }

  bool _isImage(String ct) => ct.contains('image/');
  bool _isJson(String ct) => ct.contains('json');
  bool _isXml(String ct) =>
      ct.contains('xml') || ct.contains('html');
  bool _looksLikeJson(String s) {
    final trimmed = s.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  /// Simple XML/HTML indenter.
  String _indentXml(String xml) {
    final buf = StringBuffer();
    int indent = 0;
    // Split on tags
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
        indent = math.max(0, indent - 1);
        buf.writeln('${'  ' * indent}$part');
      } else if (part.startsWith('<') && !part.startsWith('<!') &&
          !part.endsWith('/>') && !part.contains('</')) {
        buf.writeln('${'  ' * indent}$part');
        indent++;
      } else {
        buf.writeln('${'  ' * indent}$part');
      }
    }
    return buf.toString().trimRight();
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
      _colorizeJson(context, text, style),
    );
  }

  TextSpan _colorizeJson(BuildContext context, String json, TextStyle base) {
    final spans = <TextSpan>[];
    final re = RegExp(r'("(?:\\.|[^"\\])*")\s*:|("(?:\\.|[^"\\])*")|(\b\d+\.?\d*\b)|(\btrue\b|\bfalse\b|\bnull\b)');

    int lastEnd = 0;
    for (final m in re.allMatches(json)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: json.substring(lastEnd, m.start), style: base));
      }
      if (m.group(1) != null) {
        // JSON key
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(color: AppTheme.syntaxKey(context))));
        spans.add(TextSpan(text: ':', style: base));
      } else if (m.group(2) != null) {
        // String value
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(color: AppTheme.syntaxString(context))));
      } else if (m.group(3) != null) {
        // Number
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(color: AppTheme.syntaxNumber(context))));
      } else if (m.group(4) != null) {
        // Boolean/null
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(color: AppTheme.syntaxBool(context))));
      }
      lastEnd = m.end;
    }
    if (lastEnd < json.length) {
      spans.add(TextSpan(text: json.substring(lastEnd), style: base));
    }
    return TextSpan(children: spans);
  }
}
