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
        final wsClient = Get.find<WsClient>();
        final wsUrl = wsClient.baseUrl;
        final statusLabel = switch (wsStatus) {
          WsStatus.connected => 'status.connected'.tr,
          WsStatus.connecting => 'status.connecting'.tr,
          WsStatus.disconnected => 'status.disconnected'.tr,
        };

        return Row(
          children: [
            _item(context, 'status.requests'.trParams({'count': '${flowCtrl.total.value}'})),
            _sep(context),
            _item(context, 'status.up'.trParams({'size': _formatBytes(liveCtrl.uploadBytes.value)})),
            _item(context, 'status.down'.trParams({'size': _formatBytes(liveCtrl.downloadBytes.value)})),
            _sep(context),
            _item(context, 'status.mem'.trParams({'size': liveCtrl.memoryMB.value.toStringAsFixed(0)})),
            _sep(context),
            _item(context, 'status.conn'.trParams({'count': '${liveCtrl.connectionCount.value}'})),
            const Spacer(),
            Tooltip(
              message: '$statusLabel\n$wsUrl',
              child: Container(
                width: AppTheme.sizing.connectionDotSize,
                height: AppTheme.sizing.connectionDotSize,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ),
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
