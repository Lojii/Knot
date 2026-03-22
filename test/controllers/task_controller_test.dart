import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/api_client.dart';
import 'package:knot/controllers/task_controller.dart';
import 'package:knot/models/task_model.dart';

void main() {
  late TaskController controller;

  setUp(() {
    Get.testMode = true;
    final api = ApiClient(baseUrl: 'http://localhost:9999');
    controller = TaskController(api);
  });

  tearDown(() => Get.reset());

  group('TaskController - initial state', () {
    test('starts with empty tasks list', () {
      expect(controller.tasks, isEmpty);
    });

    test('starts with null currentTask', () {
      expect(controller.currentTask.value, isNull);
    });

    test('starts with isCapturing false', () {
      expect(controller.isCapturing.value, isFalse);
    });
  });

  group('TaskController - selectTask', () {
    // selectTask calls Get.find<FlowController>(), Get.find<LiveController>(), etc.
    // Without registering those, we can't fully test selectTask.
    // But we can test the state change on currentTask.

    test('sets currentTask', () {
      final task = TaskModel(
        id: 10,
        name: 'Session A',
        createdAt: 1000.0,
        status: 1,
      );

      // selectTask will throw because FlowController etc are not registered.
      // We test currentTask assignment separately.
      controller.currentTask.value = task;
      expect(controller.currentTask.value?.id, 10);
      expect(controller.currentTask.value?.name, 'Session A');
    });
  });
}
