import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../api/ws_client.dart';
import '../models/flow_summary.dart';
import '../pages/tools/breakpoint_dialog.dart';
import 'task_scope.dart';

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
  final listenPort = 8034.obs;
  final cpuPercent = 0.0.obs;
  final downloadSpeed = 0.obs;
  final uploadSpeed = 0.obs;
  final tcpChannelCount = 0.obs;

  // Speed calculation tracking
  int _lastDownloadBytes = 0;
  int _lastUploadBytes = 0;
  DateTime _lastSpeedUpdate = DateTime.now();

  void connectToTask(int taskId) {
    _msgSub?.cancel();
    _statusSub?.cancel();

    // Reset per-task counters
    requestCount.value = 0;
    uploadBytes.value = 0;
    downloadBytes.value = 0;
    downloadSpeed.value = 0;
    uploadSpeed.value = 0;
    _lastDownloadBytes = 0;
    _lastUploadBytes = 0;
    _lastSpeedUpdate = DateTime.now();

    ws.connect(taskId: taskId);

    _statusSub = ws.statusStream.listen((s) {
      final wasDisconnected = wsStatus.value != WsStatus.connected;
      wsStatus.value = s;
      // On reconnect: reload flow list (may have missed events during disconnect)
      if (s == WsStatus.connected && wasDisconnected) {
        TaskScope.flowCtrl(taskId).setTaskId(taskId);
      }
    });
    _msgSub = ws.messages.listen((msg) {
      switch (msg.type) {
        case 'flow':
          final flow = FlowSummary.fromJson(msg.data);
          TaskScope.flowCtrl(taskId).addFlowFromPush(flow);
          requestCount.value++;
          final up = msg.data['uploadBytes'] as int? ?? 0;
          final down = msg.data['downloadBytes'] as int? ?? 0;
          uploadBytes.value += up;
          downloadBytes.value += down;
          TaskScope.dashCtrl(taskId).addTrafficPoint(up + down);
          break;
        case 'flow_update':
          TaskScope.flowCtrl(taskId).updateFlowFromPush(msg.data);
          break;
        case 'metrics':
          _updateMetrics(msg.data);
          TaskScope.dashCtrl(taskId).updateFromMetrics(msg.data);
          break;
        case 'stats':
          _updateStats(msg.data);
          break;
        case 'breakpoint_hit':
          _showBreakpointDialog(msg.data);
          break;
      }
    });
  }

  void _showBreakpointDialog(Map<String, dynamic> data) {
    final context = Get.context;
    if (context == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BreakpointHitDialog(data: data),
    );
  }

  void _updateMetrics(Map<String, dynamic> data) {
    final mem = data['memory'] as Map<String, dynamic>?;
    if (mem != null) memoryMB.value = (mem['rss_mb'] as num?)?.toDouble() ?? 0;
    final cpu = data['cpu'] as Map<String, dynamic>?;
    if (cpu != null) cpuPercent.value = (cpu['percent'] as num?)?.toDouble() ?? 0;
    final conn = data['connections'] as Map<String, dynamic>?;
    if (conn != null) {
      connectionCount.value = (conn['pool_total'] as int?) ?? 0;
      tcpChannelCount.value = (conn['tcp_channels'] as int?) ?? 0;
    }
    _updateSpeed();
  }

  void _updateSpeed() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastSpeedUpdate).inMilliseconds;
    if (elapsed > 0) {
      downloadSpeed.value = ((downloadBytes.value - _lastDownloadBytes) * 1000 ~/ elapsed);
      uploadSpeed.value = ((uploadBytes.value - _lastUploadBytes) * 1000 ~/ elapsed);
      _lastDownloadBytes = downloadBytes.value;
      _lastUploadBytes = uploadBytes.value;
      _lastSpeedUpdate = now;
    }
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
