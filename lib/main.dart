import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'api/api_client.dart';
import 'api/ws_client.dart';
import 'controllers/task_controller.dart';
import 'controllers/live_controller.dart';
import 'controllers/history_controller.dart';
import 'controllers/page_controller.dart';
import 'controllers/tools_controller.dart';
import 'controllers/tab_controller.dart';
import 'controllers/theme_controller.dart';
import 'controllers/cert_controller.dart';
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
  Get.put(TaskController(api));
  Get.put(LiveController(ws));
  Get.put(HistoryController(api));
  Get.put(AppPageController());
  Get.put(ToolsController());
  Get.put(TabManager());
  Get.put(ThemeController());
  Get.put(CertController());

  runApp(const KnotApp());

  // Startup: start web API server only — no task creation, no capture
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    int port = 0;

    // Check if already running
    try {
      final status = await ProxyChannel.getStatus();
      if (status['running'] == true) {
        port = (status['port'] as int?) ?? 0;
      }
    } catch (e) { debugPrint("[Knot] Error: $e"); }

    // If not running, start it (this boots the web API server too)
    if (port == 0) {
      try {
        final result = await ProxyChannel.startProxy();
        port = (result['port'] as int?) ?? 0;
      } catch (e) { debugPrint("[Knot] Error: $e"); }
    }

    // Set API endpoints
    if (port > 0) {
      api.baseUrl = 'http://localhost:$port';
      ws.baseUrl = 'ws://localhost:$port';
      // Pre-load history for the + menu
      Get.find<HistoryController>().loadTasks();
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

    final themeCtrl = Get.find<ThemeController>();

    return Obx(() => GetMaterialApp(
      title: 'Knot',
      themeMode: themeCtrl.themeMode.value,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      home: const CapturePage(),
    ));
  }
}
