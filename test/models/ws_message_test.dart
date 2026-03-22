import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/models/ws_message.dart';

void main() {
  group('WsMessage', () {
    test('fromRaw parses valid JSON with type and data', () {
      final raw = jsonEncode({
        'type': 'flow',
        'data': {'flowId': 'abc', 'host': 'example.com'},
      });
      final msg = WsMessage.fromRaw(raw);

      expect(msg.type, 'flow');
      expect(msg.data['flowId'], 'abc');
      expect(msg.data['host'], 'example.com');
    });

    test('fromRaw handles missing type field', () {
      final raw = jsonEncode({
        'data': {'key': 'value'},
      });
      final msg = WsMessage.fromRaw(raw);

      expect(msg.type, ''); // null coalesces to ''
      expect(msg.data['key'], 'value');
    });

    test('fromRaw handles missing data field', () {
      final raw = jsonEncode({
        'type': 'metrics',
      });
      final msg = WsMessage.fromRaw(raw);

      expect(msg.type, 'metrics');
      expect(msg.data, isEmpty);
    });

    test('fromRaw handles null type and data', () {
      final raw = jsonEncode({
        'type': null,
        'data': null,
      });
      final msg = WsMessage.fromRaw(raw);

      expect(msg.type, '');
      expect(msg.data, isEmpty);
    });

    test('fromRaw handles empty JSON object', () {
      final raw = '{}';
      final msg = WsMessage.fromRaw(raw);

      expect(msg.type, '');
      expect(msg.data, isEmpty);
    });

    test('fromRaw throws on invalid JSON', () {
      expect(() => WsMessage.fromRaw('not json'), throwsA(isA<FormatException>()));
    });

    test('fromRaw throws on JSON array', () {
      // jsonDecode returns List, cast to Map will fail
      expect(() => WsMessage.fromRaw('[1,2,3]'), throwsA(isA<TypeError>()));
    });

    test('fromRaw with nested data', () {
      final raw = jsonEncode({
        'type': 'metrics',
        'data': {
          'memory': {'rss_mb': 64.5},
          'connections': {'pool_total': 10},
        },
      });
      final msg = WsMessage.fromRaw(raw);

      expect(msg.type, 'metrics');
      final mem = msg.data['memory'] as Map<String, dynamic>;
      expect(mem['rss_mb'], 64.5);
    });

    test('fromRaw with various message types', () {
      for (final type in ['flow', 'flow_update', 'metrics', 'stats']) {
        final raw = jsonEncode({'type': type, 'data': {}});
        final msg = WsMessage.fromRaw(raw);
        expect(msg.type, type);
      }
    });
  });
}
