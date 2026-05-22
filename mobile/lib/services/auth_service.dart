import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _storage = FlutterSecureStorage();

/// Log a message that appears in Android Studio's Run console and logcat.
/// Filter by "MOONGATE" in logcat to see only our logs.
void _log(String message) {
  dev.log(message, name: 'MOONGATE');
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _tokenKey = 'moongate_token';
  static const _hostKey  = 'moongate_host';

  String? _token;
  String? _host;

  String? get token  => _token;
  String? get host   => _host;
  bool get isAuthenticated => _token != null && _host != null;

  Future<void> load() async {
    _token = await _storage.read(key: _tokenKey);
    _host  = await _storage.read(key: _hostKey);
    _log('Loaded stored host=$_host token=${_token != null ? "present" : "null"}');
  }

  /// Build a base URL from a host string that may be:
  ///   • a local IP  "192.168.1.50"       → "http://192.168.1.50:80"
  ///   • IP + port   "192.168.1.50:80"    → "http://192.168.1.50:80"
  ///   • full HTTPS  "https://x.cfargotunnel.com" → unchanged
  static String buildBaseUrl(String host) {
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host.replaceAll(RegExp(r'/+$'), ''); // strip trailing slashes
    }
    final h = host.contains(':') ? host : '$host:80';
    return 'http://$h';
  }

  Future<AuthResult> exchangeCode({
    required String host,
    required String code,
    required String deviceName,
    int? ttlDays,
  }) async {
    final baseUrl = buildBaseUrl(host);
    final uri = Uri.parse('$baseUrl/server/moongate/auth');

    _log('─────────────────────────────────');
    _log('AUTH ATTEMPT');
    _log('  raw host     : $host');
    _log('  base url     : $baseUrl');
    _log('  url          : $uri');
    _log('  code         : $code');
    _log('  device       : $deviceName');

    try {
      final body = jsonEncode({
        'code':        code,
        'device_name': deviceName,
        if (ttlDays != null) 'ttl_days': ttlDays,
      });
      _log('  request body : $body');

      // Force Android to route this request through WiFi, not mobile data.
      // Smart Network Switch can send 192.168.x.x requests over cellular
      // where the subnet is unreachable → errno 113 / EHOSTUNREACH.
      // bindProcessToNetwork(wifiNet) pins the entire process to WiFi for
      // the duration of the request, then releases it.
      bool wifiBound = false;
      try {
        wifiBound = await const MethodChannel('com.moongate.app/network')
            .invokeMethod<bool>('bindToWifi') ?? false;
        _log('  wifi bind    : $wifiBound');
      } catch (e) {
        _log('  wifi bind    : skipped ($e)');
      }

      http.Response response;
      try {
        response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 15));
      } finally {
        if (wifiBound) {
          try {
            await const MethodChannel('com.moongate.app/network')
                .invokeMethod('releaseNetwork');
          } catch (_) {}
        }
      }

      _log('  http status  : ${response.statusCode}');
      _log('  response     : ${response.body}');

      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        _log('  JSON parse error: $e');
        return AuthResult.failure(
          'Bad response (HTTP ${response.statusCode}): '
          '${response.body.substring(0, response.body.length.clamp(0, 200))}',
        );
      }

      if (response.statusCode == 200) {
        final result = parsed['result'] as Map<String, dynamic>?;
        final token  = result?['token'] as String?;
        if (token == null) {
          _log('  ERROR: no token in result: $parsed');
          return AuthResult.failure('Server response missing token');
        }
        await _persist(host: baseUrl, token: token);
        _log('  SUCCESS — token stored');
        return AuthResult.success();
      }

      final err = parsed['error'];
      final msg = (err is Map ? err['message'] : err)?.toString()
          ?? 'Unknown error (HTTP ${response.statusCode})';
      _log('  ERROR: $msg');
      return AuthResult.failure('$msg  [$uri]');

    } catch (e, stack) {
      _log('  EXCEPTION: $e');
      _log('  STACK: $stack');
      return AuthResult.failure('Network error → $uri\n$e');
    }
  }

  /// Store a token + local host received directly from a QR code.
  /// No network request needed — the Pi pre-issued the token.
  Future<void> persistDirect({required String host, required String token}) async {
    final baseUrl = buildBaseUrl(host);
    await _persist(host: baseUrl, token: token);
    _log('Direct (QR) token stored for host=$baseUrl');
  }

  Future<void> _persist({required String host, required String token}) async {
    _token = token;
    _host  = host;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _hostKey,  value: host);
  }

  Future<void> signOut() async {
    _token = null;
    _host  = null;
    await _storage.deleteAll();
  }
}

class AuthResult {
  final bool    success;
  final String? error;

  AuthResult._(this.success, this.error);
  factory AuthResult.success()             => AuthResult._(true,  null);
  factory AuthResult.failure(String error) => AuthResult._(false, error);
}
