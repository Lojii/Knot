import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tree_controller.dart';
import '../../controllers/task_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/empty_state.dart';

// ============================================================
// Shared constants for unified tree row styling
// ============================================================

const double _rowHeight = 24.0;
const double _arrowSize = 14.0;
const double _arrowSpace = 18.0; // width reserved for arrow column
const double _baseIndent = 8.0;
const double _indentStep = 16.0;

class TreePanel extends StatelessWidget {
  const TreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() {
        final treeCtrl = TaskScope.tree;
        final pinned = treeCtrl.pinnedItems;
        final apps = treeCtrl.appTree;
        final allDomains = treeCtrl.tree;
        final domains = allDomains
            .where((n) => !treeCtrl.isPinned(n.domain ?? ''))
            .toList();
        final hasData =
            pinned.isNotEmpty || apps.isNotEmpty || domains.isNotEmpty;

        // Also depend on expandedNodes, selectedDomain, selectedPath so we rebuild
        treeCtrl.expandedNodes.length;
        treeCtrl.selectedDomain.value;
        treeCtrl.selectedPath.value;
        treeCtrl.selectedApp.value;

        if (!hasData) {
          return EmptyState(
            icon: Icons.account_tree_outlined,
            title: 'empty.no_data'.tr,
          );
        }

        // Build slivers with sticky section headers
        final slivers = <Widget>[];

        if (pinned.isNotEmpty) {
          final pinnedRows = <Widget>[];
          for (final item in pinned) {
            pinnedRows.add(_PinnedRow(item: item));
          }
          slivers.add(_stickyHeader(context,
              title: 'tree.pinned'.tr,
              count: pinned.length,
              onTap: () => treeCtrl.clearSelection()));
          slivers.add(SliverList(
              delegate: SliverChildListDelegate(pinnedRows)));
          slivers.add(SliverToBoxAdapter(child: Divider(
              height: 1, color: AppTheme.colors(context).divider)));
        }

        if (apps.isNotEmpty) {
          final appRows = <Widget>[];
          for (final app in apps) {
            appRows.add(_AppRow(node: app));
            if (treeCtrl.isExpanded('app:${app.name}')) {
              for (final domain in app.domains) {
                appRows.add(_AppDomainRow(
                    appName: app.name, node: domain));
              }
            }
          }
          slivers.add(_stickyHeader(context,
              title: 'tree.apps'.tr,
              count: apps.length,
              onTap: () => treeCtrl.clearSelection()));
          slivers.add(SliverList(
              delegate: SliverChildListDelegate(appRows)));
          slivers.add(SliverToBoxAdapter(child: Divider(
              height: 1, color: AppTheme.colors(context).divider)));
        }

        if (domains.isNotEmpty) {
          final domainRows = <Widget>[];
          for (final node in domains) {
            _buildDomainRows(domainRows, treeCtrl, node);
          }
          slivers.add(_stickyHeader(context,
              title: 'tree.domains'.tr,
              count: domains.length,
              onTap: () => treeCtrl.clearSelection()));
          slivers.add(SliverList(
              delegate: SliverChildListDelegate(domainRows)));
        }

        return CustomScrollView(slivers: slivers);
      }),
    );
  }

  Widget _stickyHeader(BuildContext context,
      {required String title, required int count, required VoidCallback onTap}) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyHeaderDelegate(
        title: title,
        count: count,
        onTap: onTap,
        height: AppTheme.sizing.tableHeaderHeight,
      ),
    );
  }

  void _buildDomainRows(
      List<Widget> rows, TreeController treeCtrl, TreeNode node) {
    final domain = node.domain ?? '';

    // Eagerly load children so we know if there are sub-paths to show arrow
    if (!node.childrenLoaded) {
      treeCtrl.loadChildren(node);
    }

    rows.add(_DomainRow(node: node));

    if (treeCtrl.isExpanded(domain) && node.pathRoot != null) {
      final root = node.pathRoot!;
      for (final child in root.children.values) {
        _buildPathRows(rows, treeCtrl, domain, child, 1);
      }
      // "others" for root-level requests not in any subdirectory
      if (root.requestCount > 0 && root.children.isNotEmpty) {
        rows.add(_OthersRow(
            count: root.requestCount, domain: domain, depth: 1, parentPath: ''));
      }
    }
  }

  void _buildPathRows(List<Widget> rows, TreeController treeCtrl,
      String domain, PathNode node, int depth) {
    rows.add(_PathRow(node: node, domain: domain, depth: depth));

    if (node.children.isNotEmpty &&
        treeCtrl.isExpanded(domain, node.fullPath)) {
      for (final child in node.children.values) {
        _buildPathRows(rows, treeCtrl, domain, child, depth + 1);
      }
      // "others" for requests at this directory level (not in deeper subdirectories)
      if (node.requestCount > 0) {
        rows.add(_OthersRow(
            count: node.requestCount, domain: domain, depth: depth + 1, parentPath: node.fullPath));
      }
    }
  }
}

// ============================================================
// Unified Tree Row — base widget for consistent styling
// ============================================================

class _TreeRow extends StatefulWidget {
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final bool isSelected;
  final String text;
  final String? trailingText;
  final Widget? leadingIcon;
  final VoidCallback onTap;
  final VoidCallback? onArrowTap;
  final GestureTapUpCallback? onSecondaryTapUp;

  const _TreeRow({
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.isSelected,
    required this.text,
    this.trailingText,
    this.leadingIcon,
    required this.onTap,
    this.onArrowTap,
    this.onSecondaryTapUp,
  });

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final indent = _baseIndent + (widget.depth * _indentStep);
    final selectedBg = AppTheme.mode(context).tree.selectedBackground;
    final selectedTx = AppTheme.mode(context).tree.selectedText;
    final hoverBg = AppTheme.colors(context).textSecondary.withAlpha(20);
    final textColor = widget.isSelected
        ? selectedTx
        : AppTheme.colors(context).textPrimary;
    final countColor = AppTheme.colors(context).textSecondary;

    Color? bgColor;
    if (widget.isSelected) {
      bgColor = selectedBg;
    } else if (_hovered) {
      bgColor = hoverBg;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Container(
          height: _rowHeight,
          color: bgColor,
          padding: EdgeInsets.only(left: indent, right: 8),
          child: Row(
            children: [
              // Arrow column — separate tap target, does NOT trigger row selection
              MouseRegion(
                cursor: widget.hasChildren && widget.onArrowTap != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.hasChildren && widget.onArrowTap != null
                      ? widget.onArrowTap
                      : null,
                  child: SizedBox(
                    width: _arrowSpace,
                    height: _rowHeight,
                    child: widget.hasChildren
                        ? Icon(
                            widget.isExpanded
                                ? Icons.arrow_drop_down
                                : Icons.arrow_right,
                            size: _arrowSize,
                            color: textColor,
                          )
                        : null,
                  ),
                ),
              ),
              // Rest of the row — triggers selection on tap
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: SizedBox(
                    height: _rowHeight,
                    child: Row(
                    children: [
                      if (widget.leadingIcon != null) ...[
                        widget.leadingIcon!,
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          widget.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTheme.fontSize.xs,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (widget.trailingText != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            widget.trailingText!,
                            style: TextStyle(
                              fontSize: AppTheme.fontSize.xs,
                              color: countColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Sticky Section Header Delegate
// ============================================================

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final int count;
  final VoidCallback onTap;
  final double height;

  _StickyHeaderDelegate({
    required this.title,
    required this.count,
    required this.onTap,
    required this.height,
  });

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) {
    final treeCtrl = TaskScope.tree;
    final isAllSelected = treeCtrl.selectedDomain.value == null &&
        treeCtrl.selectedPath.value == null &&
        treeCtrl.selectedApp.value == null;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
          color: isAllSelected
              ? AppTheme.mode(ctx).tree.selectedBackground
              : AppTheme.colors(ctx).surface,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: AppTheme.fontSize.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppTheme.colors(ctx).textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: AppTheme.fontSize.xs,
                  color: AppTheme.colors(ctx).textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) =>
      title != oldDelegate.title ||
      count != oldDelegate.count;
}

// ============================================================
// Pinned Row
// ============================================================

class _PinnedRow extends StatelessWidget {
  final PinnedItem item;
  const _PinnedRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = TaskScope.tree;
    final isSelected = item.type == PinType.domain &&
        treeCtrl.selectedDomain.value == item.identifier &&
        treeCtrl.selectedPath.value == null;

    return _TreeRow(
      depth: 0,
      hasChildren: false,
      isExpanded: false,
      isSelected: isSelected,
      text: item.label,
      leadingIcon:
          Icon(Icons.star, size: 12, color: AppTheme.colors(context).favorite),
      onTap: () {
        if (item.type == PinType.domain && item.identifier != null) {
          treeCtrl.selectDomain(item.identifier);
        }
      },
      onSecondaryTapUp: (details) {
        if (item.type == PinType.domain && item.identifier != null) {
          _showUnpinMenu(
              context, details.globalPosition, item.identifier!);
        }
      },
    );
  }

  void _showUnpinMenu(
      BuildContext context, Offset position, String identifier) {
    final treeCtrl = TaskScope.tree;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'unpin',
          child: Row(children: [
            const Icon(Icons.star_border, size: 16),
            SizedBox(width: AppTheme.spacing.sm),
            Text('tree.unpin'.tr),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'unpin') treeCtrl.togglePin(identifier);
    });
  }
}

// ============================================================
// App Row
// ============================================================

class _AppRow extends StatelessWidget {
  final AppNode node;
  const _AppRow({required this.node});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = TaskScope.tree;
    final isSelected = treeCtrl.selectedApp.value == node.name;
    final isExpanded = treeCtrl.isExpanded('app:${node.name}');

    return _TreeRow(
      depth: 0,
      hasChildren: node.domains.isNotEmpty,
      isExpanded: isExpanded,
      isSelected: isSelected,
      text: node.name,
      trailingText: '${node.count}',
      leadingIcon: Icon(Icons.apps,
          size: 12, color: AppTheme.colors(context).textSecondary),
      onTap: () {
        treeCtrl.toggleExpand('app:${node.name}');
        treeCtrl.selectApp(node.name);
      },
    );
  }
}

class _AppDomainRow extends StatelessWidget {
  final String appName;
  final TreeNode node;
  const _AppDomainRow({required this.appName, required this.node});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = TaskScope.tree;
    final isSelected = treeCtrl.selectedDomain.value == node.domain;

    return _TreeRow(
      depth: 1,
      hasChildren: false,
      isExpanded: false,
      isSelected: isSelected,
      text: node.label,
      trailingText: '${node.count}',
      onTap: () {
        if (node.domain != null) {
          treeCtrl.selectDomain(node.domain);
        }
      },
    );
  }
}

// ============================================================
// Domain Row
// ============================================================

class _DomainRow extends StatelessWidget {
  final TreeNode node;
  const _DomainRow({required this.node});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = TaskScope.tree;
    final domain = node.domain ?? '';
    final isSelected = treeCtrl.selectedDomain.value == domain &&
        treeCtrl.selectedPath.value == null;
    final hasSubPaths = node.hasPathChildren;
    final isExpanded = hasSubPaths && treeCtrl.isExpanded(domain);

    return _TreeRow(
      depth: 0,
      hasChildren: hasSubPaths,
      isExpanded: isExpanded,
      isSelected: isSelected,
      text: node.label,
      trailingText: '${node.count}',
      onTap: () {
        if (isSelected && hasSubPaths) {
          treeCtrl.toggleExpand(domain);
        } else {
          treeCtrl.selectDomain(domain);
          if (!node.childrenLoaded) {
            treeCtrl.loadChildren(node);
          }
        }
      },
      onArrowTap: hasSubPaths ? () {
        treeCtrl.toggleExpand(domain);
      } : null,
      onSecondaryTapUp: (details) {
        _showContextMenu(context, details.globalPosition, domain);
      },
    );
  }

  void _showContextMenu(
      BuildContext context, Offset position, String domain) {
    final treeCtrl = TaskScope.tree;
    final pinned = treeCtrl.isPinned(domain);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'toggle_pin',
          child: Row(children: [
            Icon(pinned ? Icons.star_border : Icons.star, size: 16),
            SizedBox(width: AppTheme.spacing.sm),
            Text(pinned ? 'tree.unpin'.tr : 'tree.pin'.tr),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'toggle_pin') treeCtrl.togglePin(domain);
    });
  }
}

// ============================================================
// Path Row (sub-directory under a domain)
// ============================================================

class _PathRow extends StatelessWidget {
  final PathNode node;
  final String domain;
  final int depth;

  const _PathRow(
      {required this.node, required this.domain, required this.depth});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = TaskScope.tree;
    final hasChildren = node.children.isNotEmpty;
    final isSelected = treeCtrl.selectedDomain.value == domain &&
        treeCtrl.selectedPath.value == node.fullPath;
    final isExpanded =
        hasChildren && treeCtrl.isExpanded(domain, node.fullPath);

    return _TreeRow(
      depth: depth,
      hasChildren: hasChildren,
      isExpanded: isExpanded,
      isSelected: isSelected,
      text: '/${node.segment}',
      trailingText: '${node.totalCount}',
      onTap: () {
        if (isSelected && hasChildren) {
          treeCtrl.toggleExpand(domain, node.fullPath);
        } else {
          treeCtrl.selectPath(domain, node.fullPath);
        }
      },
      onArrowTap: hasChildren ? () {
        treeCtrl.toggleExpand(domain, node.fullPath);
      } : null,
    );
  }
}

// ============================================================
// Others Row — uncategorized requests at a directory level
// ============================================================

class _OthersRow extends StatelessWidget {
  final int count;
  final String domain;
  final int depth;
  /// Parent path — "" for domain root, or the parent PathNode's fullPath.
  final String parentPath;

  const _OthersRow({
    required this.count,
    required this.domain,
    required this.depth,
    required this.parentPath,
  });

  @override
  Widget build(BuildContext context) {
    final treeCtrl = TaskScope.tree;
    // Use "parentPath/*" as a special marker for "others" selection
    final othersPath = '$parentPath/*';
    final isSelected = treeCtrl.selectedDomain.value == domain &&
        treeCtrl.selectedPath.value == othersPath;

    return _TreeRow(
      depth: depth,
      hasChildren: false,
      isExpanded: false,
      isSelected: isSelected,
      text: '',
      trailingText: '$count',
      leadingIcon: Icon(Icons.more_horiz,
          size: 14, color: AppTheme.colors(context).textSecondary),
      onTap: () {
        treeCtrl.selectPath(domain, othersPath);
      },
    );
  }
}
