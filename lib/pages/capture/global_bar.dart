import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/page_controller.dart';
import '../../widgets/connection_indicator.dart';
import '../../theme/app_theme.dart';

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
        child: Obx(() {
          return Row(
            children: [
              // Home button — always visible
              IconButton(
                icon: Icon(Icons.home_outlined, size: 18,
                  color: pageCtrl.isCapture ? theme.hintColor : theme.colorScheme.primary),
                tooltip: 'Home',
                visualDensity: VisualDensity.compact,
                onPressed: () => pageCtrl.showCapture(),
              ),
              const SizedBox(width: AppTheme.spacingXS),

              // === Left group: Task name + connection + TCP toggle ===
              Text(
                taskCtrl.currentTask.value?.name.isNotEmpty == true
                  ? taskCtrl.currentTask.value!.name
                  : 'Task ${taskCtrl.currentTask.value?.id ?? "-"}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: AppTheme.spacingSM),
              ConnectionIndicator(status: liveCtrl.wsStatus.value),
              const SizedBox(width: AppTheme.spacingSM),
              // Protocol / TCP toggle — only on capture page
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
                icon: const Icon(Icons.history, size: 18),
                tooltip: 'History',
                visualDensity: VisualDensity.compact,
                onPressed: () => pageCtrl.isHistory
                    ? pageCtrl.showCapture()
                    : pageCtrl.showHistory(),
              ),
              IconButton(
                icon: const Icon(Icons.settings, size: 18),
                tooltip: 'Settings',
                visualDensity: VisualDensity.compact,
                onPressed: () => pageCtrl.isSettings
                    ? pageCtrl.showCapture()
                    : pageCtrl.showSettings(),
              ),
            ],
          );
        }),
      ),
    );
  }
}
