import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../widgets/key_value_table.dart';
import '../../widgets/body_viewer.dart';
import '../../theme/app_theme.dart';

class FlowDetailPanel extends StatelessWidget {
  const FlowDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final detailCtrl = Get.find<DetailController>();
    final theme = Theme.of(context);

    return Obx(() {
      if (flowCtrl.selectedFlow.value == null) {
        return Center(
          child: Text('Select a request to view details',
              style: TextStyle(color: theme.hintColor)),
        );
      }

      // Loading state: show spinner while detail is loading
      if (detailCtrl.isLoadingDetail.value) {
        return const Center(child: CircularProgressIndicator());
      }

      return DefaultTabController(
        length: 4,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Headers', height: AppTheme.detailTabHeight),
                Tab(text: 'Body', height: AppTheme.detailTabHeight),
                Tab(text: 'Timing', height: AppTheme.detailTabHeight),
                Tab(text: 'Connection', height: AppTheme.detailTabHeight),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _HeadersTab(detailCtrl: detailCtrl),
                  _BodyTab(detailCtrl: detailCtrl),
                  _TimingTab(detailCtrl: detailCtrl),
                  _ConnectionTab(detailCtrl: detailCtrl),
                ],
              ),
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
    final theme = Theme.of(context);
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final reqHeaders = (metadata['requestHeaders'] as List?)
          ?.map((e) => ((e as List).first as String, e.last as String))
          .toList() ?? [];
      final rspHeaders = (metadata['responseHeaders'] as List?)
          ?.map((e) => ((e as List).first as String, e.last as String))
          .toList() ?? [];

      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingSM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request Headers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMD)),
            if (reqHeaders.isNotEmpty)
              KeyValueTable(entries: reqHeaders)
            else
              Text('No headers available', style: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSizeSM)),
            const SizedBox(height: AppTheme.spacingMD),
            const Text('Response Headers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMD)),
            if (rspHeaders.isNotEmpty)
              KeyValueTable(entries: rspHeaders)
            else
              Text('No headers available', style: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSizeSM)),
          ],
        ),
      );
    });
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

      // Extract content-type from metadata
      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final rspHeaders = metadata['responseHeaders'] as List?;
      String responseContentType = '';
      String requestContentType = '';
      if (rspHeaders != null) {
        for (final h in rspHeaders) {
          final pair = h as List;
          if ((pair.first as String).toLowerCase() == 'content-type') {
            responseContentType = pair.last as String;
            break;
          }
        }
      }
      final reqHeaders = metadata['requestHeaders'] as List?;
      if (reqHeaders != null) {
        for (final h in reqHeaders) {
          final pair = h as List;
          if ((pair.first as String).toLowerCase() == 'content-type') {
            requestContentType = pair.last as String;
            break;
          }
        }
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingSM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request Body', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMD)),
            const SizedBox(height: AppTheme.spacingXS),
            BodyViewer(body: detailCtrl.requestBody.value, label: 'Request', contentType: requestContentType),
            const SizedBox(height: AppTheme.spacingMD),
            const Text('Response Body', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMD)),
            const SizedBox(height: AppTheme.spacingXS),
            BodyViewer(body: detailCtrl.responseBody.value, label: 'Response', contentType: responseContentType),
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
    return Obx(() {
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
        padding: const EdgeInsets.all(AppTheme.spacingSM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: events.map((e) {
            final ms = e.$2 != null ? ((e.$2! - started) * 1000).toStringAsFixed(1) : '-';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 120, child: Text(e.$1, style: const TextStyle(fontSize: AppTheme.fontSizeMD))),
                  Text('${ms}ms', style: AppTheme.mono(context)),
                ],
              ),
            );
          }).toList(),
        ),
      );
    });
  }
}

class _ConnectionTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _ConnectionTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final conn = detailCtrl.detail.value?.connection;
      if (conn == null) return const Center(child: Text('No connection info'));

      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingSM),
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
    });
  }
}
