import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/detail_panel_controller.dart';
import '../../controllers/task_scope.dart';
import '../../models/flow_summary.dart';
import '../../widgets/key_value_table.dart';
import '../../widgets/body_viewer.dart';
import '../../theme/app_theme.dart';
import 'package:multi_split_view/multi_split_view.dart';

// ============================================================
// FlowDetailPanel — main container
// ============================================================

class FlowDetailPanel extends StatelessWidget {
  const FlowDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final selCtrl = TaskScope.selection;
      final flow = selCtrl.selectedFlow.value;

      if (flow == null) {
        return Center(
          child: Text('detail.select_request'.tr,
              style: TextStyle(color: theme.hintColor)),
        );
      }

      final detailCtrl = TaskScope.detail;
      if (detailCtrl.isLoadingDetail.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final panelCtrl = TaskScope.detailPanel;
      final activeTab = panelCtrl.activeTab.value;

      return Column(
        children: [
          _TitleBar(flow: flow, panelCtrl: panelCtrl),
          Expanded(
            child: activeTab == 0
                ? _DataView(detailCtrl: detailCtrl, panelCtrl: panelCtrl)
                : _DetailsView(detailCtrl: detailCtrl),
          ),
        ],
      );
    });
  }
}

// ============================================================
// 1. TitleBar — method, url, status, time on left; tab buttons on right
// ============================================================

class _TitleBar extends StatelessWidget {
  final FlowSummary flow;
  final DetailPanelController panelCtrl;
  const _TitleBar({required this.flow, required this.panelCtrl});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final detailTab = AppTheme.mode(context).detailTab;

    final statusCode = int.tryParse(flow.statusCode) ?? 0;
    final statusColor = AppTheme.statusColorOf(context, statusCode);
    final methodColor = AppTheme.methodColorOf(context, flow.method);
    final url = '${flow.protocol.toLowerCase()}://${flow.host}${flow.uri}';
    final time = _formatTime(flow.startedAt);

    return Container(
      height: AppTheme.sizing.toolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          // Method
          Text(flow.method,
              style: TextStyle(
                  fontSize: AppTheme.fontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: methodColor)),
          SizedBox(width: AppTheme.spacing.sm),
          // URL — flexible, ellipsis
          Expanded(
            child: Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTheme.fontSize.sm, color: colors.textPrimary)),
          ),
          SizedBox(width: AppTheme.spacing.sm),
          // Status code
          if (flow.statusCode.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(25),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(flow.statusCode,
                  style: TextStyle(
                      fontSize: AppTheme.fontSize.xs,
                      fontWeight: FontWeight.w600,
                      color: statusColor)),
            ),
          SizedBox(width: AppTheme.spacing.sm),
          // Time
          Text(time,
              style: TextStyle(
                  fontSize: AppTheme.fontSize.xs, color: colors.textSecondary)),
          SizedBox(width: AppTheme.spacing.lg),
          // Tab buttons: Data / Details
          Obx(() {
            final active = panelCtrl.activeTab.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tabButton(context, 'detail.data'.tr, 0, active, detailTab),
                const SizedBox(width: 2),
                _tabButton(context, 'detail.details'.tr, 1, active, detailTab),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _tabButton(BuildContext context, String label, int index, int active,
      DetailTabConfig detailTab) {
    final isActive = active == index;
    return GestureDetector(
      onTap: () => panelCtrl.switchTab(index),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: AppTheme.spacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color:
                isActive ? detailTab.activeBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(detailTab.radius),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: AppTheme.fontSize.xs,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                color: isActive
                    ? detailTab.activeText
                    : detailTab.inactiveText,
              )),
        ),
      ),
    );
  }

  String _formatTime(double ts) {
    if (ts <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    return '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// ============================================================
// 2. DataView — Request (left) | Response (right) split
// ============================================================

class _DataView extends StatelessWidget {
  final DetailController detailCtrl;
  final DetailPanelController panelCtrl;
  const _DataView({required this.detailCtrl, required this.panelCtrl});

  @override
  Widget build(BuildContext context) {
    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerPainter: DividerPainters.background(
          color: AppTheme.colors(context).divider,
          highlightedColor: AppTheme.colors(context).primary.withAlpha(80),
        ),
        dividerThickness: 1,
      ),
      child: MultiSplitView(
        axis: Axis.horizontal,
        initialAreas: [
          Area(
            min: 150,
            builder: (context, area) =>
                _RequestSection(detailCtrl: detailCtrl, panelCtrl: panelCtrl),
          ),
          Area(
            min: 150,
            builder: (context, area) =>
                _ResponseSection(detailCtrl: detailCtrl, panelCtrl: panelCtrl),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 2.1 RequestSection
// ============================================================

class _RequestSection extends StatelessWidget {
  final DetailController detailCtrl;
  final DetailPanelController panelCtrl;
  const _RequestSection({required this.detailCtrl, required this.panelCtrl});

  @override
  Widget build(BuildContext context) {
    final tabs = ['Headers', 'Body', 'Params', 'Cookies'];

    return Column(
      children: [
        _SubTabBar(
          label: 'REQUEST',
          tabs: tabs,
          activeIndex: panelCtrl.requestSubTab,
          onTap: panelCtrl.switchRequestSubTab,
        ),
        Expanded(
          child: Obx(() {
            switch (panelCtrl.requestSubTab.value) {
              case 0:
                return _RequestHeadersView(detailCtrl: detailCtrl);
              case 1:
                return _RequestBodyView(detailCtrl: detailCtrl);
              case 2:
                return _QueryParamsView(detailCtrl: detailCtrl);
              case 3:
                return _RequestCookiesView(detailCtrl: detailCtrl);
              default:
                return const SizedBox();
            }
          }),
        ),
      ],
    );
  }
}

// ============================================================
// 2.2 ResponseSection
// ============================================================

class _ResponseSection extends StatelessWidget {
  final DetailController detailCtrl;
  final DetailPanelController panelCtrl;
  const _ResponseSection({required this.detailCtrl, required this.panelCtrl});

  @override
  Widget build(BuildContext context) {
    final tabs = ['Headers', 'Body', 'Cookies'];

    return Column(
      children: [
        _SubTabBar(
          label: 'RESPONSE',
          tabs: tabs,
          activeIndex: panelCtrl.responseSubTab,
          onTap: panelCtrl.switchResponseSubTab,
        ),
        Expanded(
          child: Obx(() {
            switch (panelCtrl.responseSubTab.value) {
              case 0:
                return _ResponseHeadersView(detailCtrl: detailCtrl);
              case 1:
                return _ResponseBodyView(detailCtrl: detailCtrl);
              case 2:
                return _ResponseCookiesView(detailCtrl: detailCtrl);
              default:
                return const SizedBox();
            }
          }),
        ),
      ],
    );
  }
}

// ============================================================
// Shared SubTabBar
// ============================================================

class _SubTabBar extends StatelessWidget {
  final String label;
  final List<String> tabs;
  final RxInt activeIndex;
  final void Function(int) onTap;
  const _SubTabBar({
    required this.label,
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final detailTab = AppTheme.mode(context).detailTab;
    return Container(
      height: AppTheme.sizing.detailTabHeight,
      padding:
          EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
      child: Obx(() {
        final active = activeIndex.value;
        return Row(
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: AppTheme.fontSize.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppTheme.colors(context).textSecondary,
                )),
            SizedBox(width: AppTheme.spacing.sm),
            ...List.generate(tabs.length, (i) {
              final isActive = active == i;
              return GestureDetector(
                onTap: () => onTap(i),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: isActive
                          ? detailTab.activeBackground
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(detailTab.radius),
                    ),
                    child: Text(tabs[i],
                        style: TextStyle(
                          fontSize: AppTheme.fontSize.xs,
                          fontWeight:
                              isActive ? FontWeight.w500 : FontWeight.normal,
                          color: isActive
                              ? detailTab.activeText
                              : detailTab.inactiveText,
                        )),
                  ),
                ),
              );
            }),
          ],
        );
      }),
    );
  }
}

// ============================================================
// Request sub-views
// ============================================================

class _RequestHeadersView extends StatelessWidget {
  final DetailController detailCtrl;
  const _RequestHeadersView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final headers = DetailController.parseHeaders(raw, 'reqHeaders');

      if (headers.isEmpty) {
        return Center(
          child: Text('detail.no_headers'.tr,
              style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: AppTheme.fontSize.sm)),
        );
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: KeyValueTable(entries: headers),
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

      return Padding(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: BodyViewer(
          bytes: detailCtrl.requestBodyBytes.value,
          contentType: detailCtrl.requestContentType,
          label: 'Request',
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
      final headers = DetailController.parseHeaders(raw, 'reqHeaders');

      final cookies = <(String, String)>[];
      for (final h in headers) {
        if (h.$1.toLowerCase() == 'cookie') {
          final cookieStr = h.$2;
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

// ============================================================
// Response sub-views
// ============================================================

class _ResponseHeadersView extends StatelessWidget {
  final DetailController detailCtrl;
  const _ResponseHeadersView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final raw = detailCtrl.detail.value?.raw ?? {};
      final rspHeaders = DetailController.parseHeaders(raw, 'rspHeaders');

      if (rspHeaders.isEmpty) {
        return Center(
          child: Text('detail.no_headers'.tr,
              style: TextStyle(
                  color: Theme.of(context).hintColor,
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

      return Padding(
        padding: EdgeInsets.all(AppTheme.spacing.sm),
        child: BodyViewer(
          bytes: detailCtrl.responseBodyBytes.value,
          contentType: detailCtrl.responseContentType,
          label: 'Response',
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
      final headers = DetailController.parseHeaders(raw, 'rspHeaders');

      final cookies = <(String, String)>[];
      for (final h in headers) {
        if (h.$1.toLowerCase() == 'set-cookie') {
          final cookieStr = h.$2;
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

// ============================================================
// 3. DetailsView — card-based layout
// ============================================================

class _DetailsView extends StatelessWidget {
  final DetailController detailCtrl;
  const _DetailsView({required this.detailCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = detailCtrl.detail.value;
      if (d == null) return const SizedBox();

      return LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - 12 * 3) / 2;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _DetailCard(
                    title: 'TLS / SSL',
                    width: cardWidth,
                    children: _tlsContent(context, d)),
                _DetailCard(
                    title: 'CONNECTION',
                    width: cardWidth,
                    children: _connectionContent(context, d)),
                _DetailCard(
                    title: 'OVERVIEW',
                    width: cardWidth,
                    children: _overviewContent(context, d)),
                _DetailCard(
                    title: 'TIMING',
                    width: cardWidth,
                    children: _timingContent(context, d)),
              ],
            ),
          );
        },
      );
    });
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

    return entries.map((e) => _kvRow(context, e.$1, e.$2)).toList();
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
      final dt =
          DateTime.fromMillisecondsSinceEpoch((started * 1000).toInt());
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

    String ms(double? ts) {
      if (ts == null || started <= 0) return '-';
      return '${((ts - started) * 1000).toStringAsFixed(1)} ms';
    }

    final ended = (raw['endedAt'] as num?)?.toDouble() ?? started;

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
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ============================================================
// DetailCard — reusable card wrapper for DetailsView
// ============================================================

class _DetailCard extends StatelessWidget {
  final String title;
  final double width;
  final List<Widget> children;
  const _DetailCard(
      {required this.title, required this.width, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.colors(context).surface,
        border: Border.all(color: AppTheme.colors(context).divider),
        borderRadius: BorderRadius.circular(AppTheme.radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppTheme.colors(context).textSecondary,
              )),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
