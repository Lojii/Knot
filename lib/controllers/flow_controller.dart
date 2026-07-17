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

  /// flowId → index into [allFlows], so [updateFlowFromPush] avoids an O(n)
  /// linear scan per WebSocket message. Inserting at the head shifts every
  /// index, so instead of rebuilding on each insert we mark the map dirty and
  /// rebuild lazily at most once before the next lookup.
  final Map<String, int> _flowIndex = {};
  bool _indexDirty = false;

  void _rebuildIndex() {
    _flowIndex.clear();
    for (var i = 0; i < allFlows.length; i++) {
      _flowIndex[allFlows[i].flowId] = i;
    }
    _indexDirty = false;
  }

  int _currentPage = 1;

  /// Incremented on every [setTaskId]. An in-flight [_loadAllFlows] checks this
  /// after each await and abandons itself if a newer load has started, so
  /// concurrent loads (e.g. reconnect mid-load) can't interleave pages into
  /// the same list.
  int _loadGeneration = 0;

  void setTaskId(int tid) {
    taskId = tid;
    _currentPage = 1;
    _loadGeneration++;
    allFlows.clear();
    _flowIndex.clear();
    _indexDirty = false;
    _loadAllFlows(_loadGeneration);
  }

  Future<void> _loadAllFlows(int generation) async {
    isLoading.value = true;
    _currentPage = 1;
    try {
      final result = await api.getFlows(taskId: taskId!, page: 1, size: 200);
      if (generation != _loadGeneration) return;
      allFlows.addAll(result.items);
      final totalCount = result.total;
      while (allFlows.length < totalCount && allFlows.length < maxFlows) {
        _currentPage++;
        final more = await api.getFlows(taskId: taskId!, page: _currentPage, size: 200);
        if (generation != _loadGeneration) return;
        if (more.items.isEmpty) break;
        allFlows.addAll(more.items);
      }
    } catch (e) { debugPrint("[Knot] Error: $e"); }
    if (generation != _loadGeneration) return;
    _rebuildIndex();
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
    // insert(0, …) shifts every existing index; defer the rebuild until an
    // update actually needs the map.
    _indexDirty = true;
    _tableCtrl.reapplyFiltersDebounced();
    _treeCtrl.addDomainFromPush(flow);
    _filterCtrl.addFlowToFilters(flow);
  }

  void updateFlowFromPush(Map<String, dynamic> data) {
    final fid = data['flowId'] as String?;
    if (fid == null) return;
    if (_indexDirty) _rebuildIndex();
    final idx = _flowIndex[fid];
    if (idx != null && idx >= 0 && idx < allFlows.length && allFlows[idx].flowId == fid) {
      allFlows[idx] = FlowSummary.fromJson(data);
      _tableCtrl.reapplyFiltersDebounced();
    }
  }
}
