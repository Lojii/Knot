import 'package:get/get.dart';

enum AppPage { capture, history }

class AppPageController extends GetxController {
  final currentPage = AppPage.capture.obs;

  bool get isCapture => currentPage.value == AppPage.capture;
  bool get isHistory => currentPage.value == AppPage.history;

  void showCapture() => currentPage.value = AppPage.capture;
  void showHistory() => currentPage.value = AppPage.history;
}
