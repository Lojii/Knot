import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/hoverable.dart';

class FilterBar extends StatefulWidget {
  final FocusNode searchFocusNode;
  const FilterBar({super.key, required this.searchFocusNode});

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  bool _searchFocused = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.searchFocusNode.addListener(_onSearchFocusChange);
    // Restore search text from controller (survives tab switch)
    final existing = TaskScope.table.searchQuery.value;
    if (existing.isNotEmpty) {
      _searchController.text = existing;
    }
  }

  @override
  void dispose() {
    widget.searchFocusNode.removeListener(_onSearchFocusChange);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChange() {
    setState(() {
      _searchFocused = widget.searchFocusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filterCtrl = TaskScope.filter;
    final filterBarCtrl = TaskScope.filterBar;
    final tableCtrl = TaskScope.table;

    final searchHasText = _searchController.text.isNotEmpty;
    final searchExpanded = _searchFocused || searchHasText;

    return Container(
      height: AppTheme.sizing.filterBarHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.colors(context).divider)),
      ),
      child: Row(
        children: [
          // HTTP/TCP mode switch
          Obx(() {
            final isTcp = filterCtrl.isTcpMode;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('HTTP', style: TextStyle(
                  fontSize: AppTheme.fontSize.sm,
                  fontWeight: isTcp ? FontWeight.normal : FontWeight.w600,
                  color: isTcp ? AppTheme.colors(context).textSecondary : AppTheme.colors(context).primary,
                )),
                SizedBox(
                  height: 20,
                  width: 36,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: isTcp,
                      onChanged: (_) => filterCtrl.toggleProtocolMode(),
                      activeThumbColor: AppTheme.colors(context).primary,
                    ),
                  ),
                ),
                Text('TCP', style: TextStyle(
                  fontSize: AppTheme.fontSize.sm,
                  fontWeight: isTcp ? FontWeight.w600 : FontWeight.normal,
                  color: isTcp ? AppTheme.colors(context).primary : AppTheme.colors(context).textSecondary,
                )),
                SizedBox(width: AppTheme.spacing.sm),
                Container(width: 1, height: 16, color: AppTheme.colors(context).divider),
                SizedBox(width: AppTheme.spacing.sm),
              ],
            );
          }),

          // Filter chips area — scrollable to prevent overflow
          Expanded(
            child: Obx(() {
              if (filterCtrl.isTcpMode) return const SizedBox.shrink();
              final protos = filterCtrl.availableProtocols;
              final types = filterCtrl.availableContentTypes;
              if (protos.isEmpty && types.isEmpty) return const SizedBox.shrink();

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Protocol group: ALL + chips
                    if (protos.isNotEmpty) ...[
                      _chip(context, 'filter.all'.tr,
                        isActive: filterCtrl.activeProtocols.isEmpty,
                        onTap: () {
                          filterBarCtrl.clearAll();
                        },
                      ),
                      ...protos.map((p) => _chip(context, p,
                        isActive: filterCtrl.activeProtocols.contains(p),
                        onTap: () {
                          filterBarCtrl.toggleProtocol(p);
                        },
                      )),
                    ],
                    // Divider between groups
                    if (protos.isNotEmpty && types.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
                        child: Container(width: 1, height: 16, color: AppTheme.colors(context).divider),
                      ),
                    // Content type group: ALL + chips
                    if (types.isNotEmpty) ...[
                      _chip(context, 'filter.all'.tr,
                        isActive: filterCtrl.activeContentTypes.isEmpty,
                        onTap: () {
                          filterBarCtrl.clearAll();
                        },
                      ),
                      ...types.map((t) => _chip(context, t,
                        isActive: filterCtrl.activeContentTypes.contains(t),
                        onTap: () {
                          filterBarCtrl.toggleContentType(t);
                        },
                      )),
                    ],
                  ],
                ),
              );
            }),
          ),

          SizedBox(width: AppTheme.spacing.sm),

          // Search field — compact when empty/unfocused, expands on focus
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: searchExpanded ? AppTheme.sizing.searchFieldWidth : 100,
            height: AppTheme.sizing.searchFieldHeight,
            child: AppTextField(
              controller: _searchController,
              focusNode: widget.searchFocusNode,
              hintText: 'toolbar.search'.tr,
              prefixIcon: const Icon(Icons.search, size: 16),
              suffixIcon: searchExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '\u2318F',
                        style: TextStyle(
                          fontSize: AppTheme.fontSize.xs,
                          color: AppTheme.colors(context).textSecondary,
                        ),
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              onChanged: (v) {
                setState(() {}); // update searchHasText for width
                tableCtrl.search(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, {required bool isActive, required VoidCallback onTap}) {
    final chipConfig = AppTheme.mode(context).filterChip;
    return Padding(
      padding: EdgeInsets.only(right: AppTheme.spacing.xs),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered) => Container(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? chipConfig.activeBackground
                : hovered
                    ? chipConfig.activeBackground.withValues(alpha: 0.4)
                    : chipConfig.inactiveBackground,
            borderRadius: BorderRadius.circular(AppTheme.radius.sm),
            border: Border.all(
              color: isActive ? chipConfig.activeBorder : chipConfig.inactiveBorder,
              width: 0.5,
            ),
          ),
          child: Text(label, style: TextStyle(
            fontSize: AppTheme.fontSize.sm,
            color: isActive ? chipConfig.activeText : null,
          )),
        ),
      ),
    );
  }
}
