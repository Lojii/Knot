import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:knot/utils/magic_bytes.dart';

void main() {
  group('magic_bytes detectFileType', () {
    // ── Image formats ──

    test('PNG', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/png');
      expect(result.ext, 'png');
    });

    test('JPEG', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/jpeg');
    });

    test('GIF', () {
      final bytes = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/gif');
    });

    test('WebP', () {
      final bytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/webp');
    });

    test('ICO', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0x01, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/x-icon');
    });

    test('BMP', () {
      final bytes = Uint8List.fromList([0x42, 0x4D, 0x00, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/bmp');
    });

    test('TIFF (little-endian)', () {
      final bytes = Uint8List.fromList([0x49, 0x49, 0x2A, 0x00, 0x00, 0x00, 0x00, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/tiff');
    });

    test('PSD', () {
      final bytes = Uint8List.fromList([0x38, 0x42, 0x50, 0x53, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/vnd.adobe.photoshop');
    });

    test('JPEG XL', () {
      final bytes = Uint8List.fromList([0xFF, 0x0A, 0x00, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/jxl');
    });

    test('SVG', () {
      final bytes = Uint8List.fromList('<svg xmlns="http://www.w3.org/2000/svg"></svg>'.codeUnits);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/svg+xml');
    });

    test('AVIF (ftyp avif)', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x1C, // size
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x61, 0x76, 0x69, 0x66, // avif
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/avif');
    });

    test('HEIC (ftyp heic)', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x1C,
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x68, 0x65, 0x69, 0x63, // heic
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'image/heic');
    });

    // ── Font formats ──

    test('WOFF', () {
      final bytes = Uint8List.fromList([0x77, 0x4F, 0x46, 0x46]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'font/woff');
    });

    test('WOFF2', () {
      final bytes = Uint8List.fromList([0x77, 0x4F, 0x46, 0x32]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'font/woff2');
    });

    test('OTF', () {
      final bytes = Uint8List.fromList([0x4F, 0x54, 0x54, 0x4F]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'font/otf');
    });

    // ── Video formats ──

    test('MP4 (ftyp isom)', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20,
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x69, 0x73, 0x6F, 0x6D, // isom
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'video/mp4');
    });

    test('WebM (EBML)', () {
      final bytes = Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0x00, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, contains('video/'));
    });

    test('FLV', () {
      final bytes = Uint8List.fromList([0x46, 0x4C, 0x56, 0x01]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'video/x-flv');
    });

    test('AVI', () {
      final bytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00,
        0x41, 0x56, 0x49, 0x20, // AVI
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'video/x-msvideo');
    });

    // ── Audio formats ──

    test('MP3 (ID3)', () {
      final bytes = Uint8List.fromList([0x49, 0x44, 0x33, 0x03]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/mpeg');
    });

    test('OGG', () {
      final bytes = Uint8List.fromList([0x4F, 0x67, 0x67, 0x53]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/ogg');
    });

    test('FLAC', () {
      final bytes = Uint8List.fromList([0x66, 0x4C, 0x61, 0x43]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/flac');
    });

    test('WAV', () {
      final bytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46,
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x41, 0x56, 0x45,
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/wav');
    });

    test('AIFF', () {
      final bytes = Uint8List.fromList([
        0x46, 0x4F, 0x52, 0x4D,
        0x00, 0x00, 0x00, 0x00,
        0x41, 0x49, 0x46, 0x46,
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/aiff');
    });

    test('MIDI', () {
      final bytes = Uint8List.fromList([0x4D, 0x54, 0x68, 0x64]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/midi');
    });

    test('AAC (ADTS)', () {
      final bytes = Uint8List.fromList([0xFF, 0xF1, 0x00, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/aac');
    });

    test('AMR', () {
      final bytes = Uint8List.fromList([0x23, 0x21, 0x41, 0x4D, 0x52]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/amr');
    });

    test('M4A (ftyp M4A)', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x1C,
        0x66, 0x74, 0x79, 0x70, // ftyp
        0x4D, 0x34, 0x41, 0x20, // M4A
      ]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'audio/mp4');
    });

    // ── Document formats ──

    test('PDF', () {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/pdf');
    });

    test('RTF', () {
      final bytes = Uint8List.fromList([0x7B, 0x5C, 0x72, 0x74, 0x66]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/rtf');
    });

    test('PostScript', () {
      final bytes = Uint8List.fromList([0x25, 0x21, 0x50, 0x53]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/postscript');
    });

    test('OLE2 (generic)', () {
      final bytes = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, contains('application/'));
    });

    // ── Archive formats ──

    test('ZIP', () {
      final bytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/zip');
    });

    test('GZIP', () {
      final bytes = Uint8List.fromList([0x1F, 0x8B, 0x08]);
      // Need 4 bytes minimum
      final padded = Uint8List.fromList([0x1F, 0x8B, 0x08, 0x00]);
      final result = detectFileType(padded);
      expect(result, isNotNull);
      expect(result!.mime, 'application/gzip');
    });

    test('BZIP2', () {
      final bytes = Uint8List.fromList([0x42, 0x5A, 0x68, 0x39]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/x-bzip2');
    });

    test('7-Zip', () {
      final bytes = Uint8List.fromList([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/x-7z-compressed');
    });

    test('XZ', () {
      final bytes = Uint8List.fromList([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/x-xz');
    });

    test('Zstandard', () {
      final bytes = Uint8List.fromList([0x28, 0xB5, 0x2F, 0xFD]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/zstd');
    });

    test('RAR', () {
      final bytes = Uint8List.fromList([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/x-rar-compressed');
    });

    // ── Executable formats ──

    test('ELF', () {
      final bytes = Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, contains('application/x-'));
    });

    test('PE/EXE', () {
      final bytes = Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/x-msdownload');
    });

    test('Java class', () {
      // CAFEBABE with valid class version (0x34 = Java 8)
      final bytes = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x34]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/java-vm');
    });

    test('Mach-O (single arch)', () {
      final bytes = Uint8List.fromList([0xFE, 0xED, 0xFA, 0xCE]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/x-mach-binary');
    });

    // ── Other formats ──

    test('WASM', () {
      final bytes = Uint8List.fromList([0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/wasm');
    });

    test('SQLite', () {
      final bytes = Uint8List.fromList([0x53, 0x51, 0x4C, 0x69]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/vnd.sqlite3');
    });

    test('glTF binary', () {
      final bytes = Uint8List.fromList([0x67, 0x6C, 0x54, 0x46]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'model/gltf-binary');
    });

    test('Parquet', () {
      final bytes = Uint8List.fromList([0x50, 0x41, 0x52, 0x31]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/vnd.apache.parquet');
    });

    test('RPM', () {
      final bytes = Uint8List.fromList([0xED, 0xAB, 0xEE, 0xDB]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/x-rpm');
    });

    test('CAB', () {
      final bytes = Uint8List.fromList([0x4D, 0x53, 0x43, 0x46]);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/vnd.ms-cab-compressed');
    });

    // ── Text formats ──

    test('JSON (object)', () {
      final bytes = Uint8List.fromList('  {"key": "value"}'.codeUnits);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/json');
    });

    test('JSON (array)', () {
      final bytes = Uint8List.fromList('[1, 2, 3]'.codeUnits);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'application/json');
    });

    test('HTML', () {
      final bytes = Uint8List.fromList('<!DOCTYPE html><html>'.codeUnits);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'text/html');
    });

    test('XML', () {
      final bytes = Uint8List.fromList('<?xml version="1.0"?>'.codeUnits);
      final result = detectFileType(bytes);
      expect(result, isNotNull);
      expect(result!.mime, 'text/xml');
    });

    // ── Edge cases ──

    test('empty bytes returns null', () {
      expect(detectFileType(Uint8List(0)), isNull);
    });

    test('single byte returns null', () {
      expect(detectFileType(Uint8List.fromList([0x00])), isNull);
    });

    test('random bytes returns null', () {
      expect(detectFileType(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])), isNull);
    });

    // ── Real file tests (from /tmp) ──

    group('real file detection', () {
      final testDir = Directory('/tmp/knot_magic_test');
      if (!testDir.existsSync()) return;

      final expected = <String, String>{
        'test.png': 'image/png',
        'test.jpg': 'image/jpeg',
        'test.gif': 'image/gif',
        'test.webp': 'image/webp',
        'test.ico': 'image/x-icon',
        'test.bmp': 'image/bmp',
        'test.tif': 'image/tiff',
        'test.psd': 'image/vnd.adobe.photoshop',
        'test.jxl': 'image/jxl',
        'test.svg': 'image/svg+xml',
        'test.avif': 'image/avif',
        'test.heic': 'image/heic',
        'test.woff': 'font/woff',
        'test.woff2': 'font/woff2',
        'test.otf': 'font/otf',
        'test.mp4': 'video/mp4',
        'test.webm': 'video/webm',
        'test.flv': 'video/x-flv',
        'test.avi': 'video/x-msvideo',
        'test.mp3': 'audio/mpeg',
        'test.ogg': 'audio/ogg',
        'test.flac': 'audio/flac',
        'test.wav': 'audio/wav',
        'test.aiff': 'audio/aiff',
        'test.mid': 'audio/midi',
        'test.aac': 'audio/aac',
        'test.amr': 'audio/amr',
        'test.m4a': 'audio/mp4',
        'test.pdf': 'application/pdf',
        'test.rtf': 'application/rtf',
        'test.ps': 'application/postscript',
        'test.zip': 'application/zip',
        'test.gz': 'application/gzip',
        'test.bz2': 'application/x-bzip2',
        'test.xz': 'application/x-xz',
        'test.zst': 'application/zstd',
        'test.7z': 'application/x-7z-compressed',
        'test.rar': 'application/x-rar-compressed',
        'test.elf': 'application/x-executable',
        'test.exe': 'application/x-msdownload',
        'test.ole': 'application/x-cfb',
        'test.wasm': 'application/wasm',
        'test.sqlite': 'application/vnd.sqlite3',
        'test.glb': 'model/gltf-binary',
        'test.parquet': 'application/vnd.apache.parquet',
        'test.rpm': 'application/x-rpm',
        'test.cab': 'application/vnd.ms-cab-compressed',
        'test.class': 'application/java-vm',
        'test.macho': 'application/x-mach-binary',
        'test.json': 'application/json',
        'test.html': 'text/html',
        'test.xml': 'text/xml',
      };

      for (final entry in expected.entries) {
        test('file: ${entry.key} → ${entry.value}', () {
          final file = File('${testDir.path}/${entry.key}');
          if (!file.existsSync()) {
            markTestSkipped('File not found: ${entry.key}');
            return;
          }
          final bytes = file.readAsBytesSync();
          final result = detectFileType(Uint8List.fromList(bytes));
          expect(result, isNotNull, reason: 'Failed to detect ${entry.key}');
          expect(result!.mime, entry.value, reason: 'Wrong mime for ${entry.key}');
        });
      }
    });
  });
}
