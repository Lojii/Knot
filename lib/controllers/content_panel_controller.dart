import 'package:get/get.dart';

/// Controls the content panel's active tab: List(0), Waterfall(1), Dashboard(2).
class ContentPanelController extends GetxController {
  int? taskId;

  final activeTab = 0.obs;

  void switchTab(int index) => activeTab.value = index;
}
