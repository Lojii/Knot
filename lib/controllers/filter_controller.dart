import 'package:get/get.dart';

class FilterController extends GetxController {
  final activeProtocols = <String>{}.obs;
  final activeTypes = <String>{}.obs;
  final activeStatuses = <String>{}.obs;

  void toggleProtocol(String proto) {
    if (activeProtocols.contains(proto)) {
      activeProtocols.remove(proto);
    } else {
      activeProtocols.add(proto);
    }
  }

  void toggleType(String type) {
    if (activeTypes.contains(type)) {
      activeTypes.remove(type);
    } else {
      activeTypes.add(type);
    }
  }

  void toggleStatus(String status) {
    if (activeStatuses.contains(status)) {
      activeStatuses.remove(status);
    } else {
      activeStatuses.add(status);
    }
  }

  void clearAll() {
    activeProtocols.clear();
    activeTypes.clear();
    activeStatuses.clear();
  }

  String? get protocolParam => activeProtocols.isEmpty ? null : activeProtocols.join(',');
  String? get statusParam => activeStatuses.isEmpty ? null : activeStatuses.join(',');
}
