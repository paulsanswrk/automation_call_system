import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/position.dart';
import 'api_service.dart';

enum WsConnectionStatus { connecting, connected, disconnected }

class PositionWsService {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _positionsController = StreamController<List<Position>>.broadcast();
  final _statusController = StreamController<WsConnectionStatus>.broadcast();

  Stream<List<Position>> get positionsStream => _positionsController.stream;
  Stream<WsConnectionStatus> get statusStream => _statusController.stream;

  List<Position> _positions = [];
  List<Position> get currentPositions => List.unmodifiable(_positions);

  void connect() {
    if (_disposed) return;
    _statusController.add(WsConnectionStatus.connecting);

    final url = ApiService.wsUrl('/api/positions/ws');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _statusController.add(WsConnectionStatus.connected);

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final type = msg['type'] as String?;

            if (type == 'snapshot') {
              _positions = _parsePositions(msg['positions']);
              _positionsController.add(_positions);
            } else if (type == 'update') {
              final exchangeName = msg['exchange'] as String?;
              final updated = _parsePositions(msg['positions']);
              _positions = [
                ..._positions.where((p) => p.exchange != exchangeName),
                ...updated,
              ];
              _positionsController.add(_positions);
            } else if (type == 'remove') {
              final toRemove = _parsePositions(msg['positions'])
                  .map((p) => p.positionId)
                  .toSet();
              _positions = _positions
                  .where((p) => !toRemove.contains(p.positionId))
                  .toList();
              _positionsController.add(_positions);
            }
          } catch (e) {
            // ignore parse errors
          }
        },
        onDone: () {
          _statusController.add(WsConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        onError: (_) {
          _statusController.add(WsConnectionStatus.disconnected);
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _statusController.add(WsConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  List<Position> _parsePositions(dynamic json) {
    if (json == null) return [];
    return (json as List<dynamic>)
        .map((e) => Position.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed) connect();
    });
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _positionsController.close();
    _statusController.close();
  }
}
