import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/widgets/viewers/body_prep.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('prepareBody', () {
    test('pretty-prints JSON with 2-space indent', () {
      final result = prepareBody(BodyPrepRequest(
        bytes: _b('{"name":"Alice","age":30}'),
        language: 'json',
      ));

      final text = result.lines.map((l) => l.text).join('\n');
      expect(text, const JsonEncoder.withIndent('  ').convert({'name': 'Alice', 'age': 30}));
      expect(result.lines.first.number, 1);
      expect(result.lines.last.number, result.lines.length);
    });

    test('falls back to raw text for invalid JSON', () {
      final result = prepareBody(BodyPrepRequest(
        bytes: _b('{broken json'),
        language: 'json',
      ));

      expect(result.lines.single.text, '{broken json');
    });

    test('does not format when format is false', () {
      final result = prepareBody(BodyPrepRequest(
        bytes: _b('{"a":1}'),
        language: 'json',
        format: false,
      ));

      expect(result.lines.single.text, '{"a":1}');
    });

    test('indents XML', () {
      final result = prepareBody(BodyPrepRequest(
        bytes: _b('<root><child>text</child></root>'),
        language: 'xml',
      ));

      final texts = result.lines.map((l) => l.text).toList();
      expect(texts, contains('<root>'));
      expect(texts.any((t) => t.startsWith('  ') && t.contains('<child>')), isTrue);
    });

    test('chunks overlong lines; only first chunk keeps the line number', () {
      final long = 'x' * 5000;
      final result = prepareBody(BodyPrepRequest(
        bytes: _b('short\n$long'),
        language: 'text',
        maxLineChars: 2000,
      ));

      expect(result.lines[0].text, 'short');
      expect(result.lines[0].number, 1);

      final chunks = result.lines.skip(1).toList();
      expect(chunks.length, 3); // 2000 + 2000 + 1000
      expect(chunks[0].number, 2);
      expect(chunks[1].number, isNull);
      expect(chunks[2].number, isNull);
      expect(chunks.map((c) => c.text).join(), long);
      expect(chunks.every((c) => c.text.length <= 2000), isTrue);
    });

    test('decodes non-utf8 bytes via latin1 fallback', () {
      final result = prepareBody(BodyPrepRequest(
        bytes: Uint8List.fromList([0x68, 0x69, 0xFF]),
        language: 'text',
      ));

      expect(result.lines.single.text.startsWith('hi'), isTrue);
    });
  });
}
