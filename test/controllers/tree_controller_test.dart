import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/controllers/tree_controller.dart';
import 'package:knot/models/flow_summary.dart';

FlowSummary _flow({
  required String host,
  String method = 'GET',
  String uri = '/',
}) {
  return FlowSummary(
    flowId: '${host}_$uri',
    protocol: 'HTTP/1.1',
    host: host,
    startedAt: 100.0,
    searchKey1: method,
    searchKey2: uri,
  );
}

void main() {
  late TreeController controller;

  setUp(() {
    Get.testMode = true;
    controller = TreeController();
  });

  tearDown(() => Get.reset());

  group('TreeController - buildTree', () {
    test('empty flow list produces empty tree', () {
      controller.buildTree([]);
      expect(controller.tree, isEmpty);
    });

    test('single flow creates one group node', () {
      controller.buildTree([_flow(host: 'example.com', uri: '/api')]);

      expect(controller.tree.length, 1);
      expect(controller.tree[0].label, 'example.com');
      expect(controller.tree[0].isGroup, isTrue);
      expect(controller.tree[0].domain, 'example.com');
      expect(controller.tree[0].children.length, 1);
      expect(controller.tree[0].children[0].label, 'GET /api');
    });

    test('groups flows by host', () {
      controller.buildTree([
        _flow(host: 'a.com', uri: '/1'),
        _flow(host: 'b.com', uri: '/2'),
        _flow(host: 'a.com', uri: '/3'),
      ]);

      expect(controller.tree.length, 2);
      final aNode = controller.tree.firstWhere((n) => n.label == 'a.com');
      final bNode = controller.tree.firstWhere((n) => n.label == 'b.com');
      expect(aNode.children.length, 2);
      expect(bNode.children.length, 1);
    });

    test('sorts groups by request count descending', () {
      controller.buildTree([
        _flow(host: 'few.com', uri: '/1'),
        _flow(host: 'many.com', uri: '/a'),
        _flow(host: 'many.com', uri: '/b'),
        _flow(host: 'many.com', uri: '/c'),
        _flow(host: 'mid.com', uri: '/x'),
        _flow(host: 'mid.com', uri: '/y'),
      ]);

      expect(controller.tree[0].label, 'many.com');
      expect(controller.tree[0].children.length, 3);
      expect(controller.tree[1].label, 'mid.com');
      expect(controller.tree[1].children.length, 2);
      expect(controller.tree[2].label, 'few.com');
      expect(controller.tree[2].children.length, 1);
    });

    test('child nodes have correct labels with method and uri', () {
      controller.buildTree([
        _flow(host: 'api.com', method: 'POST', uri: '/users'),
        _flow(host: 'api.com', method: 'DELETE', uri: '/users/1'),
      ]);

      final children = controller.tree[0].children;
      expect(children[0].label, 'POST /users');
      expect(children[1].label, 'DELETE /users/1');
    });

    test('child nodes have domain set to parent host', () {
      controller.buildTree([_flow(host: 'test.com')]);

      expect(controller.tree[0].children[0].domain, 'test.com');
    });

    test('group nodes are expanded by default', () {
      controller.buildTree([_flow(host: 'test.com')]);
      expect(controller.tree[0].expanded, isTrue);
    });

    test('child nodes are not groups', () {
      controller.buildTree([_flow(host: 'test.com')]);
      expect(controller.tree[0].children[0].isGroup, isFalse);
    });
  });

  group('TreeController - selectDomain', () {
    test('sets selectedDomain', () {
      controller.selectDomain('example.com');
      expect(controller.selectedDomain.value, 'example.com');
    });

    test('clears selectedDomain with null', () {
      controller.selectDomain('example.com');
      controller.selectDomain(null);
      expect(controller.selectedDomain.value, isNull);
    });
  });

  group('TreeNode', () {
    test('default values', () {
      final node = TreeNode(label: 'test');
      expect(node.isGroup, isFalse);
      expect(node.children, isEmpty);
      expect(node.expanded, isTrue);
      expect(node.domain, isNull);
    });
  });
}
