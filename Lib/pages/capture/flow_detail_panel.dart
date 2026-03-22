import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';

class FlowDetailPanel extends StatelessWidget {
  const FlowDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();

    return Obx(() {
      if (flowCtrl.selectedFlow.value == null) {
        return const Center(
          child: Text('Select a request to view details',
              style: TextStyle(color: Colors.grey)),
        );
      }
      return const Center(child: Text('Detail panel -- next task'));
    });
  }
}
