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
      padding: const EdgeInsets.all(AppTheme.spacingLG),
      child: Obx(() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Protocol distribution + Status codes
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _card(theme, 'Protocol Distribution', _protocolPie(dc, theme))),
              const SizedBox(width: AppTheme.spacingMD),
              Expanded(child: _card(theme, 'Status Codes', _statusList(dc, theme))),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMD),
          // Row 2: System metrics
          Row(
            children: [
              Expanded(child: _metricCard(theme, 'Memory', '${dc.rssMB.value.toStringAsFixed(0)} MB', Icons.memory)),
              const SizedBox(width: AppTheme.spacingMD),
              Expanded(child: _metricCard(theme, 'CPU', '${dc.cpuPercent.value.toStringAsFixed(1)}%', Icons.speed)),
              const SizedBox(width: AppTheme.spacingMD),
              Expanded(child: _metricCard(theme, 'Threads', '${dc.threadCount.value}', Icons.account_tree)),
              const SizedBox(width: AppTheme.spacingMD),
              Expanded(child: _metricCard(theme, 'Connections', '${dc.poolTotal.value}', Icons.cable)),
              const SizedBox(width: AppTheme.spacingMD),
              Expanded(child: _metricCard(theme, 'Uptime', '${dc.uptimeSeconds.value.toStringAsFixed(0)}s', Icons.timer)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMD),
          // Row 3: Traffic
          _card(theme, 'Traffic', Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _trafficStat('Upload', dc.totalUpload.value, theme.colorScheme.primary),
                _trafficStat('Download', dc.totalDownload.value, AppTheme.methodGet),
                _trafficStat('Total', dc.totalUpload.value + dc.totalDownload.value, AppTheme.methodPost),
              ],
            ),
          )),
        ],
      )),
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) => Container(
    padding: const EdgeInsets.all(AppTheme.spacingMD),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: AppTheme.fontSizeMD, fontWeight: FontWeight.bold, color: theme.hintColor)),
        const SizedBox(height: AppTheme.spacingSM),
        child,
      ],
    ),
  );

  Widget _metricCard(ThemeData theme, String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(AppTheme.spacingMD),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      children: [
        Icon(icon, size: 20, color: theme.hintColor),
        const SizedBox(height: AppTheme.spacingXS),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: AppTheme.fontSizeXS, color: theme.hintColor)),
      ],
    ),
  );

  Widget _protocolPie(DashboardController dc, ThemeData theme) {
    final data = dc.protocols;
    if (data.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No data')));

    final sections = data.entries.where((e) => e.value > 0).map((e) => PieChartSectionData(
      value: e.value.toDouble(),
      title: '${e.key}\n${e.value}',
      titleStyle: const TextStyle(fontSize: AppTheme.fontSizeXS, fontWeight: FontWeight.bold, color: Colors.white),
      color: AppTheme.protocolColors[e.key] ?? AppTheme.methodDefault,
      radius: 50,
    )).toList();

    return SizedBox(height: 140, child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 20)));
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
                style: const TextStyle(fontSize: AppTheme.fontSizeMD)),
            const Spacer(),
            Text('${e.value}', style: const TextStyle(fontSize: AppTheme.fontSizeMD, fontWeight: FontWeight.bold)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _trafficStat(String label, int bytes, Color color) => Column(
    children: [
      Text(_fmt(bytes), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: AppTheme.fontSizeSM)),
    ],
  );

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
