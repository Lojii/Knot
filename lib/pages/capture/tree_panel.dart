import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tree_controller.dart';
import '../../theme/app_theme.dart';

class TreePanel extends StatelessWidget {
  const TreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tree header
          Container(
            height: AppTheme.sizing.tableHeaderHeight,
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text('Domains', style: theme.textTheme.labelSmall),
                const Spacer(),
                Obx(() => Text('${treeCtrl.tree.length}',
                    style: TextStyle(fontSize: AppTheme.fontSize.xs, color: theme.hintColor))),
              ],
            ),
          ),
          const Divider(height: 1),
          // "All" option
          Obx(() => ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text('All Domains', style: TextStyle(fontSize: AppTheme.fontSize.md)),
            selected: treeCtrl.selectedDomain.value == null,
            onTap: () => treeCtrl.selectDomain(null),
          )),
          // Domain tree
          Expanded(
            child: Obx(() {
              final pinned = treeCtrl.tree.where((n) => treeCtrl.isPinned(n.domain ?? '')).toList();
              final unpinned = treeCtrl.tree.where((n) => !treeCtrl.isPinned(n.domain ?? '')).toList();

              final sections = <Widget>[];

              // Pinned section
              if (pinned.isNotEmpty) {
                sections.add(Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.sm,
                    vertical: AppTheme.spacing.xs,
                  ),
                  child: Text('\u2B50 Pinned',
                      style: TextStyle(fontSize: AppTheme.fontSize.xs,
                          fontWeight: FontWeight.bold,
                          color: theme.hintColor)),
                ));
                for (final node in pinned) {
                  sections.add(_DomainTile(node: node, isPinned: true));
                }
                sections.add(const Divider(height: 1));
              }

              // Unpinned domains
              for (final node in unpinned) {
                sections.add(_DomainTile(node: node, isPinned: false));
              }

              return ListView(children: sections);
            }),
          ),
        ],
      ),
    );
  }
}

class _DomainTile extends StatelessWidget {
  final TreeNode node;
  final bool isPinned;
  const _DomainTile({required this.node, required this.isPinned});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();
    final theme = Theme.of(context);
    final domain = node.domain ?? '';

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showContextMenu(context, details.globalPosition, domain);
      },
      child: ExpansionTile(
        dense: true,
        initiallyExpanded: false,
        leading: isPinned
            ? const Icon(Icons.star, size: 14, color: Color(0xFFFFC107))
            : null,
        title: Text(node.label, style: TextStyle(fontSize: AppTheme.fontSize.md)),
        trailing: Text('${node.children.length}',
            style: TextStyle(fontSize: AppTheme.fontSize.xs, color: theme.hintColor)),
        onExpansionChanged: (_) => treeCtrl.selectDomain(node.domain),
        children: node.children.map((child) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(child.label,
              style: TextStyle(fontSize: AppTheme.fontSize.sm),
              overflow: TextOverflow.ellipsis),
          onTap: () {
            treeCtrl.selectDomain(node.domain);
          },
        )).toList(),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, String domain) {
    final treeCtrl = Get.find<TreeController>();
    final pinned = treeCtrl.isPinned(domain);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'toggle_pin',
          child: Row(
            children: [
              Icon(pinned ? Icons.star_border : Icons.star, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text(pinned ? 'Unpin' : 'Pin'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'toggle_pin') {
        treeCtrl.togglePin(domain);
      }
    });
  }
}
