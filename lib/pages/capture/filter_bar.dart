import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/filter_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../theme/app_theme.dart';

class FilterBar extends StatelessWidget {
  final FocusNode searchFocusNode;
  const FilterBar({super.key, required this.searchFocusNode});

  static const _protocols = ['HTTP', 'HTTPS', 'WS', 'WSS'];
  static const _contentTypes = ['JSON', 'IMG', 'TEXT', 'JS', 'HTML', 'CSS', 'XML'];

  @override
  Widget build(BuildContext context) {
    final filterCtrl = Get.find<FilterController>();
    final flowCtrl = Get.find<FlowController>();

    return Container(
      height: AppTheme.sizing.filterBarHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.colors(context).divider)),
      ),
      child: Row(
        children: [
          // Group 1: Protocol chips
          Obx(() => Row(
            mainAxisSize: MainAxisSize.min,
            children: _protocols.map((p) => _chip(context, p,
              isActive: filterCtrl.activeProtocols.contains(p),
              onTap: () {
                filterCtrl.toggleProtocol(p);
                flowCtrl.reloadFromFirstPage();
              },
            )).toList(),
          )),
          // Vertical divider
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
            child: Container(
              width: 1,
              height: 16,
              color: AppTheme.colors(context).divider,
            ),
          ),
          // Group 2: Content type chips
          Obx(() => Row(
            mainAxisSize: MainAxisSize.min,
            children: _contentTypes.map((t) => _chip(context, t,
              isActive: filterCtrl.activeContentTypes.contains(t),
              onTap: () {
                filterCtrl.toggleContentType(t);
                flowCtrl.reloadFromFirstPage();
              },
            )).toList(),
          )),
          // Spacer pushes search to the right
          const Spacer(),
          // Search field (moved from toolbar)
          SizedBox(
            width: AppTheme.sizing.searchFieldWidth,
            height: AppTheme.sizing.searchFieldHeight,
            child: TextField(
              focusNode: searchFocusNode,
              decoration: InputDecoration(
                hintText: 'toolbar.search'.tr,
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '\u2318F',
                    style: TextStyle(
                      fontSize: AppTheme.fontSize.xs,
                      color: AppTheme.colors(context).textSecondary,
                    ),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                isDense: true,
                filled: true,
                fillColor: AppTheme.colors(context).surface,
                contentPadding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.md),
                  borderSide: BorderSide(
                    color: AppTheme.colors(context).divider,
                    width: 0.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.md),
                  borderSide: BorderSide(
                    color: AppTheme.colors(context).divider,
                    width: 0.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.md),
                  borderSide: BorderSide(
                    color: AppTheme.colors(context).divider,
                    width: 0.5,
                  ),
                ),
              ),
              onChanged: flowCtrl.search,
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: isActive ? chipConfig.activeBackground : chipConfig.inactiveBackground,
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
