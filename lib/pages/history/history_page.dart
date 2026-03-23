import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../api/api_client.dart';
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
  final _selectedIds = <int>{}.obs;
  final _isSelecting = false.obs;

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

  void _exitSelectMode() {
    _selectedIds.clear();
    _isSelecting.value = false;
  }

  void _toggleSelect(int id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) _isSelecting.value = false;
    } else {
      _selectedIds.add(id);
      _isSelecting.value = true;
    }
  }

  void _selectAll(List<TaskModel> tasks) {
    _selectedIds.assignAll(tasks.map((t) => t.id));
    _isSelecting.value = true;
  }

  Future<void> _deleteTask(BuildContext context, TaskModel task) async {
    final confirm = await _confirmDelete(context, '确定删除 Task ${task.id} 及其所有数据？');
    if (confirm != true) return;
    try {
      await Get.find<ApiClient>().deleteTask(task.id);
      Get.find<HistoryController>().loadTasks();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _batchDelete(BuildContext context) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final confirm = await _confirmDelete(context, '确定删除 ${ids.length} 个任务及其所有数据？');
    if (confirm != true) return;
    try {
      await Get.find<ApiClient>().batchDeleteTasks(ids);
      _exitSelectMode();
      Get.find<HistoryController>().loadTasks();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量删除失败: $e')),
        );
      }
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, TaskModel task) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, overlay.size.width - position.dx, 0),
      items: [
        const PopupMenuItem(value: 'open', child: Text('打开')),
        const PopupMenuItem(value: 'select', child: Text('选择')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
      ],
    ).then((value) {
      if (value == 'open') {
        Get.find<TaskController>().selectTask(task);
        Get.find<AppPageController>().showCapture();
      } else if (value == 'select') {
        _toggleSelect(task.id);
      } else if (value == 'delete') {
        _deleteTask(context, task);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final historyCtrl = Get.find<HistoryController>();
    final taskCtrl = Get.find<TaskController>();
    final pageCtrl = Get.find<AppPageController>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Toolbar
        Container(
          height: AppTheme.toolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Obx(() => Row(
            children: [
              if (_isSelecting.value) ...[
                // Select mode toolbar
                TextButton(
                  onPressed: _exitSelectMode,
                  child: const Text('取消'),
                ),
                const SizedBox(width: AppTheme.spacingSM),
                Text('已选 ${_selectedIds.length} 项',
                    style: theme.textTheme.titleSmall),
                const SizedBox(width: AppTheme.spacingSM),
                TextButton(
                  onPressed: () {
                    final tasks = historyCtrl.tasks.toList();
                    final q = _searchQuery.value;
                    final filtered = q.isEmpty ? tasks : tasks.where((t) {
                      final name = t.name.isNotEmpty ? t.name : 'Task ${t.id}';
                      return name.toLowerCase().contains(q) || '${t.id}'.contains(q);
                    }).toList();
                    _selectAll(filtered);
                  },
                  child: const Text('全选'),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _selectedIds.isEmpty ? null : () => _batchDelete(context),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('删除 (${_selectedIds.length})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
                    minimumSize: const Size(0, 28),
                  ),
                ),
              ] else ...[
                // Normal toolbar
                Text('Capture History', style: theme.textTheme.titleSmall),
                const SizedBox(width: AppTheme.spacingLG),
                Text('${historyCtrl.tasks.length} tasks',
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
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
            ],
          )),
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
                final isSelected = _selectedIds.contains(task.id);
                return _TaskRow(
                  task: task,
                  isCurrent: isCurrent,
                  isSelected: isSelected,
                  isSelecting: _isSelecting.value,
                  onTap: () {
                    if (_isSelecting.value) {
                      _toggleSelect(task.id);
                    } else {
                      taskCtrl.selectTask(task);
                      pageCtrl.showCapture();
                    }
                  },
                  onContextMenu: (pos) => _showContextMenu(context, pos, task),
                  onToggleSelect: () => _toggleSelect(task.id),
                  onDelete: () => _deleteTask(context, task),
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
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final void Function(Offset) onContextMenu;
  final VoidCallback onToggleSelect;
  final VoidCallback onDelete;

  const _TaskRow({
    required this.task,
    required this.isCurrent,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onContextMenu,
    required this.onToggleSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch((task.createdAt * 1000).toInt());
    final timeStr = '${time.year}-${_pad(time.month)}-${_pad(time.day)}  '
        '${_pad(time.hour)}:${_pad(time.minute)}';
    final totalBytes = (task.uploadBytes ?? 0) + (task.downloadBytes ?? 0);

    Color? bgColor;
    if (isSelected) {
      bgColor = theme.colorScheme.primary.withAlpha(25);
    } else if (isCurrent) {
      bgColor = theme.colorScheme.primary.withAlpha(10);
    }

    return GestureDetector(
      onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMD,
            vertical: AppTheme.spacingSM,
          ),
          color: bgColor,
          child: Row(
            children: [
              // Checkbox in select mode, status dot otherwise
              if (isSelecting)
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelect(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              else if (isCurrent)
                Container(
                  width: 6, height: 6,
                  margin: const EdgeInsets.only(right: AppTheme.spacingSM, left: 9),
                  decoration: const BoxDecoration(
                    color: AppTheme.statusConnected,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(width: 6 + AppTheme.spacingSM + 9),

              const SizedBox(width: AppTheme.spacingSM),

              // Task name
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

              // Time
              SizedBox(
                width: 140,
                child: Text(timeStr,
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
              ),
              const SizedBox(width: AppTheme.spacingLG),

              // Flows
              SizedBox(
                width: 80,
                child: Text('${task.flowCount ?? 0} flows',
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
              ),
              const SizedBox(width: AppTheme.spacingSM),

              // Upload
              SizedBox(
                width: 80,
                child: Row(children: [
                  Icon(Icons.arrow_upward, size: 12, color: theme.hintColor),
                  const SizedBox(width: 2),
                  Text(_fmtBytes(task.uploadBytes ?? 0),
                      style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
                ]),
              ),

              // Download
              SizedBox(
                width: 80,
                child: Row(children: [
                  Icon(Icons.arrow_downward, size: 12, color: theme.hintColor),
                  const SizedBox(width: 2),
                  Text(_fmtBytes(task.downloadBytes ?? 0),
                      style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
                ]),
              ),

              const Spacer(),

              // Total badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                ),
                child: Text(_fmtBytes(totalBytes),
                    style: TextStyle(fontSize: AppTheme.fontSizeXS, color: theme.hintColor)),
              ),

              const SizedBox(width: AppTheme.spacingSM),

              // More button (...)
              SizedBox(
                width: 28,
                child: IconButton(
                  icon: const Icon(Icons.more_horiz, size: 16),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox;
                    final pos = box.localToGlobal(Offset(box.size.width - 40, box.size.height / 2));
                    onContextMenu(pos);
                  },
                ),
              ),
            ],
          ),
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
