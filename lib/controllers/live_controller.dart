import 'dart:async';
import 'package:get/get.dart';
import '../api/ws_client.dart';
import '../models/flow_summary.dart';
import 'flow_controller.dart';
import 'dashboard_controller.dart';

class LiveController extends GetxController {
  final WsClient ws;
  LiveController(this.ws);

  final wsStatus = WsStatus.disconnected.obs;
  StreamSubscription? _msgSub;
  StreamSubscription? _statusSub;

  // Metrics for status bar
  final requestCount = 0.obs;
  final uploadBytes = 0.obs;
  final downloadBytes = 0.obs;
  final memoryMB = 0.0.obs;
  final connectionCount = 0.obs;

  void connectToTask(int taskId) {
    _msgSub?.cancel();
    _statusSub?.cancel();

    ws.connect(taskId: taskId);

    _statusSub = ws.statusStream.listen((s) {
      final wasDisconnected = wsStatus.value != WsStatus.connected;
      wsStatus.value = s;
      // On reconnect: reload flow list (may have missed events during disconnect)
      if (s == WsStatus.connected && wasDisconnected) {
        Get.find<FlowController>().reloadFromFirstPage();
      }
    });
    _msgSub = ws.messages.listen((msg) {
      switch (msg.type) {
        case 'flow':
          final flow = FlowSummary.fromJson(msg.data);
          Get.find<FlowController>().addFlowFromPush(flow);
          requestCount.value++;
          final up = msg.data['uploadBytes'] as int? ?? 0;
          final down = msg.data['downloadBytes'] as int? ?? 0;
          uploadBytes.value += up;
          downloadBytes.value += down;
          Get.find<DashboardController>().addTrafficPoint(up + down);
          break;
        case 'flow_update':
          Get.find<FlowController>().updateFlowFromPush(msg.data);
          break;
        case 'metrics':
          _updateMetrics(msg.data);
          Get.find<DashboardController>().updateFromMetrics(msg.data);
          break;
        case 'stats':
          _updateStats(msg.data);
          break;
      }
    });
  }

  void _updateMetrics(Map<String, dynamic> data) {
    final mem = data['memory'] as Map<String, dynamic>?;
    if (mem != null) memoryMB.value = (mem['rss_mb'] as num?)?.toDouble() ?? 0;
    final conn = data['connections'] as Map<String, dynamic>?;
    if (conn != null) connectionCount.value = (conn['pool_total'] as int?) ?? 0;
  }

  void _updateStats(Map<String, dynamic> data) {
    if (data.containsKey('totalUploadBytes')) {
      uploadBytes.value = (data['totalUploadBytes'] as int?) ?? uploadBytes.value;
    }
    if (data.containsKey('totalDownloadBytes')) {
      downloadBytes.value = (data['totalDownloadBytes'] as int?) ?? downloadBytes.value;
    }
  }

  @override
  void onClose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    ws.disconnect();
    super.onClose();
  }
}
