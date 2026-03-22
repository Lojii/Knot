import 'package:flutter_test/flutter_test.dart';
import 'package:knot/models/flow_detail.dart';

void main() {
  group('ConnectionInfo', () {
    test('fromJson parses all fields', () {
      final json = {
        'srcIp': '192.168.1.1',
        'dstIp': '10.0.0.1',
        'srcPort': 54321,
        'dstPort': 443,
        'state': 'established',
        'tlsVersion': 'TLSv1.3',
        'tlsCipher': 'AES_256_GCM',
        'tlsSni': 'example.com',
      };
      final conn = ConnectionInfo.fromJson(json);

      expect(conn.srcIp, '192.168.1.1');
      expect(conn.dstIp, '10.0.0.1');
      expect(conn.srcPort, 54321);
      expect(conn.dstPort, 443);
      expect(conn.state, 'established');
      expect(conn.tlsVersion, 'TLSv1.3');
      expect(conn.tlsCipher, 'AES_256_GCM');
      expect(conn.tlsSni, 'example.com');
    });

    test('fromJson handles missing/null fields with defaults', () {
      final json = <String, dynamic>{};
      final conn = ConnectionInfo.fromJson(json);

      expect(conn.srcIp, '');
      expect(conn.dstIp, '');
      expect(conn.srcPort, 0);
      expect(conn.dstPort, 0);
      expect(conn.state, '');
      expect(conn.tlsVersion, isNull);
      expect(conn.tlsCipher, isNull);
      expect(conn.tlsSni, isNull);
    });

    test('fromJson handles null string fields', () {
      final json = {
        'srcIp': null,
        'dstIp': null,
        'srcPort': null,
        'dstPort': null,
        'state': null,
      };
      final conn = ConnectionInfo.fromJson(json);

      expect(conn.srcIp, '');
      expect(conn.dstIp, '');
      expect(conn.srcPort, 0);
      expect(conn.dstPort, 0);
      expect(conn.state, '');
    });
  });

  group('FlowDetail', () {
    test('fromJson with data wrapper parses correctly', () {
      final json = {
        'data': {
          'flowId': 'flow-1',
          'connectAt': 100.5,
          'connectedAt': 101.0,
          'tlsDoneAt': 102.0,
          'reqEndAt': 103.0,
          'rspStartAt': 104.0,
          'connection': {
            'srcIp': '127.0.0.1',
            'dstIp': '93.184.216.34',
            'srcPort': 12345,
            'dstPort': 443,
            'state': 'closed',
            'tlsVersion': 'TLSv1.2',
          },
        }
      };
      final detail = FlowDetail.fromJson(json);

      expect(detail.flowId, 'flow-1');
      expect(detail.connectAt, 100.5);
      expect(detail.connectedAt, 101.0);
      expect(detail.tlsDoneAt, 102.0);
      expect(detail.reqEndAt, 103.0);
      expect(detail.rspStartAt, 104.0);
      expect(detail.connection, isNotNull);
      expect(detail.connection!.srcIp, '127.0.0.1');
      expect(detail.connection!.dstPort, 443);
      expect(detail.connection!.tlsVersion, 'TLSv1.2');
    });

    test('fromJson without data wrapper uses json directly', () {
      final json = {
        'flowId': 'flow-2',
        'connectAt': 200.0,
      };
      final detail = FlowDetail.fromJson(json);

      expect(detail.flowId, 'flow-2');
      expect(detail.connectAt, 200.0);
      expect(detail.connection, isNull);
    });

    test('fromJson with no connection field', () {
      final json = {
        'data': {
          'flowId': 'flow-3',
        }
      };
      final detail = FlowDetail.fromJson(json);

      expect(detail.flowId, 'flow-3');
      expect(detail.connection, isNull);
    });

    test('timing getters return null when fields missing', () {
      final json = {
        'data': {
          'flowId': 'flow-4',
        }
      };
      final detail = FlowDetail.fromJson(json);

      expect(detail.connectAt, isNull);
      expect(detail.connectedAt, isNull);
      expect(detail.tlsDoneAt, isNull);
      expect(detail.reqEndAt, isNull);
      expect(detail.rspStartAt, isNull);
    });

    test('flowId getter returns empty string when missing', () {
      final json = {'data': <String, dynamic>{}};
      final detail = FlowDetail.fromJson(json);

      expect(detail.flowId, '');
    });

    test('timing getters accept int via num cast', () {
      final json = {
        'data': {
          'flowId': 'flow-5',
          'connectAt': 100, // int
          'connectedAt': 200, // int
        }
      };
      final detail = FlowDetail.fromJson(json);

      expect(detail.connectAt, 100.0);
      expect(detail.connectedAt, 200.0);
    });

    test('raw field contains full data map', () {
      final data = {
        'flowId': 'flow-6',
        'customField': 'customValue',
        'nested': {'a': 1},
      };
      final json = {'data': data};
      final detail = FlowDetail.fromJson(json);

      expect(detail.raw['customField'], 'customValue');
      expect(detail.raw['nested'], {'a': 1});
    });
  });
}
