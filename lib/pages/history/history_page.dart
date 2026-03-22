import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/history_controller.dart';
import '../../controllers/task_controller.dart';
import '../../models/task_model.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final historyCtrl = Get.find<HistoryController>();
    final taskCtrl = Get.find<TaskController>();

    historyCtrl.loadTasks();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture History'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: Obx(() {
        if (historyCtrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final tasks = historyCtrl.tasks;
        if (tasks.isEmpty) {
          return const Center(child: Text('No capture history'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final task = tasks[i];
            final isCurrent = taskCtrl.currentTask.value?.id == task.id;
            return _TaskCard(task: task, isCurrent: isCurrent, onTap: () {
              taskCtrl.selectTask(task);
              Get.back();
            });
          },
        );
      }),
    );
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent ? theme.colorScheme.primary.withValues(alpha: 0.08) : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isCurrent ? theme.colorScheme.primary : theme.dividerColor),
        ),
        child: Row(
          children: [
            if (isCurrent) ...[
              const Icon(Icons.circle, size: 8, color: Colors.red),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name.isNotEmpty ? task.name : 'Task ${task.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(timeStr, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                ],
              ),
            ),
            if (task.flowCount != null)
              _badge('${task.flowCount} flows', theme),
            if (task.downloadBytes != null) ...[
              const SizedBox(width: 8),
              _badge(_fmt(task.downloadBytes!), theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, ThemeData theme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: theme.hintColor)),
  );

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
