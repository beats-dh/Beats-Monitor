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
  Timer? _processQueueTimer;
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
  static const _queueProcessInterval = Duration(milliseconds: 100);
  
  final List<String> _serverAddresses = [];
  int _currentAddressIndex = 0;
  final ConfigService _config;

  final _systemDataController = StreamController<SystemData>.broadcast();
  final _serverStatusController = StreamController<ServerStatus>.broadcast();
  final _chatMessageController = StreamController<ChatMessage>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  
  final List<Map<String, dynamic>> _messageQueue = [];
  
  // Lista de eventos inscritos
  final Set<String> _subscribedEvents = {};
  bool _isReconnecting = false;

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
      _log('Fechando conexão atual');
      _isConnected = false;
      _connectionStatusController.add(false);
      notifyListeners();
    }
    
    _firstMessageTimer?.cancel();
    _firstMessageTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _processQueueTimer?.cancel();
    _processQueueTimer = null;
    
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

  void _processMessageQueue() {
    if (_messageQueue.isEmpty) return;

    // Ordena a fila por timestamp
    _messageQueue.sort((a, b) {
      final aTime = a['timestamp'] as int? ?? 0;
      final bTime = b['timestamp'] as int? ?? 0;
      return aTime.compareTo(bTime);
    });

    // Processa as mensagens em ordem
    while (_messageQueue.isNotEmpty) {
      final data = _messageQueue.removeAt(0);
      _processMessage(data);
    }
  }

  void _startQueueProcessor() {
    _processQueueTimer?.cancel();
    _processQueueTimer = Timer.periodic(_queueProcessInterval, (_) {
      _processMessageQueue();
    });
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
          _log('Pong recebido');
          return;
          
        case 'event':
          final eventType = jsonData['event'] as String?;
          if (!_subscribedEvents.contains(eventType)) {
            _log('Evento $eventType recebido mas não inscrito, ignorando');
            return;
          }

          final data = jsonData['data'] as Map<String, dynamic>;
          _log('Evento recebido: $eventType');
          _log('Dados do evento: $data');
          
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
              _log('Processando recursos do sistema');
              final systemData = SystemData.fromJson({'data': data});
              _systemDataController.add(systemData);
              break;
              
            case 'server_status':
              _log('Processando status do servidor');
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
      _log('Mensagem recebida: $message');
      final jsonData = jsonDecode(message);
      
      if (jsonData is Map<String, dynamic>) {
        // Adiciona timestamp atual se não existir
        if (!jsonData.containsKey('timestamp')) {
          jsonData['timestamp'] = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
        }
        
        // Adiciona à fila de processamento
        _messageQueue.add(jsonData);
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

      _log('Eventos após unsubscribe: $_subscribedEvents');
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
          _log('Ping enviado');
        } catch (e) {
          _log('Erro ao enviar ping: $e');
        }
      }
    });
  }

  Future<void> startConnection() async {
    if (_isStartingConnection || _isConnecting) {
      _log('Conexão já está sendo iniciada');
      return;
    }

    _isStartingConnection = true;
    manualReconnectMode = false;
    _reconnectAttempts = 0;

    try {
      await _initializeConnection();
    } finally {
      _isStartingConnection = false;
    }
  }

  Future<void> _initializeConnection() async {
    await AuthService.refreshToken();
    if (AuthService.token != null) {
      await _connect();
    }
  }

  Future<void> _connect() async {
    if (_isConnecting || _disposed || (_reconnectTimer?.isActive ?? false)) {
      return;
    }

    _isConnecting = true;
    _log('Iniciando conexão');
    notifyListeners();

    try {
      await closeCurrentConnection();
      
      if (_disposed) return;

      final uri = Uri.parse(_config.wsBaseUrl);
      _log('Conectando a $uri');

      try {
        _channel = await Future.value(WebSocketChannel.connect(uri))
            .timeout(_connectionTimeout,
                onTimeout: () => throw TimeoutException('Timeout de conexão'));

        if (_disposed) {
          await closeCurrentConnection();
          return;
        }

        await Future.value(_channel?.ready)
            .timeout(_connectionTimeout,
                onTimeout: () => throw TimeoutException('Timeout ao aguardar canal'));

        if (_disposed) {
          await closeCurrentConnection();
          return;
        }

        _currentAddressIndex = 0;
        if (!_disposed) {
          _log('Conexão estabelecida com sucesso');
          _isConnected = true;
          _connectionStatusController.add(true);
          notifyListeners();
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (_disposed || _channel == null) return;
        
        if (_subscribedEvents.isNotEmpty) {
          subscribe();
        }
        _startPingTimer();
        _startQueueProcessor();

        bool receivedFirstMessage = false;
        
        _firstMessageTimer = Timer(_connectionTimeout, () {
          if (!receivedFirstMessage && _channel != null && !_disposed) {
            _log('Timeout: Nenhuma mensagem recebida');
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
            _log('Erro no stream: $error');
            _firstMessageTimer?.cancel();
            _pingTimer?.cancel();
            _processQueueTimer?.cancel();
            if (error.toString().contains('Network is unreachable')) {
              _reconnectAttempts = math.max(2, _reconnectAttempts);
            }
            scheduleReconnect('Erro de conexão: $error');
          },
          onDone: () {
            _log('Stream fechado');
            _firstMessageTimer?.cancel();
            _pingTimer?.cancel();
            _processQueueTimer?.cancel();
            scheduleReconnect('Conexão fechada');
          },
          cancelOnError: true,
        );
      } catch (e) {
        _log('Erro ao conectar: $e');
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
    _firstMessageTimer?.cancel();
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _processQueueTimer?.cancel();
    _subscription?.cancel();
    closeCurrentConnection();
    _systemDataController.close();
    _serverStatusController.close();
    _chatMessageController.close();
    _connectionStatusController.close();
    super.dispose();
  }
}
