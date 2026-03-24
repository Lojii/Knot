import 'package:get/get.dart';
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
};

class FilterController extends GetxController {
  final activeProtocols = <String>{}.obs;
  final activeContentTypes = <String>{}.obs;

  /// Protocols present in current flow data
  final availableProtocols = <String>[].obs;
  /// Content type categories present in current flow data
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
  }

  /// Rebuild available filter options from current flows
  void updateAvailableFilters(List<FlowSummary> flows) {
    // Protocols
    final protos = <String>{};
    final ctTypes = <String>{};

    for (final f in flows) {
      final proto = f.protocol.toUpperCase();
      if (proto.isNotEmpty) protos.add(proto);

      final ct = f.contentType.toLowerCase();
      if (ct.isNotEmpty) {
        for (final entry in _contentTypeCategories.entries) {
          if (ct.contains(entry.key)) {
            ctTypes.add(entry.value);
            break;
          }
        }
      }
    }

    // Stable ordering
    const protoOrder = ['HTTP', 'HTTPS', 'H2', 'WS', 'WSS'];
    const ctOrder = ['JSON', 'IMG', 'JS', 'CSS', 'HTML', 'XML', 'Font', 'Video', 'Audio', 'PDF'];

    availableProtocols.value = protoOrder.where(protos.contains).toList();
    availableContentTypes.value = ctOrder.where(ctTypes.contains).toList();
  }

  String? get protocolParam => activeProtocols.isEmpty ? null : activeProtocols.join(',');

  /// Check if a flow matches the active content type filters
  bool matchesContentType(FlowSummary flow) {
    if (activeContentTypes.isEmpty) return true;
    final ct = flow.contentType.toLowerCase();
    for (final active in activeContentTypes) {
      // Reverse lookup: label -> substring
      for (final entry in _contentTypeCategories.entries) {
        if (entry.value == active && ct.contains(entry.key)) return true;
      }
    }
    return false;
  }
}
