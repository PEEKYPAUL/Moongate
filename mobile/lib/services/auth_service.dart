import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _storage = FlutterSecureStorage();

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _tokenKey = 'moongate_token';
  static const _hostKey = 'moongate_host';

  String? _token;
  String? _host; // e.g. "100.x.x.x:7125" (Tailscale IP + Moonraker port)

  String? get token => _token;
  String? get host => _host;
  bool get isAuthenticated => _token != null && _host != null;

  Future<void> load() async {
    _token = await _storage.read(key: _tokenKey);
    _host = await _storage.read(key: _hostKey);
  }

  /// Exchange a pairing code for a JWT token.
  /// [host] is the Tailscale IP:port of Moonraker (e.g. "100.64.0.2:7125").
  /// [code] is the raw code from the QR or manual entry (e.g. "GATE-A3F2-9K1B").
  Future<AuthResult> exchangeCode({
    required String host,
    required String code,
    required String deviceName,
    int? ttlDays,
  }) async {
    final uri = Uri.parse('http://$host/moongate/auth');
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'device_name': deviceName,
              if (ttlDays != null) 'ttl_days': ttlDays,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        await _persist(host: host, token: token);
        return AuthResult.success();
      }
      final error = (jsonDecode(response.body) as Map?)?.get('error') ?? 'unknown';
      return AuthResult.failure(error.toString());
    } catch (e) {
      return AuthResult.failure(e.toString());
    }
  }

  Future<void> _persist({required String host, required String token}) async {
    _token = token;
    _host = host;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _hostKey, value: host);
  }

  Future<void> signOut() async {
    _token = null;
    _host = null;
    await _storage.deleteAll();
  }
}

class AuthResult {
  final bool success;
  final String? error;

  AuthResult._(this.success, this.error);
  factory AuthResult.success() => AuthResult._(true, null);
  factory AuthResult.failure(String error) => AuthResult._(false, error);
}

extension _MapExt on Map {
  dynamic get(dynamic key) => this[key];
}
