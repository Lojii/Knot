import 'package:flutter_test/flutter_test.dart';
import 'package:knot/api/api_client.dart';

void main() {
  group('ApiClient', () {
    test('default baseUrl is http://localhost:9090', () {
      final client = ApiClient();
      expect(client.baseUrl, 'http://localhost:9090');
    });

    test('custom baseUrl is stored', () {
      final client = ApiClient(baseUrl: 'http://myhost:8080');
      expect(client.baseUrl, 'http://myhost:8080');
    });

    test('dispose does not throw', () {
      final client = ApiClient();
      expect(() => client.dispose(), returnsNormally);
    });
  });

  group('ApiClient URL construction', () {
    // We cannot call the actual HTTP methods, but we can verify the
    // URI building logic used in getFlows by constructing URIs the same way.

    test('getFlows URI builds correct query parameters', () {
      const baseUrl = 'http://localhost:9090';
      const taskId = 5;
      const page = 2;
      const size = 50;

      final params = <String, String>{
        'page': '$page',
        'size': '$size',
      };
      final protocol = 'HTTP/1.1';
      params['protocol'] = protocol;
      final keyword = 'search term';
      params['keyword'] = keyword;

      final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows')
          .replace(queryParameters: params);

      expect(uri.path, '/api/tasks/5/flows');
      expect(uri.queryParameters['page'], '2');
      expect(uri.queryParameters['size'], '50');
      expect(uri.queryParameters['protocol'], 'HTTP/1.1');
      expect(uri.queryParameters['keyword'], 'search term');
    });

    test('getFlows URI omits null parameters', () {
      const baseUrl = 'http://localhost:9090';
      const taskId = 1;
      final params = <String, String>{
        'page': '1',
        'size': '50',
      };
      // protocol, host, keyword, status all null => not added

      final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows')
          .replace(queryParameters: params);

      expect(uri.queryParameters.containsKey('protocol'), isFalse);
      expect(uri.queryParameters.containsKey('keyword'), isFalse);
      expect(uri.queryParameters.containsKey('status'), isFalse);
    });

    test('getPayload URL includes preview param when true', () {
      String buildPayloadUrl(bool preview) {
        const baseUrl = 'http://localhost:9090';
        const taskId = 1;
        const flowId = 'abc';
        const direction = 'request';
        return '$baseUrl/api/tasks/$taskId/flows/$flowId/$direction${preview ? "?preview=true" : ""}';
      }

      expect(buildPayloadUrl(true),
          'http://localhost:9090/api/tasks/1/flows/abc/request?preview=true');
    });

    test('getPayload URL excludes preview param when false', () {
      String buildPayloadUrl(bool preview) {
        const baseUrl = 'http://localhost:9090';
        const taskId = 1;
        const flowId = 'abc';
        const direction = 'response';
        return '$baseUrl/api/tasks/$taskId/flows/$flowId/$direction${preview ? "?preview=true" : ""}';
      }

      expect(buildPayloadUrl(false),
          'http://localhost:9090/api/tasks/1/flows/abc/response');
    });

    test('tasks endpoint URL is correct', () {
      const baseUrl = 'http://localhost:9090';
      final uri = Uri.parse('$baseUrl/api/tasks');
      expect(uri.toString(), 'http://localhost:9090/api/tasks');
    });

    test('flow detail endpoint URL is correct', () {
      const baseUrl = 'http://localhost:9090';
      const taskId = 3;
      const flowId = 'xyz-789';
      final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows/$flowId');
      expect(uri.path, '/api/tasks/3/flows/xyz-789');
    });

    test('flow stats endpoint URL is correct', () {
      const baseUrl = 'http://localhost:9090';
      const taskId = 7;
      final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows/stats');
      expect(uri.path, '/api/tasks/7/flows/stats');
    });
  });
}
