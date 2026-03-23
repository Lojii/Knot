import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/tools_controller.dart';
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

              // === Right group: Compose + Tools + History + Settings ===
              IconButton(
                icon: const Icon(Icons.edit_note, size: 18),
                tooltip: 'Compose',
                visualDensity: VisualDensity.compact,
                onPressed: () => pageCtrl.isCompose
                    ? pageCtrl.showCapture()
                    : pageCtrl.showCompose(),
              ),
              _ToolsMenuButton(pageCtrl: pageCtrl),
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

class _ToolsMenuButton extends StatelessWidget {
  final AppPageController pageCtrl;
  const _ToolsMenuButton({required this.pageCtrl});

  @override
  Widget build(BuildContext context) {
    final toolsCtrl = Get.find<ToolsController>();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.build_outlined, size: 18),
      tooltip: 'Tools',
      padding: EdgeInsets.zero,
      splashRadius: 16,
      offset: const Offset(0, AppTheme.globalBarHeight),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'mapRemote',
          child: Row(
            children: [
              Icon(Icons.alt_route, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Map Remote'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'allowBlock',
          child: Row(
            children: [
              Icon(Icons.filter_list, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Allow/Block List'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'noCaching',
          child: Obx(() => Row(
            children: [
              Icon(
                toolsCtrl.noCachingEnabled.value
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 16,
              ),
              const SizedBox(width: AppTheme.spacingSM),
              const Text('No Caching'),
            ],
          )),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'mapRemote':
            pageCtrl.isMapRemote
                ? pageCtrl.showCapture()
                : pageCtrl.showMapRemote();
          case 'allowBlock':
            pageCtrl.isAllowBlock
                ? pageCtrl.showCapture()
                : pageCtrl.showAllowBlock();
          case 'noCaching':
            toolsCtrl.toggleNoCaching();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  toolsCtrl.noCachingEnabled.value
                      ? 'No Caching enabled'
                      : 'No Caching disabled',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
        }
      },
    );
  }
}
