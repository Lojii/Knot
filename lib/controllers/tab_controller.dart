import 'package:get/get.dart';
import '../models/task_model.dart';

enum TabType { home, task }

class TabItem {
  final String id;
  final TabType type;
  final TaskModel? task;
  final RxString title;
  final RxBool isCapturing;

  TabItem._({
    required this.id,
    required this.type,
    this.task,
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
        task: task,
        title: task.name,
        isCapturing: isCapturing,
      );

  bool get isHome => type == TabType.home;

  bool get canClose => !isHome && !isCapturing.value;
}

class TabManager extends GetxController {
  final tabs = <TabItem>[TabItem.home()].obs;
  final activeTabId = '__home__'.obs;

  TabItem get activeTab =>
      tabs.firstWhere((t) => t.id == activeTabId.value);

  int? get activeTaskId {
    final tab = activeTab;
    return tab.type == TabType.task ? tab.task?.id : null;
  }

  TabItem? get capturingTab {
    try {
      return tabs.firstWhere((t) => t.isCapturing.value);
    } catch (_) {
      return null;
    }
  }

  void activateTab(String tabId) {
    if (tabs.any((t) => t.id == tabId)) {
      activeTabId.value = tabId;
    }
  }

  void openTask(TaskModel task, {bool isCapturing = false}) {
    final tabId = 'task_${task.id}';
    final existing = tabs.indexWhere((t) => t.id == tabId);

    if (existing != -1) {
      // Already open — just activate
      activeTabId.value = tabId;
      return;
    }

    final tab = TabItem.fromTask(task, isCapturing: isCapturing);

    if (isCapturing) {
      // Insert right after Home (position 1)
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

    // If closing the active tab, activate nearest neighbor
    if (activeTabId.value == tabId) {
      if (idx > 0) {
        activeTabId.value = tabs[idx - 1].id;
      } else if (idx + 1 < tabs.length) {
        activeTabId.value = tabs[idx + 1].id;
      }
    }

    tabs.removeAt(idx);
  }

  void closeAllExcept(String tabId) {
    tabs.removeWhere((t) => t.id != tabId && t.canClose);

    // If active tab was closed, fall back to the kept tab or Home
    if (!tabs.any((t) => t.id == activeTabId.value)) {
      activeTabId.value = tabId;
    }
  }

  void renameTab(String tabId, String newName) {
    try {
      final tab = tabs.firstWhere((t) => t.id == tabId);
      tab.title.value = newName;
    } catch (_) {}
  }

  void markCapturing(String tabId) {
    final idx = tabs.indexWhere((t) => t.id == tabId);
    if (idx == -1) return;

    final tab = tabs[idx];
    tab.isCapturing.value = true;

    // Move to position 1 (right after Home) if not already there
    if (idx != 1) {
      tabs.removeAt(idx);
      tabs.insert(1, tab);
    }
  }

  void markStopped(String tabId) {
    try {
      final tab = tabs.firstWhere((t) => t.id == tabId);
      tab.isCapturing.value = false;
    } catch (_) {}
  }
}
