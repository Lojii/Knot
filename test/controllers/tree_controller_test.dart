import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/api/api_client.dart';
import 'package:knot/controllers/filter_controller.dart';
import 'package:knot/controllers/flow_controller.dart';
import 'package:knot/controllers/flow_table_controller.dart';
import 'package:knot/controllers/tree_controller.dart';
import 'package:knot/models/flow_summary.dart';

FlowSummary _flow({
  required String host,
  String method = 'GET',
  String uri = '/',
}) {
  return FlowSummary(
    flowId: '${host}_$uri',
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
  late TreeController controller;

  setUp(() {
    Get.testMode = true;
    // TreeController resolves its sibling controllers via Get.find(tag:)
    final api = ApiClient(baseUrl: 'http://localhost:9999');
    Get.put(FilterController(), tag: tag);
    controller = Get.put(TreeController()..taskId = taskId, tag: tag);
    Get.put(FlowTableController()..taskId = taskId, tag: tag);
    Get.put(FlowController(api)..taskId = taskId, tag: tag);
  });

  tearDown(() => Get.reset());

  group('TreeController.normalizeHost', () {
    test('strips default HTTPS port', () {
      expect(TreeController.normalizeHost('example.com:443'), 'example.com');
    });

    test('strips default HTTP port', () {
      expect(TreeController.normalizeHost('example.com:80'), 'example.com');
    });

    test('keeps non-default ports', () {
      expect(TreeController.normalizeHost('example.com:8080'), 'example.com:8080');
    });
  });

  group('TreeController - recomputeFromFlows', () {
    test('empty flow list produces empty tree', () {
      controller.recomputeFromFlows([]);
      expect(controller.tree, isEmpty);
    });

    test('groups flows by host with counts', () {
      controller.recomputeFromFlows([
        _flow(host: 'a.com', uri: '/1'),
        _flow(host: 'b.com', uri: '/2'),
        _flow(host: 'a.com', uri: '/3'),
      ]);

      expect(controller.tree.length, 2);
      final aNode = controller.tree.firstWhere((n) => n.domain == 'a.com');
      final bNode = controller.tree.firstWhere((n) => n.domain == 'b.com');
      expect(aNode.count, 2);
      expect(bNode.count, 1);
      expect(aNode.isGroup, isTrue);
    });

    test('merges hosts that differ only by default port', () {
      controller.recomputeFromFlows([
        _flow(host: 'a.com:443', uri: '/1'),
        _flow(host: 'a.com', uri: '/2'),
      ]);

      expect(controller.tree.length, 1);
      expect(controller.tree[0].count, 2);
    });
  });

  group('TreeController - addDomainFromPush', () {
    test('increments count of an existing domain', () {
      controller.recomputeFromFlows([_flow(host: 'a.com', uri: '/1')]);
      controller.addDomainFromPush(_flow(host: 'a.com', uri: '/2'));

      final node = controller.tree.firstWhere((n) => n.domain == 'a.com');
      expect(node.count, 2);
    });

    test('adds a new domain node', () {
      controller.recomputeFromFlows([_flow(host: 'a.com')]);
      controller.addDomainFromPush(_flow(host: 'b.com'));

      expect(controller.tree.any((n) => n.domain == 'b.com'), isTrue);
    });
  });

  group('TreeController - selection', () {
    test('selectDomain sets selectedDomain and clears path/app', () {
      controller.selectApp('MyApp');
      controller.selectDomain('example.com');

      expect(controller.selectedDomain.value, 'example.com');
      expect(controller.selectedPath.value, isNull);
      expect(controller.selectedApp.value, isNull);
    });

    test('selectDomain(null) clears the selection', () {
      controller.selectDomain('example.com');
      controller.selectDomain(null);
      expect(controller.selectedDomain.value, isNull);
    });

    test('selectPath sets domain and path', () {
      controller.selectPath('example.com', '/api');
      expect(controller.selectedDomain.value, 'example.com');
      expect(controller.selectedPath.value, '/api');
    });

    test('clearSelection resets everything', () {
      controller.selectPath('example.com', '/api');
      controller.clearSelection();
      expect(controller.selectedDomain.value, isNull);
      expect(controller.selectedPath.value, isNull);
      expect(controller.selectedApp.value, isNull);
    });
  });

  group('TreeController - expand/collapse', () {
    test('toggleExpand flips expansion state', () {
      expect(controller.isExpanded('a.com'), isFalse);
      controller.toggleExpand('a.com');
      expect(controller.isExpanded('a.com'), isTrue);
      controller.toggleExpand('a.com');
      expect(controller.isExpanded('a.com'), isFalse);
    });

    test('path expansion is keyed independently of the domain', () {
      controller.toggleExpand('a.com', '/api');
      expect(controller.isExpanded('a.com', '/api'), isTrue);
      expect(controller.isExpanded('a.com'), isFalse);
    });
  });

  group('TreeController - pinning', () {
    test('togglePin adds and removes a pinned domain', () {
      controller.recomputeFromFlows([_flow(host: 'a.com')]);

      controller.togglePin('a.com');
      expect(controller.isPinned('a.com'), isTrue);
      expect(controller.pinnedItems.length, 1);

      controller.togglePin('a.com');
      expect(controller.isPinned('a.com'), isFalse);
      expect(controller.pinnedItems, isEmpty);
    });
  });

  group('TreeNode', () {
    test('default values', () {
      final node = TreeNode(label: 'test');
      expect(node.isGroup, isFalse);
      expect(node.children, isEmpty);
      expect(node.count, 0);
      expect(node.childrenLoaded, isFalse);
      expect(node.domain, isNull);
    });
  });
}
