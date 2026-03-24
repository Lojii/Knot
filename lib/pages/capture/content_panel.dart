import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';
import '../../theme/app_theme.dart';
import 'flow_table.dart';
import 'flow_detail_panel.dart';
import 'waterfall_tab.dart';
import 'dashboard_tab.dart';

class ContentPanel extends StatefulWidget {
  const ContentPanel({super.key});
  @override
  State<ContentPanel> createState() => _ContentPanelState();
}

class _ContentPanelState extends State<ContentPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = ['List', 'Waterfall', 'Dashboard'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailTab = AppTheme.mode(context).detailTab;

    return Column(
      children: [
        // Custom segmented-control tab bar
        Container(
          height: 32,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing.sm,
            vertical: 3,
          ),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final isActive = _tabController.index == i;
              return GestureDetector(
                onTap: () {
                  _tabController.animateTo(i);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.lg,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? detailTab.activeBackground
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(detailTab.radius),
                  ),
                  child: Text(
                    _tabs[i],
                    style: TextStyle(
                      fontSize: AppTheme.fontSize.sm,
                      fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                      color: isActive
                          ? detailTab.activeText
                          : detailTab.inactiveText,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // List tab: split into table + detail
              MultiSplitView(
                axis: Axis.vertical,
                initialAreas: [
                  Area(
                    min: 100,
                    size: 300,
                    builder: (context, area) => const FlowTable(),
                  ),
                  Area(
                    min: 100,
                    builder: (context, area) => const FlowDetailPanel(),
                  ),
                ],
              ),
              // Waterfall tab
              const WaterfallTab(),
              // Dashboard tab
              const DashboardTab(),
            ],
          ),
        ),
      ],
    );
  }
}
