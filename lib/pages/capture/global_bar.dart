import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/tools_controller.dart';
import '../../utils/har_export.dart';
import '../../utils/har_import.dart';
import '../../utils/list_export.dart';
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
          value: 'mapLocal',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Map Local'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'breakpointMgmt',
          child: Row(
            children: [
              Icon(Icons.pause_circle_outline, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Breakpoints'),
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
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'exportHar',
          child: Row(
            children: [
              Icon(Icons.upload_file, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Export HAR'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'importHar',
          child: Row(
            children: [
              Icon(Icons.download, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Import HAR'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'exportCsv',
          child: Row(
            children: [
              Icon(Icons.table_chart_outlined, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Export List as CSV'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'exportJson',
          child: Row(
            children: [
              Icon(Icons.data_object, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Export List as JSON'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'diff',
          child: Row(
            children: [
              Icon(Icons.compare_arrows, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Diff Tool'),
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
                      ? 'No Caching enabled'
                      : 'No Caching disabled',
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
        const SnackBar(content: Text('No flows to export')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Exporting HAR...')),
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
            content: Text('HAR exported to $path'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _importHar(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import HAR'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '/path/to/file.har',
            labelText: 'HAR file path',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
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
                      content: Text('Imported ${imported.length} requests from HAR file'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Import failed: $e')),
                  );
                }
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _exportListCsv(BuildContext context) async {
    final flowCtrl = Get.find<FlowController>();
    if (flowCtrl.flows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No flows to export')),
      );
      return;
    }
    try {
      final csv = ListExport.toCsv(flowCtrl.flows.toList());
      final path = await ListExport.writeToDesktop(csv, 'csv');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV exported to $path'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _exportListJson(BuildContext context) async {
    final flowCtrl = Get.find<FlowController>();
    if (flowCtrl.flows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No flows to export')),
      );
      return;
    }
    try {
      final json = ListExport.toJson(flowCtrl.flows.toList());
      final path = await ListExport.writeToDesktop(json, 'json');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JSON exported to $path'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}
