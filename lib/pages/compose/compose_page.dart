import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../../controllers/page_controller.dart';
import '../../widgets/body_viewer.dart';
import '../../widgets/key_value_table.dart';
import '../../theme/app_theme.dart';

/// Full-page Compose panel for building and sending custom HTTP requests.
class ComposePage extends StatefulWidget {
  const ComposePage({super.key});

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  static const _methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'];

  String _method = 'GET';
  final _urlController = TextEditingController();
  final _bodyController = TextEditingController();

  // Header rows: list of (key controller, value controller)
  final List<(TextEditingController, TextEditingController)> _headerRows = [];
  // Query param rows
  final List<(TextEditingController, TextEditingController)> _queryRows = [];

  // Body tab
  int _bodyTab = 0; // 0=Raw, 1=JSON, 2=Form

  // Response state
  bool _isSending = false;
  int? _responseStatus;
  String _responseBody = '';
  String _responseContentType = '';
  List<(String, String)> _responseHeaders = [];
  Duration? _responseTime;

  bool _prefillApplied = false;

  @override
  void initState() {
    super.initState();
    _addHeaderRow();
    _urlController.addListener(_syncQueryFromUrl);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefillApplied) {
      _prefillApplied = true;
      _applyPrefill();
    }
  }

  void _applyPrefill() {
    final pageCtrl = Get.find<AppPageController>();
    if (pageCtrl.composePrefillMethod.isNotEmpty) {
      setState(() {
        _method = pageCtrl.composePrefillMethod.toUpperCase();
        if (!_methods.contains(_method)) _method = 'GET';
        _urlController.text = pageCtrl.composePrefillUrl;
        _bodyController.text = pageCtrl.composePrefillBody;

        _headerRows.clear();
        for (final entry in pageCtrl.composePrefillHeaders.entries) {
          _headerRows.add((
            TextEditingController(text: entry.key),
            TextEditingController(text: entry.value),
          ));
        }
        if (_headerRows.isEmpty) _addHeaderRow();

        _syncQueryFromUrl();
      });
      pageCtrl.clearComposePrefill();
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController.dispose();
    for (final row in _headerRows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    for (final row in _queryRows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    super.dispose();
  }

  void _addHeaderRow() {
    setState(() {
      _headerRows.add((TextEditingController(), TextEditingController()));
    });
  }

  void _removeHeaderRow(int index) {
    setState(() {
      final row = _headerRows.removeAt(index);
      row.$1.dispose();
      row.$2.dispose();
    });
  }

  void _addQueryRow() {
    setState(() {
      _queryRows.add((TextEditingController(), TextEditingController()));
    });
  }

  void _removeQueryRow(int index) {
    setState(() {
      final row = _queryRows.removeAt(index);
      row.$1.dispose();
      row.$2.dispose();
    });
  }

  bool _syncingQuery = false;

  void _syncQueryFromUrl() {
    if (_syncingQuery) return;
    _syncingQuery = true;
    try {
      final uri = Uri.tryParse(_urlController.text);
      if (uri == null) return;
      final params = uri.queryParametersAll;

      // Dispose old controllers
      for (final row in _queryRows) {
        row.$1.dispose();
        row.$2.dispose();
      }
      _queryRows.clear();

      for (final entry in params.entries) {
        for (final val in entry.value) {
          _queryRows.add((
            TextEditingController(text: entry.key),
            TextEditingController(text: val),
          ));
        }
      }
      if (_queryRows.isEmpty) {
        _queryRows.add((TextEditingController(), TextEditingController()));
      }
      if (mounted) setState(() {});
    } finally {
      _syncingQuery = false;
    }
  }

  void _syncUrlFromQuery() {
    if (_syncingQuery) return;
    _syncingQuery = true;
    try {
      var urlText = _urlController.text;
      final uri = Uri.tryParse(urlText);
      if (uri == null) return;

      final params = <String, List<String>>{};
      for (final row in _queryRows) {
        final key = row.$1.text.trim();
        if (key.isEmpty) continue;
        params.putIfAbsent(key, () => []).add(row.$2.text);
      }

      final newUri = uri.replace(queryParameters: params.isEmpty ? null : params);
      _urlController.text = newUri.toString();
    } finally {
      _syncingQuery = false;
    }
  }

  Future<void> _sendRequest() async {
    final urlText = _urlController.text.trim();
    if (urlText.isEmpty) return;

    setState(() {
      _isSending = true;
      _responseStatus = null;
      _responseBody = '';
      _responseHeaders = [];
      _responseTime = null;
      _responseContentType = '';
    });

    try {
      final uri = Uri.parse(urlText.startsWith('http') ? urlText : 'https://$urlText');

      final headers = <String, String>{};
      for (final row in _headerRows) {
        final key = row.$1.text.trim();
        final val = row.$2.text.trim();
        if (key.isNotEmpty) headers[key] = val;
      }

      final request = http.Request(_method, uri);
      request.headers.addAll(headers);

      if (_method != 'GET' && _method != 'HEAD') {
        request.body = _bodyController.text;
      }

      final stopwatch = Stopwatch()..start();
      final streamedResponse = await http.Client().send(request);
      final response = await http.Response.fromStream(streamedResponse);
      stopwatch.stop();

      final rspHeaders = <(String, String)>[];
      response.headers.forEach((k, v) => rspHeaders.add((k, v)));

      setState(() {
        _responseStatus = response.statusCode;
        _responseBody = response.body;
        _responseHeaders = rspHeaders;
        _responseTime = stopwatch.elapsed;
        _responseContentType = response.headers['content-type'] ?? '';
      });
    } catch (e) {
      setState(() {
        _responseStatus = null;
        _responseBody = 'Error: $e';
        _responseTime = null;
      });
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.all(AppTheme.spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left half: Request Editor
          Expanded(child: _buildRequestEditor(theme)),
          VerticalDivider(width: 1, color: theme.dividerColor),
          // Right half: Response Viewer
          Expanded(child: _buildResponseViewer(theme)),
        ],
      ),
    );
  }

  Widget _buildRequestEditor(ThemeData theme) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(right: AppTheme.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Method + URL row
          Row(
            children: [
              // Method dropdown
              Container(
                height: 36,
                padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _method,
                    isDense: true,
                    style: TextStyle(
                      fontSize: AppTheme.fontSize.md,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.methodColor(_method),
                    ),
                    items: _methods.map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m, style: TextStyle(color: AppTheme.methodColor(m))),
                    )).toList(),
                    onChanged: (v) => setState(() => _method = v ?? 'GET'),
                  ),
                ),
              ),
              SizedBox(width: AppTheme.spacing.sm),
              // URL field
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _urlController,
                    style: AppTheme.mono(context).copyWith(fontSize: AppTheme.fontSize.md),
                    decoration: InputDecoration(
                      hintText: 'compose.url_hint'.tr,
                      hintStyle: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSize.md),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing.sm,
                        vertical: AppTheme.spacing.xs,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendRequest(),
                  ),
                ),
              ),
              SizedBox(width: AppTheme.spacing.sm),
              // Send button
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendRequest,
                  icon: _isSending
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, size: 16),
                  label: Text('action.send'.tr),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    textStyle: TextStyle(fontSize: AppTheme.fontSize.md, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: AppTheme.spacing.lg),

          // Headers section
          _sectionTitle('compose.headers'.tr),
          SizedBox(height: AppTheme.spacing.xs),
          _buildKeyValueEditor(
            rows: _headerRows,
            onAdd: _addHeaderRow,
            onRemove: _removeHeaderRow,
            keyHint: 'Header name',
            valueHint: 'Value',
          ),

          SizedBox(height: AppTheme.spacing.lg),

          // Query Params section
          _sectionTitle('compose.query_params'.tr),
          SizedBox(height: AppTheme.spacing.xs),
          _buildKeyValueEditor(
            rows: _queryRows,
            onAdd: _addQueryRow,
            onRemove: _removeQueryRow,
            keyHint: 'Param name',
            valueHint: 'Value',
            onChanged: _syncUrlFromQuery,
          ),

          SizedBox(height: AppTheme.spacing.lg),

          // Body section
          _sectionTitle('compose.body'.tr),
          SizedBox(height: AppTheme.spacing.xs),
          _buildBodyTabs(theme),
          SizedBox(height: AppTheme.spacing.xs),
          SizedBox(
            height: 200,
            child: TextField(
              controller: _bodyController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: AppTheme.mono(context),
              decoration: InputDecoration(
                hintText: _bodyTab == 1
                    ? '{"key": "value"}'
                    : _bodyTab == 2
                        ? 'key=value&key2=value2'
                        : 'Request body...',
                hintStyle: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSize.sm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                ),
                contentPadding: EdgeInsets.all(AppTheme.spacing.sm),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: AppTheme.fontSize.md,
    ));
  }

  Widget _buildBodyTabs(ThemeData theme) {
    final labels = ['tab.raw'.tr, 'tab.json'.tr, 'tab.form'.tr];
    return Row(
      children: List.generate(labels.length, (i) {
        final isActive = _bodyTab == i;
        return Padding(
          padding: EdgeInsets.only(right: AppTheme.spacing.xs),
          child: GestureDetector(
            onTap: () => setState(() => _bodyTab = i),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.spacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary.withAlpha(26)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                border: Border.all(
                  color: isActive ? theme.colorScheme.primary : theme.dividerColor,
                ),
              ),
              child: Text(labels[i], style: TextStyle(
                fontSize: AppTheme.fontSize.sm,
                color: isActive ? theme.colorScheme.primary : null,
              )),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildKeyValueEditor({
    required List<(TextEditingController, TextEditingController)> rows,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
    required String keyHint,
    required String valueHint,
    VoidCallback? onChanged,
  }) {
    return Column(
      children: [
        for (int i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: AppTheme.spacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: rows[i].$1,
                      style: AppTheme.mono(context).copyWith(fontSize: AppTheme.fontSize.sm),
                      decoration: InputDecoration(
                        hintText: keyHint,
                        hintStyle: TextStyle(fontSize: AppTheme.fontSize.sm),
                        contentPadding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radius.sm)),
                        isDense: true,
                      ),
                      onChanged: (_) => onChanged?.call(),
                    ),
                  ),
                ),
                SizedBox(width: AppTheme.spacing.xs),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: rows[i].$2,
                      style: AppTheme.mono(context).copyWith(fontSize: AppTheme.fontSize.sm),
                      decoration: InputDecoration(
                        hintText: valueHint,
                        hintStyle: TextStyle(fontSize: AppTheme.fontSize.sm),
                        contentPadding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radius.sm)),
                        isDense: true,
                      ),
                      onChanged: (_) => onChanged?.call(),
                    ),
                  ),
                ),
                SizedBox(width: AppTheme.spacing.xs),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: const Icon(Icons.close),
                    onPressed: rows.length > 1 ? () => onRemove(i) : null,
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 14),
            label: Text('action.add'.tr, style: TextStyle(fontSize: AppTheme.fontSize.sm)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponseViewer(ThemeData theme) {
    if (_responseStatus == null && !_isSending && _responseBody.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.send_outlined, size: 48, color: theme.hintColor),
            SizedBox(height: AppTheme.spacing.sm),
            Text(
              'empty.send_request'.tr,
              style: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSize.md),
            ),
          ],
        ),
      );
    }

    if (_isSending) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(left: AppTheme.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + timing
          Row(
            children: [
              if (_responseStatus != null) ...[
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.sm,
                    vertical: AppTheme.spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.statusColor(_responseStatus!).withAlpha(26),
                    borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                  ),
                  child: Text(
                    '$_responseStatus',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSize.lg,
                      color: AppTheme.statusColor(_responseStatus!),
                    ),
                  ),
                ),
                SizedBox(width: AppTheme.spacing.sm),
                Text(
                  _httpStatusPhrase(_responseStatus!),
                  style: TextStyle(
                    fontSize: AppTheme.fontSize.md,
                    color: AppTheme.statusColor(_responseStatus!),
                  ),
                ),
              ],
              if (_responseTime != null) ...[
                SizedBox(width: AppTheme.spacing.lg),
                Text(
                  '${_responseTime!.inMilliseconds}ms',
                  style: TextStyle(
                    fontSize: AppTheme.fontSize.md,
                    color: theme.hintColor,
                  ),
                ),
              ],
            ],
          ),

          SizedBox(height: AppTheme.spacing.lg),

          // Response Headers
          if (_responseHeaders.isNotEmpty) ...[
            _sectionTitle('compose.response_headers'.tr),
            SizedBox(height: AppTheme.spacing.xs),
            KeyValueTable(entries: _responseHeaders),
            SizedBox(height: AppTheme.spacing.lg),
          ],

          // Response Body
          _sectionTitle('compose.response_body'.tr),
          SizedBox(height: AppTheme.spacing.xs),
          BodyViewer(
            body: _responseBody,
            contentType: _responseContentType,
            label: 'Response',
          ),
        ],
      ),
    );
  }

  String _httpStatusPhrase(int code) => switch (code) {
    200 => 'OK',
    201 => 'Created',
    204 => 'No Content',
    301 => 'Moved Permanently',
    302 => 'Found',
    304 => 'Not Modified',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    500 => 'Internal Server Error',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    _ => '',
  };
}
