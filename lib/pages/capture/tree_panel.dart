import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tree_controller.dart';
import '../../theme/app_theme.dart';

class TreePanel extends StatelessWidget {
  const TreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Obx(() {
              final treeCtrl = Get.find<TreeController>();
              final pinned = treeCtrl.pinnedItems;
              final apps = treeCtrl.appTree;
              final allDomains = treeCtrl.tree;
              // Domain section: only unpinned domains
              final domains = allDomains
                  .where((n) => !treeCtrl.isPinned(n.domain ?? ''))
                  .toList();

              return ListView(
                children: [
                  // ---- Pinned Section ----
                  _SectionHeader(title: 'tree.pinned'.tr, count: pinned.length),
                  ...pinned.map((item) => _PinnedTile(item: item)),
                  Divider(height: 1, color: AppTheme.colors(context).divider),

                  // ---- Apps Section ----
                  _SectionHeader(title: 'tree.apps'.tr, count: apps.length),
                  ...apps.map((app) => _AppTile(node: app)),
                  Divider(height: 1, color: AppTheme.colors(context).divider),

                  // ---- Domains Section ----
                  _SectionHeader(
                      title: 'tree.domains'.tr, count: domains.length),
                  ...domains.map((node) => _DomainTile(node: node)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Section Header
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.sizing.tableHeaderHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppTheme.colors(context).textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              color: AppTheme.colors(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Pinned Tile
// ============================================================

class _PinnedTile extends StatelessWidget {
  final PinnedItem item;
  const _PinnedTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();

    return Obx(() {
      final isSelected = item.type == PinType.domain &&
          treeCtrl.selectedDomain.value == item.identifier &&
          treeCtrl.selectedPath.value == null;

      return GestureDetector(
        onTap: () {
          if (item.type == PinType.domain && item.identifier != null) {
            treeCtrl.selectDomain(item.identifier);
          }
        },
        onSecondaryTapUp: (details) {
          if (item.type == PinType.domain && item.identifier != null) {
            _showUnpinMenu(context, details.globalPosition, item.identifier!);
          }
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing.sm,
            vertical: 4,
          ),
          margin: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing.xs,
            vertical: 1,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.mode(context).tree.selectedBackground
                : null,
            borderRadius:
                BorderRadius.circular(AppTheme.mode(context).tree.selectedRadius),
          ),
          child: Row(
            children: [
              const Icon(Icons.star, size: 12, color: Color(0xFFFFC107)),
              SizedBox(width: AppTheme.spacing.xs),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: AppTheme.fontSize.sm,
                    color: isSelected
                        ? AppTheme.mode(context).tree.selectedText
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showUnpinMenu(
      BuildContext context, Offset position, String identifier) {
    final treeCtrl = Get.find<TreeController>();
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'unpin',
          child: Row(
            children: [
              const Icon(Icons.star_border, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tree.unpin'.tr),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'unpin') {
        treeCtrl.togglePin(identifier);
      }
    });
  }
}

// ============================================================
// App Tile
// ============================================================

class _AppTile extends StatelessWidget {
  final AppNode node;
  const _AppTile({required this.node});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
        dense: true,
        leading: Icon(Icons.apps, size: 14, color: AppTheme.colors(context).textSecondary),
        title: Text(
          node.name,
          style: TextStyle(fontSize: AppTheme.fontSize.sm),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${node.count}',
          style: TextStyle(
            fontSize: AppTheme.fontSize.xs,
            color: AppTheme.colors(context).textSecondary,
          ),
        ),
        children: node.domains.map((domain) {
          return Padding(
            padding: EdgeInsets.only(
              left: AppTheme.spacing.xl,
              right: AppTheme.spacing.sm,
              top: 2,
              bottom: 2,
            ),
            child: Text(
              domain.label,
              style: TextStyle(
                fontSize: AppTheme.fontSize.xs,
                color: AppTheme.colors(context).textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================
// Domain Tile (with nested path groups and request leaves)
// ============================================================

class _DomainTile extends StatelessWidget {
  final TreeNode node;
  const _DomainTile({required this.node});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();
    final domain = node.domain ?? '';

    return Obx(() {
      final isSelected = treeCtrl.selectedDomain.value == domain &&
          treeCtrl.selectedPath.value == null;

      return GestureDetector(
        onSecondaryTapUp: (details) {
          _showContextMenu(context, details.globalPosition, domain);
        },
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
            dense: true,
            initiallyExpanded: false,
            title: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing.xs, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.mode(context).tree.selectedBackground
                    : null,
                borderRadius: BorderRadius.circular(
                    AppTheme.mode(context).tree.selectedRadius),
              ),
              child: Text(
                node.label,
                style: TextStyle(
                  fontSize: AppTheme.fontSize.sm,
                  color: isSelected
                      ? AppTheme.mode(context).tree.selectedText
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.colors(context).textSecondary.withAlpha(25),
                borderRadius: BorderRadius.circular(AppTheme.radius.sm),
              ),
              child: Text(
                '${node.count}',
                style: TextStyle(
                  fontSize: AppTheme.fontSize.xs,
                  color: isSelected
                      ? AppTheme.mode(context).tree.selectedText.withAlpha(180)
                      : AppTheme.colors(context).textSecondary,
                ),
              ),
            ),
            onExpansionChanged: (expanded) {
              treeCtrl.selectDomain(domain);
              if (expanded) treeCtrl.loadChildren(node);
            },
            children: _buildPathGroups(context, domain),
          ),
        ),
      );
    });
  }

  /// Group children by path prefix and build nested tiles.
  List<Widget> _buildPathGroups(BuildContext context, String domain) {
    final treeCtrl = Get.find<TreeController>();
    if (node.children.isEmpty) return [];

    // Group by path directory (first path segment)
    final groups = <String, List<TreeNode>>{};
    for (final child in node.children) {
      final parts = child.label.split(' ');
      final uri = parts.length > 1 ? parts.sublist(1).join(' ') : child.label;
      final segments = uri.split('/').where((s) => s.isNotEmpty).toList();
      final groupKey = segments.isNotEmpty ? '/${segments.first}/' : '/';
      groups.putIfAbsent(groupKey, () => []).add(child);
    }

    // If only one group, show flat list
    if (groups.length <= 1) {
      return node.children.map((child) {
        final parts = child.label.split(' ');
        final path = parts.length > 1 ? parts.sublist(1).join(' ') : child.label;
        return InkWell(
          onTap: () => treeCtrl.selectPath(domain, path),
          child: Padding(
            padding: EdgeInsets.only(
              left: AppTheme.spacing.xl,
              right: AppTheme.spacing.sm,
              top: 2,
              bottom: 2,
            ),
            child: Text(
              child.label,
              style: TextStyle(
                fontSize: AppTheme.fontSize.xs,
                color: AppTheme.colors(context).textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList();
    }

    // Multiple groups: show path group tiles (Level 1) with request leaves (Level 2)
    return groups.entries.map((entry) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.only(
            left: AppTheme.spacing.xl,
            right: AppTheme.spacing.sm,
          ),
          dense: true,
          title: Text(
            entry.key,
            style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.colors(context).textSecondary.withAlpha(20),
              borderRadius: BorderRadius.circular(AppTheme.radius.sm),
            ),
            child: Text(
              '${entry.value.length}',
              style: TextStyle(
                fontSize: AppTheme.fontSize.xs,
                color: AppTheme.colors(context).textSecondary,
              ),
            ),
          ),
          children: entry.value.map((child) {
            final parts = child.label.split(' ');
            final path =
                parts.length > 1 ? parts.sublist(1).join(' ') : child.label;
            return InkWell(
              onTap: () => treeCtrl.selectPath(domain, path),
              child: Padding(
                padding: EdgeInsets.only(
                  left: AppTheme.spacing.xl + AppTheme.spacing.lg,
                  right: AppTheme.spacing.sm,
                  top: 2,
                  bottom: 2,
                ),
                child: Text(
                  child.label,
                  style: TextStyle(
                    fontSize: AppTheme.fontSize.xs,
                    color: AppTheme.colors(context).textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }

  void _showContextMenu(
      BuildContext context, Offset position, String domain) {
    final treeCtrl = Get.find<TreeController>();
    final pinned = treeCtrl.isPinned(domain);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'toggle_pin',
          child: Row(
            children: [
              Icon(pinned ? Icons.star_border : Icons.star, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text(pinned ? 'tree.unpin'.tr : 'tree.pin'.tr),
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
