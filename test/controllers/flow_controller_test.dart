import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/api_client.dart';
import 'package:knot/controllers/filter_controller.dart';
import 'package:knot/controllers/flow_controller.dart';
import 'package:knot/controllers/flow_table_controller.dart';
import 'package:knot/controllers/tree_controller.dart';
import 'package:knot/models/flow_summary.dart';

FlowSummary _flow({
  String flowId = 'f1',
  String host = 'example.com',
  String method = 'GET',
  String uri = '/',
}) {
  return FlowSummary(
    flowId: flowId,
    protocol: 'HTTP',
    host: host,
    startedAt: 100.0,
    searchKey1: method,
    searchKey2: uri,
  );
}

void main() {
  const taskId = 1;
  const tag = 'task_$taskId';
  late FlowController controller;
  late FlowTableController tableCtrl;

  setUp(() {
    Get.testMode = true;
    // FlowController resolves its sibling controllers via Get.find(tag:)
    final api = ApiClient(baseUrl: 'http://localhost:9999');
    Get.put(FilterController(), tag: tag);
    Get.put(TreeController()..taskId = taskId, tag: tag);
    tableCtrl = Get.put(FlowTableController()..taskId = taskId, tag: tag);
    controller = Get.put(FlowController(api)..taskId = taskId, tag: tag);
  });

  tearDown(() => Get.reset());

  group('FlowController - addFlowFromPush', () {
    test('inserts flow at beginning of allFlows', () {
      controller.addFlowFromPush(_flow(flowId: 'a'));
      controller.addFlowFromPush(_flow(flowId: 'b'));

      expect(controller.allFlows.length, 2);
      expect(controller.allFlows[0].flowId, 'b');
      expect(controller.allFlows[1].flowId, 'a');
    });

    test('registers the flow domain in the tree', () {
      controller.addFlowFromPush(_flow(host: 'api.example.com'));

      final treeCtrl = Get.find<TreeController>(tag: tag);
      expect(treeCtrl.tree.any((n) => n.domain == 'api.example.com'), isTrue);
    });
  });

  group('FlowController - updateFlowFromPush', () {
    test('replaces the matching flow', () {
      controller.addFlowFromPush(_flow(flowId: 'a', method: 'GET'));

      controller.updateFlowFromPush({
        'flowId': 'a',
        'protocol': 'HTTP',
        'host': 'example.com',
        'startedAt': 100.0,
        'searchKey1': 'POST',
      });

      expect(controller.allFlows.length, 1);
      expect(controller.allFlows[0].method, 'POST');
    });

    test('ignores unknown flowId', () {
      controller.addFlowFromPush(_flow(flowId: 'a'));

      controller.updateFlowFromPush({'flowId': 'missing'});

      expect(controller.allFlows.length, 1);
      expect(controller.allFlows[0].flowId, 'a');
    });

    test('ignores payload without flowId', () {
      controller.addFlowFromPush(_flow(flowId: 'a'));

      expect(() => controller.updateFlowFromPush({}), returnsNormally);
      expect(controller.allFlows.length, 1);
    });
  });

  group('FlowTableController - reapplyFilters', () {
    test('mirrors allFlows into the displayed list', () {
      controller.addFlowFromPush(_flow(flowId: 'a'));
      controller.addFlowFromPush(_flow(flowId: 'b'));

      tableCtrl.reapplyFilters();

      expect(tableCtrl.flows.length, 2);
      expect(tableCtrl.total.value, 2);
    });

    test('applies protocol filter', () {
      controller.addFlowFromPush(_flow(flowId: 'a'));
      final filterCtrl = Get.find<FilterController>(tag: tag);
      filterCtrl.toggleProtocol('WSS');

      tableCtrl.reapplyFilters();

      expect(tableCtrl.flows, isEmpty);
    });
  });
}
