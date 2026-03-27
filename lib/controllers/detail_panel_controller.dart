import 'package:get/get.dart';

/// Controls the detail panel's UI state: which tab is active (Data / Details),
/// and within the Data tab, which request/response sub-tab is active.
class DetailPanelController extends GetxController {
  int? taskId;

  /// 0 = Data tab, 1 = Details tab
  final activeTab = 0.obs;

  /// Request sub-tab: 0=Headers, 1=Body, 2=Params, 3=Cookies
  final requestSubTab = 0.obs;

  /// Response sub-tab: 0=Headers, 1=Body, 2=Cookies
  final responseSubTab = 0.obs;

  void switchTab(int index) => activeTab.value = index;
  void switchRequestSubTab(int index) => requestSubTab.value = index;
  void switchResponseSubTab(int index) => responseSubTab.value = index;

  void reset() {
    activeTab.value = 0;
    requestSubTab.value = 0;
    responseSubTab.value = 0;
  }
}
