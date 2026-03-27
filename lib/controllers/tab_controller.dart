import 'package:get/get.dart';
import '../models/task_model.dart';
import 'task_scope.dart';

enum TabType { home, task }

class TabItem {
  final String id;
  final TabType type;
  final int? taskId;
  final RxString title;
  final RxBool isCapturing;

  TabItem._({
    required this.id,
    required this.type,
    this.taskId,
    required String title,
    bool isCapturing = false,
  })  : title = title.obs,
        isCapturing = isCapturing.obs;

  factory TabItem.home() => TabItem._(
        id: '__home__',
        type: TabType.home,
        title: 'Home',
      );

  factory TabItem.fromTask(TaskModel task, {bool isCapturing = false}) =>
      TabItem._(
        id: 'task_${task.id}',
        type: TabType.task,
        taskId: task.id,
        title: task.name.isNotEmpty ? task.name : 'Task ${task.id}',
        isCapturing: isCapturing,
      );

  bool get isHome => type == TabType.home;

  bool get canClose => !isHome && !isCapturing.value;
}

class TabManager extends GetxController {
  final tabs = <TabItem>[TabItem.home()].obs;
  final activeTabId = '__home__'.obs;

  TabItem get activeTab =>
      tabs.firstWhereOrNull((t) => t.id == activeTabId.value) ?? tabs.first;

  TabItem? findTab(String tabId) =>
      tabs.firstWhereOrNull((t) => t.id == tabId);

  int? get activeTaskId {
    final tab = activeTab;
    return tab.type == TabType.task ? tab.taskId : null;
  }

  TabItem? get capturingTab =>
      tabs.firstWhereOrNull((t) => t.isCapturing.value);

  void activateTab(String tabId) {
    if (!tabs.any((t) => t.id == tabId)) return;
    activeTabId.value = tabId;
  }

  void openTask(TaskModel task, {bool isCapturing = false}) {
    final tabId = 'task_${task.id}';
    final existing = tabs.firstWhereOrNull((t) => t.id == tabId);

    // Ensure per-task controllers exist
    TaskScope.ensure(task.id);

    if (existing != null) {
      activeTabId.value = tabId;
      if (isCapturing) existing.isCapturing.value = true;
      return;
    }

    final tab = TabItem.fromTask(task, isCapturing: isCapturing);

    if (isCapturing) {
      tabs.insert(1, tab);
    } else {
      tabs.add(tab);
    }

    activeTabId.value = tabId;
  }

  void closeTab(String tabId) {
    final idx = tabs.indexWhere((t) => t.id == tabId);
    if (idx == -1) return;

    final tab = tabs[idx];
    if (!tab.canClose) return;

    if (activeTabId.value == tabId) {
      if (idx > 0) {
        activeTabId.value = tabs[idx - 1].id;
      } else if (idx + 1 < tabs.length) {
        activeTabId.value = tabs[idx + 1].id;
      }
    }

    tabs.removeAt(idx);

    // Destroy per-task controllers
    if (tab.taskId != null) {
      // Only destroy if no other tab uses the same task
      final stillUsed = tabs.any((t) => t.taskId == tab.taskId);
      if (!stillUsed) {
        TaskScope.destroy(tab.taskId!);
      }
    }
  }

  void closeAllExcept(String tabId) {
    final closeable = tabs.where((t) => t.id != tabId && t.canClose).toList();
    for (final t in closeable) {
      tabs.remove(t);
      if (t.taskId != null) {
        final stillUsed = tabs.any((tab) => tab.taskId == t.taskId);
        if (!stillUsed) {
          TaskScope.destroy(t.taskId!);
        }
      }
    }

    if (!tabs.any((t) => t.id == activeTabId.value)) {
      activeTabId.value = tabId;
    }
  }

  void renameTab(String tabId, String newName) {
    final tab = findTab(tabId);
    if (tab != null) tab.title.value = newName;
  }

  void markCapturing(String tabId) {
    final idx = tabs.indexWhere((t) => t.id == tabId);
    if (idx == -1) return;

    final tab = tabs[idx];
    tab.isCapturing.value = true;

    if (idx != 1) {
      tabs.removeAt(idx);
      tabs.insert(1, tab);
    }
  }

  void markStopped(String tabId) {
    final tab = findTab(tabId);
    if (tab != null) tab.isCapturing.value = false;
  }
}
