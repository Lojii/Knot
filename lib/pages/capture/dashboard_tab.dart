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
              Expanded(child: _card(theme, 'Protocol Distribution', _protocolPie(dc, theme))),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _card(theme, 'Status Codes', _statusList(dc, theme))),
            ],
          ),
          SizedBox(height: AppTheme.spacing.md),
          // Row 2: System metrics
          Row(
            children: [
              Expanded(child: _metricCard(theme, 'Memory', '${dc.rssMB.value.toStringAsFixed(0)} MB', Icons.memory)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'CPU', '${dc.cpuPercent.value.toStringAsFixed(1)}%', Icons.speed)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'Threads', '${dc.threadCount.value}', Icons.account_tree)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'Connections', '${dc.poolTotal.value}', Icons.cable)),
              SizedBox(width: AppTheme.spacing.md),
              Expanded(child: _metricCard(theme, 'Uptime', '${dc.uptimeSeconds.value.toStringAsFixed(0)}s', Icons.timer)),
            ],
          ),
          SizedBox(height: AppTheme.spacing.md),
          // Row 3: Traffic
          _card(theme, 'Traffic', Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _trafficStat('Upload', dc.totalUpload.value, theme.colorScheme.primary),
                _trafficStat('Download', dc.totalDownload.value, AppTheme.methodColor('GET')),
                _trafficStat('Total', dc.totalUpload.value + dc.totalDownload.value, AppTheme.methodColor('POST')),
              ],
            ),
          )),
        ],
      )),
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) => Container(
    padding: EdgeInsets.all(AppTheme.spacing.md),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radius.lg),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: AppTheme.fontSize.md, fontWeight: FontWeight.bold, color: theme.hintColor)),
        SizedBox(height: AppTheme.spacing.sm),
        child,
      ],
    ),
  );

  Widget _metricCard(ThemeData theme, String label, String value, IconData icon) => Container(
    padding: EdgeInsets.all(AppTheme.spacing.md),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radius.lg),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      children: [
        Icon(icon, size: 20, color: theme.hintColor),
        SizedBox(height: AppTheme.spacing.xs),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: AppTheme.fontSize.xs, color: theme.hintColor)),
      ],
    ),
  );

  Widget _protocolPie(DashboardController dc, ThemeData theme) {
    final data = dc.protocols;
    if (data.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No data')));

    return Builder(builder: (context) {
      final themeColors = AppTheme.colors(context);
      final sections = data.entries.where((e) => e.value > 0).map((e) => PieChartSectionData(
        value: e.value.toDouble(),
        title: '${e.key}\n${e.value}',
        titleStyle: TextStyle(fontSize: AppTheme.fontSize.xs, fontWeight: FontWeight.bold, color: Colors.white),
        color: themeColors.protocol[e.key] ?? AppTheme.methodColor('default'),
        radius: 50,
      )).toList();

      return SizedBox(height: 140, child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 20)));
    });
  }

  Widget _statusList(DashboardController dc, ThemeData theme) {
    final data = dc.statuses;
    if (data.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No data')));
    return Column(
      children: data.entries.map((e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(e.key == '1' ? 'Completed' : e.key == '2' ? 'Failed' : 'Status ${e.key}',
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
