import 'dart:convert';
import 'dart:io';
import '../models/flow_summary.dart';

/// Imports flows from a HAR (HTTP Archive) 1.2 JSON file.
class HarImport {
  /// Parse HAR JSON content and return a list of FlowSummary objects.
  ///
  /// Imported flows have flowId prefixed with "imported-" to distinguish them.
  static List<FlowSummary> parse(String jsonContent) {
    final har = jsonDecode(jsonContent) as Map<String, dynamic>;
    final log = har['log'] as Map<String, dynamic>? ?? {};
    final entries = log['entries'] as List? ?? [];

    final flows = <FlowSummary>[];
    var index = 0;

    for (final entry in entries) {
      final e = entry as Map<String, dynamic>;
      try {
        flows.add(_entryToFlowSummary(e, index));
        index++;
      } catch (_) {
        // Skip malformed entries
        index++;
      }
    }

    return flows;
  }

  /// Read a HAR file from disk and parse it.
  static Future<List<FlowSummary>> importFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('File not found: $path');
    }
    final content = await file.readAsString();
    return parse(content);
  }

  static FlowSummary _entryToFlowSummary(
    Map<String, dynamic> entry,
    int index,
  ) {
    final request = entry['request'] as Map<String, dynamic>? ?? {};
    final response = entry['response'] as Map<String, dynamic>? ?? {};
    final timings = entry['timings'] as Map<String, dynamic>? ?? {};
    final content = response['content'] as Map<String, dynamic>? ?? {};

    final method = (request['method'] as String?) ?? 'GET';
    final urlStr = (request['url'] as String?) ?? '';
    final status = (response['status'] as int?) ?? 0;
    final bodySize = (response['bodySize'] as int?) ?? 0;
    final requestBodySize = (request['bodySize'] as int?) ?? 0;
    final mimeType = (content['mimeType'] as String?) ?? '';

    // Parse the URL
    Uri? uri;
    try {
      uri = Uri.parse(urlStr);
    } catch (_) {}

    final host = uri?.host ?? '';
    final port = uri?.port ?? 0;
    final path = uri?.path ?? '/';
    final query = uri?.query ?? '';
    final fullPath = query.isNotEmpty ? '$path?$query' : path;

    // Determine protocol from httpVersion or URL scheme
    final httpVersion = (request['httpVersion'] as String?) ?? 'HTTP/1.1';
    final scheme = uri?.scheme ?? 'http';
    String protocol;
    if (httpVersion.toLowerCase() == 'h2' ||
        httpVersion.toLowerCase() == 'http/2') {
      protocol = 'H2';
    } else if (scheme == 'https') {
      protocol = 'HTTPS';
    } else {
      protocol = 'HTTP';
    }

    // Parse started time
    final startedStr = entry['startedDateTime'] as String? ?? '';
    double startedAt;
    try {
      startedAt = DateTime.parse(startedStr).millisecondsSinceEpoch / 1000.0;
    } catch (_) {
      startedAt = DateTime.now().millisecondsSinceEpoch / 1000.0;
    }

    // Total duration
    final timeMs = (entry['time'] as num?)?.toDouble() ?? 0;
    final endedAt = startedAt + (timeMs / 1000.0);

    // Compute total timing
    double totalTimingMs = 0;
    for (final key in ['connect', 'ssl', 'send', 'wait', 'receive']) {
      final v = (timings[key] as num?)?.toDouble() ?? -1;
      if (v > 0) totalTimingMs += v;
    }
    final durationMs = totalTimingMs > 0 ? totalTimingMs : timeMs;

    return FlowSummary(
      flowId: 'imported-$index-${startedAt.toStringAsFixed(0)}',
      protocol: protocol,
      host: host,
      port: port,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: durationMs,
      uploadBytes: requestBodySize,
      downloadBytes: bodySize,
      status: status,
      summary: '$method $fullPath -> $status',
      searchKey1: method,
      searchKey2: fullPath,
      searchKey3: '$status',
      searchKey4: mimeType,
    );
  }
}
