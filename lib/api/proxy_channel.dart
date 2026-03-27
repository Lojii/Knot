import 'package:flutter/services.dart';

class ProxyChannel {
  static const _channel = MethodChannel('com.knot.proxy');

  static Future<Map<String, dynamic>> startProxy() async {
    final result = await _channel.invokeMethod<Map>('startProxy');
    return Map<String, dynamic>.from(result ?? {});
  }

  static Future<void> stopProxy() async {
    await _channel.invokeMethod('stopProxy');
  }

  static Future<Map<String, dynamic>> getStatus() async {
    final result = await _channel.invokeMethod<Map>('getStatus');
    return Map<String, dynamic>.from(result ?? {});
  }

  // ── Certificate Management ──

  /// Get cert status: {"status": "none"|"installed"|"trusted", "path": "..."}
  static Future<Map<String, dynamic>> getCertStatus() async {
    final result = await _channel.invokeMethod<Map>('getCertStatus');
    return Map<String, dynamic>.from(result ?? {});
  }

  /// Install cert to Keychain + trust. Returns {"status": "trusted"|"installed"}
  /// Triggers system password dialog on macOS.
  static Future<Map<String, dynamic>> installCert() async {
    final result = await _channel.invokeMethod<Map>('installCert');
    return Map<String, dynamic>.from(result ?? {});
  }

  /// Get CA cert DER bytes for export/save.
  static Future<Uint8List?> exportCertDER() async {
    final result = await _channel.invokeMethod<Uint8List>('exportCertDER');
    return result;
  }
}
