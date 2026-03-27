import 'package:get/get.dart';
import 'filter_controller.dart';
import 'flow_table_controller.dart';

/// Thin orchestration layer for FilterBar widget.
/// Toggles filter state and triggers recomputation.
class FilterBarController extends GetxController {
  int? taskId;

  String get _tag => 'task_$taskId';
  FilterController get _filterCtrl => Get.find<FilterController>(tag: _tag);
  FlowTableController get _tableCtrl => Get.find<FlowTableController>(tag: _tag);

  void toggleProtocol(String proto) {
    _filterCtrl.toggleProtocol(proto);
    _tableCtrl.refilterAndUpdateTree();
  }

  void toggleContentType(String type) {
    _filterCtrl.toggleContentType(type);
    _tableCtrl.refilterAndUpdateTree();
  }

  void clearAll() {
    _filterCtrl.clearAll();
    _tableCtrl.refilterAndUpdateTree();
  }
}
