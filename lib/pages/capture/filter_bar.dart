import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/filter_controller.dart';
import '../../controllers/flow_controller.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final filterCtrl = Get.find<FilterController>();
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Obx(() => Row(
        children: [
          const Text('Proto: ', style: TextStyle(fontSize: 11)),
          ..._chips(['HTTP', 'HTTPS', 'WS', 'H2'], filterCtrl.activeProtocols, (p) {
            filterCtrl.toggleProtocol(p);
            flowCtrl.reloadFromFirstPage();
          }),
          const SizedBox(width: 12),
          const Text('Status: ', style: TextStyle(fontSize: 11)),
          ..._chips(['2xx', '3xx', '4xx', '5xx'], filterCtrl.activeStatuses, (s) {
            filterCtrl.toggleStatus(s);
            flowCtrl.reloadFromFirstPage();
          }),
        ],
      )),
    );
  }

  List<Widget> _chips(List<String> labels, RxSet<String> active, void Function(String) onTap) {
    return labels.map((label) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => onTap(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: active.contains(label)
                ? Colors.blue.withAlpha(51)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active.contains(label)
                  ? Colors.blue
                  : Colors.grey.withAlpha(77),
            ),
          ),
          child: Text(label, style: TextStyle(
            fontSize: 11,
            color: active.contains(label) ? Colors.blue : null,
          )),
        ),
      ),
    )).toList();
  }
}
