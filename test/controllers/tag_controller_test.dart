import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/controllers/tag_controller.dart';

void main() {
  late TagController ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = TagController();
  });

  tearDown(() {
    Get.reset();
  });

  group('TagController - tags', () {
    test('getTag returns null for non-existent flowId', () {
      expect(ctrl.getTag('nonexistent'), isNull);
    });

    test('setTag stores color for flowId', () {
      ctrl.setTag('flow-1', Colors.red);
      expect(ctrl.getTag('flow-1'), Colors.red);
    });

    test('getTag retrieves stored color', () {
      ctrl.setTag('flow-1', Colors.blue);
      final color = ctrl.getTag('flow-1');
      expect(color, Colors.blue);
    });

    test('removeTag clears tag', () {
      ctrl.setTag('flow-1', Colors.green);
      ctrl.removeTag('flow-1');
      expect(ctrl.getTag('flow-1'), isNull);
    });

    test('removeTag on non-existent flowId does not throw', () {
      expect(() => ctrl.removeTag('nonexistent'), returnsNormally);
    });

    test('multiple tags on different flows', () {
      ctrl.setTag('flow-1', Colors.red);
      ctrl.setTag('flow-2', Colors.blue);
      ctrl.setTag('flow-3', Colors.green);
      expect(ctrl.getTag('flow-1'), Colors.red);
      expect(ctrl.getTag('flow-2'), Colors.blue);
      expect(ctrl.getTag('flow-3'), Colors.green);
    });

    test('overwrite existing tag', () {
      ctrl.setTag('flow-1', Colors.red);
      ctrl.setTag('flow-1', Colors.purple);
      expect(ctrl.getTag('flow-1'), Colors.purple);
    });

    test('setting tag to same color is idempotent', () {
      ctrl.setTag('flow-1', Colors.orange);
      ctrl.setTag('flow-1', Colors.orange);
      expect(ctrl.getTag('flow-1'), Colors.orange);
    });
  });

  group('TagController - comments', () {
    test('getComment returns null for non-existent flowId', () {
      expect(ctrl.getComment('nonexistent'), isNull);
    });

    test('setComment stores comment for flowId', () {
      ctrl.setComment('flow-1', 'This is a test');
      expect(ctrl.getComment('flow-1'), 'This is a test');
    });

    test('getComment retrieves stored comment', () {
      ctrl.setComment('flow-1', 'Login request');
      final comment = ctrl.getComment('flow-1');
      expect(comment, 'Login request');
    });

    test('removeComment clears comment', () {
      ctrl.setComment('flow-1', 'test');
      ctrl.removeComment('flow-1');
      expect(ctrl.getComment('flow-1'), isNull);
    });

    test('removeComment on non-existent flowId does not throw', () {
      expect(() => ctrl.removeComment('nonexistent'), returnsNormally);
    });

    test('multiple comments on different flows', () {
      ctrl.setComment('flow-1', 'First');
      ctrl.setComment('flow-2', 'Second');
      ctrl.setComment('flow-3', 'Third');
      expect(ctrl.getComment('flow-1'), 'First');
      expect(ctrl.getComment('flow-2'), 'Second');
      expect(ctrl.getComment('flow-3'), 'Third');
    });

    test('overwrite existing comment', () {
      ctrl.setComment('flow-1', 'old comment');
      ctrl.setComment('flow-1', 'new comment');
      expect(ctrl.getComment('flow-1'), 'new comment');
    });

    test('empty string comment is valid', () {
      ctrl.setComment('flow-1', '');
      expect(ctrl.getComment('flow-1'), '');
    });

    test('comment with special characters', () {
      ctrl.setComment('flow-1', 'Unicode: \u00e9\u00e8\u00ea & symbols: <>"\'');
      expect(ctrl.getComment('flow-1'), 'Unicode: \u00e9\u00e8\u00ea & symbols: <>"\'');
    });
  });

  group('TagController - tags and comments independent', () {
    test('setting tag does not affect comment', () {
      ctrl.setTag('flow-1', Colors.red);
      expect(ctrl.getComment('flow-1'), isNull);
    });

    test('setting comment does not affect tag', () {
      ctrl.setComment('flow-1', 'test');
      expect(ctrl.getTag('flow-1'), isNull);
    });

    test('removing tag does not affect comment', () {
      ctrl.setTag('flow-1', Colors.red);
      ctrl.setComment('flow-1', 'test');
      ctrl.removeTag('flow-1');
      expect(ctrl.getTag('flow-1'), isNull);
      expect(ctrl.getComment('flow-1'), 'test');
    });

    test('removing comment does not affect tag', () {
      ctrl.setTag('flow-1', Colors.blue);
      ctrl.setComment('flow-1', 'test');
      ctrl.removeComment('flow-1');
      expect(ctrl.getComment('flow-1'), isNull);
      expect(ctrl.getTag('flow-1'), Colors.blue);
    });
  });

  group('TagController - predefined tag colors', () {
    test('tagColors has 6 entries', () {
      expect(TagController.tagColors.length, 6);
    });

    test('tagColors contains expected color names', () {
      final names = TagController.tagColors.map((e) => e.key).toList();
      expect(names, contains('Red'));
      expect(names, contains('Orange'));
      expect(names, contains('Yellow'));
      expect(names, contains('Green'));
      expect(names, contains('Blue'));
      expect(names, contains('Purple'));
    });

    test('each tagColor has a non-null Color value', () {
      for (final entry in TagController.tagColors) {
        expect(entry.value, isNotNull);
        expect(entry.value, isA<Color>());
      }
    });
  });
}
