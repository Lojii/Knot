# Knot Flutter UI P1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS desktop Flutter app for live network capture, connecting to the existing KnotWebService REST+WebSocket API.

**Architecture:** Flutter project at repo root with Swift packages under `native/`. GetX for state management. REST API for data queries, WebSocket for real-time push. Desktop three-panel layout: global bar → toolbar → filter bar → tree+content split → status bar.

**Tech Stack:** Flutter 3.x, Dart, GetX, http, web_socket_channel, multi_split_view

**Spec:** `docs/superpowers/specs/2026-03-22-knot-flutter-ui-design.md`

---

## File Structure

```
lib/
├── main.dart                              Entry point, GetX bindings, theme
├── app/
│   ├── routes.dart                        GetX route definitions
│   └── bindings.dart                      Global controller bindings
├── api/
│   ├── api_client.dart                    REST API client (http package)
│   └── ws_client.dart                     WebSocket client with auto-reconnect
├── models/
│   ├── task_model.dart                    TaskModel
│   ├── flow_summary.dart                  FlowSummary
│   ├── flow_detail.dart                   FlowDetail + ConnectionInfo
│   └── ws_message.dart                    WsMessage
├── controllers/
│   ├── task_controller.dart               Current task, task list
│   ├── flow_controller.dart               Flow list, filtering, search, selection
│   ├── live_controller.dart               WebSocket connection, event dispatch
│   ├── tree_controller.dart               Domain tree construction
│   ├── detail_controller.dart             Selected flow detail + payload
│   └── filter_controller.dart             Filter bar chip state
├── pages/
│   └── capture/
│       ├── capture_page.dart              Main capture layout (5 rows)
│       ├── global_bar.dart                Row 0: window controls, task, nav
│       ├── toolbar.dart                   Row 1: start/stop/clear/search
│       ├── filter_bar.dart                Row 2: protocol/type/status chips
│       ├── tree_panel.dart                Row 3 left: domain tree
│       ├── content_panel.dart             Row 3 right: tab container
│       ├── flow_table.dart                List tab: request table
│       ├── flow_detail_panel.dart         Detail: headers/body/timing tabs
│       └── status_bar.dart                Row 4: stats
├── widgets/
│   ├── key_value_table.dart               Reusable header/param display
│   ├── json_viewer.dart                   JSON formatting widget
│   └── connection_indicator.dart          🟢/🔴/🟡 status dot
└── theme/
    └── app_theme.dart                     Dark/light theme definitions
```

---

### Task 1: Create Flutter project and migrate Swift packages

**Files:**
- Create: `pubspec.yaml`, `lib/main.dart`, `.gitignore` (Flutter additions)
- Move: `LocalPackages/*` → `native/`
- Modify: `native/TunnelServices/Package.swift`, `native/KnotWebService/Package.swift` (verify paths)

- [ ] **Step 1: Create Flutter project in a new branch**

```bash
cd /Users/aa123/Documents/Knot-storage-redesign
git checkout -b feature/flutter-ui
flutter create --org com.knot --project-name knot --platforms macos,web .
```

This creates Flutter scaffolding in the current directory. If files conflict, Flutter will skip them.

- [ ] **Step 2: Move Swift packages to native/**

```bash
mkdir -p native
mv LocalPackages/KnotStorage native/
mv LocalPackages/KnotWebService native/
mv LocalPackages/TunnelServices native/
rmdir LocalPackages
```

- [ ] **Step 3: Update Package.swift relative paths**

In `native/TunnelServices/Package.swift`, update:
- `.package(path: "../KnotStorage")` — still correct (within native/)
- `.package(path: "../KnotWebService")` — still correct

In `native/KnotWebService/Package.swift`, update:
- `.package(path: "../KnotStorage")` — still correct

Verify: `swift build --package-path native/TunnelServices`

- [ ] **Step 4: Update .gitignore**

Append Flutter-specific entries:
```
# Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
build/
*.iml
.metadata
```

- [ ] **Step 5: Set up minimal main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() {
  runApp(const KnotApp());
}

class KnotApp extends StatelessWidget {
  const KnotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Knot',
      themeMode: ThemeMode.system,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('Knot - Coming Soon')),
      ),
    );
  }
}
```

- [ ] **Step 6: Add dependencies to pubspec.yaml**

```yaml
dependencies:
  flutter:
    sdk: flutter
  get: ^4.6.6
  http: ^1.2.0
  web_socket_channel: ^2.4.0
  multi_split_view: ^3.1.0
  google_fonts: ^6.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

Run: `flutter pub get`

- [ ] **Step 7: Verify macOS build**

Run: `flutter run -d macos`
Expected: Window opens with "Knot - Coming Soon"

- [ ] **Step 8: Add macOS entitlements**

In `macos/Runner/Release.entitlements` and `macos/Runner/DebugProfile.entitlements`, add:
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: create Flutter project, migrate Swift packages to native/"
```

---

### Task 2: Dart models + API client

**Files:**
- Create: `lib/models/task_model.dart`
- Create: `lib/models/flow_summary.dart`
- Create: `lib/models/flow_detail.dart`
- Create: `lib/models/ws_message.dart`
- Create: `lib/api/api_client.dart`
- Create: `lib/api/ws_client.dart`

- [ ] **Step 1: Create TaskModel**

`lib/models/task_model.dart`:
```dart
class TaskModel {
  final int id;
  final String name;
  final double createdAt;
  final double? startedAt;
  final double? stoppedAt;
  final int status;
  final int? flowCount;
  final int? uploadBytes;
  final int? downloadBytes;

  TaskModel({
    required this.id,
    required this.name,
    required this.createdAt,
    this.startedAt,
    this.stoppedAt,
    this.status = 0,
    this.flowCount,
    this.uploadBytes,
    this.downloadBytes,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
    id: json['id'] as int,
    name: (json['name'] as String?) ?? '',
    createdAt: (json['createdAt'] as num).toDouble(),
    startedAt: (json['startedAt'] as num?)?.toDouble(),
    stoppedAt: (json['stoppedAt'] as num?)?.toDouble(),
    status: (json['status'] as int?) ?? 0,
    flowCount: json['flowCount'] as int?,
    uploadBytes: json['uploadBytes'] as int?,
    downloadBytes: json['downloadBytes'] as int?,
  );
}
```

- [ ] **Step 2: Create FlowSummary**

`lib/models/flow_summary.dart`:
```dart
class FlowSummary {
  final String flowId;
  final String protocol;
  final String host;
  final int port;
  final double startedAt;
  final double? endedAt;
  final double? durationMs;
  final int uploadBytes;
  final int downloadBytes;
  final int status;
  final String summary;
  final String searchKey1; // method
  final String searchKey2; // uri
  final String searchKey3; // statusCode
  final String searchKey4; // contentType
  final int protoFlags;
  final int connReuse;

  FlowSummary({
    required this.flowId,
    required this.protocol,
    required this.host,
    this.port = 0,
    required this.startedAt,
    this.endedAt,
    this.durationMs,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.status = 0,
    this.summary = '',
    this.searchKey1 = '',
    this.searchKey2 = '',
    this.searchKey3 = '',
    this.searchKey4 = '',
    this.protoFlags = 0,
    this.connReuse = 0,
  });

  String get method => searchKey1;
  String get uri => searchKey2;
  String get statusCode => searchKey3;
  String get contentType => searchKey4;

  factory FlowSummary.fromJson(Map<String, dynamic> json) => FlowSummary(
    flowId: json['flowId'] as String,
    protocol: (json['protocol'] as String?) ?? '',
    host: (json['host'] as String?) ?? '',
    port: (json['port'] as int?) ?? 0,
    startedAt: (json['startedAt'] as num).toDouble(),
    endedAt: (json['endedAt'] as num?)?.toDouble(),
    durationMs: (json['durationMs'] as num?)?.toDouble(),
    uploadBytes: (json['uploadBytes'] as int?) ?? 0,
    downloadBytes: (json['downloadBytes'] as int?) ?? 0,
    status: (json['status'] as int?) ?? 0,
    summary: (json['summary'] as String?) ?? '',
    searchKey1: (json['searchKey1'] as String?) ?? '',
    searchKey2: (json['searchKey2'] as String?) ?? '',
    searchKey3: (json['searchKey3'] as String?) ?? '',
    searchKey4: (json['searchKey4'] as String?) ?? '',
    protoFlags: (json['protoFlags'] as int?) ?? 0,
    connReuse: (json['connReuse'] as int?) ?? 0,
  );
}
```

- [ ] **Step 3: Create FlowDetail + ConnectionInfo**

`lib/models/flow_detail.dart`:
```dart
class ConnectionInfo {
  final String srcIp, dstIp;
  final int srcPort, dstPort;
  final String state;
  final String? tlsVersion, tlsCipher, tlsSni;

  ConnectionInfo({
    this.srcIp = '', this.dstIp = '',
    this.srcPort = 0, this.dstPort = 0,
    this.state = '',
    this.tlsVersion, this.tlsCipher, this.tlsSni,
  });

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) => ConnectionInfo(
    srcIp: (json['srcIp'] as String?) ?? '',
    dstIp: (json['dstIp'] as String?) ?? '',
    srcPort: (json['srcPort'] as int?) ?? 0,
    dstPort: (json['dstPort'] as int?) ?? 0,
    state: (json['state'] as String?) ?? '',
    tlsVersion: json['tlsVersion'] as String?,
    tlsCipher: json['tlsCipher'] as String?,
    tlsSni: json['tlsSni'] as String?,
  );
}

class FlowDetail {
  final Map<String, dynamic> raw; // full JSON for metadata access
  final ConnectionInfo? connection;

  FlowDetail({required this.raw, this.connection});

  factory FlowDetail.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return FlowDetail(
      raw: data,
      connection: data['connection'] != null
        ? ConnectionInfo.fromJson(data['connection'] as Map<String, dynamic>)
        : null,
    );
  }

  String get flowId => raw['flowId'] as String? ?? '';
  double? get connectAt => (raw['connectAt'] as num?)?.toDouble();
  double? get connectedAt => (raw['connectedAt'] as num?)?.toDouble();
  double? get tlsDoneAt => (raw['tlsDoneAt'] as num?)?.toDouble();
  double? get reqEndAt => (raw['reqEndAt'] as num?)?.toDouble();
  double? get rspStartAt => (raw['rspStartAt'] as num?)?.toDouble();
}
```

- [ ] **Step 4: Create WsMessage**

`lib/models/ws_message.dart`:
```dart
import 'dart:convert';

class WsMessage {
  final String type;
  final Map<String, dynamic> data;

  WsMessage({required this.type, required this.data});

  factory WsMessage.fromRaw(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return WsMessage(
      type: json['type'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }
}
```

- [ ] **Step 5: Create ApiClient**

`lib/api/api_client.dart`:
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task_model.dart';
import '../models/flow_summary.dart';
import '../models/flow_detail.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _client = http.Client();

  ApiClient({this.baseUrl = 'http://localhost:9090'});

  Future<List<TaskModel>> getTasks() async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/tasks'))
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = json['data'] as List? ?? [];
    return list.map((e) => TaskModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<({List<FlowSummary> items, int total})> getFlows({
    required int taskId,
    int page = 1,
    int size = 50,
    String? protocol,
    String? host,
    String? keyword,
    String? status,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'size': '$size',
    };
    if (protocol != null) params['protocol'] = protocol;
    if (host != null) params['host'] = host;
    if (keyword != null) params['keyword'] = keyword;
    if (status != null) params['status'] = status;

    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/flows').replace(queryParameters: params);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final items = (data['items'] as List? ?? [])
        .map((e) => FlowSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (data['total'] as int?) ?? 0);
  }

  Future<FlowDetail> getFlowDetail(int taskId, String flowId) async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/tasks/$taskId/flows/$flowId'),
    ).timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return FlowDetail.fromJson(json);
  }

  Future<String> getPayload(int taskId, String flowId, String direction, {bool preview = false}) async {
    final url = '$baseUrl/api/tasks/$taskId/flows/$flowId/$direction${preview ? "?preview=true" : ""}';
    final resp = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    return resp.body;
  }

  Future<Map<String, dynamic>> getFlowStats(int taskId) async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/tasks/$taskId/flows/stats'))
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['data'] as Map<String, dynamic>? ?? {};
  }

  Future<bool> checkConnection() async {
    try {
      await _client.get(Uri.parse('$baseUrl/api/tasks')).timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}
```

- [ ] **Step 6: Create WsClient with auto-reconnect**

`lib/api/ws_client.dart`:
```dart
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/ws_message.dart';

enum WsStatus { disconnected, connecting, connected }

class WsClient {
  final String baseUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int? _taskId;

  final _messageController = StreamController<WsMessage>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  Stream<WsMessage> get messages => _messageController.stream;
  Stream<WsStatus> get statusStream => _statusController.stream;
  WsStatus _status = WsStatus.disconnected;
  WsStatus get status => _status;

  WsClient({this.baseUrl = 'ws://localhost:9090'});

  void connect({int? taskId}) {
    _taskId = taskId;
    _reconnectAttempts = 0;
    _doConnect();
  }

  void _doConnect() {
    _setStatus(WsStatus.connecting);
    final url = _taskId != null ? '$baseUrl/ws?taskId=$_taskId' : '$baseUrl/ws';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        (data) {
          _setStatus(WsStatus.connected);
          _reconnectAttempts = 0;
          try {
            _messageController.add(WsMessage.fromRaw(data as String));
          } catch (_) {}
        },
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
      );
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    _setStatus(WsStatus.disconnected);
    _subscription?.cancel();
    _channel = null;
    // Exponential backoff: 1s, 2s, 4s, 8s, max 30s
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30));
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _doConnect);
  }

  void switchTask(int taskId) {
    _taskId = taskId;
    disconnect();
    connect(taskId: taskId);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(WsStatus.disconnected);
  }

  void _setStatus(WsStatus s) {
    if (_status != s) {
      _status = s;
      _statusController.add(s);
    }
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }
}
```

- [ ] **Step 7: Verify build**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 8: Commit**

```bash
git add lib/models/ lib/api/
git commit -m "feat: add Dart models and API/WebSocket clients"
```

---

### Task 3: GetX Controllers

**Files:**
- Create: `lib/controllers/task_controller.dart`
- Create: `lib/controllers/flow_controller.dart`
- Create: `lib/controllers/live_controller.dart`
- Create: `lib/controllers/tree_controller.dart`
- Create: `lib/controllers/detail_controller.dart`
- Create: `lib/controllers/filter_controller.dart`

- [ ] **Step 1: Create TaskController**

`lib/controllers/task_controller.dart`:
```dart
import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/task_model.dart';

class TaskController extends GetxController {
  final ApiClient api;
  TaskController(this.api);

  final tasks = <TaskModel>[].obs;
  final currentTask = Rxn<TaskModel>();
  final isCapturing = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadTasks();
  }

  Future<void> loadTasks() async {
    try {
      final list = await api.getTasks();
      tasks.value = list;
      if (currentTask.value == null && list.isNotEmpty) {
        currentTask.value = list.first;
      }
    } catch (e) {
      // Connection error — handled by status indicator
    }
  }

  void selectTask(TaskModel task) {
    currentTask.value = task;
  }
}
```

- [ ] **Step 2: Create FilterController**

`lib/controllers/filter_controller.dart`:
```dart
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
```

- [ ] **Step 3: Create FlowController**

`lib/controllers/flow_controller.dart`:
```dart
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
        status: filter.statusParam,
      );
      if (append) {
        flows.addAll(result.items);
      } else {
        flows.value = result.items;
      }
      total.value = result.total;
    } catch (_) {}
    isLoading.value = false;
  }

  void loadMore() {
    _currentPage++;
    loadFlows(append: true);
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
```

- [ ] **Step 4: Create LiveController**

`lib/controllers/live_controller.dart`:
```dart
import 'dart:async';
import 'package:get/get.dart';
import '../api/ws_client.dart';
import '../models/flow_summary.dart';
import 'flow_controller.dart';

class LiveController extends GetxController {
  final WsClient ws;
  LiveController(this.ws);

  final wsStatus = WsStatus.disconnected.obs;
  StreamSubscription? _msgSub;
  StreamSubscription? _statusSub;

  // Metrics for status bar
  final requestCount = 0.obs;
  final uploadBytes = 0.obs;
  final downloadBytes = 0.obs;
  final memoryMB = 0.0.obs;
  final connectionCount = 0.obs;

  void connectToTask(int taskId) {
    _msgSub?.cancel();
    _statusSub?.cancel();

    ws.connect(taskId: taskId);

    _statusSub = ws.statusStream.listen((s) => wsStatus.value = s);
    _msgSub = ws.messages.listen((msg) {
      switch (msg.type) {
        case 'flow':
          final flow = FlowSummary.fromJson(msg.data);
          Get.find<FlowController>().addFlowFromPush(flow);
          requestCount.value++;
          break;
        case 'flow_update':
          Get.find<FlowController>().updateFlowFromPush(msg.data);
          break;
        case 'metrics':
          _updateMetrics(msg.data);
          break;
        case 'stats':
          _updateStats(msg.data);
          break;
      }
    });
  }

  void _updateMetrics(Map<String, dynamic> data) {
    final mem = data['memory'] as Map<String, dynamic>?;
    if (mem != null) memoryMB.value = (mem['rss_mb'] as num?)?.toDouble() ?? 0;
    final conn = data['connections'] as Map<String, dynamic>?;
    if (conn != null) connectionCount.value = (conn['pool_total'] as int?) ?? 0;
  }

  void _updateStats(Map<String, dynamic> data) {
    // Update status bar counters from stats push
  }

  @override
  void onClose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    ws.disconnect();
    super.onClose();
  }
}
```

- [ ] **Step 5: Create TreeController**

`lib/controllers/tree_controller.dart`:
```dart
import 'package:get/get.dart';
import '../models/flow_summary.dart';
import 'flow_controller.dart';

class TreeNode {
  final String label;
  final String? domain;
  final bool isGroup;
  final List<TreeNode> children;
  bool expanded;

  TreeNode({
    required this.label,
    this.domain,
    this.isGroup = false,
    this.children = const [],
    this.expanded = true,
  });
}

class TreeController extends GetxController {
  final tree = <TreeNode>[].obs;
  final selectedDomain = Rxn<String>();

  void buildTree(List<FlowSummary> flows) {
    final Map<String, List<FlowSummary>> grouped = {};
    for (final f in flows) {
      grouped.putIfAbsent(f.host, () => []).add(f);
    }

    final nodes = <TreeNode>[];
    for (final entry in grouped.entries) {
      nodes.add(TreeNode(
        label: entry.key,
        domain: entry.key,
        isGroup: true,
        children: entry.value.map((f) =>
          TreeNode(label: '${f.method} ${f.uri}', domain: entry.key)
        ).toList(),
      ));
    }

    // Sort by request count descending
    nodes.sort((a, b) => b.children.length.compareTo(a.children.length));
    tree.value = nodes;
  }

  void selectDomain(String? domain) {
    selectedDomain.value = domain;
  }
}
```

- [ ] **Step 6: Create DetailController**

`lib/controllers/detail_controller.dart`:
```dart
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
```

- [ ] **Step 7: Verify build**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 8: Commit**

```bash
git add lib/controllers/
git commit -m "feat: add GetX controllers (task, flow, live, tree, detail, filter)"
```

---

### Task 4: Theme + shared widgets

**Files:**
- Create: `lib/theme/app_theme.dart`
- Create: `lib/widgets/key_value_table.dart`
- Create: `lib/widgets/json_viewer.dart`
- Create: `lib/widgets/connection_indicator.dart`

- [ ] **Step 1: Create app_theme.dart**

Dark/light themes with monospace for code, system font for UI.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: Colors.blue,
    textTheme: GoogleFonts.interTextTheme(),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1a1a2e),
    colorSchemeSeed: Colors.blue,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  );

  static TextStyle mono(BuildContext context) => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    color: Theme.of(context).textTheme.bodyMedium?.color,
  );
}
```

- [ ] **Step 2: Create key_value_table.dart**

Reusable widget for displaying HTTP headers, query parameters, etc.

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class KeyValueTable extends StatelessWidget {
  final List<(String, String)> entries;
  const KeyValueTable({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      children: entries.map((e) => TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: SelectableText(e.$1,
              style: AppTheme.mono(context).copyWith(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: SelectableText(e.$2, style: AppTheme.mono(context)),
          ),
        ],
      )).toList(),
    );
  }
}
```

- [ ] **Step 3: Create connection_indicator.dart**

```dart
import 'package:flutter/material.dart';
import '../api/ws_client.dart';

class ConnectionIndicator extends StatelessWidget {
  final WsStatus status;
  const ConnectionIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      WsStatus.connected => (Colors.green, 'Connected'),
      WsStatus.connecting => (Colors.orange, 'Connecting...'),
      WsStatus.disconnected => (Colors.red, 'Disconnected'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
```

- [ ] **Step 4: Create a simple json_viewer.dart**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class JsonViewer extends StatelessWidget {
  final String jsonString;
  const JsonViewer({super.key, required this.jsonString});

  @override
  Widget build(BuildContext context) {
    String formatted;
    try {
      final obj = jsonDecode(jsonString);
      formatted = const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      formatted = jsonString;
    }
    return SelectableText(formatted, style: AppTheme.mono(context));
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add lib/theme/ lib/widgets/
git commit -m "feat: add theme and shared widgets (KeyValueTable, JsonViewer, ConnectionIndicator)"
```

---

### Task 5: Capture page layout (5 rows)

**Files:**
- Create: `lib/pages/capture/capture_page.dart`
- Create: `lib/pages/capture/global_bar.dart`
- Create: `lib/pages/capture/toolbar.dart`
- Create: `lib/pages/capture/filter_bar.dart`
- Create: `lib/pages/capture/status_bar.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Create capture_page.dart — main layout scaffold**

```dart
import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'global_bar.dart';
import 'toolbar.dart';
import 'filter_bar.dart';
import 'tree_panel.dart';
import 'content_panel.dart';
import 'status_bar.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const GlobalBar(),            // Row 0
          const CaptureToolbar(),       // Row 1
          const FilterBar(),            // Row 2
          Expanded(                     // Row 3
            child: MultiSplitView(
              axis: Axis.horizontal,
              initialAreas: [
                Area(minimalSize: 150, size: 220),
                Area(minimalSize: 300),
              ],
              children: const [
                TreePanel(),
                ContentPanel(),
              ],
            ),
          ),
          const CaptureStatusBar(),     // Row 4
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create global_bar.dart**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/live_controller.dart';
import '../../widgets/connection_indicator.dart';

class GlobalBar extends StatelessWidget {
  const GlobalBar({super.key});

  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final liveCtrl = Get.find<LiveController>();
    final theme = Theme.of(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 70), // Space for macOS traffic lights
          // Task name
          Obx(() => Text(
            taskCtrl.currentTask.value?.name.isNotEmpty == true
              ? taskCtrl.currentTask.value!.name
              : 'Task ${taskCtrl.currentTask.value?.id ?? "-"}',
            style: theme.textTheme.titleSmall,
          )),
          const SizedBox(width: 8),
          // Connection status
          Obx(() => ConnectionIndicator(status: liveCtrl.wsStatus.value)),
          const Spacer(),
          // History button
          IconButton(
            icon: const Icon(Icons.history, size: 18),
            tooltip: 'History',
            onPressed: () {/* P2 */},
          ),
          // Protocol / TCP toggle
          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 18),
            tooltip: 'Protocol ⇄ TCP/UDP',
            onPressed: () {/* P2 */},
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            tooltip: 'Settings',
            onPressed: () {/* P2 */},
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Create toolbar.dart**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/flow_controller.dart';

class CaptureToolbar extends StatelessWidget {
  const CaptureToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final taskCtrl = Get.find<TaskController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Obx(() => IconButton(
            icon: Icon(taskCtrl.isCapturing.value ? Icons.stop : Icons.play_arrow),
            color: taskCtrl.isCapturing.value ? Colors.red : Colors.green,
            tooltip: taskCtrl.isCapturing.value ? 'Stop' : 'Start',
            onPressed: () {/* platform channel P1 later */},
          )),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Clear',
            onPressed: () => flowCtrl.flows.clear(),
          ),
          const Spacer(),
          SizedBox(
            width: 240,
            height: 30,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onChanged: flowCtrl.search,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Create filter_bar.dart**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/filter_controller.dart';
import '../../controllers/flow_controller.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final filterCtrl = Get.find<FilterController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() => Row(
        children: [
          const Text('Proto: ', style: TextStyle(fontSize: 11)),
          ..._chips(['HTTP', 'HTTPS', 'WS', 'H2'], filterCtrl.activeProtocols, (p) {
            filterCtrl.toggleProtocol(p);
            flowCtrl.loadFlows();
          }),
          const SizedBox(width: 12),
          const Text('Status: ', style: TextStyle(fontSize: 11)),
          ..._chips(['2xx', '3xx', '4xx', '5xx'], filterCtrl.activeStatuses, (s) {
            filterCtrl.toggleStatus(s);
            flowCtrl.loadFlows();
          }),
        ],
      )),
    );
  }

  List<Widget> _chips(List<String> labels, Set<String> active, void Function(String) onTap) {
    return labels.map((label) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => onTap(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: active.contains(label) ? Colors.blue.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active.contains(label) ? Colors.blue : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Text(label, style: TextStyle(
            fontSize: 11,
            color: active.contains(label) ? Colors.blue : null,
          )),
        ),
      ),
    )).toList();
  }
}
```

- [ ] **Step 5: Create status_bar.dart**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/live_controller.dart';
import '../../controllers/flow_controller.dart';

class CaptureStatusBar extends StatelessWidget {
  const CaptureStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final liveCtrl = Get.find<LiveController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() => Row(
        children: [
          _item('${flowCtrl.total.value} requests'),
          _sep(),
          _item('⬆ ${_formatBytes(liveCtrl.uploadBytes.value)}'),
          _item(' ⬇ ${_formatBytes(liveCtrl.downloadBytes.value)}'),
          _sep(),
          _item('💾 ${liveCtrl.memoryMB.value.toStringAsFixed(0)} MB'),
          _sep(),
          _item('🔌 ${liveCtrl.connectionCount.value} conn'),
        ],
      )),
    );
  }

  Widget _item(String text) => Text(text, style: const TextStyle(fontSize: 11));
  Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Text('│', style: TextStyle(fontSize: 11, color: Colors.grey)),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
```

- [ ] **Step 6: Update main.dart with controller bindings**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'api/api_client.dart';
import 'api/ws_client.dart';
import 'controllers/task_controller.dart';
import 'controllers/flow_controller.dart';
import 'controllers/live_controller.dart';
import 'controllers/tree_controller.dart';
import 'controllers/detail_controller.dart';
import 'controllers/filter_controller.dart';
import 'pages/capture/capture_page.dart';
import 'theme/app_theme.dart';

void main() {
  final api = ApiClient();
  final ws = WsClient();

  Get.put(api);
  Get.put(ws);
  Get.put(FilterController());
  Get.put(TaskController(api));
  Get.put(FlowController(api));
  Get.put(LiveController(ws));
  Get.put(TreeController());
  Get.put(DetailController(api));

  runApp(const KnotApp());
}

class KnotApp extends StatelessWidget {
  const KnotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Knot',
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const CapturePage(),
    );
  }
}
```

- [ ] **Step 7: Verify macOS build**

Run: `flutter run -d macos`
Expected: Window shows the 5-row layout (global bar, toolbar, filter bar, empty content, status bar)

- [ ] **Step 8: Commit**

```bash
git add lib/
git commit -m "feat: capture page layout with global bar, toolbar, filter bar, status bar"
```

---

### Task 6: Tree panel + flow table + content panel

**Files:**
- Create: `lib/pages/capture/tree_panel.dart`
- Create: `lib/pages/capture/flow_table.dart`
- Create: `lib/pages/capture/content_panel.dart`

- [ ] **Step 1: Create tree_panel.dart**

Left sidebar showing domain-grouped tree. Read TreeController and FlowController to rebuild tree when flows change.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tree_controller.dart';
import '../../controllers/flow_controller.dart';

class TreePanel extends StatelessWidget {
  const TreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final treeCtrl = Get.find<TreeController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    // Rebuild tree when flows change
    ever(flowCtrl.flows, (_) => treeCtrl.buildTree(flowCtrl.flows));

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tree header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text('Domains', style: theme.textTheme.labelSmall),
                const Spacer(),
                Obx(() => Text('${treeCtrl.tree.length}',
                    style: TextStyle(fontSize: 10, color: theme.hintColor))),
              ],
            ),
          ),
          const Divider(height: 1),
          // "All" option
          Obx(() => ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('All Domains', style: TextStyle(fontSize: 12)),
            selected: treeCtrl.selectedDomain.value == null,
            onTap: () => treeCtrl.selectDomain(null),
          )),
          // Domain tree
          Expanded(
            child: Obx(() => ListView.builder(
              itemCount: treeCtrl.tree.length,
              itemBuilder: (ctx, i) {
                final node = treeCtrl.tree[i];
                return ExpansionTile(
                  dense: true,
                  initiallyExpanded: false,
                  title: Text(node.label, style: const TextStyle(fontSize: 12)),
                  trailing: Text('${node.children.length}',
                      style: TextStyle(fontSize: 10, color: theme.hintColor)),
                  onExpansionChanged: (_) => treeCtrl.selectDomain(node.domain),
                  children: node.children.map((child) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(child.label,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                    onTap: () {
                      treeCtrl.selectDomain(node.domain);
                      // Find and select the matching flow
                    },
                  )).toList(),
                );
              },
            )),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create flow_table.dart**

Request table with Method, Host, Path, Status, Size, Time columns.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/tree_controller.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/task_controller.dart';
import '../../models/flow_summary.dart';
import '../../theme/app_theme.dart';

class FlowTable extends StatelessWidget {
  const FlowTable({super.key});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final treeCtrl = Get.find<TreeController>();
    final theme = Theme.of(context);

    return Obx(() {
      var items = flowCtrl.flows.toList();
      // Filter by selected domain
      final domain = treeCtrl.selectedDomain.value;
      if (domain != null) {
        items = items.where((f) => f.host == domain).toList();
      }

      return Column(
        children: [
          // Table header
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
            ),
            child: const Row(
              children: [
                SizedBox(width: 60, child: Text('Method', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                SizedBox(width: 8),
                Expanded(flex: 2, child: Text('Host', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('Path', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                SizedBox(width: 50, child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                SizedBox(width: 70, child: Text('Size', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                SizedBox(width: 70, child: Text('Time', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          // Table body
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final f = items[i];
                final isSelected = flowCtrl.selectedFlow.value?.flowId == f.flowId;
                return _FlowRow(flow: f, isSelected: isSelected);
              },
            ),
          ),
        ],
      );
    });
  }
}

class _FlowRow extends StatelessWidget {
  final FlowSummary flow;
  final bool isSelected;
  const _FlowRow({required this.flow, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final detailCtrl = Get.find<DetailController>();
    final taskCtrl = Get.find<TaskController>();
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        flowCtrl.selectFlow(flow);
        final tid = taskCtrl.currentTask.value?.id;
        if (tid != null) {
          detailCtrl.loadDetail(tid, flow.flowId);
          detailCtrl.loadBodies(tid, flow.flowId);
        }
      },
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : null,
        child: Row(
          children: [
            SizedBox(width: 60, child: Text(_methodLabel(flow.method),
                style: TextStyle(fontSize: 11, color: _methodColor(flow.method)))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: Text(flow.host,
                style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            Expanded(flex: 3, child: Text(flow.uri,
                style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 50, child: Text(flow.statusCode,
                style: TextStyle(fontSize: 11, color: _statusColor(flow.statusCode)))),
            SizedBox(width: 70, child: Text(_formatSize(flow.downloadBytes),
                style: const TextStyle(fontSize: 11))),
            SizedBox(width: 70, child: Text(
                flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
                style: const TextStyle(fontSize: 11))),
          ],
        ),
      ),
    );
  }

  String _methodLabel(String m) => m.isNotEmpty ? m : '-';
  Color _methodColor(String m) => switch (m) {
    'GET' => Colors.green,
    'POST' => Colors.orange,
    'PUT' => Colors.blue,
    'DELETE' => Colors.red,
    _ => Colors.grey,
  };
  Color _statusColor(String s) {
    final code = int.tryParse(s) ?? 0;
    if (code >= 500) return Colors.red;
    if (code >= 400) return Colors.orange;
    if (code >= 300) return Colors.blue;
    if (code >= 200) return Colors.green;
    return Colors.grey;
  }
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  }
}
```

- [ ] **Step 3: Create content_panel.dart**

Right panel with tab switching (List / Waterfall / Dashboard) + detail below.

```dart
import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'flow_table.dart';
import 'flow_detail_panel.dart';

class ContentPanel extends StatefulWidget {
  const ContentPanel({super.key});
  @override
  State<ContentPanel> createState() => _ContentPanelState();
}

class _ContentPanelState extends State<ContentPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Tab bar
        Container(
          height: 32,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [
              Tab(text: 'List', height: 32),
              Tab(text: 'Waterfall', height: 32),     // P2
              Tab(text: 'Dashboard', height: 32),      // P2
            ],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // List tab: split into table + detail
              MultiSplitView(
                axis: Axis.vertical,
                initialAreas: [
                  Area(minimalSize: 100, size: 300),
                  Area(minimalSize: 100),
                ],
                children: const [
                  FlowTable(),
                  FlowDetailPanel(),
                ],
              ),
              // Waterfall tab (P2 placeholder)
              const Center(child: Text('Waterfall — coming in P2')),
              // Dashboard tab (P2 placeholder)
              const Center(child: Text('Dashboard — coming in P2')),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Create stub flow_detail_panel.dart**

Basic stub — Task 7 will implement fully.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/flow_controller.dart';

class FlowDetailPanel extends StatelessWidget {
  const FlowDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();

    return Obx(() {
      if (flowCtrl.selectedFlow.value == null) {
        return const Center(
          child: Text('Select a request to view details',
              style: TextStyle(color: Colors.grey)),
        );
      }
      return const Center(child: Text('Detail panel — next task'));
    });
  }
}
```

- [ ] **Step 5: Verify macOS build**

Run: `flutter run -d macos`
Expected: Full layout visible — global bar, toolbar, filter chips, tree on left, flow table on right, status bar at bottom

- [ ] **Step 6: Commit**

```bash
git add lib/pages/capture/
git commit -m "feat: tree panel, flow table, content panel with tab switching"
```

---

### Task 7: Flow detail panel (Headers / Body / Timing / Connection tabs)

**Files:**
- Modify: `lib/pages/capture/flow_detail_panel.dart`

- [ ] **Step 1: Implement flow_detail_panel.dart with tabs**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../widgets/key_value_table.dart';
import '../../widgets/json_viewer.dart';
import '../../theme/app_theme.dart';

class FlowDetailPanel extends StatelessWidget {
  const FlowDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final detailCtrl = Get.find<DetailController>();

    return Obx(() {
      if (flowCtrl.selectedFlow.value == null) {
        return const Center(
          child: Text('Select a request to view details',
              style: TextStyle(color: Colors.grey)),
        );
      }
      return DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Headers', height: 28),
                Tab(text: 'Body', height: 28),
                Tab(text: 'Timing', height: 28),
                Tab(text: 'Connection', height: 28),
              ],
            ),
            Expanded(
              child: Obx(() => TabBarView(
                children: [
                  _HeadersTab(detailCtrl: detailCtrl),
                  _BodyTab(detailCtrl: detailCtrl),
                  _TimingTab(detailCtrl: detailCtrl),
                  _ConnectionTab(detailCtrl: detailCtrl),
                ],
              )),
            ),
          ],
        ),
      );
    });
  }
}

class _HeadersTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _HeadersTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    final raw = detailCtrl.detail.value?.raw ?? {};
    final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
    final reqHeaders = (metadata['requestHeaders'] as List?)
        ?.map((e) => ((e as List).first as String, e.last as String))
        .toList() ?? [];
    final rspHeaders = (metadata['responseHeaders'] as List?)
        ?.map((e) => ((e as List).first as String, e.last as String))
        .toList() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Request Headers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          if (reqHeaders.isNotEmpty)
            KeyValueTable(entries: reqHeaders)
          else
            Text('No headers available', style: TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 12),
          Text('Response Headers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          if (rspHeaders.isNotEmpty)
            KeyValueTable(entries: rspHeaders)
          else
            Text('No headers available', style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}

class _BodyTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _BodyTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (detailCtrl.isLoadingBody.value) {
        return const Center(child: CircularProgressIndicator());
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request Body', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            detailCtrl.requestBody.value.isNotEmpty
                ? JsonViewer(jsonString: detailCtrl.requestBody.value)
                : Text('(empty)', style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 12),
            Text('Response Body', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            detailCtrl.responseBody.value.isNotEmpty
                ? JsonViewer(jsonString: detailCtrl.responseBody.value)
                : Text('(empty)', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      );
    });
  }
}

class _TimingTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _TimingTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    final d = detailCtrl.detail.value;
    if (d == null) return const SizedBox();

    final raw = d.raw;
    final started = (raw['startedAt'] as num?)?.toDouble() ?? 0;
    final ended = (raw['endedAt'] as num?)?.toDouble() ?? started;

    final events = <(String, double?)>[
      ('Connect', d.connectAt),
      ('Connected', d.connectedAt),
      ('TLS Done', d.tlsDoneAt),
      ('Request End', d.reqEndAt),
      ('Response Start', d.rspStartAt),
      ('Response End', ended > 0 ? ended : null),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: events.map((e) {
          final ms = e.$2 != null ? ((e.$2! - started) * 1000).toStringAsFixed(1) : '-';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 120, child: Text(e.$1, style: const TextStyle(fontSize: 12))),
                Text('${ms}ms', style: AppTheme.mono(context)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ConnectionTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _ConnectionTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    final conn = detailCtrl.detail.value?.connection;
    if (conn == null) return const Center(child: Text('No connection info'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: KeyValueTable(entries: [
        ('Source', '${conn.srcIp}:${conn.srcPort}'),
        ('Destination', '${conn.dstIp}:${conn.dstPort}'),
        ('State', conn.state),
        if (conn.tlsVersion != null && conn.tlsVersion!.isNotEmpty)
          ('TLS Version', conn.tlsVersion!),
        if (conn.tlsCipher != null && conn.tlsCipher!.isNotEmpty)
          ('Cipher', conn.tlsCipher!),
        if (conn.tlsSni != null && conn.tlsSni!.isNotEmpty)
          ('SNI', conn.tlsSni!),
      ]),
    );
  }
}
```

- [ ] **Step 2: Verify macOS build**

Run: `flutter run -d macos`
Expected: Click a flow row → detail panel shows Headers/Body/Timing/Connection tabs with data

- [ ] **Step 3: Commit**

```bash
git add lib/pages/capture/flow_detail_panel.dart
git commit -m "feat: flow detail panel with Headers, Body, Timing, Connection tabs"
```

---

### Task 8: Wire up startup — connect to API, load task, start WebSocket

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add startup logic**

After controllers are registered, check API connectivity, load tasks, connect WebSocket:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final api = ApiClient();
  final ws = WsClient();

  Get.put(api);
  Get.put(ws);
  Get.put(FilterController());
  Get.put(TaskController(api));
  Get.put(FlowController(api));
  Get.put(LiveController(ws));
  Get.put(TreeController());
  Get.put(DetailController(api));

  runApp(const KnotApp());

  // Startup sequence (after first frame)
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final taskCtrl = Get.find<TaskController>();
    final flowCtrl = Get.find<FlowController>();
    final liveCtrl = Get.find<LiveController>();

    // Wait for API to be available
    await taskCtrl.loadTasks();

    // If we have a task, load its flows and connect WS
    if (taskCtrl.currentTask.value != null) {
      final tid = taskCtrl.currentTask.value!.id;
      flowCtrl.setTaskId(tid);
      liveCtrl.connectToTask(tid);
    }
  });
}
```

- [ ] **Step 2: Add task switching reaction**

In TaskController, when currentTask changes, update flow and live controllers:

Add to `TaskController.selectTask()`:
```dart
void selectTask(TaskModel task) {
  currentTask.value = task;
  Get.find<FlowController>().setTaskId(task.id);
  Get.find<LiveController>().ws.switchTask(task.id);
  Get.find<DetailController>().clear();
}
```

- [ ] **Step 3: Verify full integration**

1. Start proxy: `swift test --package-path native/TunnelServices --filter testStartProxyForBrowserTest`
2. Run Flutter: `flutter run -d macos`
3. Make a request through proxy: `curl -x http://127.0.0.1:<PORT> http://httpbin.org/get`
4. Expected: Flow appears in the Flutter table in real-time via WebSocket push

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart lib/controllers/task_controller.dart
git commit -m "feat: wire startup — load tasks, connect WebSocket, real-time flow updates"
```
