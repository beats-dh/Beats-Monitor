import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/events.dart';
import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/connection_status_popup.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  String _selectedChannel = 'global';
  StreamSubscription<ChatMessage>? _subscription;
  StreamSubscription<bool>? _connectionSubscription;
  late WebSocketService _webSocketService;
  bool _initialized = false;
  final Set<String> _messageKeys = {};
  final List<ChatMessage> _messages = [];
  bool _historyReceived = false;
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  bool _requestedHistory = false;
  bool _isConnected = false;
  List<Map<String, dynamic>> _broadcastHistory = [];
  String? _selectedPrivatePeer;
  static const String _monitorPlayerName = 'Waldir';
  static const String _allPrivateMessagesLabel = 'All';

  // Verifica se está no Windows
  bool get _isWindows => !kIsWeb && Platform.isWindows;

  // Ajusta tamanhos para Windows
  double _getAdaptiveFontSize(double mobileSize) {
    return _isWindows ? mobileSize * 0.7 : mobileSize;
  }

  double _getAdaptiveIconSize(double mobileSize) {
    return _isWindows ? mobileSize * 0.7 : mobileSize;
  }

  double _getAdaptivePadding(double mobilePadding) {
    return _isWindows ? mobilePadding * 0.7 : mobilePadding;
  }

  Color get _channelColor {
    switch (_selectedChannel) {
      case 'local':
        return Colors.purple;
      case 'global':
        return Colors.blue;
      case 'trade':
        return Colors.green;
      case 'help':
        return Colors.orange;
      case 'private':
        return Colors.pink;
      case 'commands':
        return Colors.redAccent;
      default:
        return Colors.blue;
    }
  }

  String _getMessageKey(ChatMessage message) {
    // Chave mais robusta para evitar duplicações
    return '${message.channel}_${message.player}_${message.timestamp.millisecondsSinceEpoch}_${message.message.hashCode}';
  }

  void _addMessage(ChatMessage message) {
    final key = _getMessageKey(message);
    if (_messageKeys.add(key)) {
      // Retorna true se a key não existia
      setState(() {
        _messages.add(message);
        _selectedPrivatePeer ??= _privatePeerFor(message);
        // Ordena as mensagens por timestamp
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
    } else {
      // A mensagem já existe, não fazemos nada
      debugPrint('[ChatScreen] Mensagem duplicada ignorada: $key');
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;

    final position = _scrollController.position;
    // Aumentando o threshold e considerando também quando está no final
    const threshold = 150.0;
    return position.pixels >= (position.maxScrollExtent - threshold) ||
        position.pixels == position.maxScrollExtent;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Adicionando um pequeno delay para garantir que o layout foi atualizado
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _setupMessageSubscription() {
    _subscription = _webSocketService.chatMessageStream.listen((message) {
      if (mounted) {
        // Se recebemos uma mensagem, devemos estar conectados
        if (!_isConnected) {
          setState(() {
            _isConnected = true;
          });
        }

        final wasNearBottom = _isNearBottom();

        // Se for uma mensagem do histórico ou nova, adiciona
        _addMessage(message);

        // Se for uma mensagem do canal atual
        if (message.channel.replaceAll('chat_', '') == _selectedChannel) {
          // Se estava próximo do final, faz o scroll
          if (wasNearBottom || !_historyReceived) {
            _scrollToBottom();
          }
        }

        // Marca que o histórico foi recebido após um pequeno delay
        if (!_historyReceived) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() {
                _historyReceived = true;
              });
            }
          });
        }
      }
    });

    // Monitora o status da conexão
    _connectionSubscription =
        _webSocketService.connectionStatusStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
    });
  }

  void _ensureConnection() {
    if (!_webSocketService.connectionStatus) {
      // Se não estiver conectado, tenta iniciar a conexão
      _webSocketService.startConnection();
    }
  }

  void _requestChatHistory() {
    _ensureConnection();

    if (_webSocketService.connectionStatus) {
      // Solicita histórico para todos os canais
      _webSocketService.sendMessage({
        'type': 'chat_history',
        'channels': [
          'chat_local',
          'chat_global',
          'chat_trade',
          'chat_help',
          'chat_private'
        ] // Especifica todos os canais para garantir que receba todo o histórico
      });
      _requestedHistory = true;
    } else {
      // Se não conseguir enviar, mostra uma mensagem
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context).translate('reconnecting_to_server')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _responseMessage(dynamic response, String fallbackKey) {
    try {
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (data is Map &&
          data['mensagem'] is String &&
          (data['mensagem'] as String).isNotEmpty) {
        return data['mensagem'] as String;
      }
    } catch (_) {
      // Use the localized fallback below.
    }
    return AppLocalizations.of(context).translate(fallbackKey);
  }

  Map<String, String>? _parsePrivateMessage(String text) {
    final separator = text.indexOf(':');
    if (separator <= 0 || separator == text.length - 1) {
      return null;
    }

    final target = text.substring(0, separator).trim();
    final message = text.substring(separator + 1).trim();
    if (target.isEmpty || message.isEmpty) {
      return null;
    }

    return {'target': target, 'message': message};
  }

  String _normalizeName(String value) => value.trim().toLowerCase();

  bool _sameName(String left, String right) =>
      _normalizeName(left) == _normalizeName(right);

  String _privateConversationKey(String left, String right) {
    final names = [_normalizeName(left), _normalizeName(right)]..sort();
    return names.join('|');
  }

  String _privateConversationLabel(String left, String right) {
    final names = [left.trim(), right.trim()]
      ..sort((a, b) => _normalizeName(a).compareTo(_normalizeName(b)));
    return '${names.first} <-> ${names.last}';
  }

  String? _privateReplyTargetForSelection(String? selectedPeer) {
    if (selectedPeer == null ||
        selectedPeer.isEmpty ||
        selectedPeer == _allPrivateMessagesLabel) {
      return null;
    }

    final parts = selectedPeer.split(' <-> ');
    if (parts.length != 2) {
      return selectedPeer;
    }

    if (_sameName(parts.first, _monitorPlayerName)) {
      return parts.last;
    }
    if (_sameName(parts.last, _monitorPlayerName)) {
      return parts.first;
    }

    return null;
  }

  Map<String, String>? _parsePrivateEnvelope(ChatMessage message) {
    if (message.channel != 'chat_private') {
      return null;
    }

    final sender = message.player.trim();
    final text = message.message.trimLeft();
    final toMatch = RegExp(r'^to\s+([^:]+):\s*(.*)$', caseSensitive: false)
        .firstMatch(text);
    if (toMatch != null) {
      final target = toMatch.group(1)!.trim();
      final body = toMatch.group(2)!.trimLeft();
      return {
        'key': _privateConversationKey(sender, target),
        'peer': _privateConversationLabel(sender, target),
        'body': body,
        'direction': _sameName(sender, _monitorPlayerName) ? 'out' : 'in',
      };
    }

    final legacyMatch =
        RegExp(r'^(.+?)\s+to\s+([^:]+):\s*(.*)$', caseSensitive: false)
            .firstMatch(text);
    if (legacyMatch != null) {
      final from = legacyMatch.group(1)!.trim();
      final target = legacyMatch.group(2)!.trim();
      final body = legacyMatch.group(3)!.trimLeft();
      return {
        'key': _privateConversationKey(from, target),
        'peer': _privateConversationLabel(from, target),
        'body': body,
        'direction': _sameName(from, _monitorPlayerName) ? 'out' : 'in',
      };
    }

    return null;
  }

  String? _privatePeerFor(ChatMessage message) =>
      _parsePrivateEnvelope(message)?['peer'];

  List<String> _privatePeers() {
    final latestByPeer = <String, DateTime>{};
    final labelByKey = <String, String>{};
    for (final message in _messages) {
      final envelope = _parsePrivateEnvelope(message);
      if (envelope == null) {
        continue;
      }
      final peer = envelope['peer']!;
      final key = envelope['key'] ?? _normalizeName(peer);
      labelByKey[key] = peer;
      final current = latestByPeer[key];
      if (current == null || message.timestamp.isAfter(current)) {
        latestByPeer[key] = message.timestamp;
      }
    }

    final keys = latestByPeer.keys.toList()
      ..sort(
          (left, right) => latestByPeer[right]!.compareTo(latestByPeer[left]!));
    final peers = keys.map((key) => labelByKey[key]!).toList();
    return peers.isEmpty ? peers : [_allPrivateMessagesLabel, ...peers];
  }

  List<ChatMessage> _privateMessagesFor(String peer) {
    if (peer == _allPrivateMessagesLabel) {
      return _messages
          .where((message) => message.channel == 'chat_private')
          .toList();
    }

    return _messages.where((message) {
      final envelope = _parsePrivateEnvelope(message);
      return envelope != null && envelope['peer'] == peer;
    }).toList();
  }

  String _privateDisplayMessage(ChatMessage message) {
    return _parsePrivateEnvelope(message)?['body'] ?? message.message;
  }

  bool _privateMessageIsMine(ChatMessage message) {
    return _parsePrivateEnvelope(message)?['direction'] == 'out';
  }

  String _messageHintText(AppLocalizations l10n) {
    if (_selectedChannel == 'commands') {
      return l10n.translate('type_god_command');
    }
    if (_selectedChannel == 'private') {
      final replyTarget = _privateReplyTargetForSelection(_selectedPrivatePeer);
      if (replyTarget != null && replyTarget.isNotEmpty) {
        return l10n
            .translate('type_private_message_to')
            .replaceAll('{0}', replyTarget);
      }
      return l10n.translate('private_message_format');
    }
    return l10n.translate('type_message');
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    if (_selectedChannel == 'broadcast') {
      try {
        setState(() => _isSending = true);
        final response = await ApiService.post('server/broadcast',
            body: {"message": text.trim()});
        if (response.statusCode == 200 || response.statusCode == 202) {
          await _addBroadcastToHistory(text.trim());
          _messageController.clear();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(_responseMessage(response, 'error_sending_message')),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)
                  .translate('error_sending_message')),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Se erro, não faz nada e mantém o texto
      } finally {
        if (mounted) {
          setState(() => _isSending = false);
        }
      }
      return;
    }

    if (_selectedChannel == 'commands') {
      try {
        setState(() => _isSending = true);
        final response = await ApiService.post('server/god-command',
            body: {"command": text});
        if (response.statusCode == 200 || response.statusCode == 202) {
          _messageController.clear();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)
                    .translate('god_command_queued')),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(_responseMessage(response, 'error_sending_message')),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)
                  .translate('error_sending_message')),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSending = false);
        }
      }
      return;
    }

    // Comportamento padrão para outros canais
    try {
      setState(() => _isSending = true);
      dynamic response;
      if (_selectedChannel == 'private') {
        final replyTarget =
            _privateReplyTargetForSelection(_selectedPrivatePeer);
        final parsed = replyTarget != null && replyTarget.isNotEmpty
            ? {'target': replyTarget, 'message': text.trim()}
            : _parsePrivateMessage(text);
        if (parsed == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)
                  .translate('private_message_format')),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        response = await ApiService.post('server/chat-message', body: {
          "channel": "chat_private",
          "target": parsed['target'],
          "message": parsed['message'],
        });
        if (replyTarget == null) {
          _selectedPrivatePeer =
              _privateConversationLabel(_monitorPlayerName, parsed['target']!);
        }
      } else {
        response = await ApiService.post('server/chat-message', body: {
          "channel": "chat_$_selectedChannel",
          "message": text.trim(),
        });
      }

      if (response.statusCode != 200 && response.statusCode != 202) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(_responseMessage(response, 'error_sending_message')),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context).translate('chat_command_queued')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)
                .translate('error_sending_message')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Registra o observer do teclado
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _webSocketService = context.read<WebSocketService>();

        // Inicializa o estado de conexão com o valor atual
        setState(() {
          _isConnected = _webSocketService.connectionStatus;
        });

        // Monitora o status da conexão
        _connectionSubscription =
            _webSocketService.connectionStatusStream.listen((isConnected) {
          if (mounted) {
            setState(() {
              _isConnected = isConnected;
            });

            // Se a conexão foi estabelecida, solicita o histórico
            if (isConnected && !_requestedHistory) {
              _requestChatHistory();
            }
          }
        });

        // Garante que temos uma conexão WebSocket
        _ensureConnection();

        // Apenas se inscreve nos canais de chat, sem iniciar nova conexão
        _webSocketService.subscribe([
          'chat_local',
          'chat_global',
          'chat_trade',
          'chat_help',
          'chat_private',
          'chat_history' // Precisa subscrever para receber o histórico
        ]);

        _setupMessageSubscription();
        _initialized = true;

        // Solicita o histórico imediatamente se estiver conectado
        if (_webSocketService.connectionStatus && !_requestedHistory) {
          _requestChatHistory();
        }
      }
    });

    _loadBroadcastHistory();
  }

  @override
  void dispose() {
    // Remove o observer do teclado
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _subscription?.cancel();
    _connectionSubscription?.cancel();
    _scrollController.dispose();

    // Remove inscrição dos canais e fecha conexão
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Apenas cancela a inscrição dos eventos, sem fechar a conexão
      _webSocketService.unsubscribe([
        'chat_local',
        'chat_global',
        'chat_trade',
        'chat_help',
        'chat_private',
        'chat_history'
      ]);
    });

    // Limpa as mensagens
    _messages.clear();
    _messageKeys.clear();
    _historyReceived = false;

    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Verifica se o teclado está visível
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset > 0 && _messages.isNotEmpty) {
      // Teclado apareceu, rola para a última mensagem
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Se o aplicativo voltar ao primeiro plano, verifica a conexão
    if (state == AppLifecycleState.resumed) {
      _ensureConnection();

      // Não solicitar histórico ao retornar para primeiro plano,
      // pois isso pode duplicar mensagens
      // Vamos apenas garantir a conexão e deixar o stream de mensagens
      // funcionar normalmente
    }
  }

  String _formatChatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  void _selectChannel(String channel) {
    setState(() {
      _selectedChannel = channel;
    });

    // Rola para o final quando trocar de canal
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildChannelSelector() {
    final l10n = AppLocalizations.of(context);
    final buttonPadding = EdgeInsets.symmetric(
        horizontal: _getAdaptivePadding(_isWindows ? 8 : 12),
        vertical: _getAdaptivePadding(6));
    final buttonFontSize = _getAdaptiveFontSize(_isWindows ? 12 : 13);
    final containerPadding = EdgeInsets.symmetric(
        vertical: _getAdaptivePadding(6), horizontal: _getAdaptivePadding(4));

    return Container(
      padding: containerPadding,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => _selectChannel('local'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'local'
                    ? _channelColor.withAlpha(25)
                    : null,
                foregroundColor:
                    _selectedChannel == 'local' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'local'
                        ? _channelColor
                        : Colors.transparent,
                  ),
                ),
                padding: buttonPadding,
              ),
              child: Text(
                l10n.translate('local_chat'),
                style: TextStyle(fontSize: buttonFontSize),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _selectChannel('global'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'global'
                    ? _channelColor.withAlpha(25)
                    : null,
                foregroundColor:
                    _selectedChannel == 'global' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'global'
                        ? _channelColor
                        : Colors.transparent,
                  ),
                ),
                padding: buttonPadding,
              ),
              child: Text(
                l10n.translate('global_chat'),
                style: TextStyle(fontSize: buttonFontSize),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _selectChannel('trade'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'trade'
                    ? _channelColor.withAlpha(25)
                    : null,
                foregroundColor:
                    _selectedChannel == 'trade' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'trade'
                        ? _channelColor
                        : Colors.transparent,
                  ),
                ),
                padding: buttonPadding,
              ),
              child: Text(
                l10n.translate('trade_chat'),
                style: TextStyle(fontSize: buttonFontSize),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _selectChannel('help'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'help'
                    ? _channelColor.withAlpha(25)
                    : null,
                foregroundColor:
                    _selectedChannel == 'help' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'help'
                        ? _channelColor
                        : Colors.transparent,
                  ),
                ),
                padding: buttonPadding,
              ),
              child: Text(
                l10n.translate('help_chat'),
                style: TextStyle(fontSize: buttonFontSize),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _selectChannel('private'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'private'
                    ? _channelColor.withAlpha(25)
                    : null,
                foregroundColor:
                    _selectedChannel == 'private' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'private'
                        ? _channelColor
                        : Colors.transparent,
                  ),
                ),
                padding: buttonPadding,
              ),
              child: Text(
                l10n.translate('private_chat'),
                style: TextStyle(fontSize: buttonFontSize),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _selectChannel('commands'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'commands'
                    ? _channelColor.withAlpha(25)
                    : null,
                foregroundColor:
                    _selectedChannel == 'commands' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'commands'
                        ? _channelColor
                        : Colors.transparent,
                  ),
                ),
                padding: buttonPadding,
              ),
              child: Text(
                l10n.translate('god_commands'),
                style: TextStyle(fontSize: buttonFontSize),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _selectChannel('broadcast'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'broadcast'
                    ? _channelColor.withAlpha(25)
                    : null,
                foregroundColor:
                    _selectedChannel == 'broadcast' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'broadcast'
                        ? _channelColor
                        : Colors.transparent,
                  ),
                ),
                padding: buttonPadding,
              ),
              child: Text(
                l10n.translate('broadcast_title'),
                style: TextStyle(fontSize: buttonFontSize),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe,
      {String? displayMessage, String? displayPlayer}) {
    final theme = Theme.of(context);
    final bubblePadding = _getAdaptivePadding(8);
    final contentPadding = _getAdaptivePadding(16);

    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: bubblePadding / 2, horizontal: bubblePadding),
      child: Card(
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(
              horizontal: contentPadding, vertical: bubblePadding),
          title: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyLarge?.color,
                fontSize: _getAdaptiveFontSize(14),
              ),
              children: [
                TextSpan(
                  text: _formatChatTime(message.timestamp),
                  style: const TextStyle(
                    color: Colors.grey,
                  ),
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: displayPlayer ?? message.player,
                  style: TextStyle(
                    color: _channelColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: ' [${message.level}]: ',
                  style: const TextStyle(
                    color: Colors.grey,
                  ),
                ),
                TextSpan(
                  text: displayMessage ?? message.message,
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: _getAdaptiveFontSize(15),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivateConversationSelector() {
    final peers = _privatePeers();
    if (peers.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(_getAdaptivePadding(12)),
        child: Text(
          AppLocalizations.of(context).translate('no_private_conversations'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
      );
    }

    final selected =
        _selectedPrivatePeer != null && peers.contains(_selectedPrivatePeer)
            ? _selectedPrivatePeer!
            : peers.first;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _getAdaptivePadding(8),
        vertical: _getAdaptivePadding(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: peers.map((peer) {
            final isSelected = _sameName(selected, peer);
            return Padding(
              padding: EdgeInsets.only(right: _getAdaptivePadding(8)),
              child: ChoiceChip(
                label: Text(peer),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedPrivatePeer = peer;
                  });
                  _scrollToBottom();
                },
                selectedColor: _channelColor.withAlpha(40),
                side: BorderSide(
                    color: isSelected ? _channelColor : Colors.transparent),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPrivateMessageList() {
    final peers = _privatePeers();
    final selectedPeer =
        _selectedPrivatePeer != null && peers.contains(_selectedPrivatePeer)
            ? _selectedPrivatePeer
            : (peers.isNotEmpty ? peers.first : null);
    final messages = selectedPeer == null
        ? <ChatMessage>[]
        : _privateMessagesFor(selectedPeer);

    return Column(
      children: [
        _buildPrivateConversationSelector(),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? _buildEmptyChannelMessage()
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final mine = _privateMessageIsMine(message);
                    return _buildMessageBubble(
                      message,
                      mine,
                      displayPlayer: mine ? _monitorPlayerName : message.player,
                      displayMessage: _privateDisplayMessage(message),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyChannelMessage() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: _getAdaptiveIconSize(48),
            color: _channelColor.withAlpha(128),
          ),
          SizedBox(height: _getAdaptivePadding(16)),
          Text(
            AppLocalizations.of(context).translate('no_messages_in_channel'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodySmall?.color,
              fontSize: _getAdaptiveFontSize(14),
            ),
          ),
          SizedBox(height: _getAdaptivePadding(16)),
          ElevatedButton(
            onPressed: _requestChatHistory,
            style: _isWindows
                ? ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  )
                : null,
            child: Text(
                AppLocalizations.of(context).translate('refresh_messages')),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final l10n = AppLocalizations.of(context);
    if (_selectedChannel == 'broadcast') {
      if (_broadcastHistory.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.campaign_rounded,
                  size: 48, color: Colors.orange.withAlpha(128)),
              const SizedBox(height: 16),
              Text(l10n.translate('no_broadcasts'),
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }
      return ListView.builder(
        controller: _scrollController,
        itemCount: _broadcastHistory.length,
        itemBuilder: (context, index) {
          final item = _broadcastHistory[index];
          final dt =
              DateTime.tryParse(item['timestamp'] ?? '') ?? DateTime.now();
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: Colors.orange.withAlpha(20),
            child: ListTile(
              leading: const Icon(Icons.campaign_rounded, color: Colors.orange),
              title: Text(item['message'] ?? '-',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'),
            ),
          );
        },
      );
    } else {
      if (_selectedChannel == 'commands') {
        return Center(
          child: Padding(
            padding: EdgeInsets.all(_getAdaptivePadding(24)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.terminal_rounded,
                    size: 48, color: _channelColor.withAlpha(179)),
                SizedBox(height: _getAdaptivePadding(16)),
                Text(
                  l10n.translate('god_commands_desc'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey, fontSize: _getAdaptiveFontSize(14)),
                ),
              ],
            ),
          ),
        );
      }

      if (_selectedChannel == 'private') {
        return _buildPrivateMessageList();
      }

      // Filtra as mensagens pelo canal selecionado
      final channelMessages = _messages
          .where(
              (msg) => msg.channel.replaceAll('chat_', '') == _selectedChannel)
          .toList();

      if (channelMessages.isEmpty) {
        return _buildEmptyChannelMessage();
      }

      return ListView.builder(
        controller: _scrollController,
        itemCount: channelMessages.length,
        itemBuilder: (context, index) {
          final message = channelMessages[index];
          return _buildMessageBubble(message, false);
        },
      );
    }
  }

  // Adapta o conteúdo da tela quando não há conexão
  Widget _buildNoConnectionContent(
      BuildContext context, AppLocalizations l10n) {
    final iconSize = _isWindows
        ? MediaQuery.of(context).size.width * 0.08
        : MediaQuery.of(context).size.width * 0.15;

    final fontSize = _isWindows
        ? MediaQuery.of(context).size.width * 0.022
        : MediaQuery.of(context).size.width * 0.045;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: iconSize,
            color: Colors.grey,
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.02),
          Text(
            l10n.translate('no_server_connection'),
            style: TextStyle(
              fontSize: fontSize,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: _getAdaptivePadding(20)),
          ElevatedButton.icon(
            onPressed: _ensureConnection,
            icon: const Icon(Icons.refresh),
            style: _isWindows
                ? ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    textStyle: const TextStyle(fontSize: 14),
                  )
                : null,
            label: Text(l10n.translate('try_connect')),
          ),
        ],
      ),
    );
  }

  Future<void> _loadBroadcastHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('broadcast_history') ?? [];
    setState(() {
      _broadcastHistory =
          list.map((e) => json.decode(e) as Map<String, dynamic>).toList();
    });
  }

  Future<void> _saveBroadcastHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _broadcastHistory.map((e) => json.encode(e)).toList();
    await prefs.setStringList('broadcast_history', list);
  }

  Future<void> _addBroadcastToHistory(String message) async {
    _broadcastHistory.add({
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await _saveBroadcastHistory();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final websocketService = context.watch<WebSocketService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.chat_rounded, size: _getAdaptiveIconSize(24)),
            SizedBox(width: _getAdaptivePadding(12)),
            Text(l10n.translate('chat_title')),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: _getAdaptiveIconSize(24)),
            onPressed: _requestChatHistory,
            tooltip: l10n.translate('refresh_tooltip'),
          ),
          IconButton(
            icon: Icon(_isConnected ? Icons.wifi : Icons.wifi_off,
                size: _getAdaptiveIconSize(24)),
            onPressed: () {
              if (!_isConnected) {
                _webSocketService.reconnectManually();
                // Força atualização do estado após um breve delay
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    setState(() {
                      _isConnected = _webSocketService.connectionStatus;
                    });
                  }
                });
              } else {
                // Mostra status da conexão
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l10n.translate('connection_status'),
                      style: TextStyle(fontSize: _getAdaptiveFontSize(14)),
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            tooltip: _isConnected
                ? l10n.translate('connected_tooltip')
                : l10n.translate('reconnect_tooltip'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildChannelSelector(),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<bool>(
                  stream: websocketService.connectionStatusStream,
                  initialData: websocketService.connectionStatus,
                  builder: (context, connectionSnapshot) {
                    if (!connectionSnapshot.data!) {
                      return _buildNoConnectionContent(context, l10n);
                    }

                    return _buildMessageList();
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.symmetric(
                    horizontal: _getAdaptivePadding(16),
                    vertical: _getAdaptivePadding(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        constraints:
                            BoxConstraints(maxHeight: _isWindows ? 80 : 120),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius:
                              BorderRadius.circular(_isWindows ? 16 : 24),
                          border: Border.all(
                            color: theme.dividerColor.withAlpha(25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                decoration: InputDecoration(
                                  hintText: _messageHintText(l10n),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.fromLTRB(
                                      _getAdaptivePadding(20),
                                      _getAdaptivePadding(10),
                                      _getAdaptivePadding(20),
                                      _getAdaptivePadding(10)),
                                  hintStyle: TextStyle(
                                    color: theme.hintColor.withAlpha(153),
                                    fontSize: _getAdaptiveFontSize(14),
                                  ),
                                ),
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: _getAdaptiveFontSize(14),
                                ),
                                enabled: !_isSending && _isConnected,
                                onSubmitted: (text) {
                                  if (text.isNotEmpty) {
                                    _sendMessage(text);
                                  }
                                },
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                  right: _getAdaptivePadding(4),
                                  bottom: _getAdaptivePadding(4)),
                              child: IconButton(
                                onPressed: (_isSending || !_isConnected)
                                    ? null
                                    : () {
                                        final text = _messageController.text;
                                        if (text.isNotEmpty) {
                                          _sendMessage(text);
                                        }
                                      },
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  padding:
                                      EdgeInsets.all(_getAdaptivePadding(10)),
                                  disabledBackgroundColor:
                                      theme.colorScheme.primary.withAlpha(102),
                                ),
                                icon: _isSending
                                    ? SizedBox(
                                        width: _getAdaptiveIconSize(20),
                                        height: _getAdaptiveIconSize(20),
                                        child: CircularProgressIndicator(
                                          strokeWidth: _isWindows ? 1.5 : 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white.withAlpha(255)),
                                        ),
                                      )
                                    : Icon(Icons.send_rounded,
                                        size: _getAdaptiveIconSize(24)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Adiciona o ConnectionStatusPopup para padronizar com as outras telas
          ConnectionStatusPopup(webSocketService: websocketService),
        ],
      ),
    );
  }
}
