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
import 'pages/capture/capture_page.dart';
import 'theme/app_theme.dart';

void main() {
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

  runApp(const KnotApp());
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
