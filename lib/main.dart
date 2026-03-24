import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'api/api_client.dart';
import 'api/ws_client.dart';
import 'controllers/task_controller.dart';
import 'controllers/flow_controller.dart';
import 'controllers/live_controller.dart';
import 'controllers/tree_controller.dart';
import 'controllers/detail_controller.dart';
import 'controllers/filter_controller.dart';
import 'controllers/dashboard_controller.dart';
import 'controllers/history_controller.dart';
import 'controllers/page_controller.dart';
import 'controllers/tag_controller.dart';
import 'controllers/tools_controller.dart';
import 'api/proxy_channel.dart';
import 'pages/capture/capture_page.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppTheme.loadFromAsset();

  final api = ApiClient();
  final ws = WsClient();

  Get.put(api);
  Get.put(ws);
  Get.put(FilterController());
  Get.put(TaskController(api));
  Get.put(FlowController(api));
  Get.put(LiveController(ws));
  Get.put(TreeController());
  Get.put(DetailController(api));
  Get.put(DashboardController(api));
  Get.put(HistoryController(api));
  Get.put(AppPageController());
  Get.put(TagController());
  Get.put(ToolsController());

  runApp(const KnotApp());

  // Startup sequence (after first frame)
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final taskCtrl = Get.find<TaskController>();
    final flowCtrl = Get.find<FlowController>();
    final liveCtrl = Get.find<LiveController>();

    // Step 1: Check if proxy is already running
    bool proxyRunning = false;
    int port = 9090;
    try {
      final status = await ProxyChannel.getStatus();
      proxyRunning = status['running'] == true;
      if (proxyRunning) {
        port = (status['port'] as int?) ?? 9090;
      }
    } catch (e) {
    }

    // Step 2: If not running, try to start it automatically
    if (!proxyRunning) {
      try {
        final result = await ProxyChannel.startProxy();
        proxyRunning = result['running'] == true;
        port = (result['port'] as int?) ?? 9090;
      } catch (e) {
      }
    }

    // Step 3: If still not running, try connecting to default port (external proxy)
    if (!proxyRunning) {
      proxyRunning = await api.checkConnection();
    }

    if (proxyRunning) {
      taskCtrl.isCapturing.value = true;
      api.baseUrl = 'http://localhost:$port';
      ws.baseUrl = 'ws://localhost:$port';

      // Load tasks and connect
      await taskCtrl.loadTasks();
      if (taskCtrl.currentTask.value != null) {
        final tid = taskCtrl.currentTask.value!.id;
        flowCtrl.setTaskId(tid);
        liveCtrl.connectToTask(tid);
      }
    }
  });
}

class KnotApp extends StatelessWidget {
  const KnotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Knot',
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const CapturePage(),
    );
  }
}
