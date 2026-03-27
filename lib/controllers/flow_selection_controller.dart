import 'package:get/get.dart';
import '../models/flow_summary.dart';
import 'detail_controller.dart';

/// Owns the "which flow is selected" state.
/// Both FlowTable and FlowDetailPanel observe selectedFlow.
/// On selection, automatically loads detail + bodies.
class FlowSelectionController extends GetxController {
  int? taskId;

  String get _tag => 'task_$taskId';
  DetailController get _detailCtrl => Get.find<DetailController>(tag: _tag);

  final selectedFlow = Rxn<FlowSummary>();

  void select(FlowSummary flow) {
    selectedFlow.value = flow;
    if (taskId != null) {
      final tid = taskId!;
      final fid = flow.flowId;
      // Must load detail first (headers needed for Content-Encoding),
      // then load bodies with correct decompression.
      _detailCtrl.loadDetail(tid, fid).then((_) {
        _detailCtrl.loadBodies(tid, fid);
      });
    }
  }

  void clear() {
    selectedFlow.value = null;
  }
}
