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

class MapLocalRule {
  final bool enabled;
  final String urlPattern;
  final String? method;
  final int statusCode;
  final String filePath;
  final String responseHeaders;

  MapLocalRule({
    this.enabled = true,
    required this.urlPattern,
    this.method,
    this.statusCode = 200,
    this.filePath = '',
    this.responseHeaders = '',
  });

  MapLocalRule copyWith({
    bool? enabled,
    String? urlPattern,
    String? method,
    int? statusCode,
    String? filePath,
    String? responseHeaders,
  }) {
    return MapLocalRule(
      enabled: enabled ?? this.enabled,
      urlPattern: urlPattern ?? this.urlPattern,
      method: method ?? this.method,
      statusCode: statusCode ?? this.statusCode,
      filePath: filePath ?? this.filePath,
      responseHeaders: responseHeaders ?? this.responseHeaders,
    );
  }
}

class BreakpointRule {
  final bool enabled;
  final String urlPattern;
  final String? method;
  final String breakOn; // "request", "response", "both"
  final String comment;

  BreakpointRule({
    this.enabled = true,
    required this.urlPattern,
    this.method,
    this.breakOn = 'both',
    this.comment = '',
  });

  BreakpointRule copyWith({
    bool? enabled,
    String? urlPattern,
    String? method,
    String? breakOn,
    String? comment,
  }) {
    return BreakpointRule(
      enabled: enabled ?? this.enabled,
      urlPattern: urlPattern ?? this.urlPattern,
      method: method ?? this.method,
      breakOn: breakOn ?? this.breakOn,
      comment: comment ?? this.comment,
    );
  }
}

class ToolsController extends GetxController {
  // Map Remote rules
  final mapRemoteRules = <MapRemoteRule>[].obs;

  // Map Local rules
  final mapLocalRules = <MapLocalRule>[].obs;

  // Breakpoint rules
  final breakpointRules = <BreakpointRule>[].obs;

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

  // --- Map Local ---
  void addMapLocalRule(MapLocalRule rule) => mapLocalRules.add(rule);

  void removeMapLocalRule(int index) => mapLocalRules.removeAt(index);

  void toggleMapLocalRule(int index) {
    mapLocalRules[index] = mapLocalRules[index].copyWith(
      enabled: !mapLocalRules[index].enabled,
    );
  }

  void updateMapLocalRule(int index, MapLocalRule rule) {
    mapLocalRules[index] = rule;
  }

  // --- Breakpoint ---
  void addBreakpointRule(BreakpointRule rule) => breakpointRules.add(rule);

  void removeBreakpointRule(int index) => breakpointRules.removeAt(index);

  void toggleBreakpointRule(int index) {
    breakpointRules[index] = breakpointRules[index].copyWith(
      enabled: !breakpointRules[index].enabled,
    );
  }

  void updateBreakpointRule(int index, BreakpointRule rule) {
    breakpointRules[index] = rule;
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
