import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_summary.dart';
import 'filter_controller.dart';
import 'flow_controller.dart';

// ============================================================
// Data models
// ============================================================

class TreeNode {
  final String label;
  final String? domain;
  final bool isGroup;
  final List<TreeNode> children;
  int count;
  bool childrenLoaded;

  TreeNode({
    required this.label,
    this.domain,
    this.isGroup = false,
    List<TreeNode>? children,
    this.count = 0,
    this.childrenLoaded = false,
  }) : children = children ?? [];
}

enum PinType { domain, app, device, request }

class PinnedItem {
  final PinType type;
  final String label;
  final String? identifier;
  PinnedItem({required this.type, required this.label, this.identifier});
}

class AppNode {
  final String name;
  final int count;
  final List<TreeNode> domains;
  AppNode({required this.name, this.count = 0, List<TreeNode>? domains})
      : domains = domains ?? [];
}

class PathNode {
  final String segment;
  final String fullPath;
  final Map<String, PathNode> children;
  int requestCount;

  PathNode({required this.segment, required this.fullPath, this.requestCount = 0})
      : children = {};

  int get totalCount {
    if (children.isEmpty) return requestCount;
    return children.values.fold(requestCount, (sum, child) => sum + child.totalCount);
  }
}

// ============================================================
// Controller
// ============================================================

class TreeController extends GetxController {
  final tree = <TreeNode>[].obs;
  final selectedDomain = Rxn<String>();
  final selectedPath = Rxn<String>();
  final selectedApp = Rxn<String>();
  final pinnedDomains = <String>{}.obs;
  final pinnedItems = <PinnedItem>[].obs;
  final appTree = <AppNode>[].obs;

  int? _taskId;
  final _hostCounts = <String, int>{};

  /// Strip default ports (:443, :80) from host for grouping
  static String _normalizeHost(String host) {
    if (host.endsWith(':443')) return host.substring(0, host.length - 4);
    if (host.endsWith(':80')) return host.substring(0, host.length - 3);
    return host;
  }

  /// Load domain tree from API, optionally filtered
  Future<void> loadDomains(int taskId, {String? protocol, String? keyword}) async {
    _taskId = taskId;
    try {
      final api = Get.find<ApiClient>();
      final items = await api.getFlowDomains(taskId, protocol: protocol, keyword: keyword);
      _hostCounts.clear();
      for (final item in items) {
        final h = _normalizeHost(item.host);
        _hostCounts[h] = (_hostCounts[h] ?? 0) + item.count;
      }
      _rebuildTree();
    } catch (_) {}
  }

  /// Reload tree after filter changes.
  /// - No filters active → re-fetch full domain list from API (restores all data)
  /// - Filters active → rebuild counts from current filtered flows
  void reloadWithFilters() {
    if (_taskId == null) return;
    final filterCtrl = Get.find<FilterController>();
    final hasFilters = filterCtrl.activeProtocols.isNotEmpty ||
        filterCtrl.activeContentTypes.isNotEmpty;

    if (!hasFilters) {
      // No filters — restore full data from API
      _invalidateChildren();
      loadDomains(_taskId!);
      return;
    }

    // Has filters — compute display counts from current flows
    final flowCtrl = Get.find<FlowController>();
    final flows = flowCtrl.flows.toList();
    final filteredCounts = <String, int>{};
    final filtered = filterCtrl.activeContentTypes.isEmpty
        ? flows
        : flows.where((f) => filterCtrl.matchesContentType(f)).toList();
    for (final f in filtered) {
      if (f.host.isNotEmpty) {
        final h = _normalizeHost(f.host);
        filteredCounts[h] = (filteredCounts[h] ?? 0) + 1;
      }
    }

    // Rebuild tree: show only domains with matches, invalidate cached children
    final nodes = filteredCounts.entries.map((e) {
      return TreeNode(
        label: e.key,
        domain: e.key,
        isGroup: true,
        count: e.value,
        // Don't reuse old children — they were loaded without filter
        childrenLoaded: false,
      );
    }).toList();

    nodes.sort((a, b) {
      final aPinned = pinnedDomains.contains(a.domain);
      final bPinned = pinnedDomains.contains(b.domain);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return b.count.compareTo(a.count);
    });
    tree.value = nodes;
  }

  /// Clear cached children so they re-fetch with current filters on next expand.
  void _invalidateChildren() {
    for (final node in tree) {
      node.children.clear();
      node.childrenLoaded = false;
    }
  }

  /// Load children (requests) for a domain on expand — respects current filters.
  Future<void> loadChildren(TreeNode node) async {
    if (node.childrenLoaded || _taskId == null || node.domain == null) return;
    try {
      final api = Get.find<ApiClient>();
      final filterCtrl = Get.find<FilterController>();
      final result = await api.getFlows(
        taskId: _taskId!,
        page: 1,
        size: 200,
        host: node.domain,
        protocol: filterCtrl.protocolParam,
      );
      // Apply client-side content type filter
      final items = filterCtrl.activeContentTypes.isEmpty
          ? result.items
          : result.items.where((f) => filterCtrl.matchesContentType(f)).toList();
      node.children.clear();
      node.children.addAll(items.map((f) => TreeNode(
        label: '${f.method} ${f.uri}',
        domain: node.domain,
      )));
      node.childrenLoaded = true;
      tree.refresh();
    } catch (_) {}
  }

  /// Incrementally update from WS push
  void addDomainFromPush(FlowSummary flow) {
    if (flow.host.isEmpty) return;
    final h = _normalizeHost(flow.host);
    _hostCounts[h] = (_hostCounts[h] ?? 0) + 1;
    _rebuildTree();
  }

  void togglePin(String domain) {
    if (pinnedDomains.contains(domain)) {
      pinnedDomains.remove(domain);
      pinnedItems.removeWhere(
          (item) => item.type == PinType.domain && item.identifier == domain);
    } else {
      pinnedDomains.add(domain);
      pinnedItems.add(PinnedItem(
        type: PinType.domain,
        label: domain,
        identifier: domain,
      ));
    }
    _rebuildTree();
  }

  bool isPinned(String domain) => pinnedDomains.contains(domain);

  void selectDomain(String? domain) {
    if (selectedDomain.value == domain && selectedPath.value == null) return;
    selectedDomain.value = domain;
    selectedPath.value = null;
    selectedApp.value = null;
    _notifyFlowReload();
  }

  void selectPath(String domain, String path) {
    if (selectedDomain.value == domain && selectedPath.value == path) return;
    selectedDomain.value = domain;
    selectedPath.value = path;
    selectedApp.value = null;
    _notifyFlowReload();
  }

  void selectApp(String appName) {
    selectedApp.value = appName;
    selectedDomain.value = null;
    selectedPath.value = null;
    _notifyFlowReload();
  }

  void clearSelection() {
    selectedDomain.value = null;
    selectedPath.value = null;
    selectedApp.value = null;
    _notifyFlowReload();
  }

  void _notifyFlowReload() {
    // FlowController listens and reloads
    Get.find<FlowController>().reloadForTreeSelection();
  }

  void clear() {
    _taskId = null;
    _hostCounts.clear();
    tree.clear();
    selectedDomain.value = null;
    selectedPath.value = null;
    selectedApp.value = null;
    pinnedItems.clear();
    pinnedDomains.clear();
    appTree.clear();
  }

  /// Build hierarchical path tree from URIs — directories only (no leaf filenames).
  /// Each URI's segments are treated as directory levels. The request count is
  /// attributed to the deepest directory segment (last segment is treated as
  /// part of its parent directory, not a separate node).
  static PathNode buildPathTree(List<TreeNode> children) {
    final root = PathNode(segment: '', fullPath: '');
    for (final child in children) {
      final parts = child.label.split(' ');
      final uri = parts.length > 1 ? parts.sublist(1).join(' ') : child.label;
      final segments = uri.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        root.requestCount++;
        continue;
      }
      // Build directory nodes — all segments become directories
      var current = root;
      var path = '';
      for (final seg in segments) {
        path += '/$seg';
        current.children.putIfAbsent(seg, () => PathNode(segment: seg, fullPath: path));
        current = current.children[seg]!;
      }
      current.requestCount++;
    }
    // Collapse single-child chains: /api/ -> /v1/ -> /users/ becomes /api/v1/users/
    _collapseChains(root);
    return root;
  }

  /// Collapse nodes that have exactly one child and zero own requests into their child.
  static void _collapseChains(PathNode node) {
    // Recurse first so we collapse from leaves up
    for (final child in node.children.values) {
      _collapseChains(child);
    }
    // Collapse: if this node has exactly 1 child and 0 own requests, merge child into this
    final keys = node.children.keys.toList();
    for (final key in keys) {
      final child = node.children[key]!;
      if (child.children.length == 1 && child.requestCount == 0) {
        final grandchild = child.children.values.first;
        node.children.remove(key);
        // Merge: combined segment "seg1/seg2"
        final merged = PathNode(
          segment: '${child.segment}/${grandchild.segment}',
          fullPath: grandchild.fullPath,
          requestCount: grandchild.requestCount,
        );
        merged.children.addAll(grandchild.children);
        node.children[merged.segment] = merged;
      }
    }
  }

  void _rebuildTree() {
    // Preserve expanded/loaded state
    final oldNodes = {for (final n in tree) n.domain: n};

    final nodes = _hostCounts.entries.map((e) {
      final old = oldNodes[e.key];
      return TreeNode(
        label: e.key,
        domain: e.key,
        isGroup: true,
        count: e.value,
        children: old?.children,
        childrenLoaded: old?.childrenLoaded ?? false,
      );
    }).toList();

    nodes.sort((a, b) {
      final aPinned = pinnedDomains.contains(a.domain);
      final bPinned = pinnedDomains.contains(b.domain);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return b.count.compareTo(a.count);
    });
    tree.value = nodes;
  }
}
