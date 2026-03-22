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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Tab bar
        Container(
          height: 32,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
            tabs: const [
              Tab(text: 'List', height: 32),
              Tab(text: 'Waterfall', height: 32),
              Tab(text: 'Dashboard', height: 32),
            ],
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
