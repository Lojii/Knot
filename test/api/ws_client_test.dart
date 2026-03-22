import 'package:flutter_test/flutter_test.dart';
import 'package:knot/api/ws_client.dart';

void main() {
  group('WsClient', () {
    test('initial status is disconnected', () {
      final client = WsClient(baseUrl: 'ws://localhost:9999');
      expect(client.status, WsStatus.disconnected);
    });

    test('disconnect sets status to disconnected', () {
      final client = WsClient(baseUrl: 'ws://localhost:9999');
      client.disconnect();
      expect(client.status, WsStatus.disconnected);
    });

    test('dispose does not throw', () {
      final client = WsClient(baseUrl: 'ws://localhost:9999');
      expect(() => client.dispose(), returnsNormally);
    });

    test('default baseUrl is ws://localhost:9090', () {
      final client = WsClient();
      expect(client.baseUrl, 'ws://localhost:9090');
    });

    test('custom baseUrl is stored', () {
      final client = WsClient(baseUrl: 'ws://myhost:8080');
      expect(client.baseUrl, 'ws://myhost:8080');
    });

    test('statusStream emits status changes', () async {
      // Skip: requires actual network connection attempt, timing-sensitive
    }, skip: 'Network-dependent, tested manually');

    test('statusStream is a broadcast stream', () {
      final client = WsClient(baseUrl: 'ws://localhost:9999');
      // Should be able to listen multiple times (broadcast)
      final sub1 = client.statusStream.listen((_) {});
      final sub2 = client.statusStream.listen((_) {});
      sub1.cancel();
      sub2.cancel();
      client.dispose();
    });

    test('disconnect cancels reconnect timer', () {
      final client = WsClient(baseUrl: 'ws://localhost:9999');
      // connect will fail and schedule reconnect
      client.connect(taskId: 1);
      // disconnect should cancel the timer safely
      client.disconnect();
      expect(client.status, WsStatus.disconnected);
      client.dispose();
    });
  });

  group('WsStatus enum', () {
    test('has three values', () {
      expect(WsStatus.values.length, 3);
      expect(WsStatus.values, contains(WsStatus.disconnected));
      expect(WsStatus.values, contains(WsStatus.connecting));
      expect(WsStatus.values, contains(WsStatus.connected));
    });
  });
}
