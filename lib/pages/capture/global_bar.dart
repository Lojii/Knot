import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/tools_controller.dart';
import '../../utils/har_export.dart';
import '../../utils/har_import.dart';
import '../../utils/list_export.dart';
import '../../theme/app_theme.dart';

class GlobalBar extends StatelessWidget {
  const GlobalBar({super.key});

  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final pageCtrl = Get.find<AppPageController>();
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
        child: Obx(() {
          return Row(
            children: [
              // 1. Logo icon + "NetKnot" text
              Icon(Icons.hub, size: AppTheme.sizing.iconSize, color: theme.colorScheme.primary),
              SizedBox(width: AppTheme.spacing.xs),
              Text(
                'NetKnot',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),

              // 2. Small spacer
              SizedBox(width: AppTheme.spacing.lg),

              // 3. Start/Stop toggle switch
              _StartStopButton(taskCtrl: taskCtrl),
              SizedBox(width: AppTheme.spacing.sm),

              // 4. TCP/HTTP mode switch buttons
              _ProtocolModeButtons(),

              // 5. Expanded spacer (left)
              const Spacer(),

              // 6. Centered task name + rename + history
              _TaskNameSection(taskCtrl: taskCtrl, pageCtrl: pageCtrl),

              // 7. Expanded spacer (right)
              const Spacer(),

              // 8. Tools icon button
              _ToolsMenuButton(pageCtrl: pageCtrl),
              // 9. Settings icon button
              IconButton(
                icon: Icon(Icons.settings, size: AppTheme.sizing.iconSize),
                tooltip: 'nav.settings'.tr,
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

// ─────────────────────────────────────────────────────────────
// Start / Stop toggle button (moved from toolbar.dart)
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
              ? AppTheme.methodColor('DELETE')
              : AppTheme.methodColor('GET'),
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
// TCP / HTTP segmented mode buttons
// ─────────────────────────────────────────────────────────────

class _ProtocolModeButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _modeChip(context, 'HTTP', isActive: true, isLeft: true, theme: theme),
        _modeChip(context, 'TCP', isActive: false, isLeft: false, theme: theme),
      ],
    );
  }

  Widget _modeChip(BuildContext context, String label,
      {required bool isActive, required bool isLeft, required ThemeData theme}) {
    final colors = AppTheme.colors(context);
    return GestureDetector(
      onTap: () {/* placeholder */},
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? colors.primary.withAlpha(30) : Colors.transparent,
          border: Border.all(
            color: isActive ? colors.primary : colors.divider,
            width: 0.5,
          ),
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? Radius.circular(AppTheme.radius.sm) : Radius.zero,
            right: !isLeft ? Radius.circular(AppTheme.radius.sm) : Radius.zero,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: AppTheme.fontSize.xs,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Center: Task name + rename + history
// ─────────────────────────────────────────────────────────────

class _TaskNameSection extends StatelessWidget {
  final TaskController taskCtrl;
  final AppPageController pageCtrl;
  const _TaskNameSection({required this.taskCtrl, required this.pageCtrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.colors(context);
    final taskName = taskCtrl.currentTask.value?.name.isNotEmpty == true
        ? taskCtrl.currentTask.value!.name
        : 'Task ${taskCtrl.currentTask.value?.id ?? "-"}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius.sm),
            border: Border.all(color: colors.divider, width: 0.5),
          ),
          child: Text(
            taskName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: AppTheme.fontSize.sm,
            ),
          ),
        ),
        SizedBox(width: AppTheme.spacing.xs),
        IconButton(
          icon: Icon(Icons.edit, size: AppTheme.sizing.iconSize - 2),
          tooltip: 'Rename',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: () {/* placeholder rename */},
        ),
        IconButton(
          icon: Icon(Icons.schedule, size: AppTheme.sizing.iconSize - 2),
          tooltip: 'nav.history'.tr,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          onPressed: () => pageCtrl.isHistory
              ? pageCtrl.showCapture()
              : pageCtrl.showHistory(),
        ),
      ],
    );
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
