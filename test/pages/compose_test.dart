import 'package:flutter_test/flutter_test.dart';
import 'package:knot/utils/request_sender.dart';
import 'package:knot/models/flow_summary.dart';

void main() {
  FlowSummary makeFlow({
    String protocol = 'HTTPS',
    String host = 'example.com',
    int port = 443,
    String method = 'GET',
    String uri = '/api/resource',
  }) {
    return FlowSummary(
      flowId: 'test-1',
      protocol: protocol,
      host: host,
      port: port,
      startedAt: 1000.0,
      searchKey1: method,
      searchKey2: uri,
    );
  }

  group('RequestSender.buildUrl', () {
    test('builds https URL for HTTPS protocol', () {
      final flow = makeFlow(protocol: 'HTTPS', host: 'example.com', uri: '/api');
      expect(RequestSender.buildUrl(flow), 'https://example.com/api');
    });

    test('builds https URL for H2 protocol', () {
      final flow = makeFlow(protocol: 'H2', host: 'example.com', uri: '/data');
      expect(RequestSender.buildUrl(flow), 'https://example.com/data');
    });

    test('builds http URL for HTTP protocol', () {
      final flow = makeFlow(protocol: 'HTTP', host: 'example.com', uri: '/page');
      expect(RequestSender.buildUrl(flow), 'http://example.com/page');
    });

    test('builds http URL for unknown protocol', () {
      final flow = makeFlow(protocol: 'UNKNOWN', host: 'example.com', uri: '/');
      expect(RequestSender.buildUrl(flow), 'http://example.com/');
    });

    test('includes query parameters in URI', () {
      final flow = makeFlow(uri: '/search?q=hello&page=2');
      expect(RequestSender.buildUrl(flow), 'https://example.com/search?q=hello&page=2');
    });

    test('handles special characters in path', () {
      final flow = makeFlow(uri: '/path/with%20spaces/file%26name');
      expect(RequestSender.buildUrl(flow), 'https://example.com/path/with%20spaces/file%26name');
    });

    test('handles root URI', () {
      final flow = makeFlow(uri: '/');
      expect(RequestSender.buildUrl(flow), 'https://example.com/');
    });

    test('handles empty URI', () {
      final flow = makeFlow(uri: '');
      expect(RequestSender.buildUrl(flow), 'https://example.com');
    });

    test('case-insensitive protocol check (https)', () {
      final flow = makeFlow(protocol: 'Https', host: 'api.io', uri: '/v1');
      expect(RequestSender.buildUrl(flow), 'https://api.io/v1');
    });

    test('case-insensitive protocol check (h2)', () {
      final flow = makeFlow(protocol: 'h2', host: 'api.io', uri: '/v1');
      expect(RequestSender.buildUrl(flow), 'https://api.io/v1');
    });
  });

  group('RequestSender.extractHeaders', () {
    test('returns empty map when detail has no metadata', () {
      final headers = RequestSender.extractHeaders({});
      expect(headers, isEmpty);
    });

    test('returns empty map when metadata has no reqHeaders', () {
      final headers = RequestSender.extractHeaders({
        'metadata': <String, dynamic>{},
      });
      expect(headers, isEmpty);
    });

    test('returns empty map when reqHeaders is null', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {'reqHeaders': null},
      });
      expect(headers, isEmpty);
    });

    test('extracts single header', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {
          'reqHeaders': [
            ['Accept', 'application/json'],
          ],
        },
      });
      expect(headers, {'Accept': 'application/json'});
    });

    test('extracts multiple headers', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {
          'reqHeaders': [
            ['Accept', 'text/html'],
            ['Authorization', 'Bearer token123'],
            ['X-Custom', 'value'],
          ],
        },
      });
      expect(headers.length, 3);
      expect(headers['Accept'], 'text/html');
      expect(headers['Authorization'], 'Bearer token123');
      expect(headers['X-Custom'], 'value');
    });

    test('skips hop-by-hop headers (host)', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {
          'reqHeaders': [
            ['Host', 'example.com'],
            ['Accept', 'text/html'],
          ],
        },
      });
      expect(headers.containsKey('Host'), isFalse);
      expect(headers['Accept'], 'text/html');
    });

    test('skips connection header', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {
          'reqHeaders': [
            ['Connection', 'keep-alive'],
            ['Accept', '*/*'],
          ],
        },
      });
      expect(headers.containsKey('Connection'), isFalse);
      expect(headers['Accept'], '*/*');
    });

    test('skips transfer-encoding header', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {
          'reqHeaders': [
            ['Transfer-Encoding', 'chunked'],
            ['Accept', '*/*'],
          ],
        },
      });
      expect(headers.containsKey('Transfer-Encoding'), isFalse);
    });

    test('skips content-length header', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {
          'reqHeaders': [
            ['Content-Length', '42'],
            ['Accept', '*/*'],
          ],
        },
      });
      expect(headers.containsKey('Content-Length'), isFalse);
    });

    test('handles empty reqHeaders list', () {
      final headers = RequestSender.extractHeaders({
        'metadata': {
          'reqHeaders': [],
        },
      });
      expect(headers, isEmpty);
    });
  });
}
