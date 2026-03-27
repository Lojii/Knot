import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Hex dump viewer for binary data.
class HexViewer extends StatelessWidget {
  final Uint8List bytes;
  final int maxBytes;

  const HexViewer({super.key, required this.bytes, this.maxBytes = 8192});

  @override
  Widget build(BuildContext context) {
    final limit = math.min(bytes.length, maxBytes);
    final truncated = bytes.sublist(0, limit);
    final lines = <String>[];

    for (int offset = 0; offset < truncated.length; offset += 16) {
      final end = math.min(offset + 16, truncated.length);
      final chunk = truncated.sublist(offset, end);
      final offsetStr = offset.toRadixString(16).padLeft(8, '0');
      final hexParts = <String>[];
      for (int j = 0; j < 16; j++) {
        hexParts.add(j < chunk.length ? chunk[j].toRadixString(16).padLeft(2, '0') : '  ');
      }
      final hexLeft = hexParts.sublist(0, math.min(8, hexParts.length)).join(' ');
      final hexRight = hexParts.length > 8 ? hexParts.sublist(8).join(' ') : '';
      final ascii = chunk.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();
      lines.add('$offsetStr  $hexLeft  $hexRight  |$ascii|');
    }

    if (bytes.length > limit) {
      lines.add('... truncated at $limit bytes (total: ${bytes.length})');
    }

    return SelectableText(lines.join('\n'), style: AppTheme.mono(context));
  }
}
