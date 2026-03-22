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
      height: AppTheme.filterBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() => Row(
        children: [
          Text('Proto: ', style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
          ..._chips(context, ['HTTP', 'HTTPS', 'WS', 'H2'], filterCtrl.activeProtocols, (p) {
            filterCtrl.toggleProtocol(p);
            flowCtrl.reloadFromFirstPage();
          }),
          const SizedBox(width: AppTheme.spacingMD),
          Text('Status: ', style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
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
      padding: const EdgeInsets.only(right: AppTheme.spacingXS),
      child: GestureDetector(
        onTap: () => onTap(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM, vertical: 2),
          decoration: BoxDecoration(
            color: active.contains(label)
                ? primary.withAlpha(26)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            border: Border.all(
              color: active.contains(label)
                  ? primary
                  : theme.dividerColor,
            ),
          ),
          child: Text(label, style: TextStyle(
            fontSize: AppTheme.fontSizeSM,
            color: active.contains(label) ? primary : null,
          )),
        ),
      ),
    )).toList();
  }
}
