import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/page_controller.dart';
import '../../widgets/key_value_table.dart';
import '../../widgets/body_viewer.dart';
import '../../theme/app_theme.dart';
import '../../utils/curl_export.dart';
import '../../utils/request_sender.dart';

class FlowDetailPanel extends StatefulWidget {
  const FlowDetailPanel({super.key});

  @override
  State<FlowDetailPanel> createState() => _FlowDetailPanelState();
}

class _FlowDetailPanelState extends State<FlowDetailPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabCount = 7;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<String> get _tabs => [
    'tab.headers'.tr,
    'tab.body'.tr,
    'tab.query'.tr,
    'tab.cookies'.tr,
    'tab.timing'.tr,
    'tab.connection'.tr,
    'tab.certificate'.tr,
  ];

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final detailCtrl = Get.find<DetailController>();
    final theme = Theme.of(context);
    final detailTab = AppTheme.mode(context).detailTab;

    return Obx(() {
      if (flowCtrl.selectedFlow.value == null) {
        return Center(
          child: Text('detail.select_request'.tr,
              style: TextStyle(color: theme.hintColor)),
        );
      }

      // Loading state: show spinner while detail is loading
      if (detailCtrl.isLoadingDetail.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final tabs = _tabs;

      return Column(
        children: [
          // Toolbar with cURL export
          Container(
            height: AppTheme.sizing.toolbarHeight,
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
            child: Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final flow = flowCtrl.selectedFlow.value;
                    if (flow == null) return;
                    final raw = detailCtrl.detail.value?.raw ?? {};
                    final headers = RequestSender.extractHeaders(raw);
                    final url = RequestSender.buildUrl(flow);
                    final pageCtrl = Get.find<AppPageController>();
                    pageCtrl.openInCompose(
                      method: flow.method,
                      url: url,
                      headers: headers,
                    );
                  },
                  icon: const Icon(Icons.edit_note, size: 14),
                  label: Text('detail.edit_resend'.tr, style: TextStyle(fontSize: AppTheme.fontSize.sm)),
                ),
                TextButton.icon(
                  onPressed: () {
                    final raw = detailCtrl.detail.value?.raw ?? {};
                    final curl = CurlExport.fromFlowDetail(raw);
                    Clipboard.setData(ClipboardData(text: curl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('detail.curl_copied'.tr),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 14),
                  label: Text('detail.copy_curl'.tr, style: TextStyle(fontSize: AppTheme.fontSize.sm)),
                ),
              ],
            ),
          ),
          // Custom segmented-control tab row
          Container(
            height: AppTheme.sizing.detailTabHeight,
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.spacing.sm,
              vertical: 2,
            ),
            child: Row(
              children: List.generate(tabs.length, (i) {
                final isActive = _tabController.index == i;
                return GestureDetector(
                  onTap: () {
                    _tabController.animateTo(i);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? detailTab.activeBackground
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(detailTab.radius),
                    ),
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: AppTheme.fontSize.sm,
                        fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                        color: isActive
                            ? detailTab.activeText
                            : detailTab.inactiveText,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _HeadersTab(detailCtrl: detailCtrl),
                _BodyTab(detailCtrl: detailCtrl),
                _QueryTab(detailCtrl: detailCtrl),
                _CookiesTab(detailCtrl: detailCtrl),
                _TimingTab(detailCtrl: detailCtrl),
                _ConnectionTab(detailCtrl: detailCtrl),
                _CertificateTab(detailCtrl: detailCtrl),
              ],
            ),
          ),
        ],
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
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('detail.request_headers'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
            if (reqHeaders.isNotEmpty)
              KeyValueTable(entries: reqHeaders)
            else
              Text('detail.no_headers'.tr, style: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSize.sm)),
            SizedBox(height: AppTheme.spacing.md),
            Text('detail.response_headers'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
            if (rspHeaders.isNotEmpty)
              KeyValueTable(entries: rspHeaders)
            else
              Text('detail.no_headers'.tr, style: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSize.sm)),
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
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('detail.request_body'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
            SizedBox(height: AppTheme.spacing.xs),
            BodyViewer(body: detailCtrl.requestBody.value, label: 'Request', contentType: requestContentType),
            SizedBox(height: AppTheme.spacing.md),
            Text('detail.response_body'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
            SizedBox(height: AppTheme.spacing.xs),
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
        ('timing.connect'.tr, d.connectAt),
        ('timing.connected'.tr, d.connectedAt),
        ('timing.tls_done'.tr, d.tlsDoneAt),
        ('timing.request_end'.tr, d.reqEndAt),
        ('timing.response_start'.tr, d.rspStartAt),
        ('timing.response_end'.tr, ended > 0 ? ended : null),
      ];

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: events.map((e) {
            final ms = e.$2 != null ? ((e.$2! - started) * 1000).toStringAsFixed(1) : '-';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 120, child: Text(e.$1, style: TextStyle(fontSize: AppTheme.fontSize.md))),
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
      if (conn == null) return Center(child: Text('detail.no_connection'.tr));

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: KeyValueTable(entries: [
          ('detail.source'.tr, '${conn.srcIp}:${conn.srcPort}'),
          ('detail.destination'.tr, '${conn.dstIp}:${conn.dstPort}'),
          ('detail.state'.tr, conn.state),
          if (conn.tlsVersion != null && conn.tlsVersion!.isNotEmpty)
            ('detail.tls_version'.tr, conn.tlsVersion!),
          if (conn.tlsCipher != null && conn.tlsCipher!.isNotEmpty)
            ('detail.cipher'.tr, conn.tlsCipher!),
          if (conn.tlsSni != null && conn.tlsSni!.isNotEmpty)
            ('detail.sni'.tr, conn.tlsSni!),
        ]),
      );
    });
  }
}

class _QueryTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _QueryTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final uriStr = (raw['searchKey2'] as String?) ?? '';
      if (uriStr.isEmpty) {
        return Center(
          child: Text('detail.no_query'.tr, style: TextStyle(color: theme.hintColor)),
        );
      }

      // Parse query parameters from the URI
      final uri = Uri.tryParse(uriStr.startsWith('http') ? uriStr : 'http://x$uriStr');
      final params = uri?.queryParametersAll ?? {};
      if (params.isEmpty) {
        return Center(
          child: Text('detail.no_query'.tr, style: TextStyle(color: theme.hintColor)),
        );
      }

      final entries = <(String, String)>[];
      for (final entry in params.entries) {
        for (final val in entry.value) {
          entries.add((entry.key, val));
        }
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('detail.query_params'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
            KeyValueTable(entries: entries),
          ],
        ),
      );
    });
  }
}

class _CookiesTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _CookiesTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final reqHeaders = (metadata['requestHeaders'] as List?) ?? [];
      final rspHeaders = (metadata['responseHeaders'] as List?) ?? [];

      // Extract Cookie header from request
      final reqCookies = <(String, String)>[];
      for (final h in reqHeaders) {
        final pair = h as List;
        if ((pair.first as String).toLowerCase() == 'cookie') {
          final cookieStr = pair.last as String;
          for (final c in cookieStr.split(';')) {
            final trimmed = c.trim();
            final eqIdx = trimmed.indexOf('=');
            if (eqIdx > 0) {
              reqCookies.add((trimmed.substring(0, eqIdx).trim(), trimmed.substring(eqIdx + 1).trim()));
            } else if (trimmed.isNotEmpty) {
              reqCookies.add((trimmed, ''));
            }
          }
        }
      }

      // Extract Set-Cookie headers from response
      final rspCookies = <(String, String)>[];
      for (final h in rspHeaders) {
        final pair = h as List;
        if ((pair.first as String).toLowerCase() == 'set-cookie') {
          final cookieStr = pair.last as String;
          final eqIdx = cookieStr.indexOf('=');
          if (eqIdx > 0) {
            final name = cookieStr.substring(0, eqIdx).trim();
            final rest = cookieStr.substring(eqIdx + 1).trim();
            rspCookies.add((name, rest));
          } else {
            rspCookies.add((cookieStr, ''));
          }
        }
      }

      if (reqCookies.isEmpty && rspCookies.isEmpty) {
        return Center(
          child: Text('detail.no_cookies'.tr, style: TextStyle(color: theme.hintColor)),
        );
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reqCookies.isNotEmpty) ...[
              Text('detail.request_cookies'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
              KeyValueTable(entries: reqCookies),
              SizedBox(height: AppTheme.spacing.md),
            ],
            if (rspCookies.isNotEmpty) ...[
              Text('detail.response_cookies'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
              KeyValueTable(entries: rspCookies),
            ],
          ],
        ),
      );
    });
  }
}

class _CertificateTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _CertificateTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final conn = detailCtrl.detail.value?.connection;
      final raw = detailCtrl.detail.value?.raw ?? {};

      final hasTls = conn != null &&
          conn.tlsVersion != null &&
          conn.tlsVersion!.isNotEmpty;
      final certChainRef = raw['certChainRef'] as String?;

      if (!hasTls && (certChainRef == null || certChainRef.isEmpty)) {
        return Center(
          child: Text('detail.no_certificate'.tr, style: TextStyle(color: theme.hintColor)),
        );
      }

      final entries = <(String, String)>[];
      if (conn != null) {
        if (conn.tlsVersion != null && conn.tlsVersion!.isNotEmpty) {
          entries.add(('detail.tls_version'.tr, conn.tlsVersion!));
        }
        if (conn.tlsCipher != null && conn.tlsCipher!.isNotEmpty) {
          entries.add(('detail.cipher_suite'.tr, conn.tlsCipher!));
        }
        if (conn.tlsSni != null && conn.tlsSni!.isNotEmpty) {
          entries.add(('detail.sni'.tr, conn.tlsSni!));
        }
      }
      if (certChainRef != null && certChainRef.isNotEmpty) {
        entries.add(('detail.cert_chain_ref'.tr, certChainRef));
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('detail.tls_certificate'.tr, style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.fontSize.md, color: AppTheme.colors(context).textSecondary)),
            KeyValueTable(entries: entries),
          ],
        ),
      );
    });
  }
}
