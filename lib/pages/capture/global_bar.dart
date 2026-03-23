import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/page_controller.dart';
import '../../widgets/connection_indicator.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_page.dart';

class GlobalBar extends StatelessWidget {
  const GlobalBar({super.key});

  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final liveCtrl = Get.find<LiveController>();
    final pageCtrl = Get.find<AppPageController>();
    final theme = Theme.of(context);
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {},
      child: Container(
        height: AppTheme.globalBarHeight,
        padding: EdgeInsets.only(
          left: isMacOS ? AppTheme.macOSTrafficLightWidth : AppTheme.spacingMD,
          right: AppTheme.spacingMD,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Obx(() => Row(
          children: [
            // === Left group: Task name + connection + TCP toggle ===
            // Task name
            Text(
              taskCtrl.currentTask.value?.name.isNotEmpty == true
                ? taskCtrl.currentTask.value!.name
                : 'Task ${taskCtrl.currentTask.value?.id ?? "-"}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: AppTheme.spacingSM),
            ConnectionIndicator(status: liveCtrl.wsStatus.value),
            const SizedBox(width: AppTheme.spacingSM),
            // Protocol / TCP toggle — hidden when on history page
            if (pageCtrl.isCapture)
              IconButton(
                icon: const Icon(Icons.swap_horiz, size: 18),
                tooltip: 'Protocol / TCP/UDP',
                visualDensity: VisualDensity.compact,
                onPressed: () {/* P2 */},
              ),

            const Spacer(),

            // === Right group: History + Settings ===
            IconButton(
              icon: Icon(
                pageCtrl.isHistory ? Icons.list_alt : Icons.history,
                size: 18,
              ),
              tooltip: pageCtrl.isHistory ? 'Back to Capture' : 'History',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (pageCtrl.isHistory) {
                  pageCtrl.showCapture();
                } else {
                  pageCtrl.showHistory();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings, size: 18),
              tooltip: 'Settings',
              visualDensity: VisualDensity.compact,
              onPressed: () => Get.to(() => const SettingsPage()),
            ),
          ],
        )),
      ),
    );
  }
}
