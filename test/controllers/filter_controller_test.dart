import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/controllers/filter_controller.dart';

void main() {
  late FilterController controller;

  setUp(() {
    Get.testMode = true;
    controller = FilterController();
  });

  tearDown(() => Get.reset());

  group('FilterController - toggleProtocol', () {
    test('adds protocol when not present', () {
      controller.toggleProtocol('HTTP/1.1');
      expect(controller.activeProtocols, contains('HTTP/1.1'));
    });

    test('removes protocol when already present', () {
      controller.toggleProtocol('HTTP/2');
      expect(controller.activeProtocols, contains('HTTP/2'));
      controller.toggleProtocol('HTTP/2');
      expect(controller.activeProtocols, isNot(contains('HTTP/2')));
    });

    test('handles multiple protocols', () {
      controller.toggleProtocol('HTTP/1.1');
      controller.toggleProtocol('HTTP/2');
      controller.toggleProtocol('WebSocket');
      expect(controller.activeProtocols.length, 3);
    });
  });

  group('FilterController - toggleType', () {
    test('adds type when not present', () {
      controller.toggleType('json');
      expect(controller.activeTypes, contains('json'));
    });

    test('removes type when already present', () {
      controller.toggleType('html');
      controller.toggleType('html');
      expect(controller.activeTypes, isEmpty);
    });
  });

  group('FilterController - toggleStatus', () {
    test('adds status when not present', () {
      controller.toggleStatus('2xx');
      expect(controller.activeStatuses, contains('2xx'));
    });

    test('removes status when already present', () {
      controller.toggleStatus('4xx');
      controller.toggleStatus('4xx');
      expect(controller.activeStatuses, isEmpty);
    });
  });

  group('FilterController - clearAll', () {
    test('clears all filters', () {
      controller.toggleProtocol('HTTP/1.1');
      controller.toggleType('json');
      controller.toggleStatus('2xx');

      controller.clearAll();

      expect(controller.activeProtocols, isEmpty);
      expect(controller.activeTypes, isEmpty);
      expect(controller.activeStatuses, isEmpty);
    });

    test('clearAll on empty filters does not throw', () {
      expect(() => controller.clearAll(), returnsNormally);
    });
  });

  group('FilterController - param getters', () {
    test('protocolParam is null when no protocols selected', () {
      expect(controller.protocolParam, isNull);
    });

    test('protocolParam returns single protocol', () {
      controller.toggleProtocol('HTTP/2');
      expect(controller.protocolParam, 'HTTP/2');
    });

    test('protocolParam returns comma-separated protocols', () {
      controller.toggleProtocol('HTTP/1.1');
      controller.toggleProtocol('HTTP/2');
      final param = controller.protocolParam!;
      expect(param.contains('HTTP/1.1'), isTrue);
      expect(param.contains('HTTP/2'), isTrue);
      expect(param.contains(','), isTrue);
    });

    test('statusParam is null when no statuses selected', () {
      expect(controller.statusParam, isNull);
    });

    test('statusParam returns comma-separated statuses', () {
      controller.toggleStatus('2xx');
      controller.toggleStatus('4xx');
      final param = controller.statusParam!;
      expect(param.contains('2xx'), isTrue);
      expect(param.contains('4xx'), isTrue);
      expect(param.contains(','), isTrue);
    });
  });
}
