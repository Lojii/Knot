import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../theme/app_theme.dart';

class CaptureStatusBar extends StatelessWidget {
  const CaptureStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final liveCtrl = Get.find<LiveController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: AppTheme.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() => Row(
        children: [
          _item(context, '${flowCtrl.total.value} requests'),
          _sep(context),
          _item(context, 'Up ${_formatBytes(liveCtrl.uploadBytes.value)}'),
          _item(context, ' Down ${_formatBytes(liveCtrl.downloadBytes.value)}'),
          _sep(context),
          _item(context, 'Mem ${liveCtrl.memoryMB.value.toStringAsFixed(0)} MB'),
          _sep(context),
          _item(context, '${liveCtrl.connectionCount.value} conn'),
        ],
      )),
    );
  }

  Widget _item(BuildContext context, String text) =>
      Text(text, style: const TextStyle(fontSize: AppTheme.fontSizeSM));

  Widget _sep(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM),
    child: Text('|', style: TextStyle(
      fontSize: AppTheme.fontSizeSM,
      color: Theme.of(context).hintColor,
    )),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
