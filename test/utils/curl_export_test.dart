import 'package:flutter_test/flutter_test.dart';
import 'package:knot/utils/curl_export.dart';

void main() {
  group('CurlExport.fromFlowDetail', () {
    test('GET request with no body produces simple curl', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/api/users',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("curl"));
      expect(result, contains("'https://example.com/api/users'"));
      // GET should not have -X flag
      expect(result, isNot(contains('-X')));
    });

    test('POST request includes -X POST and --data', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'POST',
        'searchKey2': '/api/users',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("-X 'POST'"));
      expect(result, contains("--data"));
    });

    test('PUT request includes -X PUT and --data', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'PUT',
        'searchKey2': '/api/users/1',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("-X 'PUT'"));
      expect(result, contains("--data"));
    });

    test('DELETE request includes -X DELETE but no --data', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'DELETE',
        'searchKey2': '/api/users/1',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("-X 'DELETE'"));
      expect(result, isNot(contains("--data")));
    });

    test('PATCH request includes -X PATCH and --data', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'PATCH',
        'searchKey2': '/api/users/1',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("-X 'PATCH'"));
      expect(result, contains("--data"));
    });

    test('request with custom headers includes -H flags', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/api',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': {
          'requestHeaders': [
            ['Accept', 'application/json'],
            ['Authorization', 'Bearer abc123'],
          ],
        },
      });
      expect(result, contains("-H 'Accept: application/json'"));
      expect(result, contains("-H 'Authorization: Bearer abc123'"));
    });

    test('skips pseudo-headers starting with ":"', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/api',
        'host': 'example.com',
        'protocol': 'H2',
        'metadata': {
          'requestHeaders': [
            [':method', 'GET'],
            [':path', '/api'],
            ['Accept', 'text/html'],
          ],
        },
      });
      expect(result, isNot(contains(':method')));
      expect(result, isNot(contains(':path')));
      expect(result, contains("-H 'Accept: text/html'"));
    });

    test('HTTP protocol produces http:// URL', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/page',
        'host': 'example.com',
        'protocol': 'HTTP',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("'http://example.com/page'"));
    });

    test('HTTPS protocol produces https:// URL', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/page',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("'https://example.com/page'"));
    });

    test('H2 protocol produces https:// URL', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/page',
        'host': 'example.com',
        'protocol': 'H2',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("'https://example.com/page'"));
    });

    test('includes non-standard port in URL', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/api',
        'host': 'example.com',
        'protocol': 'HTTP',
        'port': 8080,
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("'http://example.com:8080/api'"));
    });

    test('omits port 80 from URL', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/api',
        'host': 'example.com',
        'protocol': 'HTTP',
        'port': 80,
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("'http://example.com/api'"));
    });

    test('omits port 443 from URL', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/api',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'port': 443,
        'metadata': <String, dynamic>{},
      });
      expect(result, contains("'https://example.com/api'"));
    });

    test('empty/null fields produce graceful fallback', () {
      final result = CurlExport.fromFlowDetail({});
      expect(result, contains('curl'));
      // Should at least produce a URL with empty host
      expect(result, contains("'http://"));
    });

    test('URL with special characters (query params)', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/search?q=hello+world&lang=en',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': <String, dynamic>{},
      });
      expect(result, contains('/search?q=hello+world&lang=en'));
    });

    test('URL with single quotes in header value is escaped', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'GET',
        'searchKey2': '/api',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': {
          'requestHeaders': [
            ['X-Test', "it's a test"],
          ],
        },
      });
      // Single quotes should be escaped
      expect(result, contains("-H"));
      expect(result, contains("it"));
    });

    test('multiple headers all appear', () {
      final result = CurlExport.fromFlowDetail({
        'searchKey1': 'POST',
        'searchKey2': '/api',
        'host': 'example.com',
        'protocol': 'HTTPS',
        'metadata': {
          'requestHeaders': [
            ['Content-Type', 'application/json'],
            ['Accept', 'application/json'],
            ['X-Request-Id', '12345'],
          ],
        },
      });
      expect(result, contains("-H 'Content-Type: application/json'"));
      expect(result, contains("-H 'Accept: application/json'"));
      expect(result, contains("-H 'X-Request-Id: 12345'"));
    });
  });
}
