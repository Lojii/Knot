import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/filter_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../theme/app_theme.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final filterCtrl = Get.find<FilterController>();
    final flowCtrl = Get.find<FlowController>();

    return Obx(() {
      final hasFlows = flowCtrl.flows.isNotEmpty;
      final hasProtos = filterCtrl.availableProtocols.isNotEmpty;
      final hasCTypes = filterCtrl.availableContentTypes.isNotEmpty;

      // Hide completely when no data
      if (!hasFlows || (!hasProtos && !hasCTypes)) {
        return const SizedBox.shrink();
      }

      return Container(
        height: AppTheme.sizing.filterBarHeight,
        padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.colors(context).divider)),
        ),
        child: Row(
          children: [
            // Group 1: Protocol
            if (hasProtos) ...[
              _chip(context, 'filter.all'.tr,
                isActive: filterCtrl.activeProtocols.isEmpty,
                onTap: () {
                  filterCtrl.toggleProtocol('All');
                  flowCtrl.reloadFromFirstPage();
                },
              ),
              ...filterCtrl.availableProtocols.map((p) => _chip(context, p,
                isActive: filterCtrl.activeProtocols.contains(p),
                onTap: () {
                  filterCtrl.toggleProtocol(p);
                  flowCtrl.reloadFromFirstPage();
                },
              )),
            ],
            // Separator between groups
            if (hasProtos && hasCTypes)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
                child: Container(
                  width: 1,
                  height: 16,
                  color: AppTheme.colors(context).divider,
                ),
              ),
            // Group 2: Content type
            if (hasCTypes) ...[
              _chip(context, 'filter.all'.tr,
                isActive: filterCtrl.activeContentTypes.isEmpty,
                onTap: () {
                  filterCtrl.toggleContentType('All');
                  flowCtrl.reloadFromFirstPage();
                },
              ),
              ...filterCtrl.availableContentTypes.map((t) => _chip(context, t,
                isActive: filterCtrl.activeContentTypes.contains(t),
                onTap: () {
                  filterCtrl.toggleContentType(t);
                  flowCtrl.reloadFromFirstPage();
                },
              )),
            ],
          ],
        ),
      );
    });
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
