import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'body_prep.dart';

/// Code viewer with syntax highlighting and line numbers.
///
/// Built for large bodies: decoding/formatting runs in an isolate above
/// [isolateThresholdBytes], rendering is virtualized per line via
/// ListView.builder, and highlighting happens lazily for visible lines only.
class CodeViewer extends StatefulWidget {
  final Uint8List bytes;
  final String language;
  final bool formatJson;
  final bool showLineNumbers;

  /// Bodies larger than this are prepared off the UI thread.
  /// Overridable in tests to force the synchronous path.
  static int isolateThresholdBytes = 100 * 1024;

  const CodeViewer({
    super.key,
    required this.bytes,
    this.language = 'text',
    this.formatJson = true,
    this.showLineNumbers = true,
  });

  @override
  State<CodeViewer> createState() => _CodeViewerState();
}

class _CodeViewerState extends State<CodeViewer> {
  PreparedBody? _prepared;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(CodeViewer old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes) ||
        old.language != widget.language ||
        old.formatJson != widget.formatJson) {
      _prepare();
    }
  }

  void _prepare() {
    final gen = ++_generation;
    final req = BodyPrepRequest(
      bytes: widget.bytes,
      language: widget.language,
      format: widget.formatJson,
    );
    if (widget.bytes.length <= CodeViewer.isolateThresholdBytes) {
      _prepared = prepareBody(req);
    } else {
      _prepared = null;
      compute(prepareBody, req).then((p) {
        if (mounted && gen == _generation) setState(() => _prepared = p);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prepared = _prepared;
    if (prepared == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final style = AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.sm);
    final lineNumColor = AppTheme.colors(context).textSecondary;
    final numPad = prepared.maxNumber.toString().length.clamp(4, 10);

    return SelectionArea(
      child: ListView.builder(
        padding: EdgeInsets.zero,
        primary: false,
        itemCount: prepared.lines.length,
        itemBuilder: (context, i) =>
            _row(context, prepared.lines[i], style, lineNumColor, numPad),
      ),
    );
  }

  Widget _row(BuildContext context, BodyLine line, TextStyle style,
      Color lineNumColor, int numPad) {
    final content = _highlightLine(context, line.text, style);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showLineNumbers)
          SelectionContainer.disabled(
            child: Text(
              '${(line.number?.toString() ?? '').padLeft(numPad)} ',
              style: style.copyWith(color: lineNumColor),
            ),
          ),
        Expanded(
          child: content == null
              ? Text(line.text, style: style)
              : Text.rich(TextSpan(children: content), style: style),
        ),
      ],
    );
  }

  /// Returns highlight spans, or null for plain text (no highlighting).
  List<TextSpan>? _highlightLine(BuildContext context, String line, TextStyle base) {
    switch (widget.language) {
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
        return null;
    }
  }

  // ── JSON highlighting ──

  static final _jsonRe = RegExp(
      r'("(?:\\.|[^"\\])*")\s*:|("(?:\\.|[^"\\])*")|(\b-?\d+\.?\d*(?:[eE][+-]?\d+)?\b)|(\btrue\b|\bfalse\b|\bnull\b)');

  List<TextSpan> _highlightJson(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in _jsonRe.allMatches(line)) {
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

  static final _markupRe = RegExp(
      r'(</?[a-zA-Z][a-zA-Z0-9:-]*)|(\s[a-zA-Z:-]+=)("[^"]*"|' "'[^']*'" r')|(/>|>|<!--.*?-->)');

  List<TextSpan> _highlightMarkup(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in _markupRe.allMatches(line)) {
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

  static final _cssRe = RegExp(r'(/\*.*?\*/)|([a-zA-Z-]+)\s*:|([#\w][^\s;{}"]+)');

  List<TextSpan> _highlightCss(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in _cssRe.allMatches(line)) {
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

  static final _jsRe = RegExp(
      r'(//[^\n]*)|("(?:\\.|[^"\\])*"|' "'(?:\\\\.|[^'\\\\])*'" r'|`(?:\\.|[^`\\])*`)|(\b\d+\.?\d*\b)|(\btrue\b|\bfalse\b|\bnull\b|\bundefined\b)|(\b[a-zA-Z_$]\w*\b)');

  List<TextSpan> _highlightJs(BuildContext context, String line, TextStyle base) {
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in _jsRe.allMatches(line)) {
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
}
