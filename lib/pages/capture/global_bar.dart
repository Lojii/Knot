import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/live_controller.dart';
import '../../widgets/connection_indicator.dart';

class GlobalBar extends StatelessWidget {
  const GlobalBar({super.key});

  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final liveCtrl = Get.find<LiveController>();
    final theme = Theme.of(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 70), // Space for macOS traffic lights
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
            onPressed: () {/* P2 */},
          ),
          // Protocol / TCP toggle
          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 18),
            tooltip: 'Protocol / TCP/UDP',
            onPressed: () {/* P2 */},
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            tooltip: 'Settings',
            onPressed: () {/* P2 */},
          ),
        ],
      ),
    );
  }
}
