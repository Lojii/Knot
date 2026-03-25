import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../controllers/dashboard_controller.dart';
import '../../controllers/task_controller.dart';
import '../../theme/app_theme.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  @override
  void initState() {
    super.initState();
    final dc = Get.find<DashboardController>();
    final tid = Get.find<TaskController>().currentTask.value?.id;
    if (tid != null) dc.loadStats(tid);
  }

  @override
  Widget build(BuildContext context) {
    final dc = Get.find<DashboardController>();
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(AppTheme.spacing.lg),
      child: Obx(() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Protocol distribution + Status codes
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _card(theme, 'dashboard.protocol_dist'.tr, _protocolPie(dc, theme))),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _card(theme, 'dashboard.status_codes'.tr, _statusList(dc, theme))),
            ],
          ),
          SizedBox(height: AppTheme.spacing.md),
          // Row 2: System metrics
          Row(
            children: [
              Expanded(child: _metricCard(theme, 'dashboard.memory'.tr, '${dc.rssMB.value.toStringAsFixed(0)} MB', Icons.memory)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'dashboard.cpu'.tr, '${dc.cpuPercent.value.toStringAsFixed(1)}%', Icons.speed)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'dashboard.threads'.tr, '${dc.threadCount.value}', Icons.account_tree)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'dashboard.connections'.tr, '${dc.poolTotal.value}', Icons.cable)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'dashboard.uptime'.tr, '${dc.uptimeSeconds.value.toStringAsFixed(0)}s', Icons.timer)),
            ],
          ),
          SizedBox(height: AppTheme.spacing.md),
          // Row 3: Traffic
          Builder(builder: (context) {
            final themeColors = AppTheme.colors(context);
            return _card(theme, 'dashboard.traffic'.tr, Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _trafficStat('dashboard.upload'.tr, dc.totalUpload.value, themeColors.primary),
                  _trafficStat('dashboard.download'.tr, dc.totalDownload.value, themeColors.method['GET'] ?? themeColors.primary),
                  _trafficStat('dashboard.total'.tr, dc.totalUpload.value + dc.totalDownload.value, themeColors.method['POST'] ?? themeColors.primary),
                ],
              ),
            ));
          }),
        ],
      )),
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) => Builder(
    builder: (context) {
      final themeColors = AppTheme.colors(context);
      return Container(
        padding: EdgeInsets.all(AppTheme.spacing.md),
        decoration: BoxDecoration(
          color: themeColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius.lg),
          border: Border.all(color: themeColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: AppTheme.fontSize.md, fontWeight: FontWeight.w600, color: themeColors.textSecondary)),
            SizedBox(height: AppTheme.spacing.sm),
            child,
          ],
        ),
      );
    },
  );

  Widget _metricCard(ThemeData theme, String label, String value, IconData icon) => Builder(
    builder: (context) {
      final themeColors = AppTheme.colors(context);
      return Container(
        padding: EdgeInsets.all(AppTheme.spacing.md),
        decoration: BoxDecoration(
          color: themeColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius.lg),
          border: Border.all(color: themeColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: themeColors.textSecondary),
            SizedBox(height: AppTheme.spacing.xs),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(fontSize: AppTheme.fontSize.xs, color: themeColors.textSecondary)),
          ],
        ),
      );
    },
  );

  Widget _protocolPie(DashboardController dc, ThemeData theme) {
    final data = dc.protocols;
    if (data.isEmpty) return SizedBox(height: 120, child: Center(child: Text('empty.no_data'.tr)));

    return Builder(builder: (context) {
      final themeColors = AppTheme.colors(context);
      final sections = data.entries.where((e) => e.value > 0).map((e) => PieChartSectionData(
        value: e.value.toDouble(),
        title: '${e.key}\n${e.value}',
        titleStyle: TextStyle(fontSize: AppTheme.fontSize.xs, fontWeight: FontWeight.bold, color: Colors.white),
        color: themeColors.protocol[e.key] ?? AppTheme.methodColorOf(context, 'default'),
        radius: 50,
      )).toList();

      return SizedBox(height: 140, child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 20)));
    });
  }

  Widget _statusList(DashboardController dc, ThemeData theme) {
    final data = dc.statuses;
    if (data.isEmpty) return SizedBox(height: 120, child: Center(child: Text('empty.no_data'.tr)));
    return Column(
      children: data.entries.map((e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(e.key == '1' ? 'dashboard.completed'.tr : e.key == '2' ? 'dashboard.failed'.tr : 'Status ${e.key}',
                style: TextStyle(fontSize: AppTheme.fontSize.md)),
            const Spacer(),
            Text('${e.value}', style: TextStyle(fontSize: AppTheme.fontSize.md, fontWeight: FontWeight.bold)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _trafficStat(String label, int bytes, Color color) => Column(
    children: [
      Text(_fmt(bytes), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: TextStyle(fontSize: AppTheme.fontSize.sm)),
    ],
  );

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
