import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/api_client.dart';
import 'package:knot/controllers/filter_controller.dart';
import 'package:knot/controllers/flow_controller.dart';
import 'package:knot/models/flow_summary.dart';

FlowSummary _flow({
  String flowId = 'f1',
  String host = 'example.com',
  String method = 'GET',
  String uri = '/',
}) {
  return FlowSummary(
    flowId: flowId,
    protocol: 'HTTP/1.1',
    host: host,
    startedAt: 100.0,
    searchKey1: method,
    searchKey2: uri,
  );
}

void main() {
  late FlowController controller;

  setUp(() {
    Get.testMode = true;
    // FlowController needs ApiClient but we won't call HTTP methods
    final api = ApiClient(baseUrl: 'http://localhost:9999');
    controller = FlowController(api);
    // Register FilterController since loadFlows uses Get.find<FilterController>()
    Get.put(FilterController());
  });

  tearDown(() => Get.reset());

  group('FlowController - addFlowFromPush', () {
    test('inserts flow at beginning of list', () {
      final f1 = _flow(flowId: 'a');
      final f2 = _flow(flowId: 'b');

      controller.addFlowFromPush(f1);
      controller.addFlowFromPush(f2);

      expect(controller.flows.length, 2);
      expect(controller.flows[0].flowId, 'b');
      expect(controller.flows[1].flowId, 'a');
    });

    test('increments total count', () {
      expect(controller.total.value, 0);
      controller.addFlowFromPush(_flow());
      expect(controller.total.value, 1);
      controller.addFlowFromPush(_flow());
      expect(controller.total.value, 2);
    });
  });

  group('FlowController - updateFlowFromPush', () {
    test('updates existing flow by flowId', () {
      controller.addFlowFromPush(_flow(flowId: 'x', host: 'old.com'));

      controller.updateFlowFromPush({
        'flowId': 'x',
        'protocol': 'HTTP/2',
        'host': 'new.com',
        'startedAt': 200.0,
        'searchKey3': '200',
      });

      expect(controller.flows[0].host, 'new.com');
      expect(controller.flows[0].protocol, 'HTTP/2');
      expect(controller.flows[0].statusCode, '200');
    });

    test('does nothing when flowId not found', () {
      controller.addFlowFromPush(_flow(flowId: 'existing'));

      controller.updateFlowFromPush({
        'flowId': 'nonexistent',
        'host': 'new.com',
        'startedAt': 200.0,
      });

      expect(controller.flows.length, 1);
      expect(controller.flows[0].flowId, 'existing');
    });

    test('does nothing when flowId is null', () {
      controller.addFlowFromPush(_flow(flowId: 'test'));
      controller.updateFlowFromPush({'host': 'no-id.com', 'startedAt': 1.0});

      expect(controller.flows.length, 1);
      expect(controller.flows[0].host, 'example.com');
    });

    test('does nothing on empty data', () {
      controller.addFlowFromPush(_flow());
      controller.updateFlowFromPush({});
      expect(controller.flows.length, 1);
    });
  });

  group('FlowController - selectFlow', () {
    test('sets selectedFlow', () {
      final flow = _flow(flowId: 'sel');
      controller.selectFlow(flow);
      expect(controller.selectedFlow.value?.flowId, 'sel');
    });
  });

  group('FlowController - search', () {
    test('search sets up debounce (does not throw)', () {
      expect(() => controller.search('test query'), returnsNormally);
    });

    test('multiple rapid searches only debounce (no crash)', () {
      for (var i = 0; i < 10; i++) {
        controller.search('query $i');
      }
      // Just verifying no exceptions from rapid calls
    });
  });

  group('FlowController - initial state', () {
    test('starts with empty flows', () {
      expect(controller.flows, isEmpty);
    });

    test('starts with null selectedFlow', () {
      expect(controller.selectedFlow.value, isNull);
    });

    test('starts with total 0', () {
      expect(controller.total.value, 0);
    });

    test('starts with isLoading false', () {
      expect(controller.isLoading.value, isFalse);
    });

    test('starts with empty searchQuery', () {
      expect(controller.searchQuery.value, '');
    });

    test('starts with hasNewFlows false', () {
      expect(controller.hasNewFlows.value, isFalse);
    });
  });
}
