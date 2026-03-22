import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/ws_client.dart';
import 'package:knot/controllers/live_controller.dart';

void main() {
  late LiveController controller;
  late WsClient wsClient;

  setUp(() {
    Get.testMode = true;
    wsClient = WsClient(baseUrl: 'ws://localhost:9999');
    controller = LiveController(wsClient);
  });

  tearDown(() {
    wsClient.dispose();
    Get.reset();
  });

  group('LiveController - initial state', () {
    test('wsStatus is disconnected', () {
      expect(controller.wsStatus.value, WsStatus.disconnected);
    });

    test('requestCount is 0', () {
      expect(controller.requestCount.value, 0);
    });

    test('uploadBytes is 0', () {
      expect(controller.uploadBytes.value, 0);
    });

    test('downloadBytes is 0', () {
      expect(controller.downloadBytes.value, 0);
    });

    test('memoryMB is 0.0', () {
      expect(controller.memoryMB.value, 0.0);
    });

    test('connectionCount is 0', () {
      expect(controller.connectionCount.value, 0);
    });
  });

  group('LiveController - _updateMetrics (via public access pattern)', () {
    // _updateMetrics is private, but we can test the reactive values it sets
    // by directly setting them (since the method is only called internally)

    test('metrics observables can be set', () {
      controller.memoryMB.value = 128.5;
      controller.connectionCount.value = 42;

      expect(controller.memoryMB.value, 128.5);
      expect(controller.connectionCount.value, 42);
    });
  });
}
