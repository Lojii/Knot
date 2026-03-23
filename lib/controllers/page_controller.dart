import 'package:get/get.dart';

enum AppPage { capture, history, settings, compose, mapRemote, allowBlock, diff }

class AppPageController extends GetxController {
  final currentPage = AppPage.capture.obs;

  bool get isCapture => currentPage.value == AppPage.capture;
  bool get isHistory => currentPage.value == AppPage.history;
  bool get isSettings => currentPage.value == AppPage.settings;
  bool get isCompose => currentPage.value == AppPage.compose;
  bool get isMapRemote => currentPage.value == AppPage.mapRemote;
  bool get isAllowBlock => currentPage.value == AppPage.allowBlock;
  bool get isDiff => currentPage.value == AppPage.diff;
  /// True when not on capture page (history, settings, or compose)
  bool get isSubPage => currentPage.value != AppPage.capture;

  void showCapture() => currentPage.value = AppPage.capture;
  void showHistory() => currentPage.value = AppPage.history;
  void showSettings() => currentPage.value = AppPage.settings;
  void showCompose() => currentPage.value = AppPage.compose;
  void showMapRemote() => currentPage.value = AppPage.mapRemote;
  void showAllowBlock() => currentPage.value = AppPage.allowBlock;
  void showDiff() => currentPage.value = AppPage.diff;

  // Pre-fill data for compose page (set before navigating)
  String composePrefillMethod = '';
  String composePrefillUrl = '';
  Map<String, String> composePrefillHeaders = {};
  String composePrefillBody = '';

  /// Navigate to compose with pre-filled data from a captured request.
  void openInCompose({
    required String method,
    required String url,
    Map<String, String> headers = const {},
    String body = '',
  }) {
    composePrefillMethod = method;
    composePrefillUrl = url;
    composePrefillHeaders = Map.from(headers);
    composePrefillBody = body;
    showCompose();
  }

  void clearComposePrefill() {
    composePrefillMethod = '';
    composePrefillUrl = '';
    composePrefillHeaders = {};
    composePrefillBody = '';
  }
}
