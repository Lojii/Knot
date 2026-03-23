import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/history_controller.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/page_controller.dart';
import '../../models/task_model.dart';
import '../../theme/app_theme.dart';

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  final _searchController = TextEditingController();
  final _searchQuery = ''.obs;

  @override
  void initState() {
    super.initState();
    Get.find<HistoryController>().loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyCtrl = Get.find<HistoryController>();
    final taskCtrl = Get.find<TaskController>();
    final pageCtrl = Get.find<AppPageController>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Search + stats bar
        Container(
          height: AppTheme.toolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Text('Capture History', style: theme.textTheme.titleSmall),
              const SizedBox(width: AppTheme.spacingLG),
              Obx(() => Text(
                '${historyCtrl.tasks.length} tasks',
                style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor),
              )),
              const Spacer(),
              SizedBox(
                width: 200,
                height: 28,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tasks...',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMD)),
                  ),
                  style: const TextStyle(fontSize: AppTheme.fontSizeSM),
                  onChanged: (v) => _searchQuery.value = v.toLowerCase(),
                ),
              ),
            ],
          ),
        ),
        // Task list
        Expanded(
          child: Obx(() {
            if (historyCtrl.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            var tasks = historyCtrl.tasks.toList();
            if (tasks.isEmpty) {
              return Center(
                child: Text('No capture history', style: TextStyle(color: theme.hintColor)),
              );
            }
            // Filter by search
            final q = _searchQuery.value;
            if (q.isNotEmpty) {
              tasks = tasks.where((t) {
                final name = t.name.isNotEmpty ? t.name : 'Task ${t.id}';
                return name.toLowerCase().contains(q) || '${t.id}'.contains(q);
              }).toList();
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppTheme.spacingMD),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final task = tasks[i];
                final isCurrent = taskCtrl.currentTask.value?.id == task.id;
                return _TaskRow(
                  task: task,
                  isCurrent: isCurrent,
                  onTap: () {
                    taskCtrl.selectTask(task);
                    pageCtrl.showCapture();
                  },
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskModel task;
  final bool isCurrent;
  final VoidCallback onTap;

  const _TaskRow({required this.task, required this.isCurrent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch((task.createdAt * 1000).toInt());
    final timeStr = '${time.year}-${_pad(time.month)}-${_pad(time.day)}  '
        '${_pad(time.hour)}:${_pad(time.minute)}';

    final totalBytes = (task.uploadBytes ?? 0) + (task.downloadBytes ?? 0);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMD,
          vertical: AppTheme.spacingSM,
        ),
        color: isCurrent ? theme.colorScheme.primary.withAlpha(15) : null,
        child: Row(
          children: [
            // Status indicator
            if (isCurrent)
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: AppTheme.spacingSM),
                decoration: const BoxDecoration(
                  color: AppTheme.statusConnected,
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(width: 6 + AppTheme.spacingSM),

            // Task name/ID
            SizedBox(
              width: 120,
              child: Text(
                task.name.isNotEmpty ? task.name : 'Task ${task.id}',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeMD,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: AppTheme.spacingLG),

            // Created time
            SizedBox(
              width: 140,
              child: Text(timeStr,
                style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
            ),

            const SizedBox(width: AppTheme.spacingLG),

            // Flow count
            SizedBox(
              width: 80,
              child: Text(
                '${task.flowCount ?? 0} flows',
                style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor),
              ),
            ),

            const SizedBox(width: AppTheme.spacingSM),

            // Upload
            SizedBox(
              width: 80,
              child: Row(
                children: [
                  Icon(Icons.arrow_upward, size: 12, color: theme.hintColor),
                  const SizedBox(width: 2),
                  Text(_fmtBytes(task.uploadBytes ?? 0),
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
                ],
              ),
            ),

            // Download
            SizedBox(
              width: 80,
              child: Row(
                children: [
                  Icon(Icons.arrow_downward, size: 12, color: theme.hintColor),
                  const SizedBox(width: 2),
                  Text(_fmtBytes(task.downloadBytes ?? 0),
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
                ],
              ),
            ),

            const Spacer(),

            // Total size badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: Text(_fmtBytes(totalBytes),
                style: TextStyle(fontSize: AppTheme.fontSizeXS, color: theme.hintColor)),
            ),
          ],
        ),
      ),
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}
