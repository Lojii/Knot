import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_summary.dart';
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

// ============================================================
// Controller
// ============================================================

class TreeController extends GetxController {
  final tree = <TreeNode>[].obs;
  final selectedDomain = Rxn<String>();
  final selectedPath = Rxn<String>();
  final pinnedDomains = <String>{}.obs;
  final pinnedItems = <PinnedItem>[].obs;
  final appTree = <AppNode>[].obs;

  int? _taskId;
  final _hostCounts = <String, int>{};

  /// Load domain tree from API
  Future<void> loadDomains(int taskId) async {
    _taskId = taskId;
    try {
      final api = Get.find<ApiClient>();
      final items = await api.getFlowDomains(taskId);
      _hostCounts.clear();
      for (final item in items) {
        _hostCounts[item.host] = item.count;
      }
      _rebuildTree();
    } catch (_) {}
  }

  /// Load children (requests) for a domain on expand
  Future<void> loadChildren(TreeNode node) async {
    if (node.childrenLoaded || _taskId == null || node.domain == null) return;
    try {
      final api = Get.find<ApiClient>();
      final result = await api.getFlows(
        taskId: _taskId!,
        page: 1,
        size: 200,
        host: node.domain,
      );
      node.children.clear();
      node.children.addAll(result.items.map((f) => TreeNode(
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
    _hostCounts[flow.host] = (_hostCounts[flow.host] ?? 0) + 1;
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
    _notifyFlowReload();
  }

  void selectPath(String domain, String path) {
    if (selectedDomain.value == domain && selectedPath.value == path) return;
    selectedDomain.value = domain;
    selectedPath.value = path;
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
    pinnedItems.clear();
    pinnedDomains.clear();
    appTree.clear();
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
