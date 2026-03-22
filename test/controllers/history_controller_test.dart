import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/api_client.dart';
import 'package:knot/controllers/history_controller.dart';

void main() {
  late HistoryController controller;

  setUp(() {
    Get.testMode = true;
    final api = ApiClient(baseUrl: 'http://localhost:9999');
    controller = HistoryController(api);
  });

  tearDown(() => Get.reset());

  group('HistoryController - initial state', () {
    test('starts with empty tasks list', () {
      expect(controller.tasks, isEmpty);
    });

    test('starts with isLoading false', () {
      expect(controller.isLoading.value, isFalse);
    });
  });
}
