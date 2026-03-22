import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_detail.dart';

class DetailController extends GetxController {
  final ApiClient api;
  DetailController(this.api);

  final detail = Rxn<FlowDetail>();
  final requestBody = ''.obs;
  final responseBody = ''.obs;
  final isLoadingDetail = false.obs;
  final isLoadingBody = false.obs;
  final selectedTab = 0.obs;

  Future<void> loadDetail(int taskId, String flowId) async {
    isLoadingDetail.value = true;
    try {
      detail.value = await api.getFlowDetail(taskId, flowId);
    } catch (_) {}
    isLoadingDetail.value = false;
  }

  Future<void> loadBodies(int taskId, String flowId) async {
    isLoadingBody.value = true;
    try {
      requestBody.value = await api.getPayload(taskId, flowId, 'request', preview: true);
      responseBody.value = await api.getPayload(taskId, flowId, 'response', preview: true);
    } catch (_) {
      requestBody.value = '';
      responseBody.value = '';
    }
    isLoadingBody.value = false;
  }

  void clear() {
    detail.value = null;
    requestBody.value = '';
    responseBody.value = '';
  }
}
