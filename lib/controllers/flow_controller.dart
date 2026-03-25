import 'dart:async';
import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_summary.dart';
import 'filter_controller.dart';
import 'tree_controller.dart';

class FlowController extends GetxController {
  final ApiClient api;
  FlowController(this.api);

  // ── Local data store ──────────────────────────────────────
  /// ALL flows for the current task — the single source of truth.
  /// Only modified by: initial load, loadMore, addFlowFromPush, updateFlowFromPush.
  final allFlows = <FlowSummary>[];

  // ── Displayed (filtered) data ─────────────────────────────
  /// Flows after applying all filters + search + tree selection — drives the UI list.
  final flows = <FlowSummary>[].obs;
  final selectedFlow = Rxn<FlowSummary>();
  final total = 0.obs;
  final isLoading = false.obs;
  final searchQuery = ''.obs;
  final scrollToTopSignal = 0.obs;

  int _currentPage = 1;
  int? _taskId;
  Timer? _searchDebounce;

  // ── Task lifecycle ────────────────────────────────────────

  void setTaskId(int taskId) {
    _taskId = taskId;
    _currentPage = 1;
    allFlows.clear();
    flows.clear();
    selectedFlow.value = null;
    searchQuery.value = '';
    _loadAllFlows();
  }

  /// Load all flows from API (initial + pagination until done).
  /// After loading, recompute everything locally.
  Future<void> _loadAllFlows() async {
    isLoading.value = true;
    _currentPage = 1;
    allFlows.clear();
    try {
      // Load first page
      final result = await api.getFlows(taskId: _taskId!, page: 1, size: 200);
      allFlows.addAll(result.items);
      final totalCount = result.total;

      // Load remaining pages
      while (allFlows.length < totalCount) {
        _currentPage++;
        final more = await api.getFlows(taskId: _taskId!, page: _currentPage, size: 200);
        if (more.items.isEmpty) break;
        allFlows.addAll(more.items);
      }
    } catch (_) {}
    isLoading.value = false;

    // Recompute everything from local data
    _recomputeAll();
  }

  // ── Local computation ─────────────────────────────────────

  /// Recompute filtered flows, tree, and filter options — all from local data.
  void _recomputeAll() {
    _applyFilters();
    Get.find<FilterController>().recomputeFromFlows(allFlows);
    Get.find<TreeController>().recomputeFromFlows(allFlows);
  }

  /// Apply all active filters + search + tree selection to allFlows → flows.
  void _applyFilters() {
    final filterCtrl = Get.find<FilterController>();
    final treeCtrl = Get.find<TreeController>();
    final query = searchQuery.value.toLowerCase();

    var result = allFlows.where((f) {
      // Protocol filter
      if (filterCtrl.activeProtocols.isNotEmpty) {
        if (!filterCtrl.activeProtocols.contains(f.protocol.toUpperCase())) {
          return false;
        }
      }
      // Content type filter
      if (filterCtrl.activeContentTypes.isNotEmpty) {
        if (!filterCtrl.matchesContentType(f)) return false;
      }
      // Tree domain selection
      final selDomain = treeCtrl.selectedDomain.value;
      if (selDomain != null) {
        if (_normalizeHost(f.host) != selDomain) return false;
      }
      // Tree path selection
      final selPath = treeCtrl.selectedPath.value;
      if (selPath != null && selPath.isNotEmpty) {
        if (!f.uri.startsWith(selPath)) return false;
      }
      // Search query
      if (query.isNotEmpty) {
        final haystack = '${f.host} ${f.uri} ${f.method} ${f.statusCode}'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();

    flows.value = result;
    total.value = result.length;
  }

  static String _normalizeHost(String host) {
    if (host.endsWith(':443')) return host.substring(0, host.length - 4);
    if (host.endsWith(':80')) return host.substring(0, host.length - 3);
    return host;
  }

  // ── Public actions (no API calls) ─────────────────────────

  /// Called when filter chips change — local recompute only.
  void reloadFromFirstPage() {
    _applyFilters();
    Get.find<TreeController>().recomputeFromFlows(allFlows);
    scrollToTopSignal.value++;
  }

  /// Called when tree selection changes — local recompute only.
  void reloadForTreeSelection() {
    _applyFilters();
    scrollToTopSignal.value++;
  }

  void search(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      searchQuery.value = query;
      _applyFilters();
      Get.find<TreeController>().recomputeFromFlows(allFlows);
      scrollToTopSignal.value++;
    });
  }

  void selectFlow(FlowSummary flow) {
    selectedFlow.value = flow;
  }

  // ── WebSocket push handlers ───────────────────────────────

  void addFlowFromPush(FlowSummary flow) {
    allFlows.insert(0, flow);
    // Recompute — no API calls
    _applyFilters();
    Get.find<TreeController>().addDomainFromPush(flow);
    Get.find<FilterController>().addFlowToFilters(flow);
  }

  void updateFlowFromPush(Map<String, dynamic> data) {
    final fid = data['flowId'] as String?;
    if (fid == null) return;
    final idx = allFlows.indexWhere((f) => f.flowId == fid);
    if (idx >= 0) {
      allFlows[idx] = FlowSummary.fromJson(data);
      _applyFilters();
    }
  }

  // ── Removed: loadMore, loadFlows — no longer needed with local-first ──
  // Pagination is handled in _loadAllFlows during initial load.
}
