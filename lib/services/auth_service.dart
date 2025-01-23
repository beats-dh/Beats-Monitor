import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'config_service.dart';

class AuthService {
  static const storage = FlutterSecureStorage();
  static const String _tokenKey = 'jwt_token';
  static const String _credentialsKey = 'credentials';
  static const String _tokenTimeKey = 'token_time';
  static Timer? _refreshTimer;
  static const _tokenValidityMinutes = 60; // 1 hora
  static const _refreshBeforeExpirationSeconds = 300; // Renova 5 minutos antes de expirar

  static String? _token;
  static String? _lastUsername;
  static String? _lastPassword;
  static DateTime? _tokenTime;

  static String? get token => _token;
  static bool get hasCredentials => _lastUsername != null && _lastPassword != null;

  static Future<bool> _shouldRefreshToken() async {
    if (_tokenTime == null) {
      final timeStr = await storage.read(key: _tokenTimeKey);
      if (timeStr != null) {
        _tokenTime = DateTime.parse(timeStr);
      }
    }

    if (_tokenTime == null) return true;

    final now = DateTime.now().toUtc();
    final diff = now.difference(_tokenTime!);
    final expirationTime = const Duration(minutes: _tokenValidityMinutes);
    final refreshTime = expirationTime - const Duration(seconds: _refreshBeforeExpirationSeconds);
    
    debugPrint('Token age: ${diff.inSeconds} seconds');
    debugPrint('Will refresh after: ${refreshTime.inSeconds} seconds');
    return diff >= refreshTime;
  }

  static Future<(bool, String?)> login(String username, String password) async {
    try {
      final url = Uri.parse('${ConfigService().apiBaseUrl}/login');
      debugPrint('Tentando login em: $url');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('O servidor demorou muito para responder. Tente novamente.');
        },
      );

      debugPrint('Status code: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _tokenTime = DateTime.now().toUtc();
        
        // Salva as credenciais para auto-refresh
        _lastUsername = username;
        _lastPassword = password;
        await storage.write(key: _credentialsKey, 
          value: json.encode({
            'username': username,
            'password': password,
          })
        );
        
        await storage.write(key: _tokenKey, value: _token);
        await storage.write(key: _tokenTimeKey, value: _tokenTime!.toIso8601String());
        _startRefreshTimer();
        return (true, null);
      }
      return (false, 'Login falhou. Verifique suas credenciais.');
    } catch (e, stackTrace) {
      debugPrint('Login error: $e');
      debugPrint('Stack trace: $stackTrace');
      return (false, e.toString());
    }
  }

  static Future<bool> refreshToken() async {
    if (!await _shouldRefreshToken()) {
      debugPrint('Token still valid, skipping refresh');
      return true;
    }

    if (_lastUsername != null && _lastPassword != null) {
      debugPrint('Token expired, refreshing...');
      final result = await login(_lastUsername!, _lastPassword!);
      return result.$1;
    }
    return false;
  }

  static Future<void> logout() async {
    _token = null;
    _lastUsername = null;
    _lastPassword = null;
    _tokenTime = null;
    _refreshTimer?.cancel();
    await storage.delete(key: _tokenKey);
    await storage.delete(key: _credentialsKey);
    await storage.delete(key: _tokenTimeKey);
  }

  static Future<bool> init() async {
    try {
      final credentialsStr = await storage.read(key: _credentialsKey);
      _token = await storage.read(key: _tokenKey);
      final timeStr = await storage.read(key: _tokenTimeKey);
      
      if (timeStr != null) {
        _tokenTime = DateTime.parse(timeStr);
      }
      
      if (credentialsStr != null) {
        final credentials = json.decode(credentialsStr);
        _lastUsername = credentials['username'];
        _lastPassword = credentials['password'];
        
        // Verifica se precisa atualizar o token
        return await refreshToken();
      }
      return false;
    } catch (e) {
      debugPrint('Error in init: $e');
      await logout();
      return false;
    }
  }

  static void _startRefreshTimer() {
    _refreshTimer?.cancel();
    
    if (_tokenTime == null) return;

    final now = DateTime.now().toUtc();
    final expirationTime = const Duration(minutes: _tokenValidityMinutes);
    final refreshTime = expirationTime - const Duration(seconds: _refreshBeforeExpirationSeconds);
    final timeUntilRefresh = refreshTime - now.difference(_tokenTime!);

    debugPrint('Agendando próximo refresh para daqui a ${timeUntilRefresh.inMinutes} minutos');
    
    // Agenda o refresh para acontecer no momento exato
    _refreshTimer = Timer(timeUntilRefresh, () async {
      if (!await refreshToken()) {
        debugPrint('Token refresh failed');
        await logout();
      }
    });
  }

  static Map<String, String> get authHeaders {
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };
  }
}
