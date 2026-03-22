import 'dart:async';
import 'package:get/get.dart';
import '../api/ws_client.dart';
import '../models/flow_summary.dart';
import 'flow_controller.dart';

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

    _statusSub = ws.statusStream.listen((s) => wsStatus.value = s);
    _msgSub = ws.messages.listen((msg) {
      switch (msg.type) {
        case 'flow':
          final flow = FlowSummary.fromJson(msg.data);
          Get.find<FlowController>().addFlowFromPush(flow);
          requestCount.value++;
          break;
        case 'flow_update':
          Get.find<FlowController>().updateFlowFromPush(msg.data);
          break;
        case 'metrics':
          _updateMetrics(msg.data);
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
    // Update status bar counters from stats push
  }

  @override
  void onClose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    ws.disconnect();
    super.onClose();
  }
}
