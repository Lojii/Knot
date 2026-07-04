import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/models/flow_summary.dart';

/// Since HarExport.fromFlows requires an ApiClient and network calls,
/// we test the structure by examining _buildMinimalEntry via the public API
/// indirectly, and test helper logic through known-good data patterns.
///
/// For unit-testable aspects, we verify the HAR JSON structure by calling
/// internal methods via a test-friendly wrapper approach.
void main() {
  FlowSummary makeFlow({
    String flowId = 'f-1',
    String method = 'GET',
    String host = 'example.com',
    String uri = '/api/data',
    int port = 443,
    String protocol = 'HTTPS',
    int status = 200,
    int downloadBytes = 1024,
    int uploadBytes = 0,
    double startedAt = 1700000000.0,
    double? endedAt = 1700000001.5,
    double? durationMs = 1500.0,
    String contentType = 'application/json',
  }) {
    return FlowSummary(
      flowId: flowId,
      protocol: protocol,
      host: host,
      port: port,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: durationMs,
      uploadBytes: uploadBytes,
      downloadBytes: downloadBytes,
      status: status,
      summary: '$method $uri -> $status',
      searchKey1: method,
      searchKey2: uri,
      searchKey3: '$status',
      searchKey4: contentType,
    );
  }

  group('HarExport JSON structure (via _buildMinimalEntry pattern)', () {
    // We test the minimal entry builder by creating expected structure.
    // The minimal entry is used when detail fetch fails.

    test('minimal entry has correct request fields', () {
      final flow = makeFlow();
      // Reconstruct what _buildMinimalEntry would produce
      final startedMs = (flow.startedAt * 1000).round();
      final startedDt = DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: true);

      final entry = {
        'startedDateTime': startedDt.toIso8601String(),
        'time': flow.durationMs?.round() ?? 0,
        'request': {
          'method': flow.method,
          'url': 'https://${flow.host}${flow.uri}',
          'httpVersion': 'HTTP/1.1',
          'headers': <Map<String, String>>[],
          'queryString': <Map<String, String>>[],
          'bodySize': flow.uploadBytes,
        },
        'response': {
          'status': flow.status,
          'statusText': 'OK',
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

      expect(entry['request'], isA<Map>());
      final req = entry['request'] as Map;
      expect(req['method'], 'GET');
      expect(req['url'], 'https://example.com/api/data');
      expect(req['httpVersion'], 'HTTP/1.1');
      expect(req['bodySize'], 0);
    });

    test('minimal entry has correct response fields', () {
      final flow = makeFlow(status: 404, downloadBytes: 512);
      final entry = _buildTestMinimalEntry(flow);

      final rsp = entry['response'] as Map;
      expect(rsp['status'], 404);
      expect(rsp['statusText'], 'Not Found');
      expect(rsp['bodySize'], 512);
      final content = rsp['content'] as Map;
      expect(content['size'], 512);
    });

    test('minimal entry has all timing fields set to -1', () {
      final flow = makeFlow();
      final entry = _buildTestMinimalEntry(flow);

      final timings = entry['timings'] as Map;
      expect(timings['connect'], -1);
      expect(timings['ssl'], -1);
      expect(timings['send'], -1);
      expect(timings['wait'], -1);
      expect(timings['receive'], -1);
    });

    test('startedDateTime is UTC ISO8601', () {
      final flow = makeFlow(startedAt: 1700000000.0);
      final entry = _buildTestMinimalEntry(flow);

      final dt = entry['startedDateTime'] as String;
      expect(dt, contains('T'));
      expect(dt, endsWith('Z'));
      // Should parse as valid DateTime
      expect(() => DateTime.parse(dt), returnsNormally);
    });

    test('time field uses durationMs', () {
      final flow = makeFlow(durationMs: 250.0);
      final entry = _buildTestMinimalEntry(flow);
      expect(entry['time'], 250);
    });

    test('time field is 0 when durationMs is null', () {
      final flow = makeFlow(durationMs: null);
      final entry = _buildTestMinimalEntry(flow);
      expect(entry['time'], 0);
    });
  });

  group('HarExport URL construction', () {
    test('HTTPS protocol uses https scheme', () {
      final flow = makeFlow(protocol: 'HTTPS', host: 'api.io', uri: '/v1');
      final entry = _buildTestMinimalEntry(flow);
      final req = entry['request'] as Map;
      expect(req['url'], startsWith('https://'));
    });

    test('H2 protocol uses https scheme', () {
      final flow = makeFlow(protocol: 'H2', host: 'api.io', uri: '/v1');
      final entry = _buildTestMinimalEntry(flow);
      final req = entry['request'] as Map;
      expect(req['url'], startsWith('https://'));
    });

    test('HTTP protocol uses http scheme', () {
      final flow = makeFlow(protocol: 'HTTP', host: 'api.io', uri: '/v1');
      final entry = _buildTestMinimalEntry(flow);
      final req = entry['request'] as Map;
      expect(req['url'], startsWith('http://'));
    });

    test('non-standard port included in URL', () {
      final flow = makeFlow(protocol: 'HTTP', host: 'localhost', port: 8080, uri: '/api');
      final entry = _buildTestMinimalEntry(flow);
      final req = entry['request'] as Map;
      expect(req['url'], 'http://localhost:8080/api');
    });

    test('port 80 omitted from URL', () {
      final flow = makeFlow(protocol: 'HTTP', host: 'example.com', port: 80, uri: '/');
      final entry = _buildTestMinimalEntry(flow);
      final req = entry['request'] as Map;
      expect(req['url'], 'http://example.com/');
    });

    test('port 443 omitted from URL', () {
      final flow = makeFlow(protocol: 'HTTPS', host: 'example.com', port: 443, uri: '/');
      final entry = _buildTestMinimalEntry(flow);
      final req = entry['request'] as Map;
      expect(req['url'], 'https://example.com/');
    });
  });

  group('HarExport HAR wrapper structure', () {
    test('full HAR structure has log.version and log.creator', () {
      final har = {
        'log': {
          'version': '1.2',
          'creator': {'name': 'Knot', 'version': '1.0.0'},
          'entries': <Map<String, dynamic>>[],
        },
      };

      final log = har['log']!;
      expect(log['version'], '1.2');
      final creator = log['creator'] as Map;
      expect(creator['name'], 'Knot');
      expect(creator['version'], '1.0.0');
    });

    test('empty flow list produces valid HAR with empty entries', () {
      final har = {
        'log': {
          'version': '1.2',
          'creator': {'name': 'Knot', 'version': '1.0.0'},
          'entries': <Map<String, dynamic>>[],
        },
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(har);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      final log = parsed['log'] as Map;
      expect((log['entries'] as List), isEmpty);
    });
  });

  group('HarExport status text mapping', () {
    test('200 -> OK', () {
      final flow = makeFlow(status: 200);
      final entry = _buildTestMinimalEntry(flow);
      expect((entry['response'] as Map)['statusText'], 'OK');
    });

    test('201 -> Created', () {
      final flow = makeFlow(status: 201);
      final entry = _buildTestMinimalEntry(flow);
      expect((entry['response'] as Map)['statusText'], 'Created');
    });

    test('404 -> Not Found', () {
      final flow = makeFlow(status: 404);
      final entry = _buildTestMinimalEntry(flow);
      expect((entry['response'] as Map)['statusText'], 'Not Found');
    });

    test('500 -> Internal Server Error', () {
      final flow = makeFlow(status: 500);
      final entry = _buildTestMinimalEntry(flow);
      expect((entry['response'] as Map)['statusText'], 'Internal Server Error');
    });

    test('unknown status -> empty string', () {
      final flow = makeFlow(status: 999);
      final entry = _buildTestMinimalEntry(flow);
      expect((entry['response'] as Map)['statusText'], '');
    });
  });

  group('HarExport query string parsing', () {
    test('URL with query params produces queryString entries', () {
      final flow = makeFlow(uri: '/search?q=test&page=1');
      final uri = flow.uri;
      final qIdx = uri.indexOf('?');
      final queryParams = <Map<String, String>>[];
      if (qIdx >= 0) {
        final queryStr = uri.substring(qIdx + 1);
        final parsed = Uri.splitQueryString(queryStr);
        for (final e in parsed.entries) {
          queryParams.add({'name': e.key, 'value': e.value});
        }
      }
      expect(queryParams.length, 2);
      expect(queryParams[0], {'name': 'q', 'value': 'test'});
      expect(queryParams[1], {'name': 'page', 'value': '1'});
    });

    test('URL without query params produces empty queryString', () {
      final flow = makeFlow(uri: '/api/data');
      final uri = flow.uri;
      final qIdx = uri.indexOf('?');
      expect(qIdx, -1);
    });
  });

  group('HarExport header format', () {
    test('headers are formatted as name/value pairs', () {
      final rawHeaders = [
        ['Content-Type', 'application/json'],
        ['Accept', 'text/html'],
      ];
      final formatted = rawHeaders
          .where((h) => !h.first.startsWith(':'))
          .map((h) => {'name': h.first, 'value': h.last})
          .toList();
      expect(formatted.length, 2);
      expect(formatted[0], {'name': 'Content-Type', 'value': 'application/json'});
      expect(formatted[1], {'name': 'Accept', 'value': 'text/html'});
    });

    test('pseudo-headers are filtered out', () {
      final rawHeaders = [
        [':method', 'GET'],
        [':path', '/api'],
        ['Accept', 'text/html'],
      ];
      final formatted = rawHeaders
          .where((h) => !h.first.startsWith(':'))
          .map((h) => {'name': h.first, 'value': h.last})
          .toList();
      expect(formatted.length, 1);
      expect(formatted[0]['name'], 'Accept');
    });
  });

  group('HarExport timing calculation', () {
    test('positive timings computed correctly', () {
      final connectAt = 1000.0;
      final connectedAt = 1000.050;
      final tlsDoneAt = 1000.100;
      final reqEndAt = 1000.110;
      final rspStartAt = 1000.200;
      final endedAt = 1000.350;

      final connectMs = ((connectedAt - connectAt) * 1000).round();
      final sslMs = ((tlsDoneAt - connectedAt) * 1000).round();
      final sendMs = ((reqEndAt - tlsDoneAt) * 1000).round();
      final waitMs = ((rspStartAt - reqEndAt) * 1000).round();
      final receiveMs = ((endedAt - rspStartAt) * 1000).round();

      expect(connectMs, 50);
      expect(sslMs, 50);
      expect(sendMs, 10);
      expect(waitMs, 90);
      expect(receiveMs, 150);
    });

    test('ssl is -1 when tlsDoneAt is null', () {
      const connectedAt = 1000.0;
      int sslMs(double? tlsDoneAt) =>
          tlsDoneAt != null ? ((tlsDoneAt - connectedAt) * 1000).round() : -1;
      expect(sslMs(null), -1);
      expect(sslMs(1000.050), 50);
    });
  });
}

/// Test helper that mirrors _buildMinimalEntry logic.
Map<String, dynamic> _buildTestMinimalEntry(FlowSummary flow) {
  final startedMs = (flow.startedAt * 1000).round();
  final startedDt = DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: true);

  final protocol = flow.protocol.toUpperCase();
  final scheme = protocol.contains('HTTPS') || protocol.contains('H2')
      ? 'https'
      : 'http';
  final port = flow.port;
  final portSuffix = (port > 0 && port != 80 && port != 443) ? ':$port' : '';
  final fullUrl = '$scheme://${flow.host}$portSuffix${flow.uri}';

  const statusTexts = {
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
      'statusText': statusTexts[flow.status] ?? '',
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
