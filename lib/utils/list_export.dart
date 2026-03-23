import 'dart:convert';
import 'dart:io';
import '../models/flow_summary.dart';

/// Exports a list of FlowSummary objects to CSV or JSON format.
class ListExport {
  /// Convert flows to a CSV string.
  ///
  /// Columns: Method, Host, Path, Status, Size (bytes), Time (ms), Protocol
  static String toCsv(List<FlowSummary> flows) {
    final buf = StringBuffer();
    buf.writeln('Method,Host,Path,Status,Size,Time,Protocol');

    for (final f in flows) {
      buf.writeln([
        _csvEscape(f.method),
        _csvEscape(f.host),
        _csvEscape(f.uri),
        f.status,
        f.downloadBytes,
        f.durationMs?.round() ?? '',
        _csvEscape(f.protocol),
      ].join(','));
    }

    return buf.toString();
  }

  /// Convert flows to a JSON array string.
  static String toJson(List<FlowSummary> flows) {
    final list = flows.map((f) => {
      'method': f.method,
      'host': f.host,
      'path': f.uri,
      'status': f.status,
      'size': f.downloadBytes,
      'time': f.durationMs?.round(),
      'protocol': f.protocol,
      'flowId': f.flowId,
      'startedAt': f.startedAt,
      'uploadBytes': f.uploadBytes,
      'contentType': f.contentType,
    }).toList();

    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Write content to a file on the Desktop and return the path.
  static Future<String> writeToDesktop(String content, String extension) async {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$home/Desktop/knot-flows-$timestamp.$extension';
    await File(path).writeAsString(content);
    return path;
  }

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
