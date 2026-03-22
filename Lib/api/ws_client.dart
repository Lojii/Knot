import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/ws_message.dart';

enum WsStatus { disconnected, connecting, connected }

class WsClient {
  final String baseUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int? _taskId;

  final _messageController = StreamController<WsMessage>.broadcast();
  final _statusController = StreamController<WsStatus>.broadcast();

  Stream<WsMessage> get messages => _messageController.stream;
  Stream<WsStatus> get statusStream => _statusController.stream;
  WsStatus _status = WsStatus.disconnected;
  WsStatus get status => _status;

  WsClient({this.baseUrl = 'ws://localhost:9090'});

  void connect({int? taskId}) {
    _taskId = taskId;
    _reconnectAttempts = 0;
    _doConnect();
  }

  void _doConnect() {
    _setStatus(WsStatus.connecting);
    final url = _taskId != null ? '$baseUrl/ws?taskId=$_taskId' : '$baseUrl/ws';
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
    // Exponential backoff: 1s, 2s, 4s, 8s, max 30s
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30));
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _doConnect);
  }

  void switchTask(int taskId) {
    _taskId = taskId;
    disconnect();
    connect(taskId: taskId);
  }

  void disconnect() {
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
