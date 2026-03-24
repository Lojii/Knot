import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/filter_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../theme/app_theme.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final filterCtrl = Get.find<FilterController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: AppTheme.sizing.filterBarHeight,
      padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() => Row(
        children: [
          Text('Proto: ', style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor)),
          ..._chips(context, ['HTTP', 'HTTPS', 'WS', 'H2'], filterCtrl.activeProtocols, (p) {
            filterCtrl.toggleProtocol(p);
            flowCtrl.reloadFromFirstPage();
          }),
          SizedBox(width: AppTheme.spacing.md),
          Text('Status: ', style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor)),
          ..._chips(context, ['2xx', '3xx', '4xx', '5xx'], filterCtrl.activeStatuses, (s) {
            filterCtrl.toggleStatus(s);
            flowCtrl.reloadFromFirstPage();
          }),
        ],
      )),
    );
  }

  List<Widget> _chips(BuildContext context, List<String> labels, RxSet<String> active, void Function(String) onTap) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return labels.map((label) => Padding(
      padding: EdgeInsets.only(right: AppTheme.spacing.xs),
      child: GestureDetector(
        onTap: () => onTap(label),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: active.contains(label)
                ? primary.withAlpha(26)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radius.sm),
            border: Border.all(
              color: active.contains(label)
                  ? primary
                  : theme.dividerColor,
            ),
          ),
          child: Text(label, style: TextStyle(
            fontSize: AppTheme.fontSize.sm,
            color: active.contains(label) ? primary : null,
          )),
        ),
      ),
    )).toList();
  }
}
