import 'package:get/get.dart';
import '../api/api_client.dart';

class DashboardController extends GetxController {
  final ApiClient api;
  DashboardController(this.api);

  // Protocol distribution
  final protocols = <String, int>{}.obs;
  // Status code distribution
  final statuses = <String, int>{}.obs;
  // Total bytes
  final totalUpload = 0.obs;
  final totalDownload = 0.obs;

  // Real-time metrics from WebSocket
  final rssMB = 0.0.obs;
  final cpuPercent = 0.0.obs;
  final threadCount = 0.obs;
  final poolTotal = 0.obs;
  final uptimeSeconds = 0.0.obs;

  // Traffic history for line chart (last 60 data points)
  final trafficHistory = <({double time, int bytes})>[].obs;

  Future<void> loadStats(int taskId) async {
    try {
      final stats = await api.getFlowStats(taskId);
      final p = stats['protocols'] as Map<String, dynamic>? ?? {};
      protocols.value = p.map((k, v) => MapEntry(k, (v as int?) ?? 0));

      final s = stats['statuses'] as Map<String, dynamic>? ?? {};
      statuses.value = s.map((k, v) => MapEntry(k, (v as int?) ?? 0));

      totalUpload.value = (stats['totalUploadBytes'] as int?) ?? 0;
      totalDownload.value = (stats['totalDownloadBytes'] as int?) ?? 0;
    } catch (_) {}
  }

  void updateFromMetrics(Map<String, dynamic> data) {
    final mem = data['memory'] as Map<String, dynamic>?;
    if (mem != null) {
      rssMB.value = (mem['rss_mb'] as num?)?.toDouble() ?? 0;
    }
    final cpu = data['cpu'] as Map<String, dynamic>?;
    if (cpu != null) {
      cpuPercent.value = (cpu['usage_percent'] as num?)?.toDouble() ?? 0;
      threadCount.value = (cpu['thread_count'] as int?) ?? 0;
    }
    final conn = data['connections'] as Map<String, dynamic>?;
    if (conn != null) {
      poolTotal.value = (conn['pool_total'] as int?) ?? 0;
    }
    final totals = data['totals'] as Map<String, dynamic>?;
    if (totals != null) {
      uptimeSeconds.value = (totals['uptime_s'] as num?)?.toDouble() ?? 0;
    }
  }

  void addTrafficPoint(int bytes) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    trafficHistory.add((time: now, bytes: bytes));
    // Keep last 60 points
    if (trafficHistory.length > 60) {
      trafficHistory.removeAt(0);
    }
  }
}
