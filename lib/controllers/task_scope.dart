import 'package:get/get.dart';
import '../api/api_client.dart';
import 'flow_controller.dart';
import 'tree_controller.dart';
import 'filter_controller.dart';
import 'detail_controller.dart';
import 'tag_controller.dart';
import 'dashboard_controller.dart';
import 'flow_selection_controller.dart';
import 'flow_table_controller.dart';
import 'filter_bar_controller.dart';
import 'detail_panel_controller.dart';
import 'content_panel_controller.dart';
import 'tab_controller.dart';

/// Manages per-task controller instances.
/// Each task gets its own FlowController, TreeController, FilterController, DetailController.
/// Controllers are created lazily on first access and destroyed when the tab is closed.
class TaskScope {
  TaskScope._();

  static final _activeTasks = <int>{};

  static String _tag(int taskId) => 'task_$taskId';

  /// Ensure controllers exist for this task. Idempotent.
  static void ensure(int taskId) {
    if (_activeTasks.contains(taskId)) return;
    _activeTasks.add(taskId);

    final tag = _tag(taskId);
    final api = Get.find<ApiClient>();

    final flowCtrl = FlowController(api)..taskId = taskId;
    final treeCtrl = TreeController()..taskId = taskId;
    Get.put(flowCtrl, tag: tag);
    Get.put(treeCtrl, tag: tag);
    Get.put(FilterController(), tag: tag);
    Get.put(DetailController(api), tag: tag);
    Get.put(TagController(), tag: tag);
    Get.put(DashboardController(api), tag: tag);
    final tableCtrl = FlowTableController()..taskId = taskId;
    final selCtrl = FlowSelectionController()..taskId = taskId;
    final filterBarCtrl = FilterBarController()..taskId = taskId;
    final detailPanelCtrl = DetailPanelController()..taskId = taskId;
    Get.put(tableCtrl, tag: tag);
    Get.put(selCtrl, tag: tag);
    Get.put(filterBarCtrl, tag: tag);
    final contentPanelCtrl = ContentPanelController()..taskId = taskId;
    Get.put(detailPanelCtrl, tag: tag);
    Get.put(contentPanelCtrl, tag: tag);
  }

  /// Destroy controllers for this task (when tab is closed).
  static void destroy(int taskId) {
    if (!_activeTasks.contains(taskId)) return;
    _activeTasks.remove(taskId);

    final tag = _tag(taskId);
    Get.delete<FlowController>(tag: tag);
    Get.delete<TreeController>(tag: tag);
    Get.delete<FilterController>(tag: tag);
    Get.delete<DetailController>(tag: tag);
    Get.delete<TagController>(tag: tag);
    Get.delete<DashboardController>(tag: tag);
    Get.delete<FlowTableController>(tag: tag);
    Get.delete<FlowSelectionController>(tag: tag);
    Get.delete<FilterBarController>(tag: tag);
    Get.delete<DetailPanelController>(tag: tag);
    Get.delete<ContentPanelController>(tag: tag);
  }

  /// Get the FlowController for a specific task.
  static FlowController flowCtrl(int taskId) =>
      Get.find<FlowController>(tag: _tag(taskId));

  static TreeController treeCtrl(int taskId) =>
      Get.find<TreeController>(tag: _tag(taskId));

  static FilterController filterCtrl(int taskId) =>
      Get.find<FilterController>(tag: _tag(taskId));

  static DetailController detailCtrl(int taskId) =>
      Get.find<DetailController>(tag: _tag(taskId));

  static TagController tagCtrl(int taskId) =>
      Get.find<TagController>(tag: _tag(taskId));

  static DashboardController dashCtrl(int taskId) =>
      Get.find<DashboardController>(tag: _tag(taskId));

  static FlowTableController tableCtrl(int taskId) =>
      Get.find<FlowTableController>(tag: _tag(taskId));

  static FlowSelectionController selectionCtrl(int taskId) =>
      Get.find<FlowSelectionController>(tag: _tag(taskId));

  static FilterBarController filterBarCtrl(int taskId) =>
      Get.find<FilterBarController>(tag: _tag(taskId));

  static DetailPanelController detailPanelCtrl(int taskId) =>
      Get.find<DetailPanelController>(tag: _tag(taskId));

  static ContentPanelController contentPanelCtrl(int taskId) =>
      Get.find<ContentPanelController>(tag: _tag(taskId));

  // ── Convenience: resolve from active tab ──

  static int? get activeTaskId => Get.find<TabManager>().activeTaskId;

  static FlowController get flow {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return flowCtrl(tid);
  }

  static TreeController get tree {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return treeCtrl(tid);
  }

  static FilterController get filter {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return filterCtrl(tid);
  }

  static DetailController get detail {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return detailCtrl(tid);
  }

  static TagController get tag {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return tagCtrl(tid);
  }

  static DashboardController get dash {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return dashCtrl(tid);
  }

  static FlowTableController get table {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return tableCtrl(tid);
  }

  static FlowSelectionController get selection {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return selectionCtrl(tid);
  }

  static FilterBarController get filterBar {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return filterBarCtrl(tid);
  }

  static DetailPanelController get detailPanel {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return detailPanelCtrl(tid);
  }

  static ContentPanelController get contentPanel {
    final tid = activeTaskId;
    if (tid == null) throw StateError('No active task');
    return contentPanelCtrl(tid);
  }
}
