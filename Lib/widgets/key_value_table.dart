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
