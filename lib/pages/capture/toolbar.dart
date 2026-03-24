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

    return Container(
      height: AppTheme.sizing.toolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
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
          Obx(() => GestureDetector(
            onTap: () async {
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
          )),
          SizedBox(width: AppTheme.spacing.sm),
          GestureDetector(
            onTap: () => flowCtrl.flows.clear(),
            child: Container(
              width: AppTheme.sizing.iconButtonSize,
              height: AppTheme.sizing.iconButtonSize,
              decoration: BoxDecoration(
                color: AppTheme.colors(context).divider.withAlpha(40),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(Icons.delete_outline, size: 14, color: AppTheme.colors(context).textSecondary),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: AppTheme.sizing.searchFieldWidth,
            height: AppTheme.sizing.searchFieldHeight,
            child: TextField(
              focusNode: widget.searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                filled: true,
                fillColor: AppTheme.colors(context).surface,
                contentPadding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.md),
                  borderSide: BorderSide(
                    color: AppTheme.colors(context).divider,
                    width: 0.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.md),
                  borderSide: BorderSide(
                    color: AppTheme.colors(context).divider,
                    width: 0.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.md),
                  borderSide: BorderSide(
                    color: AppTheme.colors(context).divider,
                    width: 0.5,
                  ),
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
