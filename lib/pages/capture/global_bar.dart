import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../api/api_client.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/history_controller.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/tools_controller.dart';
import '../../controllers/tab_controller.dart';
import '../../models/task_model.dart';
import '../../utils/har_export.dart';
import '../../utils/har_import.dart';
import '../../utils/list_export.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_page.dart';

class GlobalBar extends StatelessWidget {
  const GlobalBar({super.key});

  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final pageCtrl = Get.find<AppPageController>();
    final tabMgr = Get.find<TabManager>();
    final theme = Theme.of(context);
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {},
      child: Container(
        height: AppTheme.sizing.globalBarHeight,
        padding: EdgeInsets.only(
          left: isMacOS ? AppTheme.sizing.macOSTrafficLightWidth : AppTheme.spacing.md,
          right: AppTheme.spacing.md,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.mode(context).toolbar.gradientStart,
              AppTheme.mode(context).toolbar.gradientEnd,
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: AppTheme.colors(context).divider,
              width: AppTheme.mode(context).toolbar.borderWidth,
            ),
          ),
        ),
        child: Row(
          children: [
            // 1. Logo
            Icon(Icons.hub, size: AppTheme.sizing.iconSize, color: theme.colorScheme.primary),
            SizedBox(width: AppTheme.spacing.xs),
            Text(
              'NetKnot',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(width: AppTheme.spacing.md),

            // 2. Home tab
            Obx(() => _TabChip(
              tab: tabMgr.tabs.first,
              isActive: tabMgr.activeTabId.value == '__home__',
            )),

            // 3. Start/Stop button
            SizedBox(width: AppTheme.spacing.xs),
            _StartStopButton(taskCtrl: taskCtrl),
            SizedBox(width: AppTheme.spacing.xs),

            // 4. Task tabs (scrollable)
            Expanded(
              child: Obx(() {
                final taskTabs = tabMgr.tabs.where((t) => !t.isHome).toList();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: taskTabs.map((tab) => _TabChip(
                      tab: tab,
                      isActive: tabMgr.activeTabId.value == tab.id,
                    )).toList(),
                  ),
                );
              }),
            ),

            // 5. + button with history menu
            const _PlusMenuButton(),

            SizedBox(width: AppTheme.spacing.sm),

            // 6. Tools button
            _ToolsMenuButton(pageCtrl: pageCtrl),

            // 7. Settings button
            IconButton(
              icon: Icon(Icons.settings, size: AppTheme.sizing.iconSize),
              tooltip: 'nav.settings'.tr,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radius.popup),
                    ),
                    child: SizedBox(
                      width: 480,
                      height: 400,
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing.lg,
                              vertical: AppTheme.spacing.md,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppTheme.colors(ctx).divider),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text('nav.settings'.tr,
                                    style: Theme.of(ctx).textTheme.titleMedium),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                          const Expanded(child: SettingsPanel()),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab chip widget
// ─────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final TabItem tab;
  final bool isActive;
  const _TabChip({required this.tab, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final tabMgr = Get.find<TabManager>();
    final colors = AppTheme.colors(context);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        tabMgr.activateTab(tab.id);
        // When activating Home, switch to capture page view
        final pageCtrl = Get.find<AppPageController>();
        if (pageCtrl.isSubPage) {
          pageCtrl.showCapture();
        }
      },
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition, tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: isActive ? colors.surface : Colors.transparent,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(6),
          ),
          border: isActive
              ? Border(
                  top: BorderSide(color: colors.primary, width: 2),
                )
              : null,
        ),
        child: Obx(() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Home tab: icon only, no text
            if (tab.isHome)
              Icon(Icons.home, size: 14, color: isActive ? colors.primary : colors.textSecondary),
            // Task tabs: show title
            if (!tab.isHome) ...[
              // Capturing indicator dot
              if (tab.isCapturing.value) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                tab.title.value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? colors.textPrimary : colors.textSecondary,
                  fontSize: AppTheme.fontSize.sm,
                ),
              ),
              // Close button (not for capturing tabs)
              if (tab.canClose) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => tabMgr.closeTab(tab.id),
                  child: Icon(Icons.close, size: 12, color: colors.textSecondary),
                ),
              ],
            ],
          ],
        )),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, TabItem tab) async {
    final tabMgr = Get.find<TabManager>();

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        if (tab.canClose)
          PopupMenuItem(value: 'close', child: Text('tab.close'.tr)),
        PopupMenuItem(value: 'closeAll', child: Text('tab.close_all'.tr)),
        if (!tab.isHome)
          PopupMenuItem(value: 'rename', child: Text('tab.rename'.tr)),
        if (!tab.isHome && tab.canClose)
          PopupMenuItem(value: 'delete', child: Text('tab.delete_task'.tr)),
      ],
    );
    if (value == null) return;
    switch (value) {
      case 'close':
        tabMgr.closeTab(tab.id);
      case 'closeAll':
        tabMgr.closeAllExcept(tab.id);
      case 'rename':
        if (!context.mounted) return;
        _showRenameDialog(context, tab);
      case 'delete':
        if (!context.mounted) return;
        _deleteTask(context, tab);
    }
  }

  void _showRenameDialog(BuildContext context, TabItem tab) {
    final tabMgr = Get.find<TabManager>();
    final controller = TextEditingController(text: tab.title.value);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('tab.rename'.tr),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('action.cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              tabMgr.renameTab(tab.id, newName);
              // Persist to backend
              if (tab.taskId != null) {
                try {
                  await Get.find<ApiClient>().renameTask(tab.taskId!, newName);
                } catch (_) {}
              }
            },
            child: Text('action.save'.tr),
          ),
        ],
      ),
    );
  }

  void _deleteTask(BuildContext context, TabItem tab) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('tab.delete_task'.tr),
        content: Text('history.confirm_delete_one'.trParams({'id': '${tab.taskId ?? ""}'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('action.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('action.delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || tab.taskId == null) return;
    try {
      final tabMgr = Get.find<TabManager>();
      tabMgr.closeTab(tab.id);
      await Get.find<ApiClient>().deleteTask(tab.taskId!);
      Get.find<HistoryController>().loadTasks();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('history.delete_failed'.trParams({'error': '$e'}))),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Start / Stop toggle button
// ─────────────────────────────────────────────────────────────

class _StartStopButton extends StatelessWidget {
  final TaskController taskCtrl;
  const _StartStopButton({required this.taskCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() => GestureDetector(
      onTap: () => taskCtrl.toggleCapture(),
      child: Container(
        width: AppTheme.sizing.iconButtonSize,
        height: AppTheme.sizing.iconButtonSize,
        decoration: BoxDecoration(
          color: taskCtrl.isCapturing.value
              ? AppTheme.methodColorOf(context, 'DELETE')
              : AppTheme.methodColorOf(context, 'GET'),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(
          taskCtrl.isCapturing.value ? Icons.stop : Icons.play_arrow,
          size: 14,
          color: Colors.white,
        ),
      ),
    ));
  }
}

// ─────────────────────────────────────────────────────────────
// Tools popup menu button (preserved from original)
// ─────────────────────────────────────────────────────────────

class _ToolsMenuButton extends StatelessWidget {
  final AppPageController pageCtrl;
  const _ToolsMenuButton({required this.pageCtrl});

  @override
  Widget build(BuildContext context) {
    final toolsCtrl = Get.find<ToolsController>();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.build_outlined, size: 18),
      tooltip: 'nav.tools'.tr,
      padding: EdgeInsets.zero,
      splashRadius: 16,
      offset: Offset(0, AppTheme.sizing.globalBarHeight),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'mapRemote',
          child: Row(
            children: [
              const Icon(Icons.alt_route, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.map_remote'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'mapLocal',
          child: Row(
            children: [
              const Icon(Icons.folder_open, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.map_local'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'breakpointMgmt',
          child: Row(
            children: [
              const Icon(Icons.pause_circle_outline, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.breakpoints'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'allowBlock',
          child: Row(
            children: [
              const Icon(Icons.filter_list, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.allow_block'.tr),
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
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.no_caching'.tr),
            ],
          )),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'exportHar',
          child: Row(
            children: [
              const Icon(Icons.upload_file, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.export_har'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'importHar',
          child: Row(
            children: [
              const Icon(Icons.download, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.import_har'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'exportCsv',
          child: Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.export_csv'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'exportJson',
          child: Row(
            children: [
              const Icon(Icons.data_object, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.export_json'.tr),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'diff',
          child: Row(
            children: [
              const Icon(Icons.compare_arrows, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('tools.diff'.tr),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'mapRemote':
            pageCtrl.isMapRemote
                ? pageCtrl.showCapture()
                : pageCtrl.showMapRemote();
          case 'mapLocal':
            pageCtrl.isMapLocal
                ? pageCtrl.showCapture()
                : pageCtrl.showMapLocal();
          case 'breakpointMgmt':
            pageCtrl.isBreakpointMgmt
                ? pageCtrl.showCapture()
                : pageCtrl.showBreakpointMgmt();
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
                      ? 'tools.no_caching_enabled'.tr
                      : 'tools.no_caching_disabled'.tr,
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          case 'exportHar':
            _exportHar(context);
          case 'importHar':
            _importHar(context);
          case 'exportCsv':
            _exportListCsv(context);
          case 'exportJson':
            _exportListJson(context);
          case 'diff':
            pageCtrl.isDiff
                ? pageCtrl.showCapture()
                : pageCtrl.showDiff();
        }
      },
    );
  }

  void _exportHar(BuildContext context) async {
    final flowCtrl = Get.find<FlowController>();
    final taskCtrl = Get.find<TaskController>();
    final taskId = taskCtrl.currentTask.value?.id;
    if (taskId == null || flowCtrl.flows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('empty.no_flows_export'.tr)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('msg.exporting_har'.tr)),
    );
    try {
      final harJson = await HarExport.fromFlows(
        flowCtrl.flows.toList(),
        flowCtrl.api,
        taskId,
      );
      final path = await HarExport.writeToDesktop(harJson);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('msg.har_exported'.trParams({'path': path})),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('msg.export_failed'.trParams({'error': '$e'}))),
        );
      }
    }
  }

  void _importHar(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('tools.import_har'.tr),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'import.har_path_hint'.tr,
            labelText: 'import.har_path_label'.tr,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('action.cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final path = controller.text.trim();
              if (path.isEmpty) return;
              try {
                final flowCtrl = Get.find<FlowController>();
                final imported = await HarImport.importFromFile(path);
                for (final flow in imported) {
                  flowCtrl.flows.insert(0, flow);
                }
                flowCtrl.total.value = flowCtrl.total.value + imported.length;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('msg.imported_flows'.trParams({'count': '${imported.length}'})),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('msg.import_failed'.trParams({'error': '$e'}))),
                  );
                }
              }
            },
            child: Text('action.import'.tr),
          ),
        ],
      ),
    );
  }

  void _exportListCsv(BuildContext context) async {
    final flowCtrl = Get.find<FlowController>();
    if (flowCtrl.flows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('empty.no_flows_export'.tr)),
      );
      return;
    }
    try {
      final csv = ListExport.toCsv(flowCtrl.flows.toList());
      final path = await ListExport.writeToDesktop(csv, 'csv');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('msg.csv_exported'.trParams({'path': path})),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('msg.export_failed'.trParams({'error': '$e'}))),
        );
      }
    }
  }

  void _exportListJson(BuildContext context) async {
    final flowCtrl = Get.find<FlowController>();
    if (flowCtrl.flows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('empty.no_flows_export'.tr)),
      );
      return;
    }
    try {
      final json = ListExport.toJson(flowCtrl.flows.toList());
      final path = await ListExport.writeToDesktop(json, 'json');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('msg.json_exported'.trParams({'path': path})),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('msg.export_failed'.trParams({'error': '$e'}))),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Plus menu button — recent history tasks
// ─────────────────────────────────────────────────────────────

class _PlusMenuButton extends StatelessWidget {
  const _PlusMenuButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<dynamic>(
      icon: Icon(Icons.add, size: AppTheme.sizing.iconSize),
      tooltip: 'tab.open_task'.tr,
      padding: EdgeInsets.zero,
      splashRadius: 14,
      offset: Offset(0, AppTheme.sizing.globalBarHeight),
      onOpened: () {
        // Refresh history when menu opens
        Get.find<HistoryController>().loadTasks();
      },
      itemBuilder: (ctx) {
        final historyCtrl = Get.find<HistoryController>();
        final tasks = historyCtrl.tasks.take(10).toList();

        return [
          if (tasks.isEmpty)
            PopupMenuItem<String>(
              enabled: false,
              child: Text('empty.no_history'.tr,
                  style: TextStyle(color: AppTheme.colors(ctx).textSecondary, fontSize: AppTheme.fontSize.sm)),
            ),
          ...tasks.map((task) => PopupMenuItem<TaskModel>(
                value: task,
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 14,
                        color: AppTheme.colors(ctx).textSecondary),
                    SizedBox(width: AppTheme.spacing.sm),
                    Expanded(
                      child: Text(
                        task.name.isNotEmpty ? task.name : 'Task ${task.id}',
                        style: TextStyle(fontSize: AppTheme.fontSize.sm),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (task.flowCount != null && task.flowCount! > 0)
                      Text('${task.flowCount}',
                          style: TextStyle(
                              fontSize: AppTheme.fontSize.xs,
                              color: AppTheme.colors(ctx).textSecondary)),
                  ],
                ),
              )),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: '__manage__',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.history, size: 14,
                    color: AppTheme.colors(ctx).textSecondary),
                SizedBox(width: AppTheme.spacing.sm),
                Text('tab.manage_history'.tr,
                    style: TextStyle(fontSize: AppTheme.fontSize.sm)),
              ],
            ),
          ),
        ];
      },
      onSelected: (value) {
        if (value == '__manage__') {
          Get.find<AppPageController>().showHistory();
        } else if (value is TaskModel) {
          final tabMgr = Get.find<TabManager>();
          tabMgr.openTask(value);
          Get.find<TaskController>().selectTask(value);
        }
      },
    );
  }
}
