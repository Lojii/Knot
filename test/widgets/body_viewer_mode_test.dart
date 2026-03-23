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

  group('BodyViewer - mode toggle display', () {
    testWidgets('shows Pretty, Raw, Hex mode buttons', (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Hello'));
      expect(find.text('Pretty'), findsOneWidget);
      expect(find.text('Raw'), findsOneWidget);
      expect(find.text('Hex'), findsOneWidget);
    });

    testWidgets('no mode toggles shown for empty body', (tester) async {
      await tester.pumpWidget(buildWidget(body: ''));
      expect(find.text('Pretty'), findsNothing);
      expect(find.text('Raw'), findsNothing);
      expect(find.text('Hex'), findsNothing);
    });
  });

  group('BodyViewer - Pretty mode (default)', () {
    testWidgets('default mode is Pretty', (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Some text'));
      // In Pretty mode with plain text, it shows the text directly
      expect(find.textContaining('Some text'), findsOneWidget);
    });

    testWidgets('JSON content is auto-formatted in Pretty mode', (tester) async {
      final jsonBody = '{"name":"Alice","age":30}';
      await tester.pumpWidget(buildWidget(body: jsonBody));
      // Pretty mode should format JSON with indentation
      expect(find.textContaining('name'), findsOneWidget);
      expect(find.textContaining('Alice'), findsOneWidget);
    });

    testWidgets('JSON array is auto-formatted in Pretty mode', (tester) async {
      final jsonBody = '[1,2,3]';
      await tester.pumpWidget(buildWidget(body: jsonBody));
      expect(find.textContaining('1'), findsOneWidget);
    });

    testWidgets('XML content handled in Pretty mode', (tester) async {
      await tester.pumpWidget(buildWidget(
        body: '<root><child>text</child></root>',
        contentType: 'text/xml',
      ));
      expect(find.textContaining('<root>'), findsOneWidget);
      expect(find.textContaining('<child>'), findsOneWidget);
    });

    testWidgets('HTML content handled in Pretty mode', (tester) async {
      await tester.pumpWidget(buildWidget(
        body: '<html><body>Hello</body></html>',
        contentType: 'text/html',
      ));
      expect(find.textContaining('<html>'), findsOneWidget);
    });
  });

  group('BodyViewer - Raw mode', () {
    testWidgets('switching to Raw mode shows unformatted text', (tester) async {
      final jsonBody = '{"name":"Alice"}';
      await tester.pumpWidget(buildWidget(body: jsonBody));

      // Tap Raw mode
      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();

      // In Raw mode, should show the original unformatted string
      expect(find.textContaining('{"name":"Alice"}'), findsOneWidget);
    });

    testWidgets('Raw mode shows plain text as-is', (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Plain text content'));
      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Plain text content'), findsOneWidget);
    });
  });

  group('BodyViewer - Hex mode', () {
    testWidgets('switching to Hex mode shows hex dump', (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Hello'));
      await tester.tap(find.text('Hex'));
      await tester.pumpAndSettle();

      // Hex mode shows offset + hex bytes + ASCII
      // "Hello" = 48 65 6c 6c 6f
      expect(find.textContaining('48'), findsOneWidget);
      expect(find.textContaining('65'), findsOneWidget);
      expect(find.textContaining('|Hello|'), findsOneWidget);
    });

    testWidgets('Hex mode shows offset column', (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Test data'));
      await tester.tap(find.text('Hex'));
      await tester.pumpAndSettle();

      // Should show 00000000 offset
      expect(find.textContaining('00000000'), findsOneWidget);
    });

    testWidgets('Hex dump limited to 4KB shows truncation message', (tester) async {
      // Create body larger than 4KB
      final bigBody = 'A' * 5000;
      await tester.pumpWidget(buildWidget(body: bigBody));
      await tester.tap(find.text('Hex'));
      await tester.pumpAndSettle();

      expect(find.textContaining('truncated at 4096'), findsOneWidget);
    });

    testWidgets('Hex dump for small body shows no truncation', (tester) async {
      await tester.pumpWidget(buildWidget(body: 'Small'));
      await tester.tap(find.text('Hex'));
      await tester.pumpAndSettle();
      expect(find.textContaining('truncated'), findsNothing);
    });

    testWidgets('non-ASCII content in Hex mode shows dots for unprintable bytes', (tester) async {
      // Tab character (0x09) should show as '.'
      await tester.pumpWidget(buildWidget(body: 'A\tB'));
      await tester.tap(find.text('Hex'));
      await tester.pumpAndSettle();

      // ASCII column: A.B (tab replaced with dot)
      expect(find.textContaining('|A.B|'), findsOneWidget);
    });
  });

  group('BodyViewer - empty body', () {
    testWidgets('shows "(empty)" text', (tester) async {
      await tester.pumpWidget(buildWidget(body: ''));
      expect(find.text('(empty)'), findsOneWidget);
    });

    testWidgets('does not show mode toggles for empty body', (tester) async {
      await tester.pumpWidget(buildWidget(body: ''));
      expect(find.text('Pretty'), findsNothing);
      expect(find.text('Raw'), findsNothing);
      expect(find.text('Hex'), findsNothing);
    });
  });

  group('BodyViewer - mode switching', () {
    testWidgets('can switch from Pretty to Raw to Hex and back', (tester) async {
      await tester.pumpWidget(buildWidget(body: '{"key":"val"}'));

      // Start in Pretty
      expect(find.textContaining('key'), findsOneWidget);

      // Switch to Raw
      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();
      expect(find.textContaining('{"key":"val"}'), findsOneWidget);

      // Switch to Hex
      await tester.tap(find.text('Hex'));
      await tester.pumpAndSettle();
      expect(find.textContaining('00000000'), findsOneWidget);

      // Switch back to Pretty
      await tester.tap(find.text('Pretty'));
      await tester.pumpAndSettle();
      expect(find.textContaining('key'), findsOneWidget);
    });
  });

  group('BodyViewMode enum', () {
    test('has three values', () {
      expect(BodyViewMode.values.length, 3);
    });

    test('values are pretty, raw, hex', () {
      expect(BodyViewMode.values, contains(BodyViewMode.pretty));
      expect(BodyViewMode.values, contains(BodyViewMode.raw));
      expect(BodyViewMode.values, contains(BodyViewMode.hex));
    });
  });
}
