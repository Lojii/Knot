import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TagController extends GetxController {
  final _tags = <String, Color>{}.obs;      // flowId -> color
  final _comments = <String, String>{}.obs;  // flowId -> comment

  void setTag(String flowId, Color color) => _tags[flowId] = color;
  void removeTag(String flowId) => _tags.remove(flowId);
  Color? getTag(String flowId) => _tags[flowId];

  void setComment(String flowId, String comment) => _comments[flowId] = comment;
  void removeComment(String flowId) => _comments.remove(flowId);
  String? getComment(String flowId) => _comments[flowId];

  /// Predefined tag colors for the context menu.
  static const List<MapEntry<String, Color>> tagColors = [
    MapEntry('Red', Color(0xFFF44336)),
    MapEntry('Orange', Color(0xFFFF9800)),
    MapEntry('Yellow', Color(0xFFFFC107)),
    MapEntry('Green', Color(0xFF4CAF50)),
    MapEntry('Blue', Color(0xFF2196F3)),
    MapEntry('Purple', Color(0xFF9C27B0)),
  ];
}
