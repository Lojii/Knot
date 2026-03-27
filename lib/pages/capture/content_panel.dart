import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multi_split_view/multi_split_view.dart';
import '../../controllers/task_scope.dart';
import '../../theme/app_theme.dart';
import 'flow_table.dart';
import 'flow_detail_panel.dart';
import 'waterfall_tab.dart';
import 'dashboard_tab.dart';

class ContentPanel extends StatelessWidget {
  const ContentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailTab = AppTheme.mode(context).detailTab;
    final tabs = ['tab.list'.tr, 'tab.waterfall'.tr, 'tab.dashboard'.tr];

    return Obx(() {
      final filterCtrl = TaskScope.filter;
      if (filterCtrl.isTcpMode) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined,
                  size: 48,
                  color: AppTheme.colors(context).textSecondary),
              SizedBox(height: AppTheme.spacing.md),
              Text('tab.tcp_coming_soon'.tr,
                  style: TextStyle(
                      color: AppTheme.colors(context).textSecondary,
                      fontSize: AppTheme.fontSize.lg)),
            ],
          ),
        );
      }

      final panelCtrl = TaskScope.contentPanel;
      final activeTab = panelCtrl.activeTab.value;

      return Column(
        children: [
          // Tab bar
          Container(
            height: 32,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            padding: EdgeInsets.symmetric(
                horizontal: AppTheme.spacing.sm, vertical: 3),
            child: Row(
              children: List.generate(tabs.length, (i) {
                final isActive = activeTab == i;
                return GestureDetector(
                  onTap: () => panelCtrl.switchTab(i),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing.md, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? detailTab.activeBackground
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(detailTab.radius),
                      ),
                      child: Text(tabs[i],
                          style: TextStyle(
                            fontSize: AppTheme.fontSize.sm,
                            fontWeight: isActive
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: isActive
                                ? detailTab.activeText
                                : detailTab.inactiveText,
                          )),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Tab content
          Expanded(
            child: IndexedStack(
              index: activeTab,
              children: [
                // List tab
                _listTab(context),
                // Waterfall tab
                _waterfallTab(context),
                // Dashboard tab
                const DashboardTab(),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _listTab(BuildContext context) {
    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerPainter: DividerPainters.background(
          color: AppTheme.colors(context).divider,
          highlightedColor:
              AppTheme.colors(context).primary.withAlpha(80),
        ),
        dividerThickness: 1,
      ),
      child: MultiSplitView(
        axis: Axis.vertical,
        initialAreas: [
          Area(
              min: 100,
              size: 300,
              builder: (context, area) => const FlowTable()),
          Area(
              min: 100,
              builder: (context, area) => const FlowDetailPanel()),
        ],
      ),
    );
  }

  Widget _waterfallTab(BuildContext context) {
    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerPainter: DividerPainters.background(
          color: AppTheme.colors(context).divider,
          highlightedColor:
              AppTheme.colors(context).primary.withAlpha(80),
        ),
        dividerThickness: 1,
      ),
      child: MultiSplitView(
        axis: Axis.vertical,
        initialAreas: [
          Area(
              min: 100,
              size: 300,
              builder: (ctx, area) => const WaterfallTab()),
          Area(
              min: 100,
              builder: (ctx, area) => const FlowDetailPanel()),
        ],
      ),
    );
  }
}
