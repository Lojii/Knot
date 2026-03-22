import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/task_model.dart';

class HistoryController extends GetxController {
  final ApiClient api;
  HistoryController(this.api);

  final tasks = <TaskModel>[].obs;
  final isLoading = false.obs;

  Future<void> loadTasks() async {
    isLoading.value = true;
    try {
      tasks.value = await api.getTasks();
    } catch (_) {}
    isLoading.value = false;
  }
}
