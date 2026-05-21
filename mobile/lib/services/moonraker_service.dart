import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connects to Moonraker's JSON-RPC WebSocket API.
///
/// All communication with the printer goes through here — temperature,
/// print status, G-code, macros, etc.
class MoonrakerService {
  MoonrakerService._();
  static final MoonrakerService instance = MoonrakerService._();

  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _events =
      StreamController.broadcast();
  int _id = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> connect(String host, String token) async {
    final uri = Uri.parse('ws://$host/websocket?token=$token');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );
    // Subscribe to printer state updates
    await call('printer.objects.subscribe', {
      'objects': {
        'print_stats': null,
        'heater_bed': null,
        'extruder': null,
        'toolhead': null,
        'fan': null,
      }
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = ++_id;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _channel?.sink.add(jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': id,
    }));
    return completer.future.timeout(const Duration(seconds: 10));
  }

  Future<void> sendGcode(String gcode) =>
      call('printer.gcode.script', {'script': gcode});

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final id = msg['id'] as int?;
    if (id != null && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      if (msg.containsKey('error')) {
        completer.completeError(msg['error'].toString());
      } else {
        completer.complete(msg['result'] as Map<String, dynamic>);
      }
    } else {
      _events.add(msg);
    }
  }

  void _onError(Object error) => _events.addError(error);
  void _onDone() => _events.close();
}
