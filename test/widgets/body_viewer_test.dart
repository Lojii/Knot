import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/body_viewer.dart';

void main() {
  Widget buildWidget({
    required String body,
    String contentType = '',
    String label = '',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BodyViewer(body: body, contentType: contentType, label: label),
        ),
      ),
    );
  }

  group('BodyViewer', () {
    testWidgets('shows "(empty)" for empty body', (tester) async {
      await tester.pumpWidget(buildWidget(body: ''));

      expect(find.text('(empty)'), findsOneWidget);
    });

    testWidgets('renders plain text body', (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Hello, World!'));

      expect(find.text('Hello, World!'), findsOneWidget);
    });

    testWidgets('detects JSON by contentType containing "json"',
        (tester) async {
      final jsonBody = jsonEncode({'key': 'value'});
      await tester.pumpWidget(buildWidget(
        body: jsonBody,
        contentType: 'application/json',
      ));

      // Should pretty-print the JSON
      expect(find.textContaining('key'), findsOneWidget);
      expect(find.textContaining('value'), findsOneWidget);
    });

    testWidgets('detects JSON by body starting with {', (tester) async {
      await tester.pumpWidget(buildWidget(body: '{"name": "test"}'));

      expect(find.textContaining('name'), findsOneWidget);
      expect(find.textContaining('test'), findsOneWidget);
    });

    testWidgets('detects JSON by body starting with [', (tester) async {
      await tester.pumpWidget(buildWidget(body: '[1, 2, 3]'));

      // Should render as formatted JSON
      expect(find.textContaining('1'), findsOneWidget);
    });

    testWidgets('handles invalid JSON gracefully (shows raw text)',
        (tester) async {
      await tester.pumpWidget(buildWidget(
        body: '{broken json',
        contentType: 'application/json',
      ));

      expect(find.textContaining('{broken json'), findsOneWidget);
    });

    testWidgets('detects image contentType', (tester) async {
      // Non-base64 body with image content type should show fallback text
      await tester.pumpWidget(buildWidget(
        body: 'not-base64-data',
        contentType: 'image/png',
      ));

      // Should show image info text since base64 decode will fail
      expect(find.textContaining('image/png'), findsOneWidget);
    });

    testWidgets('JSON detection with leading whitespace', (tester) async {
      await tester.pumpWidget(buildWidget(body: '  {"key": "value"}'));

      expect(find.textContaining('key'), findsOneWidget);
    });

    testWidgets('non-JSON plain text does not get JSON formatted',
        (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Just plain text here'));

      expect(find.text('Just plain text here'), findsOneWidget);
    });
  });
}
