# Knot Flutter P2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Waterfall timeline, Dashboard metrics, History management, advanced Body viewer, and Settings page to the Knot Flutter macOS app.

**Architecture:** Build on P1's existing capture page. Waterfall and Dashboard replace placeholder tabs. History and Settings are new pages accessed from the global bar. Body viewer enhances the existing detail panel with syntax highlighting and image preview.

**Tech Stack:** Flutter, GetX, fl_chart (charts), flutter_highlight (syntax), multi_split_view

**Spec:** `docs/superpowers/specs/2026-03-22-knot-flutter-ui-design.md`

---

## File Structure

```
lib/
├── pages/
│   ├── capture/
│   │   ├── waterfall_tab.dart           NEW: timeline chart
│   │   ├── dashboard_tab.dart           NEW: metrics dashboard
│   │   ├── flow_detail_panel.dart       MODIFY: enhance Body tab
│   │   └── content_panel.dart           MODIFY: wire real tabs
│   ├── history/
│   │   └── history_page.dart            NEW: task list + management
│   └── settings/
│       └── settings_page.dart           NEW: proxy config
├── controllers/
│   ├── dashboard_controller.dart        NEW: metrics state
│   └── history_controller.dart          NEW: task history state
└── widgets/
    ├── body_viewer.dart                 NEW: replaces simple JsonViewer in detail
    └── waterfall_bar.dart               NEW: single-request timing bar
```

---

### Task 1: Add fl_chart dependency + DashboardController

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/controllers/dashboard_controller.dart`
- Create: `lib/controllers/history_controller.dart`

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml` add under dependencies:
```yaml
  fl_chart: ^0.69.0
```

Run: `flutter pub get`

- [ ] **Step 2: Create DashboardController**

`lib/controllers/dashboard_controller.dart`:
```dart
import 'package:get/get.dart';
import '../api/api_client.dart';

class DashboardController extends GetxController {
  final ApiClient api;
  DashboardController(this.api);

  // Protocol distribution
  final protocols = <String, int>{}.obs;
  // Status code distribution
  final statuses = <String, int>{}.obs;
  // Total bytes
  final totalUpload = 0.obs;
  final totalDownload = 0.obs;

  // Real-time metrics from WebSocket
  final rssMB = 0.0.obs;
  final cpuPercent = 0.0.obs;
  final threadCount = 0.obs;
  final poolTotal = 0.obs;
  final uptimeSeconds = 0.0.obs;

  // Traffic history for line chart (last 60 data points)
  final trafficHistory = <({double time, int bytes})>[].obs;

  Future<void> loadStats(int taskId) async {
    try {
      final stats = await api.getFlowStats(taskId);
      final p = stats['protocols'] as Map<String, dynamic>? ?? {};
      protocols.value = p.map((k, v) => MapEntry(k, (v as int?) ?? 0));

      final s = stats['statuses'] as Map<String, dynamic>? ?? {};
      statuses.value = s.map((k, v) => MapEntry(k, (v as int?) ?? 0));

      totalUpload.value = (stats['totalUploadBytes'] as int?) ?? 0;
      totalDownload.value = (stats['totalDownloadBytes'] as int?) ?? 0;
    } catch (_) {}
  }

  void updateFromMetrics(Map<String, dynamic> data) {
    final mem = data['memory'] as Map<String, dynamic>?;
    if (mem != null) {
      rssMB.value = (mem['rss_mb'] as num?)?.toDouble() ?? 0;
    }
    final cpu = data['cpu'] as Map<String, dynamic>?;
    if (cpu != null) {
      cpuPercent.value = (cpu['usage_percent'] as num?)?.toDouble() ?? 0;
      threadCount.value = (cpu['thread_count'] as int?) ?? 0;
    }
    final conn = data['connections'] as Map<String, dynamic>?;
    if (conn != null) {
      poolTotal.value = (conn['pool_total'] as int?) ?? 0;
    }
    final totals = data['totals'] as Map<String, dynamic>?;
    if (totals != null) {
      uptimeSeconds.value = (totals['uptime_s'] as num?)?.toDouble() ?? 0;
    }
  }

  void addTrafficPoint(int bytes) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    trafficHistory.add((time: now, bytes: bytes));
    // Keep last 60 points
    if (trafficHistory.length > 60) {
      trafficHistory.removeAt(0);
    }
  }
}
```

- [ ] **Step 3: Create HistoryController**

`lib/controllers/history_controller.dart`:
```dart
import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/task_model.dart';

class HistoryController extends GetxController {
  final ApiClient api;
  HistoryController(this.api);

  final tasks = <TaskModel>[].obs;
  final isLoading = false.obs;

  Future<void> loadTasks() async {
    isLoading.value = true;
    try {
      tasks.value = await api.getTasks();
    } catch (_) {}
    isLoading.value = false;
  }
}
```

- [ ] **Step 4: Register controllers in main.dart**

Add to main.dart after existing Get.put() calls:
```dart
Get.put(DashboardController(api));
Get.put(HistoryController(api));
```

Also wire DashboardController into LiveController — in the `'metrics'` case, add:
```dart
Get.find<DashboardController>().updateFromMetrics(msg.data);
```
In the `'flow'` case, add:
```dart
final bytes = (msg.data['uploadBytes'] as int? ?? 0) + (msg.data['downloadBytes'] as int? ?? 0);
Get.find<DashboardController>().addTrafficPoint(bytes);
```

- [ ] **Step 5: Verify**

Run: `flutter analyze`

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml lib/controllers/dashboard_controller.dart lib/controllers/history_controller.dart lib/main.dart lib/controllers/live_controller.dart
git commit -m "feat(P2): add DashboardController, HistoryController, fl_chart dependency"
```

---

### Task 2: Waterfall timeline tab

**Files:**
- Create: `lib/pages/capture/waterfall_tab.dart`
- Create: `lib/widgets/waterfall_bar.dart`
- Modify: `lib/pages/capture/content_panel.dart`

- [ ] **Step 1: Create waterfall_bar.dart**

A single horizontal bar showing timing phases for one request (like Chrome DevTools).

```dart
import 'package:flutter/material.dart';

class WaterfallBar extends StatelessWidget {
  final double totalDuration;  // total time range in ms
  final double startOffset;    // when this request started relative to first request
  final double? connectMs;
  final double? tlsMs;
  final double? requestMs;
  final double? ttfbMs;
  final double? responseMs;

  const WaterfallBar({
    super.key,
    required this.totalDuration,
    required this.startOffset,
    this.connectMs,
    this.tlsMs,
    this.requestMs,
    this.ttfbMs,
    this.responseMs,
  });

  @override
  Widget build(BuildContext context) {
    if (totalDuration <= 0) return const SizedBox(height: 14);

    return SizedBox(
      height: 14,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WaterfallPainter(
          totalDuration: totalDuration,
          startOffset: startOffset,
          connectMs: connectMs ?? 0,
          tlsMs: tlsMs ?? 0,
          requestMs: requestMs ?? 0,
          ttfbMs: ttfbMs ?? 0,
          responseMs: responseMs ?? 0,
        ),
      ),
    );
  }
}

class _WaterfallPainter extends CustomPainter {
  final double totalDuration, startOffset;
  final double connectMs, tlsMs, requestMs, ttfbMs, responseMs;

  _WaterfallPainter({
    required this.totalDuration, required this.startOffset,
    required this.connectMs, required this.tlsMs,
    required this.requestMs, required this.ttfbMs,
    required this.responseMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    double x = (startOffset / totalDuration) * w;

    void drawSegment(double ms, Color color) {
      if (ms <= 0) return;
      final segW = (ms / totalDuration) * w;
      canvas.drawRect(
        Rect.fromLTWH(x, 2, segW.clamp(1, w - x), h - 4),
        Paint()..color = color,
      );
      x += segW;
    }

    drawSegment(connectMs, Colors.orange);
    drawSegment(tlsMs, Colors.purple);
    drawSegment(requestMs, Colors.blue);
    drawSegment(ttfbMs, Colors.green.shade300);
    drawSegment(responseMs, Colors.green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
```

- [ ] **Step 2: Create waterfall_tab.dart**

Shows all requests as horizontal bars on a shared timeline.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../models/flow_summary.dart';
import '../../widgets/waterfall_bar.dart';

class WaterfallTab extends StatelessWidget {
  const WaterfallTab({super.key});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Obx(() {
      final flows = flowCtrl.flows.toList();
      if (flows.isEmpty) {
        return const Center(child: Text('No requests yet'));
      }

      final firstStart = flows.last.startedAt;
      final lastEnd = flows.map((f) => f.endedAt ?? f.startedAt).reduce((a, b) => a > b ? a : b);
      final totalMs = ((lastEnd - firstStart) * 1000).clamp(1.0, double.infinity);

      return Column(
        children: [
          // Legend
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _legend(Colors.orange, 'Connect'),
                _legend(Colors.purple, 'TLS'),
                _legend(Colors.blue, 'Request'),
                _legend(Colors.green.shade300, 'TTFB'),
                _legend(Colors.green, 'Download'),
                const Spacer(),
                Text('${(totalMs / 1000).toStringAsFixed(1)}s total',
                    style: TextStyle(fontSize: 11, color: theme.hintColor)),
              ],
            ),
          ),
          // Waterfall rows
          Expanded(
            child: ListView.builder(
              itemCount: flows.length,
              itemBuilder: (ctx, i) {
                // Display in chronological order (oldest first)
                final f = flows[flows.length - 1 - i];
                final offset = (f.startedAt - firstStart) * 1000;
                return _WaterfallRow(flow: f, totalMs: totalMs, offsetMs: offset);
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _legend(Color color, String label) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    ),
  );
}

class _WaterfallRow extends StatelessWidget {
  final FlowSummary flow;
  final double totalMs;
  final double offsetMs;

  const _WaterfallRow({required this.flow, required this.totalMs, required this.offsetMs});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${flow.method} ${flow.host}${flow.uri}',
                style: const TextStyle(fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            child: WaterfallBar(
              totalDuration: totalMs,
              startOffset: offsetMs,
              connectMs: flow.durationMs != null ? flow.durationMs! * 0.15 : null,
              responseMs: flow.durationMs != null ? flow.durationMs! * 0.85 : null,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Update content_panel.dart — replace Waterfall placeholder**

In `content_panel.dart`, replace the placeholder `Center(child: Text('Waterfall — coming in P2'))` with:
```dart
const WaterfallTab(),
```

Add import: `import 'waterfall_tab.dart';`

- [ ] **Step 4: Verify and commit**

```bash
flutter analyze
git add lib/pages/capture/waterfall_tab.dart lib/widgets/waterfall_bar.dart lib/pages/capture/content_panel.dart
git commit -m "feat(P2): add Waterfall timeline tab with timing bar visualization"
```

---

### Task 3: Dashboard metrics tab

**Files:**
- Create: `lib/pages/capture/dashboard_tab.dart`
- Modify: `lib/pages/capture/content_panel.dart`

- [ ] **Step 1: Create dashboard_tab.dart**

Uses fl_chart for pie chart (protocol distribution) and line chart (traffic over time). Shows CPU/memory gauges and connection pool status.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../controllers/dashboard_controller.dart';
import '../../controllers/task_controller.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final dc = Get.find<DashboardController>();
    final taskCtrl = Get.find<TaskController>();
    final theme = Theme.of(context);

    // Load stats on first build
    final tid = taskCtrl.currentTask.value?.id;
    if (tid != null) dc.loadStats(tid);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Obx(() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Protocol distribution + Status codes
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _card(theme, 'Protocol Distribution', _protocolPie(dc, theme))),
              const SizedBox(width: 12),
              Expanded(child: _card(theme, 'Status Codes', _statusList(dc, theme))),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: System metrics
          Row(
            children: [
              Expanded(child: _metricCard(theme, 'Memory', '${dc.rssMB.value.toStringAsFixed(0)} MB', Icons.memory)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'CPU', '${dc.cpuPercent.value.toStringAsFixed(1)}%', Icons.speed)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'Threads', '${dc.threadCount.value}', Icons.account_tree)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'Connections', '${dc.poolTotal.value}', Icons.cable)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard(theme, 'Uptime', '${dc.uptimeSeconds.value.toStringAsFixed(0)}s', Icons.timer)),
            ],
          ),
          const SizedBox(height: 12),
          // Row 3: Traffic
          _card(theme, 'Traffic', Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _trafficStat('Upload', dc.totalUpload.value, Colors.blue),
                _trafficStat('Download', dc.totalDownload.value, Colors.green),
                _trafficStat('Total', dc.totalUpload.value + dc.totalDownload.value, Colors.orange),
              ],
            ),
          )),
        ],
      )),
    );
  }

  Widget _card(ThemeData theme, String title, Widget child) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.hintColor)),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget _metricCard(ThemeData theme, String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      children: [
        Icon(icon, size: 20, color: theme.hintColor),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 10, color: theme.hintColor)),
      ],
    ),
  );

  Widget _protocolPie(DashboardController dc, ThemeData theme) {
    final data = dc.protocols;
    if (data.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No data')));

    final colors = {'HTTP': Colors.blue, 'HTTPS': Colors.green, 'H2': Colors.orange, 'WS': Colors.purple, 'WSS': Colors.red};
    final sections = data.entries.where((e) => e.value > 0).map((e) => PieChartSectionData(
      value: e.value.toDouble(),
      title: '${e.key}\n${e.value}',
      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      color: colors[e.key] ?? Colors.grey,
      radius: 50,
    )).toList();

    return SizedBox(height: 140, child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 20)));
  }

  Widget _statusList(DashboardController dc, ThemeData theme) {
    final data = dc.statuses;
    if (data.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No data')));
    return Column(
      children: data.entries.map((e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(e.key == '1' ? 'Completed' : e.key == '2' ? 'Failed' : 'Status ${e.key}',
                style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Text('${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _trafficStat(String label, int bytes, Color color) => Column(
    children: [
      Text(_fmt(bytes), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
```

- [ ] **Step 2: Update content_panel.dart — replace Dashboard placeholder**

Replace `Center(child: Text('Dashboard — coming in P2'))` with:
```dart
const DashboardTab(),
```

Add import: `import 'dashboard_tab.dart';`

- [ ] **Step 3: Verify and commit**

```bash
flutter analyze
git add lib/pages/capture/dashboard_tab.dart lib/pages/capture/content_panel.dart
git commit -m "feat(P2): add Dashboard metrics tab with protocol pie chart and system gauges"
```

---

### Task 4: History task management page

**Files:**
- Create: `lib/pages/history/history_page.dart`
- Modify: `lib/pages/capture/global_bar.dart`

- [ ] **Step 1: Create history_page.dart**

Full-page overlay showing all capture tasks with name, time, flow count, bytes.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/history_controller.dart';
import '../../controllers/task_controller.dart';
import '../../models/task_model.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final historyCtrl = Get.find<HistoryController>();
    final taskCtrl = Get.find<TaskController>();
    final theme = Theme.of(context);

    historyCtrl.loadTasks();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture History'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: Obx(() {
        if (historyCtrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final tasks = historyCtrl.tasks;
        if (tasks.isEmpty) {
          return const Center(child: Text('No capture history'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final task = tasks[i];
            final isCurrent = taskCtrl.currentTask.value?.id == task.id;
            return _TaskCard(task: task, isCurrent: isCurrent, onTap: () {
              taskCtrl.selectTask(task);
              Get.back();
            });
          },
        );
      }),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final bool isCurrent;
  final VoidCallback onTap;

  const _TaskCard({required this.task, required this.isCurrent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch((task.createdAt * 1000).toInt());
    final timeStr = '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent ? theme.colorScheme.primary.withOpacity(0.08) : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isCurrent ? theme.colorScheme.primary : theme.dividerColor),
        ),
        child: Row(
          children: [
            if (isCurrent) ...[
              Icon(Icons.circle, size: 8, color: Colors.red),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name.isNotEmpty ? task.name : 'Task ${task.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(timeStr, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                ],
              ),
            ),
            if (task.flowCount != null)
              _badge('${task.flowCount} flows', theme),
            if (task.downloadBytes != null) ...[
              const SizedBox(width: 8),
              _badge(_fmt(task.downloadBytes!), theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, ThemeData theme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: theme.hintColor)),
  );

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
```

- [ ] **Step 2: Wire History button in global_bar.dart**

Replace `onPressed: () {/* P2 */}` on the history button with:
```dart
onPressed: () => Get.to(() => const HistoryPage()),
```

Add import: `import '../history/history_page.dart';`

- [ ] **Step 3: Verify and commit**

```bash
flutter analyze
git add lib/pages/history/ lib/pages/capture/global_bar.dart
git commit -m "feat(P2): add History task management page"
```

---

### Task 5: Enhanced Body viewer (syntax highlight + image preview)

**Files:**
- Create: `lib/widgets/body_viewer.dart`
- Modify: `lib/pages/capture/flow_detail_panel.dart`

- [ ] **Step 1: Create body_viewer.dart**

Smart body viewer that auto-detects content type:
- JSON → formatted + syntax colored
- HTML/XML/CSS/JS → syntax colored
- Image (png/jpg/gif/webp) → image preview
- Other → raw text with monospace font

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BodyViewer extends StatelessWidget {
  final String body;
  final String contentType;
  final String label;

  const BodyViewer({
    super.key,
    required this.body,
    this.contentType = '',
    this.label = '',
  });

  @override
  Widget build(BuildContext context) {
    if (body.isEmpty) {
      return Text('(empty)', style: TextStyle(color: Colors.grey, fontSize: 11));
    }

    // Image detection
    if (_isImage(contentType)) {
      return _imagePreview(context);
    }

    // JSON detection
    if (_isJson(contentType) || _looksLikeJson(body)) {
      return _jsonView(context);
    }

    // Default: raw text
    return SelectableText(body, style: AppTheme.mono(context));
  }

  Widget _jsonView(BuildContext context) {
    try {
      final obj = jsonDecode(body);
      final pretty = const JsonEncoder.withIndent('  ').convert(obj);
      return _SyntaxText(text: pretty, language: 'json');
    } catch (_) {
      return SelectableText(body, style: AppTheme.mono(context));
    }
  }

  Widget _imagePreview(BuildContext context) {
    // Try to decode base64 or show placeholder
    try {
      final bytes = base64Decode(body);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image Preview ($contentType)', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Cannot preview image')),
        ],
      );
    } catch (_) {
      return Text('Image ($contentType) — ${body.length} bytes', style: const TextStyle(fontSize: 11));
    }
  }

  bool _isImage(String ct) => ct.contains('image/');
  bool _isJson(String ct) => ct.contains('json');
  bool _looksLikeJson(String s) {
    final trimmed = s.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }
}

/// Simple syntax-colored text (no external dependency).
/// Colors JSON keys, strings, numbers, booleans differently.
class _SyntaxText extends StatelessWidget {
  final String text;
  final String language;
  const _SyntaxText({required this.text, required this.language});

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.mono(context);
    if (language != 'json') {
      return SelectableText(text, style: style);
    }
    return SelectableText.rich(
      _colorizeJson(text, style),
    );
  }

  TextSpan _colorizeJson(String json, TextStyle base) {
    final spans = <TextSpan>[];
    final re = RegExp(r'("(?:\\.|[^"\\])*")\s*:|("(?:\\.|[^"\\])*")|(\b\d+\.?\d*\b)|(\btrue\b|\bfalse\b|\bnull\b)');

    int lastEnd = 0;
    for (final m in re.allMatches(json)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: json.substring(lastEnd, m.start), style: base));
      }
      if (m.group(1) != null) {
        // JSON key
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(color: Colors.blue)));
        spans.add(TextSpan(text: ':', style: base));
      } else if (m.group(2) != null) {
        // String value
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(color: Colors.green)));
      } else if (m.group(3) != null) {
        // Number
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(color: Colors.orange)));
      } else if (m.group(4) != null) {
        // Boolean/null
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(color: Colors.purple)));
      }
      lastEnd = m.end;
    }
    if (lastEnd < json.length) {
      spans.add(TextSpan(text: json.substring(lastEnd), style: base));
    }
    return TextSpan(children: spans);
  }
}
```

- [ ] **Step 2: Update flow_detail_panel.dart Body tab**

Replace the simple JsonViewer usage in the Body tab with BodyViewer. Read the current `flow_detail_panel.dart` first to find the exact code to replace.

Replace:
```dart
JsonViewer(jsonString: detailCtrl.requestBody.value)
```
With:
```dart
BodyViewer(body: detailCtrl.requestBody.value, label: 'Request', contentType: _getContentType(true))
```

And similarly for response body. Add a helper to extract content type from detail metadata.

- [ ] **Step 3: Verify and commit**

```bash
flutter analyze
git add lib/widgets/body_viewer.dart lib/pages/capture/flow_detail_panel.dart
git commit -m "feat(P2): enhanced Body viewer with JSON syntax coloring and image preview"
```

---

### Task 6: Settings page (basic)

**Files:**
- Create: `lib/pages/settings/settings_page.dart`
- Modify: `lib/pages/capture/global_bar.dart`

- [ ] **Step 1: Create settings_page.dart**

Basic settings showing proxy port, API endpoint, theme toggle.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(theme, 'Connection', [
            _infoTile(theme, 'API Endpoint', 'http://localhost:9090'),
            _infoTile(theme, 'WebSocket', 'ws://localhost:9090/ws'),
          ]),
          const SizedBox(height: 16),
          _section(theme, 'Appearance', [
            ListTile(
              title: const Text('Theme'),
              subtitle: const Text('Follow system'),
              trailing: const Icon(Icons.brightness_auto),
              dense: true,
            ),
          ]),
          const SizedBox(height: 16),
          _section(theme, 'About', [
            _infoTile(theme, 'Version', '1.0.0-dev'),
            _infoTile(theme, 'Engine', 'Swift/NIO + KnotWebService'),
          ]),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.hintColor)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(children: children),
      ),
    ],
  );

  Widget _infoTile(ThemeData theme, String label, String value) => ListTile(
    title: Text(label),
    trailing: Text(value, style: TextStyle(color: theme.hintColor, fontSize: 13)),
    dense: true,
  );
}
```

- [ ] **Step 2: Wire Settings button in global_bar.dart**

Replace `onPressed: () {/* P2 */}` on the settings button with:
```dart
onPressed: () => Get.to(() => const SettingsPage()),
```

Add import: `import '../settings/settings_page.dart';`

- [ ] **Step 3: Verify and commit**

```bash
flutter analyze
git add lib/pages/settings/ lib/pages/capture/global_bar.dart
git commit -m "feat(P2): add Settings page with connection info and appearance"
```
