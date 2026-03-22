import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/task_model.dart';

class TaskController extends GetxController {
  final ApiClient api;
  TaskController(this.api);

  final tasks = <TaskModel>[].obs;
  final currentTask = Rxn<TaskModel>();
  final isCapturing = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadTasks();
  }

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
  }
}
