import 'package:get/get.dart';

class MapRemoteRule {
  final bool enabled;
  final String matchPattern;
  final String? replaceScheme;
  final String? replaceHost;
  final int? replacePort;
  final String? replacePath;

  MapRemoteRule({
    this.enabled = true,
    required this.matchPattern,
    this.replaceScheme,
    this.replaceHost,
    this.replacePort,
    this.replacePath,
  });

  MapRemoteRule copyWith({
    bool? enabled,
    String? matchPattern,
    String? replaceScheme,
    String? replaceHost,
    int? replacePort,
    String? replacePath,
  }) {
    return MapRemoteRule(
      enabled: enabled ?? this.enabled,
      matchPattern: matchPattern ?? this.matchPattern,
      replaceScheme: replaceScheme ?? this.replaceScheme,
      replaceHost: replaceHost ?? this.replaceHost,
      replacePort: replacePort ?? this.replacePort,
      replacePath: replacePath ?? this.replacePath,
    );
  }

  /// Human-readable summary of replacement target.
  String get replacementSummary {
    final parts = <String>[];
    if (replaceScheme != null && replaceScheme!.isNotEmpty) {
      parts.add('$replaceScheme://');
    }
    if (replaceHost != null && replaceHost!.isNotEmpty) {
      parts.add(replaceHost!);
    }
    if (replacePort != null) {
      parts.add(':$replacePort');
    }
    if (replacePath != null && replacePath!.isNotEmpty) {
      parts.add(replacePath!);
    }
    return parts.isEmpty ? '(no change)' : parts.join();
  }
}

class ToolsController extends GetxController {
  // Map Remote rules
  final mapRemoteRules = <MapRemoteRule>[].obs;

  // Allow/Block lists
  final allowList = <String>[].obs;
  final blockList = <String>[].obs;

  // No Caching
  final noCachingEnabled = false.obs;

  // --- Map Remote ---
  void addMapRemoteRule(MapRemoteRule rule) => mapRemoteRules.add(rule);

  void removeMapRemoteRule(int index) => mapRemoteRules.removeAt(index);

  void toggleMapRemoteRule(int index) {
    mapRemoteRules[index] = mapRemoteRules[index].copyWith(
      enabled: !mapRemoteRules[index].enabled,
    );
  }

  void updateMapRemoteRule(int index, MapRemoteRule rule) {
    mapRemoteRules[index] = rule;
  }

  // --- Allow/Block ---
  void addToAllowList(String pattern) {
    if (pattern.isNotEmpty && !allowList.contains(pattern)) {
      allowList.add(pattern);
    }
  }

  void removeFromAllowList(int index) => allowList.removeAt(index);

  void addToBlockList(String pattern) {
    if (pattern.isNotEmpty && !blockList.contains(pattern)) {
      blockList.add(pattern);
    }
  }

  void removeFromBlockList(int index) => blockList.removeAt(index);

  // --- No Caching ---
  void toggleNoCaching() => noCachingEnabled.value = !noCachingEnabled.value;
}
