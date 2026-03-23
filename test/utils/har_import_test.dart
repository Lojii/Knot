import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/utils/har_import.dart';

void main() {
  String _buildHar(List<Map<String, dynamic>> entries) {
    return jsonEncode({
      'log': {
        'version': '1.2',
        'creator': {'name': 'TestTool', 'version': '0.1'},
        'entries': entries,
      },
    });
  }

  Map<String, dynamic> _makeEntry({
    String method = 'GET',
    String url = 'https://example.com/api',
    int status = 200,
    int bodySize = 1024,
    int requestBodySize = 0,
    String mimeType = 'application/json',
    String httpVersion = 'HTTP/1.1',
    String startedDateTime = '2024-01-15T10:30:00.000Z',
    int timeMs = 150,
    Map<String, dynamic>? timings,
    List<Map<String, String>>? requestHeaders,
    List<Map<String, String>>? responseHeaders,
  }) {
    return {
      'startedDateTime': startedDateTime,
      'time': timeMs,
      'request': {
        'method': method,
        'url': url,
        'httpVersion': httpVersion,
        if (requestHeaders != null) 'headers': requestHeaders,
        'bodySize': requestBodySize,
      },
      'response': {
        'status': status,
        'statusText': 'OK',
        'httpVersion': httpVersion,
        if (responseHeaders != null) 'headers': responseHeaders,
        'content': {
          'size': bodySize,
          'mimeType': mimeType,
        },
        'bodySize': bodySize,
      },
      if (timings != null) 'timings': timings,
    };
  }

  group('HarImport.parse - basic parsing', () {
    test('parses single entry and returns one FlowSummary', () {
      final har = _buildHar([_makeEntry()]);
      final flows = HarImport.parse(har);
      expect(flows.length, 1);
    });

    test('parses multiple entries', () {
      final har = _buildHar([
        _makeEntry(url: 'https://a.com/1'),
        _makeEntry(url: 'https://b.com/2'),
        _makeEntry(url: 'https://c.com/3'),
      ]);
      final flows = HarImport.parse(har);
      expect(flows.length, 3);
    });

    test('empty entries array returns empty list', () {
      final har = _buildHar([]);
      final flows = HarImport.parse(har);
      expect(flows, isEmpty);
    });

    test('invalid JSON throws FormatException', () {
      expect(() => HarImport.parse('not json at all'), throwsFormatException);
    });

    test('missing log key returns empty list', () {
      final har = jsonEncode({'other': 'data'});
      final flows = HarImport.parse(har);
      expect(flows, isEmpty);
    });

    test('missing entries key returns empty list', () {
      final har = jsonEncode({
        'log': {'version': '1.2'},
      });
      final flows = HarImport.parse(har);
      expect(flows, isEmpty);
    });
  });

  group('HarImport.parse - field extraction', () {
    test('parses method from request', () {
      final har = _buildHar([_makeEntry(method: 'POST')]);
      final flow = HarImport.parse(har).first;
      expect(flow.method, 'POST');
    });

    test('parses various HTTP methods', () {
      for (final method in ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']) {
        final har = _buildHar([_makeEntry(method: method)]);
        final flow = HarImport.parse(har).first;
        expect(flow.method, method, reason: 'method $method');
      }
    });

    test('parses host from URL', () {
      final har = _buildHar([_makeEntry(url: 'https://api.example.com/v1/users')]);
      final flow = HarImport.parse(har).first;
      expect(flow.host, 'api.example.com');
    });

    test('parses path from URL', () {
      final har = _buildHar([_makeEntry(url: 'https://example.com/v1/users')]);
      final flow = HarImport.parse(har).first;
      expect(flow.uri, '/v1/users');
    });

    test('parses URL with query parameters', () {
      final har = _buildHar([
        _makeEntry(url: 'https://example.com/search?q=test&page=2'),
      ]);
      final flow = HarImport.parse(har).first;
      expect(flow.uri, contains('/search'));
      expect(flow.uri, contains('q=test'));
      expect(flow.uri, contains('page=2'));
    });

    test('parses status from response', () {
      final har = _buildHar([_makeEntry(status: 404)]);
      final flow = HarImport.parse(har).first;
      expect(flow.status, 404);
    });

    test('parses download bytes from response bodySize', () {
      final har = _buildHar([_makeEntry(bodySize: 2048)]);
      final flow = HarImport.parse(har).first;
      expect(flow.downloadBytes, 2048);
    });

    test('parses upload bytes from request bodySize', () {
      final har = _buildHar([_makeEntry(requestBodySize: 512)]);
      final flow = HarImport.parse(har).first;
      expect(flow.uploadBytes, 512);
    });

    test('parses port from URL', () {
      final har = _buildHar([_makeEntry(url: 'https://example.com:8443/api')]);
      final flow = HarImport.parse(har).first;
      expect(flow.port, 8443);
    });
  });

  group('HarImport.parse - protocol detection', () {
    test('h2 httpVersion maps to H2 protocol', () {
      final har = _buildHar([_makeEntry(httpVersion: 'h2')]);
      final flow = HarImport.parse(har).first;
      expect(flow.protocol, 'H2');
    });

    test('HTTP/2 httpVersion maps to H2 protocol', () {
      final har = _buildHar([_makeEntry(httpVersion: 'HTTP/2')]);
      final flow = HarImport.parse(har).first;
      expect(flow.protocol, 'H2');
    });

    test('https URL with HTTP/1.1 maps to HTTPS protocol', () {
      final har = _buildHar([
        _makeEntry(url: 'https://example.com/api', httpVersion: 'HTTP/1.1'),
      ]);
      final flow = HarImport.parse(har).first;
      expect(flow.protocol, 'HTTPS');
    });

    test('http URL with HTTP/1.1 maps to HTTP protocol', () {
      final har = _buildHar([
        _makeEntry(url: 'http://example.com/api', httpVersion: 'HTTP/1.1'),
      ]);
      final flow = HarImport.parse(har).first;
      expect(flow.protocol, 'HTTP');
    });
  });

  group('HarImport.parse - flow IDs', () {
    test('imported flow IDs have "imported-" prefix', () {
      final har = _buildHar([_makeEntry(), _makeEntry()]);
      final flows = HarImport.parse(har);
      expect(flows[0].flowId, startsWith('imported-'));
      expect(flows[1].flowId, startsWith('imported-'));
    });

    test('imported flow IDs include index', () {
      final har = _buildHar([_makeEntry(), _makeEntry(), _makeEntry()]);
      final flows = HarImport.parse(har);
      expect(flows[0].flowId, contains('imported-0'));
      expect(flows[1].flowId, contains('imported-1'));
      expect(flows[2].flowId, contains('imported-2'));
    });
  });

  group('HarImport.parse - timing data', () {
    test('uses timings sum for durationMs when available', () {
      final har = _buildHar([
        _makeEntry(
          timeMs: 500,
          timings: {
            'connect': 10,
            'ssl': 20,
            'send': 5,
            'wait': 100,
            'receive': 15,
          },
        ),
      ]);
      final flow = HarImport.parse(har).first;
      expect(flow.durationMs, 150.0); // 10+20+5+100+15
    });

    test('uses time field when timings are all -1', () {
      final har = _buildHar([
        _makeEntry(
          timeMs: 300,
          timings: {
            'connect': -1,
            'ssl': -1,
            'send': -1,
            'wait': -1,
            'receive': -1,
          },
        ),
      ]);
      final flow = HarImport.parse(har).first;
      expect(flow.durationMs, 300.0);
    });

    test('uses time field when timings are absent', () {
      final har = _buildHar([_makeEntry(timeMs: 250)]);
      final flow = HarImport.parse(har).first;
      expect(flow.durationMs, 250.0);
    });

    test('partially valid timings are summed correctly', () {
      final har = _buildHar([
        _makeEntry(
          timeMs: 500,
          timings: {
            'connect': 10,
            'ssl': -1,
            'send': 5,
            'wait': 100,
            'receive': -1,
          },
        ),
      ]);
      final flow = HarImport.parse(har).first;
      expect(flow.durationMs, 115.0); // 10+5+100
    });
  });

  group('HarImport.parse - startedDateTime parsing', () {
    test('parses valid ISO8601 startedDateTime', () {
      final har = _buildHar([
        _makeEntry(startedDateTime: '2024-06-15T12:00:00.000Z'),
      ]);
      final flow = HarImport.parse(har).first;
      final expected = DateTime.parse('2024-06-15T12:00:00.000Z')
              .millisecondsSinceEpoch /
          1000.0;
      expect(flow.startedAt, expected);
    });

    test('computes endedAt from startedAt + time', () {
      final har = _buildHar([
        _makeEntry(
          startedDateTime: '2024-06-15T12:00:00.000Z',
          timeMs: 500,
        ),
      ]);
      final flow = HarImport.parse(har).first;
      // endedAt = startedAt + 500/1000
      expect(flow.endedAt, closeTo(flow.startedAt + 0.5, 0.001));
    });
  });

  group('HarImport.parse - edge cases', () {
    test('entry with only request (no response) creates partial flow', () {
      final har = jsonEncode({
        'log': {
          'version': '1.2',
          'entries': [
            {
              'startedDateTime': '2024-01-01T00:00:00.000Z',
              'time': 100,
              'request': {
                'method': 'GET',
                'url': 'https://example.com/',
                'httpVersion': 'HTTP/1.1',
              },
            },
          ],
        },
      });
      final flows = HarImport.parse(har);
      expect(flows.length, 1);
      expect(flows.first.method, 'GET');
      expect(flows.first.status, 0); // no response
    });

    test('missing method defaults to GET', () {
      final har = jsonEncode({
        'log': {
          'version': '1.2',
          'entries': [
            {
              'startedDateTime': '2024-01-01T00:00:00.000Z',
              'time': 50,
              'request': {
                'url': 'https://example.com/',
              },
            },
          ],
        },
      });
      final flows = HarImport.parse(har);
      expect(flows.first.method, 'GET');
    });

    test('missing URL defaults gracefully', () {
      final har = jsonEncode({
        'log': {
          'version': '1.2',
          'entries': [
            {
              'startedDateTime': '2024-01-01T00:00:00.000Z',
              'time': 50,
              'request': {
                'method': 'GET',
              },
            },
          ],
        },
      });
      final flows = HarImport.parse(har);
      expect(flows.length, 1);
      // Empty URL should still produce a flow
      expect(flows.first.host, isEmpty);
    });

    test('summary includes method, path, and status', () {
      final har = _buildHar([
        _makeEntry(method: 'POST', url: 'https://api.com/v2/create', status: 201),
      ]);
      final flow = HarImport.parse(har).first;
      expect(flow.summary, contains('POST'));
      expect(flow.summary, contains('/v2/create'));
      expect(flow.summary, contains('201'));
    });
  });
}
