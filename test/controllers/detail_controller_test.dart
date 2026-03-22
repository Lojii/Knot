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

    test('requestBody is empty initially', () {
      expect(controller.requestBody.value, '');
    });

    test('responseBody is empty initially', () {
      expect(controller.responseBody.value, '');
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
    test('clear resets detail to null', () {
      controller.detail.value = null; // already null, just to set up
      controller.requestBody.value = 'some request';
      controller.responseBody.value = 'some response';

      controller.clear();

      expect(controller.detail.value, isNull);
      expect(controller.requestBody.value, '');
      expect(controller.responseBody.value, '');
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
}
