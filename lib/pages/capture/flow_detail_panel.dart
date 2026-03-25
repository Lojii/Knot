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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final detailCtrl = Get.find<DetailController>();
    final theme = Theme.of(context);

    return Obx(() {
      if (flowCtrl.selectedFlow.value == null) {
        return Center(
          child: Text('detail.select_request'.tr,
              style: TextStyle(color: theme.hintColor)),
        );
      }

      if (detailCtrl.isLoadingDetail.value) {
        return const Center(child: CircularProgressIndicator());
      }

      return Column(
        children: [
          _actionBar(context, flowCtrl, detailCtrl),
          _tabBar(context),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DataTab(detailCtrl: detailCtrl),
                _DetailsTab(detailCtrl: detailCtrl),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _actionBar(BuildContext context, FlowController flowCtrl, DetailController detailCtrl) {
    return Container(
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
            label: Text('detail.edit_resend'.tr,
                style: TextStyle(fontSize: AppTheme.fontSize.sm)),
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
            label: Text('detail.copy_curl'.tr,
                style: TextStyle(fontSize: AppTheme.fontSize.sm)),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(BuildContext context) {
    final detailTab = AppTheme.mode(context).detailTab;
    final tabs = ['Data', 'Details'];

    return Container(
      height: AppTheme.sizing.detailTabHeight,
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.spacing.sm,
        vertical: 2,
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = _tabController.index == i;
          return GestureDetector(
            onTap: () => _tabController.animateTo(i),
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
    );
  }
}

// ===========================================================================
// Data Tab — horizontal split: Request (left) | Response (right)
// ===========================================================================

class _DataTab extends StatefulWidget {
  final DetailController detailCtrl;
  const _DataTab({required this.detailCtrl});

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> with TickerProviderStateMixin {
  late final TabController _reqTabCtrl;
  late final TabController _rspTabCtrl;

  @override
  void initState() {
    super.initState();
    _reqTabCtrl = TabController(length: 4, vsync: this);
    _rspTabCtrl = TabController(length: 3, vsync: this);
    _reqTabCtrl.addListener(() => setState(() {}));
    _rspTabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reqTabCtrl.dispose();
    _rspTabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Request
        Expanded(
          child: Column(
            children: [
              _subTabBar(context, 'REQUEST', _reqTabCtrl,
                  ['Headers', 'Body', 'Params', 'Cookies']),
              Expanded(
                child: TabBarView(
                  controller: _reqTabCtrl,
                  children: [
                    _RequestHeadersView(detailCtrl: widget.detailCtrl),
                    _RequestBodyView(detailCtrl: widget.detailCtrl),
                    _QueryParamsView(detailCtrl: widget.detailCtrl),
                    _RequestCookiesView(detailCtrl: widget.detailCtrl),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: Response
        Expanded(
          child: Column(
            children: [
              _subTabBar(context, 'RESPONSE', _rspTabCtrl,
                  ['Headers', 'Body', 'Cookies']),
              Expanded(
                child: TabBarView(
                  controller: _rspTabCtrl,
                  children: [
                    _ResponseHeadersView(detailCtrl: widget.detailCtrl),
                    _ResponseBodyView(detailCtrl: widget.detailCtrl),
                    _ResponseCookiesView(detailCtrl: widget.detailCtrl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _subTabBar(BuildContext context, String label,
      TabController controller, List<String> tabs) {
    final detailTab = AppTheme.mode(context).detailTab;
    return Container(
      height: AppTheme.sizing.detailTabHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppTheme.colors(context).textSecondary,
            ),
          ),
          SizedBox(width: AppTheme.spacing.sm),
          ...List.generate(tabs.length, (i) {
            final isActive = controller.index == i;
            return GestureDetector(
              onTap: () => controller.animateTo(i),
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
                    fontSize: AppTheme.fontSize.xs,
                    fontWeight:
                        isActive ? FontWeight.w500 : FontWeight.normal,
                    color: isActive
                        ? detailTab.activeText
                        : detailTab.inactiveText,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ===========================================================================
// Request sub-views
// ===========================================================================

class _RequestHeadersView extends StatelessWidget {
  final DetailController detailCtrl;
  const _RequestHeadersView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final reqHeaders = (metadata['requestHeaders'] as List?)
              ?.map((e) => ((e as List).first as String, e.last as String))
              .toList() ??
          [];

      if (reqHeaders.isEmpty) {
        return Center(
          child: Text('detail.no_headers'.tr,
              style: TextStyle(color: Theme.of(context).hintColor,
                  fontSize: AppTheme.fontSize.sm)),
        );
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: KeyValueTable(entries: reqHeaders),
      );
    });
  }
}

class _RequestBodyView extends StatelessWidget {
  final DetailController detailCtrl;
  const _RequestBodyView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (detailCtrl.isLoadingBody.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final reqHeaders = metadata['requestHeaders'] as List?;
      String contentType = '';
      if (reqHeaders != null) {
        for (final h in reqHeaders) {
          final pair = h as List;
          if ((pair.first as String).toLowerCase() == 'content-type') {
            contentType = pair.last as String;
            break;
          }
        }
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: BodyViewer(
          body: detailCtrl.requestBody.value,
          label: 'Request',
          contentType: contentType,
        ),
      );
    });
  }
}

class _QueryParamsView extends StatelessWidget {
  final DetailController detailCtrl;
  const _QueryParamsView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final uriStr = (raw['searchKey2'] as String?) ?? '';
      if (uriStr.isEmpty) {
        return Center(
          child: Text('detail.no_query'.tr,
              style: TextStyle(color: Theme.of(context).hintColor)),
        );
      }

      final uri = Uri.tryParse(
          uriStr.startsWith('http') ? uriStr : 'http://x$uriStr');
      final params = uri?.queryParametersAll ?? {};
      if (params.isEmpty) {
        return Center(
          child: Text('detail.no_query'.tr,
              style: TextStyle(color: Theme.of(context).hintColor)),
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
        child: KeyValueTable(entries: entries),
      );
    });
  }
}

class _RequestCookiesView extends StatelessWidget {
  final DetailController detailCtrl;
  const _RequestCookiesView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final reqHeaders = (metadata['requestHeaders'] as List?) ?? [];

      final cookies = <(String, String)>[];
      for (final h in reqHeaders) {
        final pair = h as List;
        if ((pair.first as String).toLowerCase() == 'cookie') {
          final cookieStr = pair.last as String;
          for (final c in cookieStr.split(';')) {
            final trimmed = c.trim();
            final eqIdx = trimmed.indexOf('=');
            if (eqIdx > 0) {
              cookies.add((trimmed.substring(0, eqIdx).trim(),
                  trimmed.substring(eqIdx + 1).trim()));
            } else if (trimmed.isNotEmpty) {
              cookies.add((trimmed, ''));
            }
          }
        }
      }

      if (cookies.isEmpty) {
        return Center(
          child: Text('detail.no_cookies'.tr,
              style: TextStyle(color: Theme.of(context).hintColor)),
        );
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: KeyValueTable(entries: cookies),
      );
    });
  }
}

// ===========================================================================
// Response sub-views
// ===========================================================================

class _ResponseHeadersView extends StatelessWidget {
  final DetailController detailCtrl;
  const _ResponseHeadersView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final rspHeaders = (metadata['responseHeaders'] as List?)
              ?.map((e) => ((e as List).first as String, e.last as String))
              .toList() ??
          [];

      if (rspHeaders.isEmpty) {
        return Center(
          child: Text('detail.no_headers'.tr,
              style: TextStyle(color: Theme.of(context).hintColor,
                  fontSize: AppTheme.fontSize.sm)),
        );
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: KeyValueTable(entries: rspHeaders),
      );
    });
  }
}

class _ResponseBodyView extends StatelessWidget {
  final DetailController detailCtrl;
  const _ResponseBodyView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (detailCtrl.isLoadingBody.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final rspHeaders = metadata['responseHeaders'] as List?;
      String contentType = '';
      if (rspHeaders != null) {
        for (final h in rspHeaders) {
          final pair = h as List;
          if ((pair.first as String).toLowerCase() == 'content-type') {
            contentType = pair.last as String;
            break;
          }
        }
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: BodyViewer(
          body: detailCtrl.responseBody.value,
          label: 'Response',
          contentType: contentType,
        ),
      );
    });
  }
}

class _ResponseCookiesView extends StatelessWidget {
  final DetailController detailCtrl;
  const _ResponseCookiesView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
      final rspHeaders = (metadata['responseHeaders'] as List?) ?? [];

      final cookies = <(String, String)>[];
      for (final h in rspHeaders) {
        final pair = h as List;
        if ((pair.first as String).toLowerCase() == 'set-cookie') {
          final cookieStr = pair.last as String;
          final eqIdx = cookieStr.indexOf('=');
          if (eqIdx > 0) {
            final name = cookieStr.substring(0, eqIdx).trim();
            final rest = cookieStr.substring(eqIdx + 1).trim();
            cookies.add((name, rest));
          } else {
            cookies.add((cookieStr, ''));
          }
        }
      }

      if (cookies.isEmpty) {
        return Center(
          child: Text('detail.no_cookies'.tr,
              style: TextStyle(color: Theme.of(context).hintColor)),
        );
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: KeyValueTable(entries: cookies),
      );
    });
  }
}

// ===========================================================================
// Details Tab — card-based wrap view
// ===========================================================================

class _DetailsTab extends StatelessWidget {
  final DetailController detailCtrl;
  const _DetailsTab({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = detailCtrl.detail.value;
      if (d == null) return const SizedBox();

      return LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - 12 * 3) / 2; // 2 cols, spacing=12
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildCard(context, 'TLS / SSL', cardWidth, _tlsContent(context, d)),
                _buildCard(context, 'CONNECTION', cardWidth, _connectionContent(context, d)),
                _buildCard(context, 'OVERVIEW', cardWidth, _overviewContent(context, d)),
                _buildCard(context, 'TIMING', cardWidth, _timingContent(context, d)),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildCard(BuildContext context, String title, double cardWidth,
      List<Widget> content) {
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.colors(context).surface,
        border: Border.all(color: AppTheme.colors(context).divider),
        borderRadius: BorderRadius.circular(AppTheme.radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppTheme.colors(context).textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...content,
        ],
      ),
    );
  }

  List<Widget> _tlsContent(BuildContext context, dynamic d) {
    final conn = d.connection;
    final raw = d.raw as Map<String, dynamic>;
    final certChainRef = raw['certChainRef'] as String?;

    if (conn == null &&
        (certChainRef == null || certChainRef.isEmpty)) {
      return [
        Text('detail.no_certificate'.tr,
            style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: AppTheme.fontSize.sm)),
      ];
    }

    final entries = <(String, String)>[];
    if (conn != null) {
      if (conn.tlsVersion != null && conn.tlsVersion!.isNotEmpty) {
        entries.add(('TLS Version', conn.tlsVersion!));
      }
      if (conn.tlsCipher != null && conn.tlsCipher!.isNotEmpty) {
        entries.add(('Cipher Suite', conn.tlsCipher!));
      }
      if (conn.tlsSni != null && conn.tlsSni!.isNotEmpty) {
        entries.add(('SNI', conn.tlsSni!));
      }
    }
    if (certChainRef != null && certChainRef.isNotEmpty) {
      entries.add(('Cert Chain', certChainRef));
    }

    if (entries.isEmpty) {
      return [
        Text('detail.no_certificate'.tr,
            style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: AppTheme.fontSize.sm)),
      ];
    }

    return entries
        .map((e) => _kvRow(context, e.$1, e.$2))
        .toList();
  }

  List<Widget> _connectionContent(BuildContext context, dynamic d) {
    final conn = d.connection;
    if (conn == null) {
      return [
        Text('detail.no_connection'.tr,
            style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: AppTheme.fontSize.sm)),
      ];
    }

    return [
      _kvRow(context, 'Source', '${conn.srcIp}:${conn.srcPort}'),
      _kvRow(context, 'Destination', '${conn.dstIp}:${conn.dstPort}'),
      _kvRow(context, 'State', conn.state),
    ];
  }

  List<Widget> _overviewContent(BuildContext context, dynamic d) {
    final raw = d.raw as Map<String, dynamic>;
    final started = (raw['startedAt'] as num?)?.toDouble() ?? 0;
    final ended = (raw['endedAt'] as num?)?.toDouble() ?? 0;
    final duration = (started > 0 && ended > started)
        ? '${((ended - started) * 1000).toStringAsFixed(1)} ms'
        : '-';

    final uploadBytes = raw['uploadBytes'] as num?;
    final downloadBytes = raw['downloadBytes'] as num?;

    String startedStr = '-';
    if (started > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
          (started * 1000).toInt());
      startedStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}.${dt.millisecond.toString().padLeft(3, '0')}';
    }

    return [
      _kvRow(context, 'Started', startedStr),
      _kvRow(context, 'Duration', duration),
      _kvRow(context, 'Upload',
          uploadBytes != null ? _formatBytes(uploadBytes.toInt()) : '-'),
      _kvRow(context, 'Download',
          downloadBytes != null ? _formatBytes(downloadBytes.toInt()) : '-'),
    ];
  }

  List<Widget> _timingContent(BuildContext context, dynamic d) {
    final raw = d.raw as Map<String, dynamic>;
    final started = (raw['startedAt'] as num?)?.toDouble() ?? 0;
    final ended = (raw['endedAt'] as num?)?.toDouble() ?? started;

    String ms(double? ts) {
      if (ts == null || started <= 0) return '-';
      return '${((ts - started) * 1000).toStringAsFixed(1)} ms';
    }

    return [
      _kvRow(context, 'Connect', ms(d.connectAt)),
      _kvRow(context, 'Connected', ms(d.connectedAt)),
      _kvRow(context, 'TLS Done', ms(d.tlsDoneAt)),
      _kvRow(context, 'Request End', ms(d.reqEndAt)),
      _kvRow(context, 'Response Start', ms(d.rspStartAt)),
      _kvRow(context, 'Response End', ms(ended > 0 ? ended : null)),
    ];
  }

  Widget _kvRow(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(key,
                style: TextStyle(
                    fontSize: AppTheme.fontSize.sm,
                    color: AppTheme.colors(context).textSecondary)),
          ),
          Expanded(
            child: Text(value, style: AppTheme.mono(context)),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
