import 'package:get/get.dart';
import '../models/flow_summary.dart';
import 'flow_controller.dart';

class TreeNode {
  final String label;
  final String? domain;
  final bool isGroup;
  final List<TreeNode> children;
  bool expanded;

  TreeNode({
    required this.label,
    this.domain,
    this.isGroup = false,
    this.children = const [],
    this.expanded = true,
  });
}

class TreeController extends GetxController {
  final tree = <TreeNode>[].obs;
  final selectedDomain = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    // Rebuild tree whenever flow list changes (registered once, not per build)
    final flowCtrl = Get.find<FlowController>();
    ever(flowCtrl.flows, (_) => buildTree(flowCtrl.flows));
  }

  void buildTree(List<FlowSummary> flows) {
    final Map<String, List<FlowSummary>> grouped = {};
    for (final f in flows) {
      grouped.putIfAbsent(f.host, () => []).add(f);
    }

    final nodes = <TreeNode>[];
    for (final entry in grouped.entries) {
      nodes.add(TreeNode(
        label: entry.key,
        domain: entry.key,
        isGroup: true,
        children: entry.value.map((f) =>
          TreeNode(label: '${f.method} ${f.uri}', domain: entry.key)
        ).toList(),
      ));
    }

    // Sort by request count descending
    nodes.sort((a, b) => b.children.length.compareTo(a.children.length));
    tree.value = nodes;
  }

  void selectDomain(String? domain) {
    selectedDomain.value = domain;
  }
}
