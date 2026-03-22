import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/live_controller.dart';
import '../../widgets/connection_indicator.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';

class GlobalBar extends StatelessWidget {
  const GlobalBar({super.key});

  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final liveCtrl = Get.find<LiveController>();
    final theme = Theme.of(context);
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

    return GestureDetector(
      // Allow dragging the window by this bar
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {},
      child: Container(
        height: 38,
        padding: EdgeInsets.only(
          // macOS: leave 78px for traffic light buttons (close/min/max)
          left: isMacOS ? 78 : 12,
          right: 12,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            // Task name
            Obx(() => Text(
              taskCtrl.currentTask.value?.name.isNotEmpty == true
                ? taskCtrl.currentTask.value!.name
                : 'Task ${taskCtrl.currentTask.value?.id ?? "-"}',
              style: theme.textTheme.titleSmall,
            )),
            const SizedBox(width: 8),
            // Connection status
            Obx(() => ConnectionIndicator(status: liveCtrl.wsStatus.value)),
            const Spacer(),
            // History button
            IconButton(
              icon: const Icon(Icons.history, size: 18),
              tooltip: 'History',
              visualDensity: VisualDensity.compact,
              onPressed: () => Get.to(() => const HistoryPage()),
            ),
            // Protocol / TCP toggle
            IconButton(
              icon: const Icon(Icons.swap_horiz, size: 18),
              tooltip: 'Protocol / TCP/UDP',
              visualDensity: VisualDensity.compact,
              onPressed: () {/* P2 */},
            ),
            // Settings
            IconButton(
              icon: const Icon(Icons.settings, size: 18),
              tooltip: 'Settings',
              visualDensity: VisualDensity.compact,
              onPressed: () => Get.to(() => const SettingsPage()),
            ),
          ],
        ),
      ),
    );
  }
}
