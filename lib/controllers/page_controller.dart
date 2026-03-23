import 'package:get/get.dart';

enum AppPage { capture, history, settings }

class AppPageController extends GetxController {
  final currentPage = AppPage.capture.obs;

  bool get isCapture => currentPage.value == AppPage.capture;
  bool get isHistory => currentPage.value == AppPage.history;
  bool get isSettings => currentPage.value == AppPage.settings;
  /// True when not on capture page (history or settings)
  bool get isSubPage => currentPage.value != AppPage.capture;

  void showCapture() => currentPage.value = AppPage.capture;
  void showHistory() => currentPage.value = AppPage.history;
  void showSettings() => currentPage.value = AppPage.settings;
}
