import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConfigService extends ChangeNotifier {
  static const storage = FlutterSecureStorage();
  static const String _baseUrlKey = 'base_url';
  static const String _autoReconnectKey = 'auto_reconnect';
  static const String _reconnectAttemptsKey = 'reconnect_attempts';
  static const String _defaultBaseUrl = '177.23.187.59:8081';
  
  String _baseUrl = _defaultBaseUrl;
  bool _autoReconnect = true;
  int _reconnectAttempts = 5;

  String get baseUrl => _baseUrl;
  String get apiBaseUrl => 'http://$_baseUrl/api/v1';
  String get wsBaseUrl => 'ws://$_baseUrl/ws';
  String get defaultBaseUrl => _defaultBaseUrl;
  bool get autoReconnect => _autoReconnect;
  int get reconnectAttempts => _reconnectAttempts;

  static final ConfigService _instance = ConfigService._internal();
  
  factory ConfigService() {
    return _instance;
  }

  ConfigService._internal();

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
    await setBaseUrl(_defaultBaseUrl);
    await setAutoReconnect(true);
    await setReconnectAttempts(5);
  }
}
