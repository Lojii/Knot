import 'package:get/get.dart';
import '../api/api_client.dart';
import '../api/ws_client.dart';
import '../api/proxy_channel.dart';
import '../models/task_model.dart';
import 'flow_controller.dart';
import 'live_controller.dart';
import 'detail_controller.dart';

class TaskController extends GetxController {
  final ApiClient api;
  TaskController(this.api);

  final tasks = <TaskModel>[].obs;
  final currentTask = Rxn<TaskModel>();
  final isCapturing = false.obs;

  Future<void> loadTasks() async {
    try {
      final list = await api.getTasks();
      tasks.value = list;
      if (currentTask.value == null && list.isNotEmpty) {
        currentTask.value = list.first;
      }
    } catch (e) {
      // Connection error — handled by status indicator
    }
  }

  void selectTask(TaskModel task) {
    currentTask.value = task;
    Get.find<FlowController>().setTaskId(task.id);
    Get.find<LiveController>().ws.switchTask(task.id);
    Get.find<DetailController>().clear();
  }

  /// Toggle capture on/off — used by both the global bar button and Cmd+E shortcut.
  Future<void> toggleCapture() async {
    if (isCapturing.value) {
      await ProxyChannel.stopProxy();
      isCapturing.value = false;
    } else {
      try {
        final result = await ProxyChannel.startProxy();
        final port = (result['port'] as int?) ?? 0;
        if (port > 0) {
          Get.find<ApiClient>().baseUrl = 'http://localhost:$port';
          Get.find<WsClient>().baseUrl = 'ws://localhost:$port';
        }
        isCapturing.value = true;
        await loadTasks();
        if (currentTask.value != null) {
          final tid = currentTask.value!.id;
          Get.find<FlowController>().setTaskId(tid);
          Get.find<LiveController>().connectToTask(tid);
        }
      } catch (e) {
        Get.snackbar('Error', 'Start failed: $e');
      }
    }
  }
}
