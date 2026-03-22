import 'package:flutter_test/flutter_test.dart';
import 'package:knot/models/flow_summary.dart';

void main() {
  group('FlowSummary', () {
    test('fromJson parses all fields correctly', () {
      final json = {
        'flowId': 'abc-123',
        'protocol': 'HTTP/1.1',
        'host': 'example.com',
        'port': 443,
        'startedAt': 1711234567.5,
        'endedAt': 1711234568.0,
        'durationMs': 500.0,
        'uploadBytes': 512,
        'downloadBytes': 2048,
        'status': 1,
        'summary': 'GET /api/data',
        'searchKey1': 'GET',
        'searchKey2': '/api/data',
        'searchKey3': '200',
        'searchKey4': 'application/json',
        'protoFlags': 3,
        'connReuse': 1,
      };
      final flow = FlowSummary.fromJson(json);

      expect(flow.flowId, 'abc-123');
      expect(flow.protocol, 'HTTP/1.1');
      expect(flow.host, 'example.com');
      expect(flow.port, 443);
      expect(flow.startedAt, 1711234567.5);
      expect(flow.endedAt, 1711234568.0);
      expect(flow.durationMs, 500.0);
      expect(flow.uploadBytes, 512);
      expect(flow.downloadBytes, 2048);
      expect(flow.status, 1);
      expect(flow.summary, 'GET /api/data');
      expect(flow.protoFlags, 3);
      expect(flow.connReuse, 1);
    });

    test('convenience getters return correct searchKey values', () {
      final json = {
        'flowId': 'x',
        'startedAt': 100.0,
        'searchKey1': 'POST',
        'searchKey2': '/users',
        'searchKey3': '201',
        'searchKey4': 'text/html',
      };
      final flow = FlowSummary.fromJson(json);

      expect(flow.method, 'POST');
      expect(flow.uri, '/users');
      expect(flow.statusCode, '201');
      expect(flow.contentType, 'text/html');
    });

    test('fromJson handles missing optional fields with defaults', () {
      final json = {
        'flowId': 'minimal-id',
        'startedAt': 100.0,
      };
      final flow = FlowSummary.fromJson(json);

      expect(flow.flowId, 'minimal-id');
      expect(flow.protocol, '');
      expect(flow.host, '');
      expect(flow.port, 0);
      expect(flow.endedAt, isNull);
      expect(flow.durationMs, isNull);
      expect(flow.uploadBytes, 0);
      expect(flow.downloadBytes, 0);
      expect(flow.status, 0);
      expect(flow.summary, '');
      expect(flow.method, '');
      expect(flow.uri, '');
      expect(flow.statusCode, '');
      expect(flow.contentType, '');
      expect(flow.protoFlags, 0);
      expect(flow.connReuse, 0);
    });

    test('fromJson handles null string fields', () {
      final json = {
        'flowId': 'id-1',
        'protocol': null,
        'host': null,
        'startedAt': 50.0,
        'summary': null,
        'searchKey1': null,
        'searchKey2': null,
        'searchKey3': null,
        'searchKey4': null,
      };
      final flow = FlowSummary.fromJson(json);

      expect(flow.protocol, '');
      expect(flow.host, '');
      expect(flow.summary, '');
      expect(flow.method, '');
      expect(flow.uri, '');
      expect(flow.statusCode, '');
      expect(flow.contentType, '');
    });

    test('fromJson accepts int startedAt via num cast', () {
      final json = {
        'flowId': 'id-int',
        'startedAt': 1000, // int, not double
      };
      final flow = FlowSummary.fromJson(json);

      expect(flow.startedAt, 1000.0);
    });

    test('fromJson handles null int fields', () {
      final json = {
        'flowId': 'id-null-ints',
        'startedAt': 100.0,
        'port': null,
        'uploadBytes': null,
        'downloadBytes': null,
        'status': null,
        'protoFlags': null,
        'connReuse': null,
      };
      final flow = FlowSummary.fromJson(json);

      expect(flow.port, 0);
      expect(flow.uploadBytes, 0);
      expect(flow.downloadBytes, 0);
      expect(flow.status, 0);
      expect(flow.protoFlags, 0);
      expect(flow.connReuse, 0);
    });
  });
}
