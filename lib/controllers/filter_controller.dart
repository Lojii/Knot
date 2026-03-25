import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_summary.dart';

/// Content type category mapping: contentType substring -> label
const _contentTypeCategories = <String, String>{
  'json': 'JSON',
  'javascript': 'JS',
  'xml': 'XML',
  'html': 'HTML',
  'image/': 'IMG',
  'css': 'CSS',
  'font': 'Font',
  'video/': 'Video',
  'audio/': 'Audio',
  'pdf': 'PDF',
  'text/plain': 'TEXT',
};

class FilterController extends GetxController {
  static const protocolOptions = ['HTTP', 'HTTPS', 'WS', 'WSS'];
  static const contentTypeOptions = ['JSON', 'IMG', 'TEXT', 'JS', 'HTML', 'CSS', 'XML'];

  final activeProtocols = <String>{}.obs;
  final activeContentTypes = <String>{}.obs;

  final protocolMode = 'HTTP'.obs; // 'HTTP' or 'TCP'

  void toggleProtocolMode() {
    protocolMode.value = protocolMode.value == 'HTTP' ? 'TCP' : 'HTTP';
  }

  bool get isTcpMode => protocolMode.value == 'TCP';

  /// Available protocols from API
  final availableProtocols = <String>[].obs;
  /// Available content type categories from API
  final availableContentTypes = <String>[].obs;

  void toggleProtocol(String proto) {
    if (proto == 'All') {
      activeProtocols.clear();
    } else if (activeProtocols.contains(proto)) {
      activeProtocols.remove(proto);
    } else {
      activeProtocols.add(proto);
    }
  }

  void toggleContentType(String type) {
    if (type == 'All') {
      activeContentTypes.clear();
    } else if (activeContentTypes.contains(type)) {
      activeContentTypes.remove(type);
    } else {
      activeContentTypes.add(type);
    }
  }

  void clearAll() {
    activeProtocols.clear();
    activeContentTypes.clear();
    availableProtocols.clear();
    availableContentTypes.clear();
  }

  /// Fetch available filter options from API
  Future<void> loadFilters(int taskId) async {
    try {
      final api = Get.find<ApiClient>();
      final result = await api.getFlowFilters(taskId);

      // Protocols: stable ordering
      const protoOrder = ['HTTP', 'HTTPS', 'H2', 'WS', 'WSS'];
      final protos = result.protocols.map((p) => p.toUpperCase()).toSet();
      availableProtocols.value = protoOrder.where(protos.contains).toList();

      // Content types: categorize raw values into labels
      const ctOrder = ['JSON', 'IMG', 'TEXT', 'JS', 'CSS', 'HTML', 'XML', 'Font', 'Video', 'Audio', 'PDF'];
      final ctLabels = <String>{};
      for (final ct in result.contentTypes) {
        final lower = ct.toLowerCase();
        for (final entry in _contentTypeCategories.entries) {
          if (lower.contains(entry.key)) {
            ctLabels.add(entry.value);
            break;
          }
        }
      }
      availableContentTypes.value = ctOrder.where(ctLabels.contains).toList();
    } catch (_) {
      // API not available yet — keep current values
    }
  }

  String? get protocolParam => activeProtocols.isEmpty ? null : activeProtocols.join(',');

  /// Check if a flow matches the active content type filters
  bool matchesContentType(FlowSummary flow) {
    if (activeContentTypes.isEmpty) return true;
    final ct = flow.contentType.toLowerCase();
    for (final active in activeContentTypes) {
      for (final entry in _contentTypeCategories.entries) {
        if (entry.value == active && ct.contains(entry.key)) return true;
      }
    }
    return false;
  }
}
