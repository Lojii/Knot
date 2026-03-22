import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/flow_controller.dart';

class CaptureStatusBar extends StatelessWidget {
  const CaptureStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final liveCtrl = Get.find<LiveController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() => Row(
        children: [
          _item('${flowCtrl.total.value} requests'),
          _sep(),
          _item('Up ${_formatBytes(liveCtrl.uploadBytes.value)}'),
          _item(' Down ${_formatBytes(liveCtrl.downloadBytes.value)}'),
          _sep(),
          _item('Mem ${liveCtrl.memoryMB.value.toStringAsFixed(0)} MB'),
          _sep(),
          _item('${liveCtrl.connectionCount.value} conn'),
        ],
      )),
    );
  }

  Widget _item(String text) => Text(text, style: const TextStyle(fontSize: 11));
  Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Text('|', style: TextStyle(fontSize: 11, color: Colors.grey)),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
