import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../api/api_client.dart';
import '../../controllers/history_controller.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/tab_controller.dart';
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
  bool _isDeleting = false;

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
    final confirm = await _confirmDelete(ctx, 'history.confirm_delete_one'.trParams({'id': '${task.id}'}));
    if (confirm != true) return;
    setState(() => _isDeleting = true);
    try {
      await Get.find<ApiClient>().deleteTask(task.id);
      await Get.find<HistoryController>().loadTasks();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('history.delete_failed'.trParams({'error': '$e'}))));
      }
    }
    if (mounted) setState(() => _isDeleting = false);
  }

  Future<void> _batchDelete(BuildContext ctx) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final confirm = await _confirmDelete(ctx, 'history.confirm_delete_batch'.trParams({'count': '${ids.length}'}));
    if (confirm != true) return;
    setState(() => _isDeleting = true);
    try {
      await Get.find<ApiClient>().batchDeleteTasks(ids);
      _exitEditMode();
      await Get.find<HistoryController>().loadTasks();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('history.batch_delete_failed'.trParams({'error': '$e'}))));
      }
    }
    if (mounted) setState(() => _isDeleting = false);
  }

  Future<bool?> _confirmDelete(BuildContext ctx, String message) {
    return showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text('history.confirm_delete'.tr),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('action.cancel'.tr)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('action.delete'.tr),
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
        PopupMenuItem(value: 'open', child: Text('menu.open'.tr)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('menu.delete'.tr, style: const TextStyle(color: Colors.red))),
      ],
    ).then((value) {
      if (value == 'open') {
        Get.find<TabManager>().openTask(task);
        Get.find<TaskController>().selectTask(task);
        Get.find<AppPageController>().showCapture();
      } else if (value == 'delete') {
        if (ctx.mounted) _deleteTask(ctx, task);
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
          height: AppTheme.sizing.toolbarHeight,
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.lg),
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
                  SizedBox(width: AppTheme.spacing.sm),
                  Text('history.selected'.trParams({'selected': '${_selectedIds.length}', 'total': '${visibleTasks.length}'}),
                      style: theme.textTheme.titleSmall),
                  SizedBox(width: AppTheme.spacing.md),
                  TextButton(
                    onPressed: _exitEditMode,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
                    ),
                    child: Text('history.done'.tr),
                  ),
                  const Spacer(),
                  if (_selectedIds.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _batchDelete(context),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: Text('history.delete_count'.trParams({'count': '${_selectedIds.length}'})),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                ] else ...[
                  // Normal mode: title + count + edit button + search
                  Text('history.title'.tr, style: theme.textTheme.titleSmall),
                  SizedBox(width: AppTheme.spacing.sm),
                  Text('history.tasks'.trParams({'count': '${historyCtrl.tasks.length}'}),
                      style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor)),
                  SizedBox(width: AppTheme.spacing.md),
                  TextButton.icon(
                    onPressed: _enterEditMode,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: Text('history.edit'.tr),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 200,
                    height: 28,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'history.search'.tr,
                        prefixIcon: const Icon(Icons.search, size: 16),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radius.md)),
                      ),
                      style: TextStyle(fontSize: AppTheme.fontSize.sm),
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
          child: Stack(
            children: [
              Obx(() {
            if (historyCtrl.isLoading.value && !_isDeleting) {
              return const Center(child: CircularProgressIndicator());
            }
            final tasks = _getVisibleTasks();
            if (tasks.isEmpty) {
              return Center(
                child: Text('empty.no_history'.tr, style: TextStyle(color: theme.hintColor)),
              );
            }
            return ListView.separated(
              padding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
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
                      Get.find<TabManager>().openTask(task);
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
              // Deleting overlay
              if (_isDeleting)
                Container(
                  color: Colors.black.withAlpha(30),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.spacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            SizedBox(height: AppTheme.spacing.md),
                            Text('history.deleting'.tr),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing.lg,
            vertical: AppTheme.spacing.sm,
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
                  margin: EdgeInsets.only(right: AppTheme.spacing.sm, left: 10),
                  decoration: BoxDecoration(color: AppTheme.colors(context).statusConnected, shape: BoxShape.circle),
                )
              else
                SizedBox(width: 18 + AppTheme.spacing.sm),

              SizedBox(width: AppTheme.spacing.sm),

              // Task name
              SizedBox(
                width: 120,
                child: Text(
                  task.name.isNotEmpty ? task.name : 'Task ${task.id}',
                  style: TextStyle(
                    fontSize: AppTheme.fontSize.md,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: AppTheme.spacing.lg),

              // Time
              SizedBox(width: 140, child: Text(timeStr,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor))),
              SizedBox(width: AppTheme.spacing.lg),

              // Flows
              SizedBox(width: 80, child: Text('${task.flowCount ?? 0} flows',
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor))),
              SizedBox(width: AppTheme.spacing.sm),

              // Upload
              SizedBox(width: 80, child: Row(children: [
                Icon(Icons.arrow_upward, size: 12, color: theme.hintColor),
                const SizedBox(width: 2),
                Text(_fmtBytes(task.uploadBytes ?? 0),
                    style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor)),
              ])),

              // Download
              SizedBox(width: 80, child: Row(children: [
                Icon(Icons.arrow_downward, size: 12, color: theme.hintColor),
                const SizedBox(width: 2),
                Text(_fmtBytes(task.downloadBytes ?? 0),
                    style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor)),
              ])),

              const Spacer(),

              // Total badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                ),
                child: Text(_fmtBytes(totalBytes),
                    style: TextStyle(fontSize: AppTheme.fontSize.xs, color: theme.hintColor)),
              ),

              SizedBox(width: AppTheme.spacing.sm),

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
