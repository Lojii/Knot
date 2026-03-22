import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tree_controller.dart';
import '../../controllers/flow_controller.dart';

class TreePanel extends StatelessWidget {
  const TreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    // Rebuild tree when flows change
    ever(flowCtrl.flows, (_) => treeCtrl.buildTree(flowCtrl.flows));

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tree header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text('Domains', style: theme.textTheme.labelSmall),
                const Spacer(),
                Obx(() => Text('${treeCtrl.tree.length}',
                    style: TextStyle(fontSize: 10, color: theme.hintColor))),
              ],
            ),
          ),
          const Divider(height: 1),
          // "All" option
          Obx(() => ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('All Domains', style: TextStyle(fontSize: 12)),
            selected: treeCtrl.selectedDomain.value == null,
            onTap: () => treeCtrl.selectDomain(null),
          )),
          // Domain tree
          Expanded(
            child: Obx(() => ListView.builder(
              itemCount: treeCtrl.tree.length,
              itemBuilder: (ctx, i) {
                final node = treeCtrl.tree[i];
                return ExpansionTile(
                  dense: true,
                  initiallyExpanded: false,
                  title: Text(node.label, style: const TextStyle(fontSize: 12)),
                  trailing: Text('${node.children.length}',
                      style: TextStyle(fontSize: 10, color: theme.hintColor)),
                  onExpansionChanged: (_) => treeCtrl.selectDomain(node.domain),
                  children: node.children.map((child) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(child.label,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                    onTap: () {
                      treeCtrl.selectDomain(node.domain);
                      // Find and select the matching flow
                    },
                  )).toList(),
                );
              },
            )),
          ),
        ],
      ),
    );
  }
}
