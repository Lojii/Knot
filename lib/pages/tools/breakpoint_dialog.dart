import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../theme/app_theme.dart';

/// Modal dialog that appears when a breakpoint is hit.
/// Shows request details and allows the user to resume, cancel, or abort.
class BreakpointHitDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  const BreakpointHitDialog({super.key, required this.data});

  @override
  State<BreakpointHitDialog> createState() => _BreakpointHitDialogState();
}

class _BreakpointHitDialogState extends State<BreakpointHitDialog> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headersCtrl;
  late String _method;
  bool _sending = false;

  static const _methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'];

  String get flowId => widget.data['flowId'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.data['url'] as String? ?? '');
    _method = widget.data['method'] as String? ?? 'GET';
    if (!_methods.contains(_method)) _method = 'GET';

    // Convert headers map to readable JSON string
    final headers = widget.data['headers'] as Map<String, dynamic>? ?? {};
    final headerLines = headers.entries.map((e) => '  "${e.key}": "${e.value}"').join(',\n');
    _headersCtrl = TextEditingController(
      text: headers.isEmpty ? '{}' : '{\n$headerLines\n}',
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  Future<void> _resume(String action) async {
    if (_sending) return;
    setState(() => _sending = true);

    try {
      final api = Get.find<FlowController>().api;
      await api.resumeBreakpoint(flowId, action);
    } catch (_) {
      // Best effort — dialog closes regardless
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.pause_circle_filled, color: Colors.orange, size: 20),
          SizedBox(width: AppTheme.spacing.sm),
          Text('breakpoint.hit'.trParams({'flowId': flowId})),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Method
            Text('breakpoint.method'.tr, style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              color: theme.hintColor,
              fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 2),
            SizedBox(
              height: 32,
              child: DropdownButtonFormField<String>(
                initialValue: _method,
                items: _methods
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m, style: TextStyle(fontSize: AppTheme.fontSize.sm)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? 'GET'),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.sm,
                    vertical: AppTheme.spacing.xs,
                  ),
                ),
              ),
            ),
            SizedBox(height: AppTheme.spacing.sm),
            // URL
            Text('breakpoint.url'.tr, style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              color: theme.hintColor,
              fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 2),
            TextField(
              controller: _urlCtrl,
              style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.sm),
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing.sm,
                  vertical: AppTheme.spacing.sm,
                ),
              ),
            ),
            SizedBox(height: AppTheme.spacing.sm),
            // Headers
            Text('tab.headers'.tr, style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              color: theme.hintColor,
              fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 2),
            SizedBox(
              height: 120,
              child: TextField(
                controller: _headersCtrl,
                maxLines: null,
                expands: true,
                style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.sm),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.sm,
                    vertical: AppTheme.spacing.sm,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        // Abort (red)
        TextButton(
          onPressed: _sending ? null : () => _resume('abort'),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text('action.abort'.tr),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cancel (grey) — pass through unmodified
            TextButton(
              onPressed: _sending ? null : () => _resume('cancel'),
              child: Text('action.cancel'.tr),
            ),
            SizedBox(width: AppTheme.spacing.sm),
            // Execute (green) — resume with (optionally modified) request
            ElevatedButton(
              onPressed: _sending ? null : () => _resume('execute'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text('action.execute'.tr),
            ),
          ],
        ),
      ],
    );
  }
}
