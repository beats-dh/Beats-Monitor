import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConfigService extends ChangeNotifier {
  static const storage = FlutterSecureStorage();
  static const String _baseUrlKey = 'base_url';
  static const String _autoReconnectKey = 'auto_reconnect';
  static const String _reconnectAttemptsKey = 'reconnect_attempts';
  static const String _defaultWebBaseUrl = String.fromEnvironment(
    'BEATS_MONITOR_DEFAULT_BASE_URL',
    defaultValue: '/beats-monitor-api',
  );
  static const String _defaultNativeBaseUrl = '127.0.0.1:51842';

  String _baseUrl = kIsWeb ? _defaultWebBaseUrl : _defaultNativeBaseUrl;
  bool _autoReconnect = true;
  int _reconnectAttempts = 5;

  String get baseUrl => _baseUrl;
  String get apiBaseUrl => _buildHttpBaseUrl(_baseUrl);
  String get wsBaseUrl => _buildWebSocketBaseUrl(_baseUrl);
  String get defaultBaseUrl =>
      kIsWeb ? _defaultWebBaseUrl : _defaultNativeBaseUrl;
  bool get autoReconnect => _autoReconnect;
  int get reconnectAttempts => _reconnectAttempts;

  static final ConfigService _instance = ConfigService._internal();

  factory ConfigService() {
    return _instance;
  }

  ConfigService._internal();

  String _cleanBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.length > 1 && trimmed.endsWith('/')) {
      return trimmed.replaceAll(RegExp(r'/+$'), '');
    }
    return trimmed;
  }

  String _currentOrigin() {
    final current = Uri.base;
    if (!current.hasScheme || current.authority.isEmpty) {
      return '';
    }
    return '${current.scheme}://${current.authority}';
  }

  String _buildHttpBaseUrl(String value) {
    final base = _cleanBaseUrl(value);
    if (base.startsWith('http://') || base.startsWith('https://')) {
      return '$base/api/v1';
    }
    if (base.startsWith('/')) {
      return '${_currentOrigin()}$base/api/v1';
    }
    return 'http://$base/api/v1';
  }

  String _buildWebSocketBaseUrl(String value) {
    final base = _cleanBaseUrl(value);
    if (base.startsWith('https://')) {
      return 'wss://${base.substring('https://'.length)}/ws';
    }
    if (base.startsWith('http://')) {
      return 'ws://${base.substring('http://'.length)}/ws';
    }
    if (base.startsWith('/')) {
      final current = Uri.base;
      final scheme = current.scheme == 'https' ? 'wss' : 'ws';
      return '$scheme://${current.authority}$base/ws';
    }
    return 'ws://$base/ws';
  }

  Future<void> init() async {
    final savedUrl = await storage.read(key: _baseUrlKey);
    if (savedUrl != null) {
      _baseUrl = savedUrl;
    }

    final savedAutoReconnect = await storage.read(key: _autoReconnectKey);
    if (savedAutoReconnect != null) {
      _autoReconnect = savedAutoReconnect == 'true';
    }

    final savedAttempts = await storage.read(key: _reconnectAttemptsKey);
    if (savedAttempts != null) {
      _reconnectAttempts = int.tryParse(savedAttempts) ?? 5;
    }

    notifyListeners();
  }

  Future<void> setBaseUrl(String newUrl) async {
    _baseUrl = newUrl;
    await storage.write(key: _baseUrlKey, value: newUrl);
    notifyListeners();
  }

  Future<void> setAutoReconnect(bool value) async {
    _autoReconnect = value;
    await storage.write(key: _autoReconnectKey, value: value.toString());
    notifyListeners();
  }

  Future<void> setReconnectAttempts(int value) async {
    _reconnectAttempts = value;
    await storage.write(key: _reconnectAttemptsKey, value: value.toString());
    notifyListeners();
  }

  Future<void> resetToDefault() async {
    await setBaseUrl(defaultBaseUrl);
    await setAutoReconnect(true);
    await setReconnectAttempts(5);
  }
}
