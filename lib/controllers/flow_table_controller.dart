import 'dart:async';
import 'package:get/get.dart';
import '../models/flow_summary.dart';
import 'flow_controller.dart';
import 'filter_controller.dart';
import 'tree_controller.dart';

enum SortColumn { protocol, host, path, method, status, time, duration, size }

/// Owns the filtered/displayed flow list, search, sort state, and scroll signals.
class FlowTableController extends GetxController {
  int? taskId;

  /// Sort state — persists across tab switches
  final sortColumn = Rxn<SortColumn>();
  final sortAscending = true.obs;

  /// Column flex weights — resizable by dragging header dividers.
  /// Drag transfers weight between adjacent columns (total stays constant).
  /// Order: protocol, host, path, method, status, time, duration, size
  final columnWeights = <double>[3, 8, 12, 3, 3, 4, 4, 3].obs;

  static const double minWeight = 1.5;

  void resizeColumns(int leftIndex, double delta, double totalWidth) {
    final totalWeight = columnWeights.fold<double>(0, (s, w) => s + w);
    final deltaWeight = delta / totalWidth * totalWeight;
    final newLeft = columnWeights[leftIndex] + deltaWeight;
    final newRight = columnWeights[leftIndex + 1] - deltaWeight;
    if (newLeft >= minWeight && newRight >= minWeight) {
      columnWeights[leftIndex] = newLeft;
      columnWeights[leftIndex + 1] = newRight;
    }
  }

  String get _tag => 'task_$taskId';
  FlowController get _flowCtrl => Get.find<FlowController>(tag: _tag);
  FilterController get _filterCtrl => Get.find<FilterController>(tag: _tag);
  TreeController get _treeCtrl => Get.find<TreeController>(tag: _tag);

  final flows = <FlowSummary>[].obs;
  final total = 0.obs;
  final searchQuery = ''.obs;
  final scrollToTopSignal = 0.obs;

  Timer? _reapplyDebounce;
  bool _reapplyScheduled = false;

  Timer? _searchDebounce;

  /// Apply all active filters + search + tree selection to allFlows → flows.
  void reapplyFilters() {
    final allFlows = _flowCtrl.allFlows;
    final filterCtrl = _filterCtrl;
    final treeCtrl = _treeCtrl;
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
        if (selPath.endsWith('/*')) {
          final parentDir = selPath.substring(0, selPath.length - 2);
          final uri = Uri.tryParse(f.uri)?.path ?? f.uri;
          final segments = uri.split('/').where((s) => s.isNotEmpty).toList();
          if (parentDir.isEmpty) {
            if (segments.length > 1) return false;
          } else {
            final parentSegments = parentDir.split('/').where((s) => s.isNotEmpty).toList();
            if (!uri.startsWith(parentDir)) return false;
            if (segments.length != parentSegments.length + 1) return false;
          }
        } else {
          if (!f.uri.startsWith(selPath)) return false;
        }
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

  /// Debounced reapplyFilters — coalesces rapid WS pushes into one recompute.
  void reapplyFiltersDebounced() {
    if (_reapplyScheduled) return;
    _reapplyScheduled = true;
    _reapplyDebounce?.cancel();
    _reapplyDebounce = Timer(const Duration(milliseconds: 100), () {
      _reapplyScheduled = false;
      reapplyFilters();
    });
  }

  static String _normalizeHost(String host) {
    if (host.endsWith(':443')) return host.substring(0, host.length - 4);
    if (host.endsWith(':80')) return host.substring(0, host.length - 3);
    return host;
  }

  void search(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      searchQuery.value = query;
      reapplyFilters();
      _treeCtrl.recomputeFromFlows(_flowCtrl.allFlows);
      scrollToTopSignal.value++;
    });
  }

  /// Called after filter chip change — refilter + update tree.
  void refilterAndUpdateTree() {
    reapplyFilters();
    _treeCtrl.recomputeFromFlows(_flowCtrl.allFlows);
    scrollToTopSignal.value++;
  }

  /// Called after tree selection change — refilter only (tree already updated).
  void refilterForTreeSelection() {
    reapplyFilters();
    scrollToTopSignal.value++;
  }

  void toggleSort(SortColumn col) {
    if (sortColumn.value == col) {
      if (sortAscending.value) {
        sortAscending.value = false;
      } else {
        sortColumn.value = null;
        sortAscending.value = true;
      }
    } else {
      sortColumn.value = col;
      sortAscending.value = true;
    }
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    _reapplyDebounce?.cancel();
    super.onClose();
  }
}
