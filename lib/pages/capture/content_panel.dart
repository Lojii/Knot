import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multi_split_view/multi_split_view.dart';
import '../../controllers/task_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_tab_bar.dart';
import '../../widgets/common/empty_state.dart';
import 'flow_table.dart';
import 'flow_detail_panel.dart';
import 'waterfall_tab.dart';
import 'dashboard_tab.dart';

class ContentPanel extends StatelessWidget {
  const ContentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = ['tab.list'.tr, 'tab.waterfall'.tr, 'tab.dashboard'.tr];

    return Obx(() {
      final filterCtrl = TaskScope.filter;
      if (filterCtrl.isTcpMode) {
        return EmptyState(
          icon: Icons.dns_outlined,
          title: 'tab.tcp_coming_soon'.tr,
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppTabBar(
                tabs: tabs,
                activeIndex: activeTab,
                onChanged: panelCtrl.switchTab,
              ),
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
