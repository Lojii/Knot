import 'dart:async';
import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_summary.dart';
import 'filter_controller.dart';

class FlowController extends GetxController {
  final ApiClient api;
  FlowController(this.api);

  final flows = <FlowSummary>[].obs;
  final selectedFlow = Rxn<FlowSummary>();
  final total = 0.obs;
  final isLoading = false.obs;
  final searchQuery = ''.obs;
  final hasNewFlows = false.obs;

  int _currentPage = 1;
  int? _taskId;
  Timer? _searchDebounce;

  void setTaskId(int taskId) {
    _taskId = taskId;
    _currentPage = 1;
    flows.clear();
    selectedFlow.value = null;
    loadFlows();
  }

  Future<void> loadFlows({bool append = false}) async {
    if (_taskId == null) return;
    isLoading.value = true;
    try {
      final filter = Get.find<FilterController>();
      final result = await api.getFlows(
        taskId: _taskId!,
        page: _currentPage,
        protocol: filter.protocolParam,
        keyword: searchQuery.value.isEmpty ? null : searchQuery.value,
      );
      if (append) {
        flows.addAll(result.items);
      } else {
        flows.value = result.items;
      }
      total.value = result.total;
      Get.find<FilterController>().updateAvailableFilters(flows);
    } catch (_) {}
    isLoading.value = false;
  }

  void loadMore() {
    if (isLoading.value || flows.length >= total.value) return;
    _currentPage++;
    loadFlows(append: true);
  }

  /// Reset to first page and reload — call after filter/search changes
  void reloadFromFirstPage() {
    _currentPage = 1;
    loadFlows();
  }

  void search(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      searchQuery.value = query;
      _currentPage = 1;
      loadFlows();
    });
  }

  void selectFlow(FlowSummary flow) {
    selectedFlow.value = flow;
  }

  void addFlowFromPush(FlowSummary flow) {
    flows.insert(0, flow);
    total.value++;
    Get.find<FilterController>().updateAvailableFilters(flows);
  }

  void updateFlowFromPush(Map<String, dynamic> data) {
    final fid = data['flowId'] as String?;
    if (fid == null) return;
    final idx = flows.indexWhere((f) => f.flowId == fid);
    if (idx >= 0) {
      flows[idx] = FlowSummary.fromJson(data);
    }
  }
}
