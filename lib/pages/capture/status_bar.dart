import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../api/ws_client.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../theme/app_theme.dart';

class CaptureStatusBar extends StatelessWidget {
  const CaptureStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final liveCtrl = Get.find<LiveController>();
    final flowCtrl = Get.find<FlowController>();

    return Container(
      height: AppTheme.sizing.statusBarHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.mode(context).toolbar.gradientStart,
            AppTheme.mode(context).toolbar.gradientEnd,
          ],
        ),
        border: Border(
          top: BorderSide(
            color: AppTheme.colors(context).divider,
            width: AppTheme.mode(context).toolbar.borderWidth,
          ),
        ),
      ),
      child: Obx(() {
        final wsStatus = liveCtrl.wsStatus.value;
        final themeColors = AppTheme.colors(context);
        final dotColor = switch (wsStatus) {
          WsStatus.connected => themeColors.statusConnected,
          WsStatus.connecting => themeColors.statusConnecting,
          WsStatus.disconnected => themeColors.statusDisconnected,
        };
        return Row(
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            _item(context, 'Listening on :${liveCtrl.listenPort.value}'),
            _sep(context),
            _item(context, 'Mem: ${liveCtrl.memoryMB.value.toStringAsFixed(0)} MB'),
            _sep(context),
            _item(context, 'CPU: ${liveCtrl.cpuPercent.value.toStringAsFixed(1)}%'),
            _sep(context),
            Text('\u2193 ${_formatSpeed(liveCtrl.downloadSpeed.value)}', style: TextStyle(color: themeColors.statusConnected, fontSize: AppTheme.fontSize.sm)),
            const SizedBox(width: 8),
            Text('\u2191 ${_formatSpeed(liveCtrl.uploadSpeed.value)}', style: TextStyle(color: themeColors.primary, fontSize: AppTheme.fontSize.sm)),
            _sep(context),
            _item(context, 'Connections: ${liveCtrl.connectionCount.value}'),
            _sep(context),
            _item(context, 'TCP: ${liveCtrl.tcpChannelCount.value}'),
            const Spacer(),
            _item(context, '${flowCtrl.total.value} requests'),
          ],
        );
      }),
    );
  }

  Widget _item(BuildContext context, String text) =>
      Text(text, style: TextStyle(fontSize: AppTheme.fontSize.sm));

  Widget _sep(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
    child: Text('·', style: TextStyle(
      fontSize: AppTheme.fontSize.sm,
      color: AppTheme.colors(context).textSecondary,
    )),
  );

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }
}
