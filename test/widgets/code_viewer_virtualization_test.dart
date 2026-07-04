import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:knot/i18n/translations.dart';
import 'package:knot/widgets/body_viewer.dart';
import 'package:knot/widgets/viewers/code_viewer.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('CodeViewer virtualization', () {
    testWidgets('builds only visible rows for a body with thousands of lines',
        (tester) async {
      // ~5000 lines, well under the isolate threshold so prep runs synchronously.
      final body = List.generate(5000, (i) => '"row $i"').join('\n');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CodeViewer(bytes: _b(body), language: 'json', formatJson: false),
          ),
        ),
      ));

      // Virtualized: only rows near the viewport are materialized.
      final rowCount = tester.widgetList(find.byType(RichText)).length;
      expect(rowCount, lessThan(300));

      // First line is visible, far-away lines are not built.
      expect(find.textContaining('row 0', findRichText: true), findsWidgets);
      expect(find.textContaining('row 4999', findRichText: true), findsNothing);
    });

    testWidgets('scrolling reveals later lines', (tester) async {
      final body = List.generate(2000, (i) => 'line-$i').join('\n');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: CodeViewer(bytes: _b(body), language: 'text'),
          ),
        ),
      ));

      expect(find.textContaining('line-1999', findRichText: true), findsNothing);

      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.textContaining('line-1999', findRichText: true),
        5000,
        scrollable: list,
        maxScrolls: 200,
      );

      expect(find.textContaining('line-1999', findRichText: true), findsWidgets);
    });
  });

  group('BodyViewer layout', () {
    testWidgets('renders inside unbounded height without throwing',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('en', 'US'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyViewer(
              bytes: _b('{"key":"value"}'),
              contentType: 'application/json',
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('key', findRichText: true), findsWidgets);
    });
  });
}
