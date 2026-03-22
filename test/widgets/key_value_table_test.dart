import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/key_value_table.dart';

void main() {
  Widget buildWidget(List<(String, String)> entries) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KeyValueTable(entries: entries),
        ),
      ),
    );
  }

  group('KeyValueTable', () {
    testWidgets('renders key-value entries', (tester) async {
      await tester.pumpWidget(buildWidget([
        ('Host', 'example.com'),
        ('Method', 'GET'),
        ('Status', '200'),
      ]));

      expect(find.text('Host'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('Method'), findsOneWidget);
      expect(find.text('GET'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
    });

    testWidgets('renders empty table without error', (tester) async {
      await tester.pumpWidget(buildWidget([]));

      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('renders single entry', (tester) async {
      await tester.pumpWidget(buildWidget([
        ('Content-Type', 'text/html'),
      ]));

      expect(find.text('Content-Type'), findsOneWidget);
      expect(find.text('text/html'), findsOneWidget);
    });

    testWidgets('renders entries with empty values', (tester) async {
      await tester.pumpWidget(buildWidget([
        ('Key', ''),
      ]));

      expect(find.text('Key'), findsOneWidget);
      // Empty string still creates a SelectableText widget
      expect(find.byType(SelectableText), findsWidgets);
    });

    testWidgets('uses Table widget', (tester) async {
      await tester.pumpWidget(buildWidget([
        ('A', 'B'),
      ]));

      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('keys are rendered bold', (tester) async {
      await tester.pumpWidget(buildWidget([
        ('BoldKey', 'NormalValue'),
      ]));

      // Find all SelectableText widgets and check the one containing 'BoldKey'
      final selectables = tester.widgetList<SelectableText>(find.byType(SelectableText));
      final keyWidget = selectables.where((w) => w.data == 'BoldKey').firstOrNull;
      expect(keyWidget, isNotNull);
      expect(keyWidget!.style?.fontWeight, FontWeight.bold);
    });
  });
}
