import 'package:get/get.dart';
import '../models/flow_summary.dart';
import 'filter_controller.dart';
import 'flow_controller.dart';
import 'flow_table_controller.dart';

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
  /// Cached path tree root built from children — set by loadChildren.
  PathNode? pathRoot;

  TreeNode({
    required this.label,
    this.domain,
    this.isGroup = false,
    List<TreeNode>? children,
    this.count = 0,
    this.childrenLoaded = false,
    this.pathRoot,
  }) : children = children ?? [];

  /// Whether this domain has expandable sub-paths (only valid after loadChildren).
  bool get hasPathChildren => pathRoot != null && pathRoot!.children.isNotEmpty;
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
// Controller — all computation is local, NO API calls
// ============================================================

class TreeController extends GetxController {
  int? taskId;

  String get _tag => 'task_$taskId';
  FlowController get _flowCtrl => Get.find<FlowController>(tag: _tag);
  FilterController get _filterCtrl => Get.find<FilterController>(tag: _tag);
  FlowTableController get _tableCtrl => Get.find<FlowTableController>(tag: _tag);

  final tree = <TreeNode>[].obs;
  final selectedDomain = Rxn<String>();
  final selectedPath = Rxn<String>();
  final selectedApp = Rxn<String>();
  final pinnedDomains = <String>{}.obs;
  final pinnedItems = <PinnedItem>[].obs;
  final appTree = <AppNode>[].obs;

  /// Expand/collapse state keyed by node id (domain or "domain:path")
  final expandedNodes = <String>{}.obs;

  /// Full host→count map from ALL flows (unfiltered baseline).
  final _fullHostCounts = <String, int>{};

  /// Domain first-seen order — lower index = appeared earlier.
  /// Used for sorting: newer (higher index) domains appear first.
  final _domainOrder = <String, int>{};
  int _orderCounter = 0;

  /// Strip default ports (:443, :80) from host for grouping
  static String normalizeHost(String host) {
    if (host.endsWith(':443')) return host.substring(0, host.length - 4);
    if (host.endsWith(':80')) return host.substring(0, host.length - 3);
    return host;
  }

  // ── Compute from local flows (no API) ─────────────────────

  /// Recompute domain tree from the full local flow list.
  /// Called after initial load and after filter changes.
  /// Tree counts reflect filter bar (protocol/contentType/search) only,
  /// NOT the tree's own selection — so selecting a domain doesn't hide others.
  void recomputeFromFlows(List<FlowSummary> allFlows) {
    // Rebuild full host counts and first-seen order from ALL flows (unfiltered)
    _fullHostCounts.clear();
    _domainOrder.clear();
    _orderCounter = 0;
    for (final f in allFlows) {
      if (f.host.isNotEmpty) {
        final h = normalizeHost(f.host);
        _fullHostCounts[h] = (_fullHostCounts[h] ?? 0) + 1;
        _domainOrder.putIfAbsent(h, () => _orderCounter++);
      }
    }

    final filterCtrl = _filterCtrl;

    final hasFilters = filterCtrl.activeProtocols.isNotEmpty ||
        filterCtrl.activeContentTypes.isNotEmpty ||
        _tableCtrl.searchQuery.value.isNotEmpty;

    if (!hasFilters) {
      _rebuildTree(_fullHostCounts, invalidateChildren: false);
      return;
    }

    // Compute display counts by filtering allFlows with filter bar only
    // (protocol + contentType + search), excluding tree selection
    final query = _tableCtrl.searchQuery.value.toLowerCase();
    final displayCounts = <String, int>{};
    for (final f in allFlows) {
      if (f.host.isEmpty) continue;
      // Protocol filter
      if (filterCtrl.activeProtocols.isNotEmpty &&
          !filterCtrl.activeProtocols.contains(f.protocol.toUpperCase())) {
        continue;
      }
      // Content type filter
      if (filterCtrl.activeContentTypes.isNotEmpty &&
          !filterCtrl.matchesContentType(f)) {
        continue;
      }
      // Search query
      if (query.isNotEmpty) {
        final haystack = '${f.host} ${f.uri} ${f.method} ${f.statusCode}'.toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      final h = normalizeHost(f.host);
      displayCounts[h] = (displayCounts[h] ?? 0) + 1;
    }

    _rebuildTree(displayCounts, invalidateChildren: true);
  }

  /// Incrementally add a single flow from WS push — no API.
  void addDomainFromPush(FlowSummary flow) {
    if (flow.host.isEmpty) return;
    final h = normalizeHost(flow.host);
    _fullHostCounts[h] = (_fullHostCounts[h] ?? 0) + 1;
    _domainOrder.putIfAbsent(h, () => _orderCounter++);

    // Update tree node count in-place if it exists, otherwise rebuild
    final existing = tree.firstWhereOrNull((n) => n.domain == h);
    if (existing != null) {
      existing.count = _fullHostCounts[h]!;
      // Mark children as stale so next expand re-computes
      existing.childrenLoaded = false;
      existing.children.clear();
      tree.refresh();
    } else {
      _rebuildTree(_fullHostCounts, invalidateChildren: false);
    }
  }

  /// Get children (paths) for a domain from local flows — no API.
  void loadChildren(TreeNode node) {
    if (node.childrenLoaded || node.domain == null) return;

    final flowCtrl = _flowCtrl;
    final filterCtrl = _filterCtrl;
    final domain = node.domain!;

    // Filter from local allFlows by domain + current filters
    final items = flowCtrl.allFlows.where((f) {
      if (normalizeHost(f.host) != domain) return false;
      if (filterCtrl.activeProtocols.isNotEmpty) {
        if (!filterCtrl.activeProtocols.contains(f.protocol.toUpperCase())) return false;
      }
      if (!filterCtrl.matchesContentType(f)) return false;
      return true;
    }).toList();

    node.children.clear();
    node.children.addAll(items.map((f) => TreeNode(
      label: '${f.method} ${f.uri}',
      domain: domain,
    )));
    node.pathRoot = buildPathTree(node.children);
    node.childrenLoaded = true;
  }

  // ── Expand/Collapse ──────────────────────────────────────

  String nodeKey(String domain, [String? path]) =>
      path != null ? '$domain:$path' : domain;

  bool isExpanded(String domain, [String? path]) =>
      expandedNodes.contains(nodeKey(domain, path));

  void toggleExpand(String domain, [String? path]) {
    final key = nodeKey(domain, path);
    if (expandedNodes.contains(key)) {
      expandedNodes.remove(key);
    } else {
      expandedNodes.add(key);
    }
  }

  // ── Selection ─────────────────────────────────────────────

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
    _rebuildTree(_fullHostCounts, invalidateChildren: false);
  }

  bool isPinned(String domain) => pinnedDomains.contains(domain);

  void selectDomain(String? domain) {
    selectedDomain.value = domain;
    selectedPath.value = null;
    selectedApp.value = null;
    _tableCtrl.refilterForTreeSelection();
  }

  void selectPath(String domain, String path) {
    selectedDomain.value = domain;
    selectedPath.value = path;
    selectedApp.value = null;
    _tableCtrl.refilterForTreeSelection();
  }

  void selectApp(String appName) {
    selectedApp.value = appName;
    selectedDomain.value = null;
    selectedPath.value = null;
    _tableCtrl.refilterForTreeSelection();
  }

  void clearSelection() {
    selectedDomain.value = null;
    selectedPath.value = null;
    selectedApp.value = null;
    _tableCtrl.refilterForTreeSelection();
  }

  void clear() {
    _fullHostCounts.clear();
    _domainOrder.clear();
    _orderCounter = 0;
    tree.clear();
    selectedDomain.value = null;
    selectedPath.value = null;
    selectedApp.value = null;
    pinnedItems.clear();
    pinnedDomains.clear();
    appTree.clear();
    expandedNodes.clear();
  }

  // ── Path tree builder ─────────────────────────────────────

  /// Build hierarchical path tree from URIs — directory nodes only, no file/endpoint leaves.
  /// e.g. "GET /api/v1/users/123" → directories: /api, /v1, /users — "123" is NOT a node.
  /// The request count is attributed to the deepest directory.
  static PathNode buildPathTree(List<TreeNode> children) {
    final root = PathNode(segment: '', fullPath: '');
    for (final child in children) {
      final parts = child.label.split(' ');
      final raw = parts.length > 1 ? parts.sublist(1).join(' ') : child.label;
      // Use Uri.parse to properly extract the path (handles %, ?, # correctly)
      final parsed = Uri.tryParse(raw);
      final pathOnly = parsed?.path ?? raw;
      final segments = pathOnly.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        root.requestCount++;
        continue;
      }
      // Always drop the last segment — it's either a filename or a leaf resource.
      // Tree shows parent directories only. Requests count toward their parent.
      // e.g. /api/v1/users/123 → tree: /api/v1/users (count+1)
      // e.g. /static/js/app.js → tree: /static/js (count+1)
      // Single-segment like /favicon.ico → count goes to root
      if (segments.length <= 1) {
        root.requestCount++;
        continue;
      }
      final dirSegments = segments.sublist(0, segments.length - 1);
      var current = root;
      var path = '';
      for (final seg in dirSegments) {
        path += '/$seg';
        current.children.putIfAbsent(seg, () => PathNode(segment: seg, fullPath: path));
        current = current.children[seg]!;
      }
      current.requestCount++;
    }
    _collapseChains(root);
    return root;
  }

  /// Collapse single-child chains: if a node has exactly 1 child, merge them.
  /// e.g. /obj → /tiktok_web_login_static → /tiktok → ... becomes one node.
  /// requestCount is accumulated during merge.
  static void _collapseChains(PathNode node) {
    // Recurse first
    for (final child in node.children.values) {
      _collapseChains(child);
    }
    // Collapse: if a child has exactly 1 grandchild, merge child+grandchild
    final keys = node.children.keys.toList();
    for (final key in keys) {
      var child = node.children[key]!;
      // Keep merging as long as the child has exactly 1 sub-child
      // BUT stop if the child has its own requests (files at this level)
      while (child.children.length == 1 && child.requestCount == 0) {
        final grandchild = child.children.values.first;
        final merged = PathNode(
          segment: '${child.segment}/${grandchild.segment}',
          fullPath: grandchild.fullPath,
          requestCount: grandchild.requestCount,
        );
        merged.children.addAll(grandchild.children);
        child = merged;
      }
      // Replace original child with the collapsed version
      if (child.segment != key) {
        node.children.remove(key);
        node.children[child.segment] = child;
      }
    }
  }

  // ── Private ───────────────────────────────────────────────

  void _rebuildTree(Map<String, int> counts, {required bool invalidateChildren}) {
    final oldNodes = {for (final n in tree) n.domain: n};

    final nodes = counts.entries
        .where((e) => e.value > 0)
        .map((e) {
      final old = oldNodes[e.key];
      return TreeNode(
        label: e.key,
        domain: e.key,
        isGroup: true,
        count: e.value,
        children: invalidateChildren ? null : old?.children,
        childrenLoaded: invalidateChildren ? false : (old?.childrenLoaded ?? false),
        pathRoot: invalidateChildren ? null : old?.pathRoot,
      );
    }).toList();

    nodes.sort((a, b) {
      final aPinned = pinnedDomains.contains(a.domain);
      final bPinned = pinnedDomains.contains(b.domain);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      // Sort by first-seen order: newer (higher index) first
      final aOrder = _domainOrder[a.domain] ?? 0;
      final bOrder = _domainOrder[b.domain] ?? 0;
      return aOrder.compareTo(bOrder);
    });
    tree.value = nodes;
  }
}
