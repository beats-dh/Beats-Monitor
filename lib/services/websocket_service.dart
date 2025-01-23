import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/system_data.dart';
import '../services/auth_service.dart';
import '../services/config_service.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _firstMessageTimer;
  int _reconnectAttempts = 0;
  bool manualReconnectMode = false;
  bool _isConnecting = false;
  bool _disposed = false;
  bool _isStartingConnection = false;
  static const _connectionTimeout = Duration(seconds: 3);
  static const _baseReconnectDelay = Duration(milliseconds: 2000);
  static const _maxReconnectDelay = Duration(seconds: 10);
  
  final List<String> _serverAddresses = [];
  int _currentAddressIndex = 0;
  final ConfigService _config;

  final _systemDataController = StreamController<SystemData>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  Stream<SystemData> get systemDataStream => _systemDataController.stream;
  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  
  int get reconnectAttempts => _reconnectAttempts;
  int get maxReconnectAttempts => _config.reconnectAttempts;

  WebSocketService(this._config) {
    _connectionStatusController.add(false);
  }

  void _log(String message) {
    debugPrint('[WebSocket] $message');
  }

  Future<void> closeCurrentConnection() async {
    if (!_disposed) {
      _connectionStatusController.add(false);
    }
    
    _firstMessageTimer?.cancel();
    _firstMessageTimer = null;
    
    try {
      await _subscription?.cancel();
      _subscription = null;
      
      if (_channel != null) {
        await Future.value(_channel?.sink.close(status.goingAway)).timeout(
          const Duration(seconds: 1),
          onTimeout: () {},
        );
      }
    } catch (e) {
      _log('Erro ao fechar conexão: $e');
    } finally {
      _channel = null;
      _isConnecting = false;
    }
  }

  void scheduleReconnect(String reason) {
    closeCurrentConnection();
    
    if (_reconnectAttempts >= _config.reconnectAttempts) {
      manualReconnectMode = true;
      _reconnectAttempts = 0;
      _currentAddressIndex = 0;
      return;
    }

    if (manualReconnectMode || !_config.autoReconnect) {
      manualReconnectMode = true;
      return;
    }

    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    
    final baseDelay = _baseReconnectDelay.inMilliseconds;
    final maxDelay = _maxReconnectDelay.inMilliseconds;
    final delay = Duration(milliseconds: 
      math.min(baseDelay + (_reconnectAttempts - 1) * 1000, maxDelay)
    );
    
    _reconnectTimer = Timer(delay, _connect);
  }

  Future<void> reconnectManually() async {
    manualReconnectMode = false;
    _reconnectAttempts = 0;
    await _connect();
  }

  void handleMessage(String message) {
    try {
      final jsonData = jsonDecode(message);
      
      if (jsonData is Map<String, dynamic>) {
        if (jsonData['type'] == 'subscribed') {
          return;
        }
        
        if (jsonData.containsKey('data')) {
          final data = SystemData.fromJson(jsonData);
          _systemDataController.add(data);
          return;
        }

        if (jsonData.containsKey('cpu') || jsonData.containsKey('system')) {
          final data = SystemData.fromJson({'data': jsonData});
          _systemDataController.add(data);
          return;
        }
      }
    } catch (e) {
      _log('Erro ao processar mensagem: $e');
    }
  }

  void subscribe() {
    if (_channel == null || _disposed) return;
    
    try {
      _channel?.sink.add(jsonEncode({
        'type': 'subscribe',
        'events': ['system_resources'],
        'token': AuthService.token
      }));
    } catch (e) {
      scheduleReconnect('Erro de assinatura');
    }
  }

  Future<void> startConnection() async {
    if (_isStartingConnection) {
      return;
    }
    
    _isStartingConnection = true;
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      await AuthService.refreshToken();
      
      if (AuthService.token != null) {
        manualReconnectMode = false;
        _reconnectAttempts = 0;
        await _connect();
      }
    } finally {
      _isStartingConnection = false;
    }
  }

  Future<void> _connect() async {
    if (_isConnecting || _disposed || (_reconnectTimer?.isActive ?? false)) {
      return;
    }

    await AuthService.refreshToken();
    _isConnecting = true;

    try {
      await closeCurrentConnection();
      final uri = Uri.parse(_config.wsBaseUrl);

      try {
        _channel = await Future.value(WebSocketChannel.connect(uri)).timeout(
          _connectionTimeout,
          onTimeout: () {
            throw TimeoutException('Timeout de conexão');
          },
        );

        if (_disposed) {
          await closeCurrentConnection();
          return;
        }

        await Future.value(_channel?.ready).timeout(
          _connectionTimeout,
          onTimeout: () {
            throw TimeoutException('Timeout ao aguardar canal');
          },
        );

        if (!_disposed) {
          _currentAddressIndex = 0;
          _connectionStatusController.add(true);
          _reconnectAttempts = 0;
          
          await Future.delayed(const Duration(milliseconds: 100));
          
          if (_disposed || _channel == null) return;
          
          subscribe();

          bool receivedFirstMessage = false;
          
          _firstMessageTimer = Timer(_connectionTimeout, () {
            if (!receivedFirstMessage && _channel != null && !_disposed) {
              scheduleReconnect('Sem dados iniciais');
            }
          });
          
          _subscription = _channel?.stream.listen(
            (data) {
              if (!_disposed) {
                receivedFirstMessage = true;
                _firstMessageTimer?.cancel();
                handleMessage(data as String);
              }
            },
            onError: (error) {
              _firstMessageTimer?.cancel();
              if (error.toString().contains('Network is unreachable')) {
                _reconnectAttempts = math.max(2, _reconnectAttempts);
              }
              scheduleReconnect('Erro de conexão');
            },
            onDone: () {
              _firstMessageTimer?.cancel();
              scheduleReconnect('Conexão fechada');
            },
            cancelOnError: true,
          );
        }
      } catch (e) {
        if (_currentAddressIndex < _serverAddresses.length - 1) {
          _currentAddressIndex++;
          throw Exception('Tentando próximo servidor');
        }
        rethrow;
      }
    } catch (e) {
      scheduleReconnect('Erro de conexão');
    } finally {
      _isConnecting = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _firstMessageTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    closeCurrentConnection();
    _systemDataController.close();
    _connectionStatusController.close();
    super.dispose();
  }
}
