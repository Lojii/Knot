import 'dart:convert';

class WsMessage {
  final String type;
  final Map<String, dynamic> data;

  WsMessage({required this.type, required this.data});

  factory WsMessage.fromRaw(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return WsMessage(
      type: json['type'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }
}
