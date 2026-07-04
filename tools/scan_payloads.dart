#!/usr/bin/env dart
// ignore_for_file: avoid_print

// Scans all captured payload files, detects file types via magic bytes,
// decompresses gzip/zlib/brotli before detection, and outputs statistics.
//
// Usage: dart run tools/scan_payloads.dart

import 'dart:io';
import 'dart:typed_data';

// ── Inline magic bytes detection (same logic as lib/utils/magic_bytes.dart) ──

class FileType {
  final String mime;
  final String ext;
  const FileType(this.mime, this.ext);
  @override
  String toString() => '$mime (.$ext)';
}

FileType? detectFileType(Uint8List bytes) {
  if (bytes.length < 2) return null;

  // Images
  if (_match(bytes, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return const FileType('image/png', 'png');
  if (_match(bytes, [0xFF, 0xD8, 0xFF])) return const FileType('image/jpeg', 'jpg');
  if (_match(bytes, [0x47, 0x49, 0x46, 0x38])) return const FileType('image/gif', 'gif');
  if (_matchStr(bytes, 'RIFF') && bytes.length >= 12 && _matchStr(bytes, 'WEBP', offset: 8)) return const FileType('image/webp', 'webp');
  if (_match(bytes, [0xFF, 0x0A])) return const FileType('image/jxl', 'jxl');
  if (_match(bytes, [0x00, 0x00, 0x01, 0x00])) return const FileType('image/x-icon', 'ico');
  if (_match(bytes, [0x42, 0x4D])) return const FileType('image/bmp', 'bmp');
  if (_match(bytes, [0x49, 0x49, 0x2A, 0x00]) || _match(bytes, [0x4D, 0x4D, 0x00, 0x2A])) return const FileType('image/tiff', 'tif');
  if (_matchStr(bytes, '8BPS')) return const FileType('image/vnd.adobe.photoshop', 'psd');
  if (_matchStr(bytes, '<svg') || (_matchStr(bytes, '<?xml') && _containsStr(bytes, '<svg', limit: 512))) return const FileType('image/svg+xml', 'svg');

  // ftyp-based (HEIF/HEIC/AVIF/MP4/MOV/3GPP/M4A)
  if (bytes.length >= 12 && _matchStr(bytes, 'ftyp', offset: 4)) {
    final brand = _readStr(bytes, 8, 4);
    if (brand != null) {
      if (brand == 'avif' || brand == 'avis') return const FileType('image/avif', 'avif');
      if (brand == 'heic' || brand == 'heix') return const FileType('image/heic', 'heic');
      if (brand == 'mif1') return const FileType('image/heif', 'heif');
      if (brand == 'M4A ') return const FileType('audio/mp4', 'm4a');
      if (brand == 'qt  ') return const FileType('video/quicktime', 'mov');
      if (brand.startsWith('3gp')) return const FileType('video/3gpp', '3gp');
      return const FileType('video/mp4', 'mp4');
    }
  }

  // Fonts
  if (_match(bytes, [0x77, 0x4F, 0x46, 0x46])) return const FileType('font/woff', 'woff');
  if (_match(bytes, [0x77, 0x4F, 0x46, 0x32])) return const FileType('font/woff2', 'woff2');
  if (_matchStr(bytes, 'OTTO')) return const FileType('font/otf', 'otf');
  if (_matchStr(bytes, 'true')) return const FileType('font/ttf', 'ttf');
  if (_match(bytes, [0x00, 0x01, 0x00, 0x00]) && bytes.length > 12) return const FileType('font/ttf', 'ttf');

  // Video
  if (_match(bytes, [0x1A, 0x45, 0xDF, 0xA3])) return const FileType('video/webm', 'webm');
  if (_match(bytes, [0x46, 0x4C, 0x56, 0x01])) return const FileType('video/x-flv', 'flv');
  if (_matchStr(bytes, 'RIFF') && bytes.length >= 12 && _matchStr(bytes, 'AVI ', offset: 8)) return const FileType('video/x-msvideo', 'avi');

  // Audio
  if (_matchStr(bytes, 'ID3')) return const FileType('audio/mpeg', 'mp3');
  if (_match(bytes, [0xFF, 0xFB]) || _match(bytes, [0xFF, 0xF3]) || _match(bytes, [0xFF, 0xF2])) return const FileType('audio/mpeg', 'mp3');
  if (_matchStr(bytes, 'OggS')) return const FileType('audio/ogg', 'ogg');
  if (_matchStr(bytes, 'fLaC')) return const FileType('audio/flac', 'flac');
  if (_matchStr(bytes, 'RIFF') && bytes.length >= 12 && _matchStr(bytes, 'WAVE', offset: 8)) return const FileType('audio/wav', 'wav');
  if (_match(bytes, [0xFF, 0xF1]) || _match(bytes, [0xFF, 0xF9])) return const FileType('audio/aac', 'aac');

  // Documents
  if (_match(bytes, [0x25, 0x50, 0x44, 0x46])) return const FileType('application/pdf', 'pdf');
  if (_matchStr(bytes, '{\\rtf')) return const FileType('application/rtf', 'rtf');
  if (_match(bytes, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) return const FileType('application/x-cfb', 'cfb');
  if (_match(bytes, [0x50, 0x4B, 0x03, 0x04])) return const FileType('application/zip', 'zip');

  // Archives
  if (_match(bytes, [0x1F, 0x8B])) return const FileType('application/gzip', 'gz');
  if (_matchStr(bytes, 'BZh')) return const FileType('application/x-bzip2', 'bz2');
  if (_match(bytes, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) return const FileType('application/x-7z-compressed', '7z');
  if (_match(bytes, [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) return const FileType('application/x-xz', 'xz');
  if (_match(bytes, [0x28, 0xB5, 0x2F, 0xFD])) return const FileType('application/zstd', 'zst');
  if (_match(bytes, [0x78, 0x01]) || _match(bytes, [0x78, 0x9C]) || _match(bytes, [0x78, 0xDA])) return const FileType('application/zlib', 'zlib');

  // Executables
  if (_match(bytes, [0x7F, 0x45, 0x4C, 0x46])) return const FileType('application/x-executable', 'elf');
  if (_match(bytes, [0x4D, 0x5A])) return const FileType('application/x-msdownload', 'exe');
  if (_match(bytes, [0x00, 0x61, 0x73, 0x6D])) return const FileType('application/wasm', 'wasm');

  // Database
  if (_matchStr(bytes, 'SQLi')) return const FileType('application/vnd.sqlite3', 'sqlite');

  // Text-based
  final trimmed = _trimWS(bytes);
  if (trimmed.isNotEmpty && (trimmed[0] == 0x7B || trimmed[0] == 0x5B)) return const FileType('application/json', 'json');
  if (_matchStr(bytes, '<!DOCTYPE') || _matchStr(bytes, '<html') || _matchStr(bytes, '<!doctype')) return const FileType('text/html', 'html');
  if (_matchStr(bytes, '<?xml')) return const FileType('text/xml', 'xml');

  // Detect plain text
  if (_isText(bytes)) return const FileType('text/plain', 'txt');

  return null;
}

bool _match(Uint8List b, List<int> sig, {int offset = 0}) {
  if (b.length < offset + sig.length) return false;
  for (int i = 0; i < sig.length; i++) { if (b[offset + i] != sig[i]) return false; }
  return true;
}
bool _matchStr(Uint8List b, String s, {int offset = 0}) {
  if (b.length < offset + s.length) return false;
  for (int i = 0; i < s.length; i++) { if (b[offset + i] != s.codeUnitAt(i)) return false; }
  return true;
}
bool _containsStr(Uint8List b, String s, {int limit = 0}) {
  final end = limit > 0 ? limit.clamp(0, b.length) : b.length;
  final t = s.codeUnits;
  for (int i = 0; i <= end - t.length; i++) {
    bool f = true;
    for (int j = 0; j < t.length; j++) { if (b[i + j] != t[j]) { f = false; break; } }
    if (f) return true;
  }
  return false;
}
String? _readStr(Uint8List b, int off, int len) {
  if (b.length < off + len) return null;
  return String.fromCharCodes(b, off, off + len);
}
Uint8List _trimWS(Uint8List b) {
  int i = 0;
  while (i < b.length && (b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D)) {
    i++;
  }
  return i > 0 ? b.sublist(i) : b;
}
bool _isText(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  final sample = bytes.length > 512 ? bytes.sublist(0, 512) : bytes;
  int p = 0;
  for (final b in sample) { if ((b >= 32 && b <= 126) || b == 10 || b == 13 || b == 9) p++; }
  return p / sample.length > 0.85;
}

// ── Decompression ──

Uint8List? _tryGzip(Uint8List bytes) { try { return Uint8List.fromList(gzip.decode(bytes)); } catch (_) { return null; } }
Uint8List? _tryZlib(Uint8List bytes) { try { return Uint8List.fromList(zlib.decode(bytes)); } catch (_) { return null; } }

Uint8List _decompress(Uint8List bytes) {
  if (bytes.length < 2) return bytes;
  // gzip
  if (bytes[0] == 0x1F && bytes[1] == 0x8B) return _tryGzip(bytes) ?? bytes;
  // zlib
  if (bytes[0] == 0x78 && (bytes[1] == 0x01 || bytes[1] == 0x9C || bytes[1] == 0xDA)) return _tryZlib(bytes) ?? bytes;
  return bytes;
}

// ── Main ──

void main() async {
  final root = '/Users/aa123/Library/Group Containers/group.Lojii.NIO1901/tasks';
  final tasksDir = Directory(root);

  if (!tasksDir.existsSync()) {
    print('Tasks directory not found: $root');
    exit(1);
  }

  final counts = <String, int>{};       // mime → count
  final sizes = <String, int>{};        // mime → total bytes
  final compressed = <String, int>{};    // compression type → count
  int totalFiles = 0;
  int emptyFiles = 0;
  int unknownFiles = 0;
  int decompressedCount = 0;
  int errorCount = 0;

  final taskDirs = tasksDir.listSync().whereType<Directory>().toList();
  print('Found ${taskDirs.length} task directories');
  print('Scanning...\n');

  for (final taskDir in taskDirs) {
    final rawDir = Directory('${taskDir.path}/payloads/raw');
    if (!rawDir.existsSync()) continue;

    // Only scan response files (_rsp.bin) — they have the actual content
    final files = rawDir.listSync().whereType<File>().where((f) => f.path.endsWith('_rsp.bin')).toList();

    for (final file in files) {
      totalFiles++;
      if (totalFiles % 5000 == 0) {
        stdout.write('\r  Scanned $totalFiles files...');
      }

      try {
        var bytes = file.readAsBytesSync();

        if (bytes.isEmpty) {
          emptyFiles++;
          continue;
        }

        // Read first 8KB for detection (enough for most signatures)
        final sample = bytes.length > 8192 ? Uint8List.sublistView(bytes, 0, 8192) : Uint8List.fromList(bytes);

        // First pass: detect raw
        var detected = detectFileType(sample);

        // If compressed, decompress and re-detect
        if (detected != null && (detected.mime == 'application/gzip' || detected.mime == 'application/zlib')) {
          compressed[detected.mime] = (compressed[detected.mime] ?? 0) + 1;

          // Decompress full file for re-detection
          final decompressed = _decompress(Uint8List.fromList(bytes));
          if (decompressed.length != bytes.length) {
            decompressedCount++;
            final decompSample = decompressed.length > 8192
                ? Uint8List.sublistView(decompressed, 0, 8192)
                : Uint8List.fromList(decompressed);
            final inner = detectFileType(decompSample);
            if (inner != null) {
              detected = inner;
            }
          }
        }

        if (detected != null) {
          counts[detected.mime] = (counts[detected.mime] ?? 0) + 1;
          sizes[detected.mime] = (sizes[detected.mime] ?? 0) + bytes.length;
        } else {
          unknownFiles++;
        }
      } catch (e) {
        errorCount++;
      }
    }
  }

  stdout.write('\r');
  print('=' * 80);
  print('PAYLOAD TYPE DISTRIBUTION REPORT');
  print('=' * 80);
  print('');
  print('Total response files scanned: $totalFiles');
  print('Empty files (no body):        $emptyFiles');
  print('Unknown/undetected:           $unknownFiles');
  print('Errors:                       $errorCount');
  print('Compressed (gzip):            ${compressed['application/gzip'] ?? 0}');
  print('Compressed (zlib):            ${compressed['application/zlib'] ?? 0}');
  print('Successfully decompressed:    $decompressedCount');
  print('');

  // Sort by count descending
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final totalDetected = sorted.fold<int>(0, (s, e) => s + e.value);

  print('${'Type'.padRight(55)} ${'Count'.padLeft(8)} ${'%'.padLeft(7)} ${'Size'.padLeft(10)}');
  print('-' * 80);

  for (final entry in sorted) {
    final pct = (entry.value / totalDetected * 100).toStringAsFixed(1);
    final sizeBytes = sizes[entry.key] ?? 0;
    final sizeStr = _formatSize(sizeBytes);
    print('${entry.key.padRight(55)} ${entry.value.toString().padLeft(8)} ${pct.padLeft(6)}% ${sizeStr.padLeft(10)}');
  }

  print('-' * 80);
  print('${'TOTAL'.padRight(55)} ${totalDetected.toString().padLeft(8)}');
  print('');

  // Category summary
  print('CATEGORY SUMMARY:');
  print('-' * 40);
  final categories = <String, int>{};
  for (final e in sorted) {
    final cat = e.key.split('/').first;
    categories[cat] = (categories[cat] ?? 0) + e.value;
  }
  final catSorted = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final c in catSorted) {
    final pct = (c.value / totalDetected * 100).toStringAsFixed(1);
    print('  ${c.key.padRight(20)} ${c.value.toString().padLeft(8)} ${pct.padLeft(6)}%');
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
