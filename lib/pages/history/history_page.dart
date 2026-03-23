import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/history_controller.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/page_controller.dart';
import '../../models/task_model.dart';
import '../../theme/app_theme.dart';

/// Embeddable history panel — displayed inside the main layout
/// when the user clicks the History button in GlobalBar.
/// No Scaffold or AppBar — GlobalBar stays on top.
class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  @override
  void initState() {
    super.initState();
    Get.find<HistoryController>().loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    final historyCtrl = Get.find<HistoryController>();
    final taskCtrl = Get.find<TaskController>();
    final pageCtrl = Get.find<AppPageController>();
    final theme = Theme.of(context);

    return Obx(() {
      if (historyCtrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      final tasks = historyCtrl.tasks;
      if (tasks.isEmpty) {
        return Center(
          child: Text('No capture history', style: TextStyle(color: theme.hintColor)),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSM),
        itemBuilder: (ctx, i) {
          final task = tasks[i];
          final isCurrent = taskCtrl.currentTask.value?.id == task.id;
          return _TaskCard(task: task, isCurrent: isCurrent, onTap: () {
            taskCtrl.selectTask(task);
            pageCtrl.showCapture(); // Switch back to capture view
          });
        },
      );
    });
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final bool isCurrent;
  final VoidCallback onTap;

  const _TaskCard({required this.task, required this.isCurrent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch((task.createdAt * 1000).toInt());
    final timeStr = '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingLG),
        decoration: BoxDecoration(
          color: isCurrent ? theme.colorScheme.primary.withAlpha(20) : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(color: isCurrent ? theme.colorScheme.primary : theme.dividerColor),
        ),
        child: Row(
          children: [
            if (isCurrent) ...[
              const Icon(Icons.circle, size: 8, color: AppTheme.statusConnected),
              const SizedBox(width: AppTheme.spacingSM),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name.isNotEmpty ? task.name : 'Task ${task.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(timeStr, style: TextStyle(fontSize: AppTheme.fontSizeMD, color: theme.hintColor)),
                ],
              ),
            ),
            if (task.flowCount != null)
              _badge('${task.flowCount} flows', theme),
            if (task.downloadBytes != null) ...[
              const SizedBox(width: AppTheme.spacingSM),
              _badge(_fmt(task.downloadBytes!), theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, ThemeData theme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM, vertical: 2),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
    ),
    child: Text(text, style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
  );

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
