import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../controllers/dashboard_controller.dart';
import '../../controllers/task_controller.dart';

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
      padding: const EdgeInsets.all(16),
      child: Obx(() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Protocol distribution + Status codes
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _card(theme, 'Protocol Distribution', _protocolPie(dc, theme))),
              const SizedBox(width: 12),
              Expanded(child: _card(theme, 'Status Codes', _statusList(dc, theme))),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: System metrics
          Row(
            children: [
              Expanded(child: _metricCard(theme, 'Memory', '${dc.rssMB.value.toStringAsFixed(0)} MB', Icons.memory)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'CPU', '${dc.cpuPercent.value.toStringAsFixed(1)}%', Icons.speed)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'Threads', '${dc.threadCount.value}', Icons.account_tree)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'Connections', '${dc.poolTotal.value}', Icons.cable)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'Uptime', '${dc.uptimeSeconds.value.toStringAsFixed(0)}s', Icons.timer)),
            ],
          ),
          const SizedBox(height: 12),
          // Row 3: Traffic
          _card(theme, 'Traffic', Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _trafficStat('Upload', dc.totalUpload.value, Colors.blue),
                _trafficStat('Download', dc.totalDownload.value, Colors.green),
                _trafficStat('Total', dc.totalUpload.value + dc.totalDownload.value, Colors.orange),
              ],
            ),
          )),
        ],
      )),
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.hintColor)),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget _metricCard(ThemeData theme, String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      children: [
        Icon(icon, size: 20, color: theme.hintColor),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 10, color: theme.hintColor)),
      ],
    ),
  );

  Widget _protocolPie(DashboardController dc, ThemeData theme) {
    final data = dc.protocols;
    if (data.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No data')));

    final colors = <String, Color>{
      'HTTP': Colors.blue,
      'HTTPS': Colors.green,
      'H2': Colors.orange,
      'WS': Colors.purple,
      'WSS': Colors.red,
    };
    final sections = data.entries.where((e) => e.value > 0).map((e) => PieChartSectionData(
      value: e.value.toDouble(),
      title: '${e.key}\n${e.value}',
      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      color: colors[e.key] ?? Colors.grey,
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
                style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Text('${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _trafficStat(String label, int bytes, Color color) => Column(
    children: [
      Text(_fmt(bytes), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
