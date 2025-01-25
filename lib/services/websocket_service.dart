import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/system_data.dart';
import '../models/events.dart';
import '../services/auth_service.dart';
import '../services/config_service.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _firstMessageTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  bool manualReconnectMode = false;
  bool _isConnecting = false;
  bool _disposed = false;
  bool _isStartingConnection = false;
  bool _isConnected = false;
  static const _connectionTimeout = Duration(seconds: 3);
  static const _baseReconnectDelay = Duration(milliseconds: 2000);
  static const _maxReconnectDelay = Duration(seconds: 10);
  static const _pingInterval = Duration(seconds: 30);
  
  final List<String> _serverAddresses = [];
  int _currentAddressIndex = 0;
  final ConfigService _config;

  final _systemDataController = StreamController<SystemData>.broadcast();
  final _serverStatusController = StreamController<ServerStatus>.broadcast();
  final _chatMessageController = StreamController<ChatMessage>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  
  // Lista de eventos inscritos
  final Set<String> _subscribedEvents = {};
  final bool _isReconnecting = false;

  Stream<SystemData> get systemDataStream => _systemDataController.stream;
  Stream<ServerStatus> get serverStatusStream => _serverStatusController.stream;
  Stream<ChatMessage> get chatMessageStream => _chatMessageController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  bool get connectionStatus => _isConnected;
  int get reconnectAttempts => _reconnectAttempts;
  int get maxReconnectAttempts => _config.reconnectAttempts;
  bool get autoReconnect => _config.autoReconnect;

  WebSocketService(this._config) {
    _connectionStatusController.add(false);
    _isConnected = false;
    notifyListeners();
  }

  void _log(String message) {
    debugPrint('[WebSocket] $message');
  }

  Future<void> closeCurrentConnection() async {
    if (!_disposed) {
      _isConnected = false;
      _connectionStatusController.add(false);
      notifyListeners();
    }
    
    _firstMessageTimer?.cancel();
    _firstMessageTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    
    try {
      await _subscription?.cancel();
      _subscription = null;
      
      if (_channel != null) {
        try {
          await Future.value(_channel?.sink.close(1000))
              .timeout(const Duration(seconds: 1), onTimeout: () {})
              .catchError((_) {});
        } catch (_) {
          // Ignora erros ao fechar a conexão
        }
      }
    } finally {
      _channel = null;
      _isConnecting = false;
      notifyListeners();
    }
  }

  void scheduleReconnect(String reason) {
    if (_disposed) return;

    closeCurrentConnection();
    
    if (_reconnectAttempts >= _config.reconnectAttempts && _config.autoReconnect) {
      manualReconnectMode = true;
      _reconnectAttempts = 0;
      _currentAddressIndex = 0;
      return;
    }

    if (manualReconnectMode || !_config.autoReconnect) {
      _reconnectAttempts = 0;
      _currentAddressIndex = 0;
      return;
    }

    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    
    final baseDelay = _baseReconnectDelay.inMilliseconds;
    final maxDelay = _maxReconnectDelay.inMilliseconds;
    final delay = Duration(milliseconds: 
      math.min(baseDelay + (_reconnectAttempts - 1) * 1000, maxDelay)
    );
    
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && !manualReconnectMode) {
        _connect();
      }
    });
  }

  Future<void> reconnectManually() async {
    if (_disposed) return;
    
    manualReconnectMode = false;
    _reconnectAttempts = 0;
    _currentAddressIndex = 0;
    await _connect();
  }

  void _processMessage(Map<String, dynamic> jsonData) {
    try {
      final type = jsonData['type'] as String?;
      _log('Processando mensagem do tipo: $type');
      
      switch (type) {
        case 'subscribed':
          _log('Inscrito nos eventos com sucesso');
          return;
          
        case 'pong':
          return;
          
        case 'event':
          final eventType = jsonData['event'] as String?;
          if (!_subscribedEvents.contains(eventType)) {
            _log('Evento $eventType recebido mas não inscrito, ignorando');
            return;
          }

          final data = jsonData['data'] as Map<String, dynamic>;
          _log('Evento recebido: $eventType');
          
          switch (eventType) {
            case 'chat_global':
            case 'chat_trade':
            case 'chat_help':
              final message = ChatMessage.fromJson({
                ...data,
                'channel': eventType,
              });
              _log('Mensagem de chat processada: ${message.player} em ${message.channel}: ${message.message}');
              _chatMessageController.add(message);
              break;
              
            case 'system_resources':
              final systemData = SystemData.fromJson({'data': data});
              _systemDataController.add(systemData);
              break;
              
            case 'server_status':
              final serverStatus = ServerStatus.fromJson(data);
              _serverStatusController.add(serverStatus);
              break;
          }
          break;
          
        case 'error':
          _log('Erro do servidor: ${jsonData['message']}');
          break;
          
        default:
          if (jsonData.containsKey('cpu') || jsonData.containsKey('system')) {
            final systemData = SystemData.fromJson({'data': jsonData});
            _systemDataController.add(systemData);
          }
      }
    } catch (e, stackTrace) {
      _log('Erro ao processar mensagem: $e\n$stackTrace');
    }
  }

  void handleMessage(String message) {
    try {
      final jsonData = jsonDecode(message);
      
      if (jsonData is Map<String, dynamic>) {
        // Adiciona timestamp atual se não existir
        if (!jsonData.containsKey('timestamp')) {
          jsonData['timestamp'] = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
        }
        
        _processMessage(jsonData);
      }
    } catch (e, stackTrace) {
      _log('Erro ao decodificar mensagem: $e\n$stackTrace');
    }
  }

  void subscribe([List<String>? events]) {
    if (events != null && events.isNotEmpty) {
      _subscribedEvents.addAll(events);
    }

    if (_channel == null || _disposed) return;
    
    try {
      _channel?.sink.add(jsonEncode({
        'type': 'subscribe',
        'events': _subscribedEvents.toList(),
        'token': AuthService.token
      }));

      _log('Inscrito nos eventos: $_subscribedEvents');
    } catch (e) {
      scheduleReconnect('Erro de assinatura');
    }
  }

  void unsubscribe([List<String>? events]) {
    if (_channel == null || _disposed) return;
    
    try {
      if (events != null) {
        _subscribedEvents.removeAll(events);
      } else {
        _subscribedEvents.clear();
      }

      _channel?.sink.add(jsonEncode({
        'type': 'unsubscribe',
        'events': events ?? [],
        'token': AuthService.token
      }));

    } catch (e) {
      _log('Erro ao cancelar inscrição: $e');
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_channel != null && !_disposed) {
        try {
          _channel?.sink.add(jsonEncode({
            'type': 'ping'
          }));
        } catch (e) {
          _log('Erro ao enviar ping: $e');
        }
      }
    });
  }

  Future<void> startConnection() async {
    if (_isStartingConnection || _isConnecting) {
      return;
    }

    _isStartingConnection = true;
    manualReconnectMode = false;
    _reconnectAttempts = 0;

    try {
      if (_serverAddresses.isEmpty) {
        _serverAddresses.add(_config.wsBaseUrl);
      }

      if (_currentAddressIndex >= _serverAddresses.length) {
        _currentAddressIndex = 0;
      }

      if (_reconnectAttempts >= _config.reconnectAttempts && _config.autoReconnect) {
        manualReconnectMode = true;
        _reconnectAttempts = 0;
        _currentAddressIndex = 0;
        _isStartingConnection = false;
        notifyListeners();
        return;
      }

      if (manualReconnectMode && !_config.autoReconnect) {
        _isStartingConnection = false;
        notifyListeners();
        return;
      }

      await _connect();
    } finally {
      _isStartingConnection = false;
      notifyListeners();
    }
  }

  Future<void> _connect() async {
    if (_disposed) return;

    _isConnecting = true;
    notifyListeners();

    try {
      await closeCurrentConnection();
      if (_disposed) return;

      final uri = Uri.parse(_config.wsBaseUrl);

      try {
        _channel = await Future.value(WebSocketChannel.connect(uri))
          .timeout(const Duration(seconds: 5));

        var receivedFirstMessage = false;
        
        _firstMessageTimer = Timer(_connectionTimeout, () {
          if (!receivedFirstMessage && _channel != null && !_disposed) {
            scheduleReconnect('Sem dados iniciais');
          }
        });

        _subscription = _channel?.stream.listen(
          (message) {
            if (!receivedFirstMessage) {
              receivedFirstMessage = true;
              _firstMessageTimer?.cancel();
            }
            if (message is String) {
              handleMessage(message);
            }
          },
          onError: (error) {
            _firstMessageTimer?.cancel();
            _pingTimer?.cancel();
            if (!_disposed) {
              scheduleReconnect('Erro de conexão: $error');
            }
          },
          onDone: () {
            _firstMessageTimer?.cancel();
            _pingTimer?.cancel();
            scheduleReconnect('Conexão fechada');
          },
          cancelOnError: true,
        );

        _currentAddressIndex = 0;
        if (!_disposed) {
          _isConnected = true;
          _connectionStatusController.add(true);
          notifyListeners();
        }

        _startPingTimer();
        subscribe(_subscribedEvents.toList());

      } catch (e) {
        scheduleReconnect('Falha na conexão: $e');
      }
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    closeCurrentConnection();
    _reconnectTimer?.cancel();
    _firstMessageTimer?.cancel();
    _pingTimer?.cancel();
    _systemDataController.close();
    _serverStatusController.close();
    _chatMessageController.close();
    _connectionStatusController.close();
    super.dispose();
  }
}
