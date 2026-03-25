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
  'text/plain': 'TEXT',
};

class FilterController extends GetxController {
  final activeProtocols = <String>{}.obs;
  final activeContentTypes = <String>{}.obs;

  final protocolMode = 'HTTP'.obs;

  void toggleProtocolMode() {
    protocolMode.value = protocolMode.value == 'HTTP' ? 'TCP' : 'HTTP';
  }

  bool get isTcpMode => protocolMode.value == 'TCP';

  /// Available protocols — computed from local flows
  final availableProtocols = <String>[].obs;

  /// Available content type categories — computed from local flows
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

  /// Recompute available filter options from the full local flow list.
  /// No API call — pure local computation.
  void recomputeFromFlows(List<FlowSummary> allFlows) {
    // Protocols: stable ordering
    const protoOrder = ['HTTP', 'HTTPS', 'H2', 'WS', 'WSS'];
    final protos = <String>{};
    final ctLabels = <String>{};

    for (final f in allFlows) {
      // Protocol
      final p = f.protocol.toUpperCase();
      if (p.isNotEmpty) protos.add(p);

      // Content type
      final ct = f.contentType.toLowerCase();
      if (ct.isNotEmpty) {
        for (final entry in _contentTypeCategories.entries) {
          if (ct.contains(entry.key)) {
            ctLabels.add(entry.value);
            break;
          }
        }
      }
    }

    availableProtocols.value = protoOrder.where(protos.contains).toList();

    const ctOrder = ['JSON', 'IMG', 'TEXT', 'JS', 'CSS', 'HTML', 'XML', 'Font', 'Video', 'Audio', 'PDF'];
    availableContentTypes.value = ctOrder.where(ctLabels.contains).toList();
  }

  /// Incrementally add a single flow's protocol/contentType to available filters.
  /// No API call.
  void addFlowToFilters(FlowSummary flow) {
    // Protocol
    final p = flow.protocol.toUpperCase();
    if (p.isNotEmpty && !availableProtocols.contains(p)) {
      const protoOrder = ['HTTP', 'HTTPS', 'H2', 'WS', 'WSS'];
      if (protoOrder.contains(p)) {
        final newList = [...availableProtocols, p];
        newList.sort((a, b) => protoOrder.indexOf(a).compareTo(protoOrder.indexOf(b)));
        availableProtocols.value = newList;
      }
    }

    // Content type
    final ct = flow.contentType.toLowerCase();
    if (ct.isNotEmpty) {
      for (final entry in _contentTypeCategories.entries) {
        if (ct.contains(entry.key)) {
          final label = entry.value;
          if (!availableContentTypes.contains(label)) {
            const ctOrder = ['JSON', 'IMG', 'TEXT', 'JS', 'CSS', 'HTML', 'XML', 'Font', 'Video', 'Audio', 'PDF'];
            final newList = [...availableContentTypes, label];
            newList.sort((a, b) => ctOrder.indexOf(a).compareTo(ctOrder.indexOf(b)));
            availableContentTypes.value = newList;
          }
          break;
        }
      }
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
