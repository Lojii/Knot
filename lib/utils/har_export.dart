import 'dart:convert';
import 'dart:io';
import '../api/api_client.dart';
import '../controllers/detail_controller.dart';
import '../models/flow_summary.dart';
import '../models/flow_detail.dart';

/// Exports a list of flows to HAR (HTTP Archive) 1.2 format.
class HarExport {
  /// Builds a HAR JSON string from flows by fetching detail for each.
  ///
  /// Bodies larger than [bodySizeLimit] bytes are skipped.
  static Future<String> fromFlows(
    List<FlowSummary> flows,
    ApiClient api,
    int taskId, {
    int bodySizeLimit = 1024 * 1024, // 1 MB
  }) async {
    final entries = <Map<String, dynamic>>[];

    for (final flow in flows) {
      try {
        final detail = await api.getFlowDetail(taskId, flow.flowId);
        final entry = _buildEntry(flow, detail, api, taskId, bodySizeLimit);
        entries.add(await entry);
      } catch (_) {
        // Skip flows that fail to load
        entries.add(_buildMinimalEntry(flow));
      }
    }

    final har = {
      'log': {
        'version': '1.2',
        'creator': {'name': 'Knot', 'version': '1.0.0'},
        'entries': entries,
      },
    };

    return const JsonEncoder.withIndent('  ').convert(har);
  }

  static Future<Map<String, dynamic>> _buildEntry(
    FlowSummary flow,
    FlowDetail detail,
    ApiClient api,
    int taskId,
    int bodySizeLimit,
  ) async {
    final raw = detail.raw;

    // Build started datetime from epoch seconds
    final startedMs = (flow.startedAt * 1000).round();
    final startedDt = DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: true);

    // Request headers
    final reqHeadersList = DetailController.parseHeaders(raw, 'reqHeaders');
    final reqHeaders = <Map<String, String>>[];
    for (final h in reqHeadersList) {
      if (h.$1.startsWith(':')) continue; // skip pseudo-headers
      reqHeaders.add({'name': h.$1, 'value': h.$2});
    }

    // Response headers
    final rspHeadersList = DetailController.parseHeaders(raw, 'rspHeaders');
    final rspHeaders = <Map<String, String>>[];
    for (final h in rspHeadersList) {
      if (h.$1.startsWith(':')) continue;
      rspHeaders.add({'name': h.$1, 'value': h.$2});
    }

    // Parse query string from URI
    final queryParams = <Map<String, String>>[];
    final uri = flow.uri;
    final qIdx = uri.indexOf('?');
    if (qIdx >= 0) {
      final queryStr = uri.substring(qIdx + 1);
      final parsed = Uri.splitQueryString(queryStr);
      for (final e in parsed.entries) {
        queryParams.add({'name': e.key, 'value': e.value});
      }
    }

    // Build URL
    final scheme = flow.protocol.toUpperCase().contains('HTTPS') ||
        flow.protocol.toUpperCase().contains('H2')
        ? 'https'
        : 'http';
    final port = flow.port;
    final portSuffix = (port > 0 && port != 80 && port != 443) ? ':$port' : '';
    final fullUrl = '$scheme://${flow.host}$portSuffix$uri';

    // HTTP version
    final httpVersion = flow.protocol.toUpperCase().contains('H2')
        ? 'h2'
        : 'HTTP/1.1';

    // Fetch response body if within size limit
    String? responseText;
    if (flow.downloadBytes <= bodySizeLimit && flow.downloadBytes > 0) {
      try {
        final bytes = await api.getPayloadBytes(taskId, flow.flowId, 'response', preview: true);
        responseText = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
    }

    // Timings
    final connectAt = detail.connectAt ?? flow.startedAt;
    final connectedAt = detail.connectedAt ?? flow.startedAt;
    final tlsDoneAt = detail.tlsDoneAt;
    final reqEndAt = detail.reqEndAt ?? flow.startedAt;
    final rspStartAt = detail.rspStartAt ?? flow.startedAt;
    final endedAt = flow.endedAt ?? flow.startedAt;

    final connectMs = ((connectedAt - connectAt) * 1000).round();
    final sslMs = tlsDoneAt != null ? ((tlsDoneAt - connectedAt) * 1000).round() : -1;
    final sendMs = ((reqEndAt - (tlsDoneAt ?? connectedAt)) * 1000).round();
    final waitMs = ((rspStartAt - reqEndAt) * 1000).round();
    final receiveMs = ((endedAt - rspStartAt) * 1000).round();

    return {
      'startedDateTime': startedDt.toIso8601String(),
      'time': flow.durationMs?.round() ?? 0,
      'request': {
        'method': flow.method,
        'url': fullUrl,
        'httpVersion': httpVersion,
        'headers': reqHeaders,
        'queryString': queryParams,
        'bodySize': flow.uploadBytes,
      },
      'response': {
        'status': flow.status,
        'statusText': _statusText(flow.status),
        'httpVersion': httpVersion,
        'headers': rspHeaders,
        'content': {
          'size': flow.downloadBytes,
          'mimeType': flow.contentType.isNotEmpty ? flow.contentType : 'application/octet-stream',
          if (responseText != null) 'text': responseText,
        },
        'bodySize': flow.downloadBytes,
      },
      'timings': {
        'connect': connectMs,
        'ssl': sslMs,
        'send': sendMs,
        'wait': waitMs,
        'receive': receiveMs,
      },
    };
  }

  static Map<String, dynamic> _buildMinimalEntry(FlowSummary flow) {
    final startedMs = (flow.startedAt * 1000).round();
    final startedDt = DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: true);

    final scheme = flow.protocol.toUpperCase().contains('HTTPS') ||
        flow.protocol.toUpperCase().contains('H2')
        ? 'https'
        : 'http';
    final port = flow.port;
    final portSuffix = (port > 0 && port != 80 && port != 443) ? ':$port' : '';
    final fullUrl = '$scheme://${flow.host}$portSuffix${flow.uri}';

    return {
      'startedDateTime': startedDt.toIso8601String(),
      'time': flow.durationMs?.round() ?? 0,
      'request': {
        'method': flow.method,
        'url': fullUrl,
        'httpVersion': 'HTTP/1.1',
        'headers': <Map<String, String>>[],
        'queryString': <Map<String, String>>[],
        'bodySize': flow.uploadBytes,
      },
      'response': {
        'status': flow.status,
        'statusText': _statusText(flow.status),
        'httpVersion': 'HTTP/1.1',
        'headers': <Map<String, String>>[],
        'content': {
          'size': flow.downloadBytes,
          'mimeType': 'application/octet-stream',
        },
        'bodySize': flow.downloadBytes,
      },
      'timings': {
        'connect': -1,
        'ssl': -1,
        'send': -1,
        'wait': -1,
        'receive': -1,
      },
    };
  }

  /// Write HAR JSON to a file on the Desktop and return the path.
  static Future<String> writeToDesktop(String harJson) async {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$home/Desktop/knot-export-$timestamp.har';
    await File(path).writeAsString(harJson);
    return path;
  }

  static String _statusText(int status) {
    const texts = {
      200: 'OK',
      201: 'Created',
      204: 'No Content',
      301: 'Moved Permanently',
      302: 'Found',
      304: 'Not Modified',
      400: 'Bad Request',
      401: 'Unauthorized',
      403: 'Forbidden',
      404: 'Not Found',
      500: 'Internal Server Error',
      502: 'Bad Gateway',
      503: 'Service Unavailable',
    };
    return texts[status] ?? '';
  }
}
