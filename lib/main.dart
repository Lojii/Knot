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
import 'dart:ui' as ui;
import 'pages/capture/capture_page.dart';
import 'theme/app_theme.dart';
import 'i18n/translations.dart';

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

  // Startup: only initialize web API connection, don't start proxy
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Check if proxy is already running (from a previous session)
    int port = 0;
    try {
      final status = await ProxyChannel.getStatus();
      if (status['running'] == true) {
        port = (status['port'] as int?) ?? 0;
      }
    } catch (_) {}

    // Set API endpoints if we got a port
    if (port > 0) {
      api.baseUrl = 'http://localhost:$port';
      ws.baseUrl = 'ws://localhost:$port';
    }
  });
}

class KnotApp extends StatelessWidget {
  const KnotApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Detect system locale, fallback to en_US
    final systemLocale = ui.PlatformDispatcher.instance.locale;
    final locale = systemLocale.languageCode == 'zh'
        ? const Locale('zh', 'CN')
        : const Locale('en', 'US');

    return GetMaterialApp(
      title: 'Knot',
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      home: const CapturePage(),
    );
  }
}
