import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/controllers/tools_controller.dart';

void main() {
  late ToolsController ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = ToolsController();
  });

  tearDown(() {
    Get.reset();
  });

  // --- Map Remote Rules ---
  group('ToolsController - Map Remote rules', () {
    test('initial state has empty mapRemoteRules', () {
      expect(ctrl.mapRemoteRules, isEmpty);
    });

    test('addMapRemoteRule adds a rule', () {
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: '*.example.com'));
      expect(ctrl.mapRemoteRules.length, 1);
      expect(ctrl.mapRemoteRules[0].matchPattern, '*.example.com');
    });

    test('addMapRemoteRule adds multiple rules', () {
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: '*.a.com'));
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: '*.b.com'));
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: '*.c.com'));
      expect(ctrl.mapRemoteRules.length, 3);
    });

    test('removeMapRemoteRule removes by index', () {
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: 'first'));
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: 'second'));
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: 'third'));
      ctrl.removeMapRemoteRule(1);
      expect(ctrl.mapRemoteRules.length, 2);
      expect(ctrl.mapRemoteRules[0].matchPattern, 'first');
      expect(ctrl.mapRemoteRules[1].matchPattern, 'third');
    });

    test('toggleMapRemoteRule flips enabled state', () {
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: 'test', enabled: true));
      expect(ctrl.mapRemoteRules[0].enabled, isTrue);
      ctrl.toggleMapRemoteRule(0);
      expect(ctrl.mapRemoteRules[0].enabled, isFalse);
      ctrl.toggleMapRemoteRule(0);
      expect(ctrl.mapRemoteRules[0].enabled, isTrue);
    });

    test('updateMapRemoteRule replaces rule at index', () {
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: 'old'));
      ctrl.updateMapRemoteRule(0, MapRemoteRule(matchPattern: 'new', replaceHost: 'localhost'));
      expect(ctrl.mapRemoteRules[0].matchPattern, 'new');
      expect(ctrl.mapRemoteRules[0].replaceHost, 'localhost');
    });

    test('new rules default to enabled', () {
      ctrl.addMapRemoteRule(MapRemoteRule(matchPattern: 'test'));
      expect(ctrl.mapRemoteRules[0].enabled, isTrue);
    });
  });

  // --- MapRemoteRule model ---
  group('MapRemoteRule model', () {
    test('copyWith preserves unchanged fields', () {
      final rule = MapRemoteRule(
        matchPattern: 'pattern',
        replaceScheme: 'https',
        replaceHost: 'new.host',
        replacePort: 8080,
        replacePath: '/new',
        enabled: true,
      );
      final copy = rule.copyWith(enabled: false);
      expect(copy.matchPattern, 'pattern');
      expect(copy.replaceScheme, 'https');
      expect(copy.replaceHost, 'new.host');
      expect(copy.replacePort, 8080);
      expect(copy.replacePath, '/new');
      expect(copy.enabled, isFalse);
    });

    test('replacementSummary with all fields', () {
      final rule = MapRemoteRule(
        matchPattern: 'test',
        replaceScheme: 'https',
        replaceHost: 'new.host',
        replacePort: 9090,
        replacePath: '/api',
      );
      final summary = rule.replacementSummary;
      expect(summary, contains('https://'));
      expect(summary, contains('new.host'));
      expect(summary, contains(':9090'));
      expect(summary, contains('/api'));
    });

    test('replacementSummary with no fields returns "(no change)"', () {
      final rule = MapRemoteRule(matchPattern: 'test');
      expect(rule.replacementSummary, '(no change)');
    });
  });

  // --- Map Local Rules ---
  group('ToolsController - Map Local rules', () {
    test('initial state has empty mapLocalRules', () {
      expect(ctrl.mapLocalRules, isEmpty);
    });

    test('addMapLocalRule adds a rule', () {
      ctrl.addMapLocalRule(MapLocalRule(urlPattern: '*/api/*'));
      expect(ctrl.mapLocalRules.length, 1);
    });

    test('removeMapLocalRule removes by index', () {
      ctrl.addMapLocalRule(MapLocalRule(urlPattern: 'a'));
      ctrl.addMapLocalRule(MapLocalRule(urlPattern: 'b'));
      ctrl.removeMapLocalRule(0);
      expect(ctrl.mapLocalRules.length, 1);
      expect(ctrl.mapLocalRules[0].urlPattern, 'b');
    });

    test('toggleMapLocalRule flips enabled', () {
      ctrl.addMapLocalRule(MapLocalRule(urlPattern: 'test'));
      expect(ctrl.mapLocalRules[0].enabled, isTrue);
      ctrl.toggleMapLocalRule(0);
      expect(ctrl.mapLocalRules[0].enabled, isFalse);
    });
  });

  // --- MapLocalRule model ---
  group('MapLocalRule model', () {
    test('creation with all fields', () {
      final rule = MapLocalRule(
        urlPattern: '*/api/*',
        method: 'GET',
        statusCode: 200,
        filePath: '/tmp/response.json',
        responseHeaders: 'Content-Type: application/json',
        enabled: true,
      );
      expect(rule.urlPattern, '*/api/*');
      expect(rule.method, 'GET');
      expect(rule.statusCode, 200);
      expect(rule.filePath, '/tmp/response.json');
      expect(rule.responseHeaders, 'Content-Type: application/json');
      expect(rule.enabled, isTrue);
    });

    test('default values', () {
      final rule = MapLocalRule(urlPattern: 'test');
      expect(rule.enabled, isTrue);
      expect(rule.method, isNull);
      expect(rule.statusCode, 200);
      expect(rule.filePath, '');
      expect(rule.responseHeaders, '');
    });

    test('copyWith toggles enabled', () {
      final rule = MapLocalRule(urlPattern: 'test', enabled: true);
      final toggled = rule.copyWith(enabled: false);
      expect(toggled.enabled, isFalse);
      expect(toggled.urlPattern, 'test');
    });
  });

  // --- Breakpoint Rules ---
  group('ToolsController - Breakpoint rules', () {
    test('initial state has empty breakpointRules', () {
      expect(ctrl.breakpointRules, isEmpty);
    });

    test('addBreakpointRule adds a rule', () {
      ctrl.addBreakpointRule(BreakpointRule(urlPattern: '*/login*'));
      expect(ctrl.breakpointRules.length, 1);
    });

    test('removeBreakpointRule removes by index', () {
      ctrl.addBreakpointRule(BreakpointRule(urlPattern: 'a'));
      ctrl.addBreakpointRule(BreakpointRule(urlPattern: 'b'));
      ctrl.removeBreakpointRule(0);
      expect(ctrl.breakpointRules.length, 1);
      expect(ctrl.breakpointRules[0].urlPattern, 'b');
    });

    test('toggleBreakpointRule flips enabled', () {
      ctrl.addBreakpointRule(BreakpointRule(urlPattern: 'test'));
      expect(ctrl.breakpointRules[0].enabled, isTrue);
      ctrl.toggleBreakpointRule(0);
      expect(ctrl.breakpointRules[0].enabled, isFalse);
      ctrl.toggleBreakpointRule(0);
      expect(ctrl.breakpointRules[0].enabled, isTrue);
    });

    test('updateBreakpointRule replaces rule', () {
      ctrl.addBreakpointRule(BreakpointRule(urlPattern: 'old'));
      ctrl.updateBreakpointRule(
        0,
        BreakpointRule(urlPattern: 'new', breakOn: 'request'),
      );
      expect(ctrl.breakpointRules[0].urlPattern, 'new');
      expect(ctrl.breakpointRules[0].breakOn, 'request');
    });
  });

  // --- BreakpointRule model ---
  group('BreakpointRule model', () {
    test('creation with all fields', () {
      final rule = BreakpointRule(
        urlPattern: '*/api/*',
        method: 'POST',
        breakOn: 'request',
        comment: 'Debug login',
        enabled: false,
      );
      expect(rule.urlPattern, '*/api/*');
      expect(rule.method, 'POST');
      expect(rule.breakOn, 'request');
      expect(rule.comment, 'Debug login');
      expect(rule.enabled, isFalse);
    });

    test('default breakOn is "both"', () {
      final rule = BreakpointRule(urlPattern: 'test');
      expect(rule.breakOn, 'both');
    });

    test('default enabled is true', () {
      final rule = BreakpointRule(urlPattern: 'test');
      expect(rule.enabled, isTrue);
    });

    test('default comment is empty', () {
      final rule = BreakpointRule(urlPattern: 'test');
      expect(rule.comment, '');
    });

    test('default method is null', () {
      final rule = BreakpointRule(urlPattern: 'test');
      expect(rule.method, isNull);
    });

    test('copyWith preserves fields', () {
      final rule = BreakpointRule(
        urlPattern: 'p',
        method: 'GET',
        breakOn: 'request',
        comment: 'c',
      );
      final copy = rule.copyWith(breakOn: 'response');
      expect(copy.urlPattern, 'p');
      expect(copy.method, 'GET');
      expect(copy.breakOn, 'response');
      expect(copy.comment, 'c');
    });
  });

  // --- Allow/Block Lists ---
  group('ToolsController - Allow/Block lists', () {
    test('initial allowList is empty', () {
      expect(ctrl.allowList, isEmpty);
    });

    test('initial blockList is empty', () {
      expect(ctrl.blockList, isEmpty);
    });

    test('addToAllowList adds a pattern', () {
      ctrl.addToAllowList('*.example.com');
      expect(ctrl.allowList.length, 1);
      expect(ctrl.allowList[0], '*.example.com');
    });

    test('addToAllowList ignores empty string', () {
      ctrl.addToAllowList('');
      expect(ctrl.allowList, isEmpty);
    });

    test('addToAllowList ignores duplicates', () {
      ctrl.addToAllowList('*.example.com');
      ctrl.addToAllowList('*.example.com');
      expect(ctrl.allowList.length, 1);
    });

    test('removeFromAllowList removes by index', () {
      ctrl.addToAllowList('first');
      ctrl.addToAllowList('second');
      ctrl.removeFromAllowList(0);
      expect(ctrl.allowList.length, 1);
      expect(ctrl.allowList[0], 'second');
    });

    test('addToBlockList adds a pattern', () {
      ctrl.addToBlockList('*.ads.com');
      expect(ctrl.blockList.length, 1);
      expect(ctrl.blockList[0], '*.ads.com');
    });

    test('addToBlockList ignores empty string', () {
      ctrl.addToBlockList('');
      expect(ctrl.blockList, isEmpty);
    });

    test('addToBlockList ignores duplicates', () {
      ctrl.addToBlockList('*.ads.com');
      ctrl.addToBlockList('*.ads.com');
      expect(ctrl.blockList.length, 1);
    });

    test('removeFromBlockList removes by index', () {
      ctrl.addToBlockList('first');
      ctrl.addToBlockList('second');
      ctrl.removeFromBlockList(0);
      expect(ctrl.blockList.length, 1);
      expect(ctrl.blockList[0], 'second');
    });

    test('allow and block lists are independent', () {
      ctrl.addToAllowList('allow.com');
      ctrl.addToBlockList('block.com');
      expect(ctrl.allowList.length, 1);
      expect(ctrl.blockList.length, 1);
      expect(ctrl.allowList[0], 'allow.com');
      expect(ctrl.blockList[0], 'block.com');
    });
  });

  // --- No Caching ---
  group('ToolsController - No Caching', () {
    test('initial state is false', () {
      expect(ctrl.noCachingEnabled.value, isFalse);
    });

    test('toggleNoCaching turns on', () {
      ctrl.toggleNoCaching();
      expect(ctrl.noCachingEnabled.value, isTrue);
    });

    test('toggleNoCaching turns off after on', () {
      ctrl.toggleNoCaching();
      ctrl.toggleNoCaching();
      expect(ctrl.noCachingEnabled.value, isFalse);
    });

    test('double toggle returns to original state', () {
      final original = ctrl.noCachingEnabled.value;
      ctrl.toggleNoCaching();
      ctrl.toggleNoCaching();
      expect(ctrl.noCachingEnabled.value, original);
    });
  });
}
