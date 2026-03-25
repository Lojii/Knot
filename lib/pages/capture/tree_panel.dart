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
              final domains = allDomains
                  .where((n) => !treeCtrl.isPinned(n.domain ?? ''))
                  .toList();
              final hasData = pinned.isNotEmpty || apps.isNotEmpty || domains.isNotEmpty;

              if (!hasData) {
                return Center(
                  child: Text('empty.no_data'.tr,
                    style: TextStyle(color: AppTheme.colors(context).textSecondary)),
                );
              }

              return ListView(
                children: [
                  // Pinned — ONLY if non-empty
                  if (pinned.isNotEmpty) ...[
                    _SectionHeader(title: 'tree.pinned'.tr, count: pinned.length),
                    ...pinned.map((item) => _PinnedTile(item: item)),
                    Divider(height: 1, color: AppTheme.colors(context).divider),
                  ],
                  // Apps — ONLY if non-empty
                  if (apps.isNotEmpty) ...[
                    _SectionHeader(title: 'tree.apps'.tr, count: apps.length),
                    ...apps.map((app) => _AppTile(node: app)),
                    Divider(height: 1, color: AppTheme.colors(context).divider),
                  ],
                  // Domains — ONLY if non-empty
                  if (domains.isNotEmpty) ...[
                    _SectionHeader(title: 'tree.domains'.tr, count: domains.length),
                    ...domains.map((node) => _DomainTile(node: node)),
                  ],
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
    final treeCtrl = Get.find<TreeController>();

    return Obx(() {
      final isSelected = treeCtrl.selectedApp.value == node.name;

      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
          dense: true,
          leading: Icon(Icons.apps, size: 14, color: AppTheme.colors(context).textSecondary),
          title: Text(
            node.name,
            style: TextStyle(
              fontSize: AppTheme.fontSize.sm,
              color: isSelected
                  ? AppTheme.mode(context).tree.selectedText
                  : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            '${node.count}',
            style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              color: AppTheme.colors(context).textSecondary,
            ),
          ),
          onExpansionChanged: (expanded) {
            if (expanded) {
              treeCtrl.selectApp(node.name);
            } else {
              treeCtrl.clearSelection();
            }
          },
          children: node.domains.map((domain) {
            return InkWell(
              onTap: () {
                if (domain.domain != null) {
                  treeCtrl.selectDomain(domain.domain);
                }
              },
              child: Padding(
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
              ),
            );
          }).toList(),
        ),
      );
    });
  }
}

// ============================================================
// Domain Tile (with nested hierarchical path tree)
// ============================================================

class _DomainTile extends StatefulWidget {
  final TreeNode node;
  const _DomainTile({required this.node});

  @override
  State<_DomainTile> createState() => _DomainTileState();
}

class _DomainTileState extends State<_DomainTile> {
  final _controller = ExpansibleController();
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();
    final domain = widget.node.domain ?? '';

    return Obx(() {
      final isSelected = treeCtrl.selectedDomain.value == domain &&
          treeCtrl.selectedPath.value == null;
      final isDomainActive = treeCtrl.selectedDomain.value == domain;

      return GestureDetector(
        onTap: () {
          treeCtrl.selectDomain(domain);
          if (!_expanded) {
            _controller.expand();
            treeCtrl.loadChildren(widget.node);
          }
        },
        onSecondaryTapUp: (details) {
          _showContextMenu(context, details.globalPosition, domain);
        },
        child: Container(
          color: isSelected
              ? AppTheme.mode(context).tree.selectedBackground
              : null,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              controller: _controller,
              tilePadding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
              dense: true,
              title: Text(
                widget.node.label,
                style: TextStyle(
                  fontSize: AppTheme.fontSize.sm,
                  color: isDomainActive
                      ? AppTheme.mode(context).tree.selectedText
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.colors(context).textSecondary.withAlpha(25),
                borderRadius: BorderRadius.circular(AppTheme.radius.sm),
              ),
              child: Text(
                '${widget.node.count}',
                style: TextStyle(
                  fontSize: AppTheme.fontSize.xs,
                  color: isDomainActive
                      ? AppTheme.mode(context).tree.selectedText.withAlpha(180)
                      : AppTheme.colors(context).textSecondary,
                ),
              ),
            ),
            onExpansionChanged: (expanded) {
              _expanded = expanded;
              if (expanded) {
                treeCtrl.selectDomain(domain);
                treeCtrl.loadChildren(widget.node);
              }
            },
            children: _buildPathTree(context, domain),
          ),
        ),
        ),
      );
    });
  }

  /// Build hierarchical path tree from loaded children.
  List<Widget> _buildPathTree(BuildContext context, String domain) {
    if (widget.node.children.isEmpty) return [];

    final pathRoot = TreeController.buildPathTree(widget.node.children);

    return pathRoot.children.values.map((child) {
      return _PathTreeTile(node: child, domain: domain, depth: 0);
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

// ============================================================
// Recursive Path Tree Tile
// ============================================================

class _PathTreeTile extends StatefulWidget {
  final PathNode node;
  final String domain;
  final int depth;

  const _PathTreeTile({required this.node, required this.domain, required this.depth});

  @override
  State<_PathTreeTile> createState() => _PathTreeTileState();
}

class _PathTreeTileState extends State<_PathTreeTile> {
  ExpansibleController? _controller;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();
    final hasChildren = widget.node.children.isNotEmpty;
    final indent = AppTheme.spacing.xl + (widget.depth * AppTheme.spacing.md);

    if (!hasChildren) {
      // Leaf node — clickable path
      return Obx(() {
        final isSelected = treeCtrl.selectedDomain.value == widget.domain &&
            treeCtrl.selectedPath.value == widget.node.fullPath;

        return InkWell(
          onTap: () => treeCtrl.selectPath(widget.domain, widget.node.fullPath),
          child: Container(
            color: isSelected ? AppTheme.mode(context).tree.selectedBackground : null,
            padding: EdgeInsets.only(left: indent, right: AppTheme.spacing.sm, top: 3, bottom: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '/${widget.node.segment}',
                    style: TextStyle(
                      fontSize: AppTheme.fontSize.xs,
                      color: isSelected
                          ? AppTheme.mode(context).tree.selectedText
                          : AppTheme.colors(context).textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.node.requestCount > 0)
                  Text(
                    '${widget.node.requestCount}',
                    style: TextStyle(
                      fontSize: AppTheme.fontSize.xs,
                      color: AppTheme.colors(context).textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        );
      });
    }

    // Branch node — expandable + clickable
    _controller ??= ExpansibleController();
    return Obx(() {
      final isSelected = treeCtrl.selectedDomain.value == widget.domain &&
          treeCtrl.selectedPath.value == widget.node.fullPath;

      return GestureDetector(
        onTap: () {
          treeCtrl.selectPath(widget.domain, widget.node.fullPath);
          if (!_expanded) {
            _controller!.expand();
          }
        },
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Container(
            color: isSelected ? AppTheme.mode(context).tree.selectedBackground : null,
            child: ExpansionTile(
              controller: _controller,
              tilePadding: EdgeInsets.only(left: indent, right: AppTheme.spacing.sm),
              dense: true,
              onExpansionChanged: (expanded) {
                _expanded = expanded;
                if (expanded) {
                  treeCtrl.selectPath(widget.domain, widget.node.fullPath);
                }
              },
              title: Text(
                '/${widget.node.segment}/',
                style: TextStyle(
                  fontSize: AppTheme.fontSize.xs,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppTheme.mode(context).tree.selectedText : null,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.colors(context).textSecondary.withAlpha(20),
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                ),
                child: Text(
                  '${widget.node.totalCount}',
                  style: TextStyle(
                    fontSize: AppTheme.fontSize.xs,
                    color: isSelected
                        ? AppTheme.mode(context).tree.selectedText.withAlpha(180)
                        : AppTheme.colors(context).textSecondary,
                  ),
                ),
              ),
              children: widget.node.children.values.map((child) =>
                _PathTreeTile(node: child, domain: widget.domain, depth: widget.depth + 1),
              ).toList(),
            ),
          ),
        ),
      );
    });
  }
}
