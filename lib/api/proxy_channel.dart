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
}
