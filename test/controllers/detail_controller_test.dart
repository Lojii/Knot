import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/api_client.dart';
import 'package:knot/controllers/detail_controller.dart';

void main() {
  late DetailController controller;

  setUp(() {
    Get.testMode = true;
    final api = ApiClient(baseUrl: 'http://localhost:9999');
    controller = DetailController(api);
  });

  tearDown(() => Get.reset());

  group('DetailController - initial state', () {
    test('detail is null initially', () {
      expect(controller.detail.value, isNull);
    });

    test('body bytes are null initially', () {
      expect(controller.requestBodyBytes.value, isNull);
      expect(controller.responseBodyBytes.value, isNull);
    });

    test('body text getters are empty initially', () {
      expect(controller.requestBodyText, '');
      expect(controller.responseBodyText, '');
    });

    test('isLoadingDetail is false initially', () {
      expect(controller.isLoadingDetail.value, isFalse);
    });

    test('isLoadingBody is false initially', () {
      expect(controller.isLoadingBody.value, isFalse);
    });

    test('selectedTab is 0 initially', () {
      expect(controller.selectedTab.value, 0);
    });
  });

  group('DetailController - clear', () {
    test('clear resets detail and body bytes', () {
      controller.requestBodyBytes.value = Uint8List.fromList([1, 2, 3]);
      controller.responseBodyBytes.value = Uint8List.fromList([4, 5]);

      controller.clear();

      expect(controller.detail.value, isNull);
      expect(controller.requestBodyBytes.value, isNull);
      expect(controller.responseBodyBytes.value, isNull);
      expect(controller.requestBodyText, '');
      expect(controller.responseBodyText, '');
    });

    test('clear on already-empty state does not throw', () {
      expect(() => controller.clear(), returnsNormally);
    });
  });

  group('DetailController - selectedTab', () {
    test('can change selected tab', () {
      controller.selectedTab.value = 1;
      expect(controller.selectedTab.value, 1);

      controller.selectedTab.value = 2;
      expect(controller.selectedTab.value, 2);
    });
  });

  group('DetailController.parseHeaders', () {
    test('parses new array-of-arrays format', () {
      final raw = {
        'metadata': {
          'reqHeaders': [
            ['Content-Type', 'text/html'],
            ['X-Custom', 'abc'],
          ],
        },
      };
      final headers = DetailController.parseHeaders(raw, 'reqHeaders');
      expect(headers, [('Content-Type', 'text/html'), ('X-Custom', 'abc')]);
    });

    test('parses old array-of-maps format', () {
      final raw = {
        'metadata': {
          'rspHeaders': [
            {'Content-Type': 'application/json'},
          ],
        },
      };
      final headers = DetailController.parseHeaders(raw, 'rspHeaders');
      expect(headers, [('Content-Type', 'application/json')]);
    });

    test('returns empty list when metadata is missing', () {
      expect(DetailController.parseHeaders({}, 'reqHeaders'), isEmpty);
    });
  });
}
