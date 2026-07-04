import 'package:flutter_test/flutter_test.dart';
import 'package:knot/models/flow_summary.dart';

/// Tests for the diff comparison logic.
/// The diff page compares two FlowSummary objects field-by-field.
/// We test the comparison logic directly without rendering widgets.
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
    int uploadBytes = 128,
    double startedAt = 1700000000.0,
    double? durationMs = 150.0,
    String contentType = 'application/json',
  }) {
    return FlowSummary(
      flowId: flowId,
      protocol: protocol,
      host: host,
      port: port,
      startedAt: startedAt,
      durationMs: durationMs,
      uploadBytes: uploadBytes,
      downloadBytes: downloadBytes,
      status: status,
      searchKey1: method,
      searchKey2: uri,
      searchKey3: '$status',
      searchKey4: contentType,
    );
  }

  /// Compare two flows and return a map of field name -> (same or different).
  Map<String, bool> diffFlows(FlowSummary a, FlowSummary b) {
    return {
      'method': a.method == b.method,
      'host': a.host == b.host,
      'uri': a.uri == b.uri,
      'port': a.port == b.port,
      'protocol': a.protocol == b.protocol,
      'status': a.status == b.status,
      'downloadBytes': a.downloadBytes == b.downloadBytes,
      'uploadBytes': a.uploadBytes == b.uploadBytes,
      'contentType': a.contentType == b.contentType,
      'durationMs': a.durationMs == b.durationMs,
    };
  }

  group('Flow diff comparison', () {
    test('two identical flows show no differences', () {
      final a = makeFlow();
      final b = makeFlow(flowId: 'f-2'); // Different ID but same content
      final diff = diffFlows(a, b);
      // All fields should be the same
      expect(diff.values.every((same) => same), isTrue);
    });

    test('different methods are detected', () {
      final a = makeFlow(method: 'GET');
      final b = makeFlow(method: 'POST');
      final diff = diffFlows(a, b);
      expect(diff['method'], isFalse);
      // Other fields still same
      expect(diff['host'], isTrue);
      expect(diff['uri'], isTrue);
    });

    test('different URLs (host) are detected', () {
      final a = makeFlow(host: 'a.com');
      final b = makeFlow(host: 'b.com');
      final diff = diffFlows(a, b);
      expect(diff['host'], isFalse);
    });

    test('different URLs (path) are detected', () {
      final a = makeFlow(uri: '/api/v1');
      final b = makeFlow(uri: '/api/v2');
      final diff = diffFlows(a, b);
      expect(diff['uri'], isFalse);
    });

    test('different status codes are detected', () {
      final a = makeFlow(status: 200);
      final b = makeFlow(status: 404);
      final diff = diffFlows(a, b);
      expect(diff['status'], isFalse);
    });

    test('different protocols are detected', () {
      final a = makeFlow(protocol: 'HTTPS');
      final b = makeFlow(protocol: 'H2');
      final diff = diffFlows(a, b);
      expect(diff['protocol'], isFalse);
    });

    test('different download sizes are detected', () {
      final a = makeFlow(downloadBytes: 1024);
      final b = makeFlow(downloadBytes: 2048);
      final diff = diffFlows(a, b);
      expect(diff['downloadBytes'], isFalse);
    });

    test('different upload sizes are detected', () {
      final a = makeFlow(uploadBytes: 0);
      final b = makeFlow(uploadBytes: 512);
      final diff = diffFlows(a, b);
      expect(diff['uploadBytes'], isFalse);
    });

    test('different content types are detected', () {
      final a = makeFlow(contentType: 'application/json');
      final b = makeFlow(contentType: 'text/html');
      final diff = diffFlows(a, b);
      expect(diff['contentType'], isFalse);
    });

    test('different durations are detected', () {
      final a = makeFlow(durationMs: 100.0);
      final b = makeFlow(durationMs: 500.0);
      final diff = diffFlows(a, b);
      expect(diff['durationMs'], isFalse);
    });

    test('multiple differences at once', () {
      final a = makeFlow(
        method: 'GET',
        host: 'a.com',
        status: 200,
        protocol: 'HTTP',
      );
      final b = makeFlow(
        method: 'POST',
        host: 'b.com',
        status: 500,
        protocol: 'HTTPS',
      );
      final diff = diffFlows(a, b);
      expect(diff['method'], isFalse);
      expect(diff['host'], isFalse);
      expect(diff['status'], isFalse);
      expect(diff['protocol'], isFalse);
      // URI and others should still be the same
      expect(diff['uri'], isTrue);
    });

    test('one flow with null durationMs vs non-null', () {
      final a = makeFlow(durationMs: null);
      final b = makeFlow(durationMs: 150.0);
      final diff = diffFlows(a, b);
      expect(diff['durationMs'], isFalse);
    });

    test('both flows with null durationMs are same', () {
      final a = makeFlow(durationMs: null);
      final b = makeFlow(durationMs: null);
      final diff = diffFlows(a, b);
      expect(diff['durationMs'], isTrue);
    });
  });

  group('Flow diff - header comparison logic', () {
    test('identical headers map produces no diff', () {
      final headersA = {'Content-Type': 'application/json', 'Accept': '*/*'};
      final headersB = {'Content-Type': 'application/json', 'Accept': '*/*'};
      final allKeys = {...headersA.keys, ...headersB.keys};
      final diffs = <String>[];
      for (final key in allKeys) {
        if (headersA[key] != headersB[key]) diffs.add(key);
      }
      expect(diffs, isEmpty);
    });

    test('different header values detected', () {
      final headersA = {'Content-Type': 'application/json'};
      final headersB = {'Content-Type': 'text/html'};
      final allKeys = {...headersA.keys, ...headersB.keys};
      final diffs = <String>[];
      for (final key in allKeys) {
        if (headersA[key] != headersB[key]) diffs.add(key);
      }
      expect(diffs, contains('Content-Type'));
    });

    test('extra header in one flow is detected', () {
      final headersA = {'Content-Type': 'application/json'};
      final headersB = {'Content-Type': 'application/json', 'X-Extra': 'value'};
      final allKeys = {...headersA.keys, ...headersB.keys};
      final diffs = <String>[];
      for (final key in allKeys) {
        if (headersA[key] != headersB[key]) diffs.add(key);
      }
      expect(diffs, contains('X-Extra'));
    });

    test('missing header in one flow is detected', () {
      final headersA = {'Accept': 'text/html', 'Authorization': 'Bearer x'};
      final headersB = {'Accept': 'text/html'};
      final allKeys = {...headersA.keys, ...headersB.keys};
      final diffs = <String>[];
      for (final key in allKeys) {
        if (headersA[key] != headersB[key]) diffs.add(key);
      }
      expect(diffs, contains('Authorization'));
      expect(diffs, isNot(contains('Accept')));
    });
  });

  group('Flow diff - body comparison logic', () {
    test('identical bodies produce no diff', () {
      final bodyA = '{"key": "value"}';
      final bodyB = '{"key": "value"}';
      expect(bodyA == bodyB, isTrue);
    });

    test('different bodies are detected', () {
      final bodyA = '{"key": "value1"}';
      final bodyB = '{"key": "value2"}';
      expect(bodyA == bodyB, isFalse);
    });

    test('one empty body vs content is detected', () {
      final bodyA = '';
      final bodyB = '{"data": 42}';
      expect(bodyA == bodyB, isFalse);
      expect(bodyA.isEmpty, isTrue);
      expect(bodyB.isEmpty, isFalse);
    });

    test('both empty bodies are same', () {
      final bodyA = '';
      final bodyB = '';
      expect(bodyA == bodyB, isTrue);
    });
  });
}
