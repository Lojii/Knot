import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:brotli/brotli.dart';
import 'package:get/get.dart';
import '../api/api_client.dart';
import '../models/flow_detail.dart';

class DetailController extends GetxController {
  final ApiClient api;
  DetailController(this.api);

  final detail = Rxn<FlowDetail>();
  final isLoadingDetail = false.obs;
  final isLoadingBody = false.obs;
  final selectedTab = 0.obs;

  // Payload bytes (decompressed on client side from raw server data)
  final requestBodyBytes = Rxn<Uint8List>();
  final responseBodyBytes = Rxn<Uint8List>();

  // Content-types extracted from headers
  String get requestContentType => _headerValue(detail.value, 'reqHeaders', 'content-type');
  String get responseContentType => _headerValue(detail.value, 'rspHeaders', 'content-type');

  // Content-encoding extracted from headers
  String get requestContentEncoding => _headerValue(detail.value, 'reqHeaders', 'content-encoding');
  String get responseContentEncoding => _headerValue(detail.value, 'rspHeaders', 'content-encoding');

  // Convenience: decode bytes as text (utf-8 with fallback)
  String get requestBodyText => _decodeText(requestBodyBytes.value);
  String get responseBodyText => _decodeText(responseBodyBytes.value);

  Future<void> loadDetail(int taskId, String flowId) async {
    isLoadingDetail.value = true;
    try {
      detail.value = await api.getFlowDetail(taskId, flowId);
    } catch (e) { debugPrint("[Knot] Error: $e"); }
    isLoadingDetail.value = false;
  }

  Future<void> loadBodies(int taskId, String flowId) async {
    isLoadingBody.value = true;
    try {
      // Fetch raw bytes from server (no server-side decompression)
      final results = await Future.wait([
        api.getPayloadBytes(taskId, flowId, 'request'),
        api.getPayloadBytes(taskId, flowId, 'response'),
      ]);

      // Client-side decompression based on Content-Encoding + magic bytes
      requestBodyBytes.value = _decompress(results[0], requestContentEncoding);
      responseBodyBytes.value = _decompress(results[1], responseContentEncoding);
    } catch (_) {
      requestBodyBytes.value = null;
      responseBodyBytes.value = null;
    }
    isLoadingBody.value = false;
  }

  void clear() {
    detail.value = null;
    requestBodyBytes.value = null;
    responseBodyBytes.value = null;
  }

  // ── Decompression ──

  /// Client-side decompression: Content-Encoding header + magic bytes fallback.
  static Uint8List _decompress(Uint8List bytes, String encoding) {
    if (bytes.isEmpty) return bytes;

    final enc = encoding.toLowerCase().trim();

    // By header
    if (enc == 'gzip' || enc == 'x-gzip') return _tryGzip(bytes) ?? bytes;
    if (enc == 'deflate') return _tryZlib(bytes) ?? bytes;
    if (enc == 'br') return _tryBrotli(bytes) ?? bytes;

    // By magic bytes (header missing or unknown)
    if (bytes.length >= 2) {
      if (bytes[0] == 0x1f && bytes[1] == 0x8b) return _tryGzip(bytes) ?? bytes;
      if (bytes[0] == 0x78 && (bytes[1] == 0x01 || bytes[1] == 0x9c || bytes[1] == 0xda)) return _tryZlib(bytes) ?? bytes;
    }

    // No magic bytes for brotli — if header says identity but content isn't valid text,
    // try brotli as last resort
    if (enc.isEmpty || enc == 'identity') {
      if (bytes.length > 4 && !_looksLikeText(bytes)) {
        return _tryBrotli(bytes) ?? bytes;
      }
    }

    return bytes;
  }

  static bool _looksLikeText(Uint8List bytes) {
    final sample = bytes.length > 512 ? bytes.sublist(0, 512) : bytes;
    int printable = 0;
    for (final b in sample) {
      if ((b >= 32 && b <= 126) || b == 10 || b == 13 || b == 9) printable++;
    }
    return printable / sample.length > 0.85;
  }

  static Uint8List? _tryBrotli(Uint8List bytes) {
    try {
      return Uint8List.fromList(brotliDecode(bytes));
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _tryGzip(Uint8List bytes) {
    try {
      return Uint8List.fromList(gzip.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _tryZlib(Uint8List bytes) {
    try {
      return Uint8List.fromList(zlib.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ──

  static String _headerValue(FlowDetail? d, String headerListKey, String headerName) {
    if (d == null) return '';
    final headers = parseHeaders(d.raw, headerListKey);
    for (final h in headers) {
      if (h.$1.toLowerCase() == headerName) return h.$2;
    }
    return '';
  }

  /// Parse headers from metadata, supporting both formats:
  /// New: [["Content-Type", "text/html"], ...]  (array of arrays)
  /// Old: [{"Content-Type": "text/html"}, ...]  (array of single-entry maps)
  static List<(String, String)> parseHeaders(Map<String, dynamic> raw, String key) {
    final metadata = raw['metadata'] as Map<String, dynamic>? ?? {};
    final list = metadata[key] as List?;
    if (list == null) return [];

    final result = <(String, String)>[];
    for (final item in list) {
      if (item is List && item.length >= 2) {
        // New format: [name, value]
        result.add((item[0].toString(), item[1].toString()));
      } else if (item is Map) {
        // Old format: {name: value}
        for (final entry in item.entries) {
          result.add((entry.key.toString(), entry.value.toString()));
        }
      }
    }
    return result;
  }

  static String _decodeText(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}
