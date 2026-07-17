import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/ws_message.dart';

enum WsStatus { disconnected, connecting, connected }

class WsClient {
  String baseUrl;

  /// Per-session bearer token; appended to the WS URL as `?token=`.
  String? authToken;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int? _taskId;

  /// Set when the client is intentionally closed so the auto-reconnect loop
  /// does not fire after an explicit [disconnect].
  bool _intentionalClose = false;

  final _messageController = StreamController<WsMessage>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  Stream<WsMessage> get messages => _messageController.stream;
  Stream<WsStatus> get statusStream => _statusController.stream;
  WsStatus _status = WsStatus.disconnected;
  WsStatus get status => _status;

  WsClient({this.baseUrl = 'ws://localhost:9090'});

  void connect({int? taskId}) {
    // Tear down any existing connection so this doubles as a task switch
    // without leaking the previous channel.
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _taskId = taskId;
    _reconnectAttempts = 0;
    _intentionalClose = false;
    _doConnect();
  }

  void _doConnect() {
    _setStatus(WsStatus.connecting);
    final params = <String, String>{};
    if (_taskId != null) params['taskId'] = '$_taskId';
    if (authToken != null) params['token'] = authToken!;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final url = query.isEmpty ? '$baseUrl/ws' : '$baseUrl/ws?$query';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        (data) {
          _setStatus(WsStatus.connected);
          _reconnectAttempts = 0;
          try {
            _messageController.add(WsMessage.fromRaw(data as String));
          } catch (_) {}
        },
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
      );
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    _setStatus(WsStatus.disconnected);
    _subscription?.cancel();
    _channel = null;
    // Do not reconnect after an intentional disconnect.
    if (_intentionalClose) return;
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, capped at 30s.
    // Cap the shift so the counter can't overflow to 0/negative on long outages.
    final delay = Duration(seconds: (1 << (_reconnectAttempts.clamp(0, 5))).clamp(1, 30));
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _doConnect);
  }

  void disconnect() {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(WsStatus.disconnected);
  }

  void _setStatus(WsStatus s) {
    if (_status != s) {
      _status = s;
      _statusController.add(s);
    }
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }
}
