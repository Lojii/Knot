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
  String _searchQuery = '';
  final _selectedIds = <int>{};
  bool _isEditing = false;

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

  void _enterEditMode() {
    setState(() {
      _isEditing = true;
      _selectedIds.clear();
    });
  }

  void _exitEditMode() {
    setState(() {
      _isEditing = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  List<TaskModel> _getVisibleTasks() {
    var tasks = Get.find<HistoryController>().tasks.toList();
    final q = _searchQuery;
    if (q.isNotEmpty) {
      tasks = tasks.where((t) {
        final name = t.name.isNotEmpty ? t.name : 'Task ${t.id}';
        return name.toLowerCase().contains(q) || '${t.id}'.contains(q);
      }).toList();
    }
    return tasks;
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_getVisibleTasks().map((t) => t.id));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _deleteTask(BuildContext ctx, TaskModel task) async {
    final confirm = await _confirmDelete(ctx, '确定删除 Task ${task.id} 及其所有数据？');
    if (confirm != true) return;
    try {
      await Get.find<ApiClient>().deleteTask(task.id);
      Get.find<HistoryController>().loadTasks();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  Future<void> _batchDelete(BuildContext ctx) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final confirm = await _confirmDelete(ctx, '确定删除 ${ids.length} 个任务及其所有数据？');
    if (confirm != true) return;
    try {
      await Get.find<ApiClient>().batchDeleteTasks(ids);
      _exitEditMode();
      Get.find<HistoryController>().loadTasks();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('批量删除失败: $e')));
      }
    }
  }

  Future<bool?> _confirmDelete(BuildContext ctx, String message) {
    return showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('删除确认'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext ctx, Offset position, TaskModel task) {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(position.dx, position.dy, overlay.size.width - position.dx, 0),
      items: [
        const PopupMenuItem(value: 'open', child: Text('打开')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
      ],
    ).then((value) {
      if (value == 'open') {
        Get.find<TaskController>().selectTask(task);
        Get.find<AppPageController>().showCapture();
      } else if (value == 'delete') {
        _deleteTask(ctx, task);
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
          child: Obx(() {
            final editing = _isEditing;
            final visibleTasks = _getVisibleTasks();
            final allSelected = visibleTasks.isNotEmpty &&
                visibleTasks.every((t) => _selectedIds.contains(t.id));

            return Row(
              children: [
                if (editing) ...[
                  // Edit mode: selectAll checkbox + count + cancel + delete
                  SizedBox(
                    width: 28,
                    child: Checkbox(
                      value: allSelected,
                      onChanged: (_) => allSelected ? _deselectAll() : _selectAll(),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSM),
                  Text('已选 ${_selectedIds.length} / ${visibleTasks.length}',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(width: AppTheme.spacingMD),
                  TextButton(
                    onPressed: _exitEditMode,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM),
                    ),
                    child: const Text('完成'),
                  ),
                  const Spacer(),
                  if (_selectedIds.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _batchDelete(context),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: Text('删除 (${_selectedIds.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                ] else ...[
                  // Normal mode: title + count + edit button + search
                  Text('Capture History', style: theme.textTheme.titleSmall),
                  const SizedBox(width: AppTheme.spacingSM),
                  Text('${historyCtrl.tasks.length} tasks',
                      style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
                  const SizedBox(width: AppTheme.spacingMD),
                  TextButton.icon(
                    onPressed: _enterEditMode,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('编辑'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM),
                    ),
                  ),
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
                      onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
        // Task list
        Expanded(
          child: Obx(() {
            if (historyCtrl.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            final tasks = _getVisibleTasks();
            if (tasks.isEmpty) {
              return Center(
                child: Text('No capture history', style: TextStyle(color: theme.hintColor)),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final task = tasks[i];
                final isCurrent = taskCtrl.currentTask.value?.id == task.id;
                final isSelected = _selectedIds.contains(task.id);
                final editing = _isEditing;
                return _TaskRow(
                  task: task,
                  isCurrent: isCurrent,
                  isSelected: isSelected,
                  isEditing: editing,
                  onTap: () {
                    if (editing) {
                      _toggleSelect(task.id);
                    } else {
                      taskCtrl.selectTask(task);
                      pageCtrl.showCapture();
                    }
                  },
                  onContextMenu: (pos) => _showContextMenu(context, pos, task),
                  onToggleSelect: () => _toggleSelect(task.id),
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
  final bool isEditing;
  final VoidCallback onTap;
  final void Function(Offset) onContextMenu;
  final VoidCallback onToggleSelect;

  const _TaskRow({
    required this.task,
    required this.isCurrent,
    required this.isSelected,
    required this.isEditing,
    required this.onTap,
    required this.onContextMenu,
    required this.onToggleSelect,
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
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingLG,
            vertical: AppTheme.spacingSM,
          ),
          color: bgColor,
          child: Row(
            children: [
              // Checkbox in edit mode, status dot otherwise
              if (isEditing)
                SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelect(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              else if (isCurrent)
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(right: AppTheme.spacingSM, left: 10),
                  decoration: const BoxDecoration(color: AppTheme.statusConnected, shape: BoxShape.circle),
                )
              else
                const SizedBox(width: 18 + AppTheme.spacingSM),

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
              SizedBox(width: 140, child: Text(timeStr,
                  style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor))),
              const SizedBox(width: AppTheme.spacingLG),

              // Flows
              SizedBox(width: 80, child: Text('${task.flowCount ?? 0} flows',
                  style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor))),
              const SizedBox(width: AppTheme.spacingSM),

              // Upload
              SizedBox(width: 80, child: Row(children: [
                Icon(Icons.arrow_upward, size: 12, color: theme.hintColor),
                const SizedBox(width: 2),
                Text(_fmtBytes(task.uploadBytes ?? 0),
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
              ])),

              // Download
              SizedBox(width: 80, child: Row(children: [
                Icon(Icons.arrow_downward, size: 12, color: theme.hintColor),
                const SizedBox(width: 2),
                Text(_fmtBytes(task.downloadBytes ?? 0),
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
              ])),

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

              // More button
              if (!isEditing)
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
