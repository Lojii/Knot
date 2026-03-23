import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/controllers/page_controller.dart';

void main() {
  late AppPageController ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = AppPageController();
  });

  tearDown(() {
    Get.reset();
  });

  group('AppPageController - initial state', () {
    test('initial page is capture', () {
      expect(ctrl.currentPage.value, AppPage.capture);
    });

    test('isCapture is true initially', () {
      expect(ctrl.isCapture, isTrue);
    });

    test('isSubPage is false initially', () {
      expect(ctrl.isSubPage, isFalse);
    });

    test('all other page booleans are false initially', () {
      expect(ctrl.isHistory, isFalse);
      expect(ctrl.isSettings, isFalse);
      expect(ctrl.isCompose, isFalse);
      expect(ctrl.isMapRemote, isFalse);
      expect(ctrl.isMapLocal, isFalse);
      expect(ctrl.isAllowBlock, isFalse);
      expect(ctrl.isDiff, isFalse);
      expect(ctrl.isBreakpointMgmt, isFalse);
    });
  });

  group('AppPageController - navigation', () {
    test('showHistory changes to history', () {
      ctrl.showHistory();
      expect(ctrl.currentPage.value, AppPage.history);
      expect(ctrl.isHistory, isTrue);
      expect(ctrl.isCapture, isFalse);
    });

    test('showSettings changes to settings', () {
      ctrl.showSettings();
      expect(ctrl.currentPage.value, AppPage.settings);
      expect(ctrl.isSettings, isTrue);
    });

    test('showCompose changes to compose', () {
      ctrl.showCompose();
      expect(ctrl.currentPage.value, AppPage.compose);
      expect(ctrl.isCompose, isTrue);
    });

    test('showCapture returns to capture', () {
      ctrl.showHistory();
      expect(ctrl.isCapture, isFalse);
      ctrl.showCapture();
      expect(ctrl.isCapture, isTrue);
      expect(ctrl.currentPage.value, AppPage.capture);
    });

    test('showMapRemote navigates to mapRemote', () {
      ctrl.showMapRemote();
      expect(ctrl.isMapRemote, isTrue);
    });

    test('showMapLocal navigates to mapLocal', () {
      ctrl.showMapLocal();
      expect(ctrl.isMapLocal, isTrue);
    });

    test('showAllowBlock navigates to allowBlock', () {
      ctrl.showAllowBlock();
      expect(ctrl.isAllowBlock, isTrue);
    });

    test('showDiff navigates to diff', () {
      ctrl.showDiff();
      expect(ctrl.isDiff, isTrue);
    });

    test('showBreakpointMgmt navigates to breakpointMgmt', () {
      ctrl.showBreakpointMgmt();
      expect(ctrl.isBreakpointMgmt, isTrue);
    });
  });

  group('AppPageController - isSubPage', () {
    test('isSubPage true for history', () {
      ctrl.showHistory();
      expect(ctrl.isSubPage, isTrue);
    });

    test('isSubPage true for settings', () {
      ctrl.showSettings();
      expect(ctrl.isSubPage, isTrue);
    });

    test('isSubPage true for compose', () {
      ctrl.showCompose();
      expect(ctrl.isSubPage, isTrue);
    });

    test('isSubPage true for mapRemote', () {
      ctrl.showMapRemote();
      expect(ctrl.isSubPage, isTrue);
    });

    test('isSubPage true for diff', () {
      ctrl.showDiff();
      expect(ctrl.isSubPage, isTrue);
    });

    test('isSubPage true for breakpointMgmt', () {
      ctrl.showBreakpointMgmt();
      expect(ctrl.isSubPage, isTrue);
    });

    test('isSubPage false for capture', () {
      ctrl.showHistory(); // go away first
      ctrl.showCapture();
      expect(ctrl.isSubPage, isFalse);
    });
  });

  group('AppPageController - compose prefill', () {
    test('openInCompose sets prefill data and navigates to compose', () {
      ctrl.openInCompose(
        method: 'POST',
        url: 'https://api.example.com/v1/create',
        headers: {'Content-Type': 'application/json'},
        body: '{"name": "test"}',
      );
      expect(ctrl.isCompose, isTrue);
      expect(ctrl.composePrefillMethod, 'POST');
      expect(ctrl.composePrefillUrl, 'https://api.example.com/v1/create');
      expect(ctrl.composePrefillHeaders, {'Content-Type': 'application/json'});
      expect(ctrl.composePrefillBody, '{"name": "test"}');
    });

    test('openInCompose with default headers and body', () {
      ctrl.openInCompose(
        method: 'GET',
        url: 'https://example.com/',
      );
      expect(ctrl.composePrefillHeaders, isEmpty);
      expect(ctrl.composePrefillBody, '');
    });

    test('clearComposePrefill clears all prefill data', () {
      ctrl.openInCompose(
        method: 'PUT',
        url: 'https://example.com/update',
        headers: {'Auth': 'Bearer x'},
        body: 'data',
      );
      ctrl.clearComposePrefill();
      expect(ctrl.composePrefillMethod, '');
      expect(ctrl.composePrefillUrl, '');
      expect(ctrl.composePrefillHeaders, isEmpty);
      expect(ctrl.composePrefillBody, '');
    });

    test('initial prefill data is empty', () {
      expect(ctrl.composePrefillMethod, '');
      expect(ctrl.composePrefillUrl, '');
      expect(ctrl.composePrefillHeaders, isEmpty);
      expect(ctrl.composePrefillBody, '');
    });

    test('openInCompose copies headers map (not reference)', () {
      final originalHeaders = {'Key': 'Value'};
      ctrl.openInCompose(
        method: 'GET',
        url: 'https://example.com/',
        headers: originalHeaders,
      );
      // Modifying original should not affect stored prefill
      originalHeaders['NewKey'] = 'NewValue';
      expect(ctrl.composePrefillHeaders.containsKey('NewKey'), isFalse);
    });

    test('openInCompose with multiple headers', () {
      ctrl.openInCompose(
        method: 'POST',
        url: 'https://example.com/',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer abc',
          'X-Request-Id': '12345',
        },
      );
      expect(ctrl.composePrefillHeaders.length, 3);
    });
  });

  group('AppPageController - boolean getters consistency', () {
    test('only one page boolean is true at a time', () {
      final checks = [
        () { ctrl.showCapture(); return [ctrl.isCapture, ctrl.isHistory, ctrl.isSettings, ctrl.isCompose, ctrl.isMapRemote, ctrl.isMapLocal, ctrl.isAllowBlock, ctrl.isDiff, ctrl.isBreakpointMgmt]; },
        () { ctrl.showHistory(); return [ctrl.isCapture, ctrl.isHistory, ctrl.isSettings, ctrl.isCompose, ctrl.isMapRemote, ctrl.isMapLocal, ctrl.isAllowBlock, ctrl.isDiff, ctrl.isBreakpointMgmt]; },
        () { ctrl.showSettings(); return [ctrl.isCapture, ctrl.isHistory, ctrl.isSettings, ctrl.isCompose, ctrl.isMapRemote, ctrl.isMapLocal, ctrl.isAllowBlock, ctrl.isDiff, ctrl.isBreakpointMgmt]; },
        () { ctrl.showCompose(); return [ctrl.isCapture, ctrl.isHistory, ctrl.isSettings, ctrl.isCompose, ctrl.isMapRemote, ctrl.isMapLocal, ctrl.isAllowBlock, ctrl.isDiff, ctrl.isBreakpointMgmt]; },
        () { ctrl.showDiff(); return [ctrl.isCapture, ctrl.isHistory, ctrl.isSettings, ctrl.isCompose, ctrl.isMapRemote, ctrl.isMapLocal, ctrl.isAllowBlock, ctrl.isDiff, ctrl.isBreakpointMgmt]; },
      ];

      for (final check in checks) {
        final bools = check();
        final trueCount = bools.where((b) => b).length;
        expect(trueCount, 1, reason: 'Exactly one page boolean should be true');
      }
    });
  });
}
