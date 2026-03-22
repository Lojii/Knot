import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/json_viewer.dart';

void main() {
  Widget buildWidget(String jsonString) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: JsonViewer(jsonString: jsonString),
        ),
      ),
    );
  }

  group('JsonViewer', () {
    testWidgets('renders valid JSON object with pretty printing',
        (tester) async {
      final input = jsonEncode({'name': 'test', 'count': 42});
      await tester.pumpWidget(buildWidget(input));

      // Should find the pretty-printed version
      expect(find.textContaining('name'), findsOneWidget);
      expect(find.textContaining('test'), findsOneWidget);
      expect(find.textContaining('42'), findsOneWidget);
    });

    testWidgets('renders valid JSON array', (tester) async {
      final input = jsonEncode([1, 2, 3]);
      await tester.pumpWidget(buildWidget(input));

      expect(find.textContaining('1'), findsOneWidget);
    });

    testWidgets('renders nested JSON', (tester) async {
      final input = jsonEncode({
        'outer': {'inner': 'value'},
      });
      await tester.pumpWidget(buildWidget(input));

      expect(find.textContaining('outer'), findsOneWidget);
      expect(find.textContaining('inner'), findsOneWidget);
      expect(find.textContaining('value'), findsOneWidget);
    });

    testWidgets('renders invalid JSON as raw string', (tester) async {
      const input = 'this is not json {{{';
      await tester.pumpWidget(buildWidget(input));

      expect(find.text(input), findsOneWidget);
    });

    testWidgets('renders empty string', (tester) async {
      await tester.pumpWidget(buildWidget(''));

      expect(find.text(''), findsOneWidget);
    });

    testWidgets('renders empty JSON object', (tester) async {
      await tester.pumpWidget(buildWidget('{}'));

      expect(find.textContaining('{}'), findsOneWidget);
    });

    testWidgets('renders empty JSON array', (tester) async {
      await tester.pumpWidget(buildWidget('[]'));

      expect(find.textContaining('[]'), findsOneWidget);
    });

    testWidgets('uses SelectableText for output', (tester) async {
      await tester.pumpWidget(buildWidget('{"a":1}'));

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('pretty prints with 2-space indentation', (tester) async {
      final input = jsonEncode({'key': 'value'});
      await tester.pumpWidget(buildWidget(input));

      // The pretty-printed version should have indentation
      final expected = const JsonEncoder.withIndent('  ').convert({'key': 'value'});
      expect(find.text(expected), findsOneWidget);
    });
  });
}
