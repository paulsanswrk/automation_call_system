import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

/// Callback type for channel heartbeat events
typedef HeartbeatCallback = void Function(String channelName, String timestamp);

/// Callback for new discord messages arriving in real-time
typedef NewMessageCallback = void Function(Map<String, dynamic> messageData);

/// Callback for trade pipeline events (new_trade_action, new_ai_log, etc.)
typedef TradeEventCallback = void Function(
    String eventType, Map<String, dynamic> data);

class SystemWsService {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _disposed = false;

  HeartbeatCallback? onHeartbeat;
  NewMessageCallback? onNewMessage;
  TradeEventCallback? onTradeEvent;

  /// Stream controller for broadcasting raw events to multiple listeners
  final _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of all raw system events
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  void connect({
    HeartbeatCallback? heartbeatCallback,
    NewMessageCallback? newMessageCallback,
    TradeEventCallback? tradeEventCallback,
  }) {
    if (_disposed) return;
    onHeartbeat = heartbeatCallback ?? onHeartbeat;
    onNewMessage = newMessageCallback ?? onNewMessage;
    onTradeEvent = tradeEventCallback ?? onTradeEvent;

    // Close previous connection before reconnecting
    _channel?.sink.close();

    final url = ApiService.wsUrl('/api/system/ws');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final eventType = msg['event_type'] as String? ?? '';
            final payload = msg['data'] as Map<String, dynamic>?;

            // Emit to broadcast stream
            _eventController.add(msg);

            switch (eventType) {
              case 'channel_heartbeat':
                if (payload != null) {
                  final channelName =
                      payload['channel_name'] as String? ?? '';
                  final timestamp = payload['timestamp'] as String? ?? '';
                  onHeartbeat?.call(channelName, timestamp);
                }
                break;

              case 'new_discord_message':
                if (payload != null) {
                  onNewMessage?.call(payload);
                }
                break;

              case 'new_trade_action':
              case 'new_ai_log':
              case 'trade_skip':
              case 'trade_error':
                if (payload != null) {
                  onTradeEvent?.call(eventType, payload);
                }
                break;
            }
          } catch (_) {}
        },
        onDone: () => _scheduleReconnect(),
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed) connect();
    });
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _eventController.close();
  }
}
