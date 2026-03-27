import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_summary.dart';
import 'filter_controller.dart';
import 'tree_controller.dart';
import 'flow_table_controller.dart';

/// Pure data store + loader for flows.
/// Holds allFlows (source of truth), loads from API, handles WebSocket pushes.
/// Does NOT own filtered list, selection, search, or scroll — those live
/// in FlowTableController and FlowSelectionController.
class FlowController extends GetxController {
  final ApiClient api;
  int? taskId;
  FlowController(this.api);

  String get _tag => 'task_$taskId';
  FilterController get _filterCtrl => Get.find<FilterController>(tag: _tag);
  TreeController get _treeCtrl => Get.find<TreeController>(tag: _tag);
  FlowTableController get _tableCtrl => Get.find<FlowTableController>(tag: _tag);

  /// ALL flows for the current task — the single source of truth.
  /// Capped at [maxFlows] to prevent unbounded memory growth.
  static const maxFlows = 50000;
  final allFlows = <FlowSummary>[];
  final isLoading = false.obs;

  int _currentPage = 1;

  void setTaskId(int tid) {
    taskId = tid;
    _currentPage = 1;
    allFlows.clear();
    _loadAllFlows();
  }

  Future<void> _loadAllFlows() async {
    isLoading.value = true;
    _currentPage = 1;
    allFlows.clear();
    try {
      final result = await api.getFlows(taskId: taskId!, page: 1, size: 200);
      allFlows.addAll(result.items);
      final totalCount = result.total;
      while (allFlows.length < totalCount) {
        _currentPage++;
        final more = await api.getFlows(taskId: taskId!, page: _currentPage, size: 200);
        if (more.items.isEmpty) break;
        allFlows.addAll(more.items);
      }
    } catch (e) { debugPrint("[Knot] Error: $e"); }
    isLoading.value = false;
    _recomputeAll();
  }

  void _recomputeAll() {
    _tableCtrl.reapplyFilters();
    _filterCtrl.recomputeFromFlows(allFlows);
    _treeCtrl.recomputeFromFlows(allFlows);
  }

  // ── WebSocket push handlers ───────────────────────────────

  void addFlowFromPush(FlowSummary flow) {
    allFlows.insert(0, flow);
    if (allFlows.length > maxFlows) {
      allFlows.removeRange(maxFlows, allFlows.length);
    }
    _tableCtrl.reapplyFiltersDebounced();
    _treeCtrl.addDomainFromPush(flow);
    _filterCtrl.addFlowToFilters(flow);
  }

  void updateFlowFromPush(Map<String, dynamic> data) {
    final fid = data['flowId'] as String?;
    if (fid == null) return;
    final idx = allFlows.indexWhere((f) => f.flowId == fid);
    if (idx >= 0) {
      allFlows[idx] = FlowSummary.fromJson(data);
      _tableCtrl.reapplyFilters();
    }
  }
}
