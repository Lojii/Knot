import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/controllers/filter_controller.dart';
import 'package:knot/models/flow_summary.dart';

FlowSummary _flow({
  String flowId = 'f1',
  String protocol = 'HTTP',
  String host = 'example.com',
  String contentType = '',
}) {
  return FlowSummary(
    flowId: flowId,
    protocol: protocol,
    host: host,
    startedAt: 100.0,
    searchKey4: contentType,
  );
}

void main() {
  late FilterController controller;

  setUp(() {
    Get.testMode = true;
    controller = FilterController();
  });

  tearDown(() => Get.reset());

  group('FilterController - toggleProtocol', () {
    test('adds and removes a protocol', () {
      controller.toggleProtocol('HTTP');
      expect(controller.activeProtocols, {'HTTP'});

      controller.toggleProtocol('HTTP');
      expect(controller.activeProtocols, isEmpty);
    });

    test('"All" clears active protocols', () {
      controller.toggleProtocol('HTTP');
      controller.toggleProtocol('WS');
      controller.toggleProtocol('All');
      expect(controller.activeProtocols, isEmpty);
    });
  });

  group('FilterController - toggleContentType', () {
    test('adds and removes a content type', () {
      controller.toggleContentType('JSON');
      expect(controller.activeContentTypes, {'JSON'});

      controller.toggleContentType('JSON');
      expect(controller.activeContentTypes, isEmpty);
    });

    test('"All" clears active content types', () {
      controller.toggleContentType('JSON');
      controller.toggleContentType('IMG');
      controller.toggleContentType('All');
      expect(controller.activeContentTypes, isEmpty);
    });
  });

  group('FilterController - protocolParam', () {
    test('is null when no protocol is active', () {
      expect(controller.protocolParam, isNull);
    });

    test('joins active protocols with comma', () {
      controller.toggleProtocol('HTTP');
      controller.toggleProtocol('WS');
      expect(controller.protocolParam!.split(','), containsAll(['HTTP', 'WS']));
    });
  });

  group('FilterController - protocolMode', () {
    test('defaults to HTTP mode', () {
      expect(controller.protocolMode.value, 'HTTP');
      expect(controller.isTcpMode, isFalse);
    });

    test('toggleProtocolMode switches between HTTP and TCP', () {
      controller.toggleProtocolMode();
      expect(controller.isTcpMode, isTrue);
      controller.toggleProtocolMode();
      expect(controller.isTcpMode, isFalse);
    });
  });

  group('FilterController - recomputeFromFlows', () {
    test('computes available protocols in stable order', () {
      controller.recomputeFromFlows([
        _flow(flowId: 'a', protocol: 'WS'),
        _flow(flowId: 'b', protocol: 'HTTP'),
        _flow(flowId: 'c', protocol: 'HTTPS'),
      ]);
      expect(controller.availableProtocols, ['HTTP', 'HTTPS', 'WS']);
    });

    test('maps content types to category labels', () {
      controller.recomputeFromFlows([
        _flow(flowId: 'a', contentType: 'application/json'),
        _flow(flowId: 'b', contentType: 'image/png'),
        _flow(flowId: 'c', contentType: 'text/html'),
      ]);
      expect(controller.availableContentTypes, ['JSON', 'IMG', 'HTML']);
    });

    test('empty flows produce empty availability', () {
      controller.recomputeFromFlows([]);
      expect(controller.availableProtocols, isEmpty);
      expect(controller.availableContentTypes, isEmpty);
    });
  });

  group('FilterController - addFlowToFilters', () {
    test('incrementally adds protocol and content type once', () {
      controller.addFlowToFilters(
          _flow(protocol: 'HTTPS', contentType: 'application/json'));
      controller.addFlowToFilters(
          _flow(protocol: 'HTTPS', contentType: 'application/json'));

      expect(controller.availableProtocols, ['HTTPS']);
      expect(controller.availableContentTypes, ['JSON']);
    });
  });

  group('FilterController - matchesContentType', () {
    test('matches everything when no filter is active', () {
      expect(controller.matchesContentType(_flow(contentType: 'text/html')),
          isTrue);
    });

    test('matches flows in the active category only', () {
      controller.toggleContentType('JSON');
      expect(
          controller
              .matchesContentType(_flow(contentType: 'application/json')),
          isTrue);
      expect(controller.matchesContentType(_flow(contentType: 'text/html')),
          isFalse);
    });
  });

  group('FilterController - clearAll', () {
    test('clears active and available filters', () {
      controller.toggleProtocol('HTTP');
      controller.toggleContentType('JSON');
      controller.recomputeFromFlows([_flow(contentType: 'application/json')]);

      controller.clearAll();

      expect(controller.activeProtocols, isEmpty);
      expect(controller.activeContentTypes, isEmpty);
      expect(controller.availableProtocols, isEmpty);
      expect(controller.availableContentTypes, isEmpty);
    });
  });
}
