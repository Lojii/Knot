import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Preprocessing for body preview: decode + pretty-format + split into
/// render-ready lines. Pure top-level function so it can run in an isolate
/// via [compute] for large payloads.

/// Bodies larger than this skip pretty-formatting (indented JSON/XML can
/// blow up several times in size); they are still decoded and split.
const int kMaxFormatBytes = 10 * 1024 * 1024;

class BodyPrepRequest {
  final Uint8List bytes;
  final String language;
  final bool format;

  /// Longest renderable line; longer lines are split into continuation
  /// chunks so no single text paragraph explodes layout cost.
  final int maxLineChars;

  const BodyPrepRequest({
    required this.bytes,
    required this.language,
    this.format = true,
    this.maxLineChars = 2000,
  });
}

class BodyLine {
  /// 1-based source line number; null for continuation chunks of a long line.
  final int? number;
  final String text;
  const BodyLine(this.number, this.text);
}

class PreparedBody {
  final List<BodyLine> lines;

  /// Highest source line number, for line-number column padding.
  final int maxNumber;
  const PreparedBody(this.lines, this.maxNumber);
}

PreparedBody prepareBody(BodyPrepRequest req) {
  var text = decodeBodyText(req.bytes);

  if (req.format && req.bytes.length <= kMaxFormatBytes) {
    if (req.language == 'json') {
      try {
        text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      } catch (_) {}
    } else if (req.language == 'xml' || req.language == 'html') {
      text = indentXml(text);
    }
  }

  final rawLines = text.split('\n');
  final lines = <BodyLine>[];
  for (int i = 0; i < rawLines.length; i++) {
    final line = rawLines[i];
    if (line.length <= req.maxLineChars) {
      lines.add(BodyLine(i + 1, line));
    } else {
      for (int s = 0; s < line.length; s += req.maxLineChars) {
        lines.add(BodyLine(
          s == 0 ? i + 1 : null,
          line.substring(s, math.min(line.length, s + req.maxLineChars)),
        ));
      }
    }
  }
  return PreparedBody(lines, rawLines.length);
}

String decodeBodyText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

String indentXml(String xml) {
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
