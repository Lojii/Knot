import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../api/proxy_channel.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/live_controller.dart';
import '../../theme/app_theme.dart';

class CaptureToolbar extends StatefulWidget {
  final FocusNode searchFocusNode;
  const CaptureToolbar({super.key, required this.searchFocusNode});

  @override
  State<CaptureToolbar> createState() => _CaptureToolbarState();
}

class _CaptureToolbarState extends State<CaptureToolbar> {
  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: AppTheme.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Obx(() => IconButton(
            icon: Icon(taskCtrl.isCapturing.value ? Icons.stop : Icons.play_arrow),
            color: taskCtrl.isCapturing.value
                ? AppTheme.methodDelete
                : AppTheme.methodGet,
            tooltip: taskCtrl.isCapturing.value ? 'Stop' : 'Start',
            onPressed: () async {
              if (taskCtrl.isCapturing.value) {
                await ProxyChannel.stopProxy();
                taskCtrl.isCapturing.value = false;
              } else {
                try {
                  await ProxyChannel.startProxy();
                  taskCtrl.isCapturing.value = true;
                  await taskCtrl.loadTasks();
                  if (taskCtrl.currentTask.value != null) {
                    final tid = taskCtrl.currentTask.value!.id;
                    Get.find<FlowController>().setTaskId(tid);
                    Get.find<LiveController>().connectToTask(tid);
                  }
                } catch (e) {
                  Get.snackbar('Error', 'Failed to start proxy: $e');
                }
              }
            },
          )),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Clear',
            onPressed: () => flowCtrl.flows.clear(),
          ),
          const Spacer(),
          SizedBox(
            width: 240,
            height: 30,
            child: TextField(
              focusNode: widget.searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
              ),
              onChanged: flowCtrl.search,
            ),
          ),
        ],
      ),
    );
  }
}
