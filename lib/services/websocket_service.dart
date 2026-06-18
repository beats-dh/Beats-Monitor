import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/system_data.dart';
import '../models/events.dart';
import '../models/websocket_events.dart';
import '../services/auth_service.dart';
import '../services/config_service.dart';
import '../services/monitor_notification_service.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _firstMessageTimer;
  Timer? _pingTimer;
  Timer? _connectionCheckTimer;
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
  static const _connectionCheckInterval = Duration(seconds: 15);

  final List<String> _serverAddresses = [];
  int _currentAddressIndex = 0;
  final ConfigService _config;

  final _systemDataController = StreamController<SystemData>.broadcast();
  final _serverStatusController = StreamController<ServerStatus>.broadcast();
  final _chatMessageController = StreamController<ChatMessage>.broadcast();
  final _runtimeLogController = StreamController<RuntimeLogEvent>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();

  // Lista de eventos inscritos
  final Set<String> _subscribedEvents = {};

  Stream<SystemData> get systemDataStream => _systemDataController.stream;
  Stream<ServerStatus> get serverStatusStream => _serverStatusController.stream;
  Stream<ChatMessage> get chatMessageStream => _chatMessageController.stream;
  Stream<RuntimeLogEvent> get runtimeLogStream => _runtimeLogController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  bool get connectionStatus => _isConnected;
  int get reconnectAttempts => _reconnectAttempts;
  int get maxReconnectAttempts => _config.reconnectAttempts;
  bool get autoReconnect => _config.autoReconnect;

  WebSocketService(this._config) {
    unawaited(MonitorNotificationService.initialize());
    _connectionStatusController.add(false);
    _isConnected = false;

    // Inicia o timer de verificação de conexão
    _startConnectionCheckTimer();

    notifyListeners();
  }

  void _log(String message) {
    debugPrint('[WebSocket] $message');
  }

  void _startConnectionCheckTimer() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (_) {
      // Verifica se a conexão ainda está ativa
      if (!_isConnecting && !_isStartingConnection && !_disposed) {
        if (_channel == null || !_isConnected) {
          _log('Verificação periódica detectou desconexão');
          if (!manualReconnectMode && _config.autoReconnect) {
            _log('Tentando reconectar automaticamente...');
            startConnection();
          }
        }
      }
    });
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
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void scheduleReconnect(String reason) {
    if (_disposed) return;

    closeCurrentConnection();

    if (_reconnectAttempts >= _config.reconnectAttempts &&
        _config.autoReconnect) {
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
    final delay = Duration(
        milliseconds:
            math.min(baseDelay + (_reconnectAttempts - 1) * 1000, maxDelay));

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
          _log('Evento recebido: $eventType');

          if (!_subscribedEvents.contains(eventType)) {
            _log('Evento $eventType recebido mas não inscrito, ignorando');
            return;
          }

          // Verifica se data existe e é um Map, caso contrário, cria um Map vazio
          final data = jsonData['data'];

          if (eventType == WebSocketEvents.chatHistory) {
            // Tratamento seguro para o caso de data ser null ou não ser um Map
            if (data == null) {
              _log('Histórico de chat vazio ou em formato inválido');
              return;
            }

            try {
              if (data is Map<String, dynamic>) {
                // Processa cada canal
                data.forEach((channel, messages) {
                  _log('Processando histórico do canal: $channel');
                  if (messages is List) {
                    _log('Histórico contém ${messages.length} mensagens');
                    for (final msgData in messages) {
                      if (msgData is Map<String, dynamic>) {
                        final message = ChatMessage.fromJson({
                          ...msgData,
                          'channel': channel,
                        });
                        _chatMessageController.add(message);
                      }
                    }
                  }
                });
              } else if (data is List) {
                // Alguns servidores podem enviar uma lista direta de mensagens
                _log(
                    'Histórico recebido como lista com ${data.length} mensagens');
                for (final msgData in data) {
                  if (msgData is Map<String, dynamic> &&
                      msgData.containsKey('channel')) {
                    final message = ChatMessage.fromJson(msgData);
                    _chatMessageController.add(message);
                  }
                }
              } else {
                _log('Formato de histórico inválido: ${data.runtimeType}');
              }
            } catch (e) {
              _log('Erro ao processar histórico: $e');
            }
            return;
          }

          // Para outros eventos, certifica-se que data é Map<String, dynamic>
          Map<String, dynamic> eventData;
          if (data is Map<String, dynamic>) {
            eventData = data;
          } else {
            _log('Formato de dados inválido para evento $eventType');
            return;
          }

          switch (eventType) {
            case WebSocketEvents.chatLocal:
            case WebSocketEvents.chatGlobal:
            case WebSocketEvents.chatTrade:
            case WebSocketEvents.chatHelp:
            case WebSocketEvents.chatPrivate:
              final message = ChatMessage.fromJson({
                ...eventData,
                'channel': eventType,
              });
              _chatMessageController.add(message);
              MonitorNotificationService.notifyForChatMessage(message);
              break;

            case WebSocketEvents.runtimeLog:
              _runtimeLogController.add(RuntimeLogEvent.fromJson(eventData));
              break;

            case WebSocketEvents.systemResources:
              final systemData = SystemData.fromJson({'data': eventData});
              _systemDataController.add(systemData);
              break;

            case WebSocketEvents.serverStatus:
              final serverStatus = ServerStatus.fromJson(eventData);
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
      // Decodifica a mensagem recebida como UTF-8
      final bytes = utf8.encode(message);
      final decodedMessage = utf8.decode(bytes, allowMalformed: true);

      final jsonData = jsonDecode(decodedMessage) as Map<String, dynamic>;
      _processMessage(jsonData);
    } catch (e) {
      _log('Erro ao processar mensagem: $e');
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
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
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

      if (_reconnectAttempts >= _config.reconnectAttempts &&
          _config.autoReconnect) {
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

              // Marca como conectado assim que receber a primeira mensagem
              if (!_isConnected && !_disposed) {
                _isConnected = true;
                _connectionStatusController.add(true);
                notifyListeners();
              }
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

        // Marca como conectado, mas verifica novamente quando receber a primeira mensagem
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

  void sendMessage(Map<String, dynamic> message) {
    if (_channel != null && _isConnected) {
      try {
        final jsonMessage = jsonEncode(message);
        _channel!.sink.add(jsonMessage);
      } catch (e) {
        _log('Erro ao enviar mensagem: $e');
      }
    } else {
      _log('Tentativa de enviar mensagem sem conexão ativa');

      // Tenta reconectar automaticamente
      if (!_isConnecting && !_isStartingConnection && !manualReconnectMode) {
        _log('Tentando reconectar automaticamente...');
        startConnection();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    closeCurrentConnection();
    _reconnectTimer?.cancel();
    _firstMessageTimer?.cancel();
    _pingTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _systemDataController.close();
    _serverStatusController.close();
    _chatMessageController.close();
    _runtimeLogController.close();
    _connectionStatusController.close();
    super.dispose();
  }
}
