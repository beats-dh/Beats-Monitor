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

class _ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
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
    if (_messageKeys.add(key)) { // Retorna true se a key não existia
      setState(() {
        _messages.add(message);
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
    _connectionSubscription = _webSocketService.connectionStatusStream.listen((isConnected) {
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
        'channels': ['chat_local', 'chat_global', 'chat_trade', 'chat_help', 'chat_private'] // Especifica todos os canais para garantir que receba todo o histórico
      });
      _requestedHistory = true;
    } else {
      // Se não conseguir enviar, mostra uma mensagem
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('reconnecting_to_server')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    if (_selectedChannel == 'broadcast') {
      try {
        setState(() => _isSending = true);
        final response = await ApiService.post('server/broadcast', body: {"message": text.trim()});
        if (response.statusCode == 200) {
          await _addBroadcastToHistory(text.trim());
          _messageController.clear();
        }
      } catch (e) {
        // Se erro, não faz nada e mantém o texto
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
      _ensureConnection();
      _webSocketService.sendMessage({
        'type': 'chat_message',
        'data': {
          'message': text.trim(),
          'channel': 'chat_$_selectedChannel'
        }
      });
      _messageController.clear();
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
            content: Text(AppLocalizations.of(context).translate('error_sending_message')),
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
        _connectionSubscription = _webSocketService.connectionStatusStream.listen((isConnected) {
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
          'chat_history'  // Precisa subscrever para receber o histórico
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
      vertical: _getAdaptivePadding(6)
    );
    final buttonFontSize = _getAdaptiveFontSize(_isWindows ? 12 : 13);
    final containerPadding = EdgeInsets.symmetric(
      vertical: _getAdaptivePadding(6),
      horizontal: _getAdaptivePadding(4)
    );
    
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
                backgroundColor: _selectedChannel == 'local' ? _channelColor.withAlpha(25) : null,
                foregroundColor: _selectedChannel == 'local' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'local' ? _channelColor : Colors.transparent,
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
                backgroundColor: _selectedChannel == 'global' ? _channelColor.withAlpha(25) : null,
                foregroundColor: _selectedChannel == 'global' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'global' ? _channelColor : Colors.transparent,
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
                backgroundColor: _selectedChannel == 'trade' ? _channelColor.withAlpha(25) : null,
                foregroundColor: _selectedChannel == 'trade' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'trade' ? _channelColor : Colors.transparent,
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
                backgroundColor: _selectedChannel == 'help' ? _channelColor.withAlpha(25) : null,
                foregroundColor: _selectedChannel == 'help' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'help' ? _channelColor : Colors.transparent,
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
                backgroundColor: _selectedChannel == 'private' ? _channelColor.withAlpha(25) : null,
                foregroundColor: _selectedChannel == 'private' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'private' ? _channelColor : Colors.transparent,
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
              onPressed: () => _selectChannel('broadcast'),
              style: TextButton.styleFrom(
                backgroundColor: _selectedChannel == 'broadcast' ? _channelColor.withAlpha(25) : null,
                foregroundColor: _selectedChannel == 'broadcast' ? _channelColor : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_getAdaptivePadding(20)),
                  side: BorderSide(
                    color: _selectedChannel == 'broadcast' ? _channelColor : Colors.transparent,
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

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    final theme = Theme.of(context);
    final bubblePadding = _getAdaptivePadding(8);
    final contentPadding = _getAdaptivePadding(16);
    
    return Padding(
      padding: EdgeInsets.symmetric(vertical: bubblePadding / 2, horizontal: bubblePadding),
      child: Card(
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: contentPadding, vertical: bubblePadding),
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
                  text: message.player,
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
                  text: message.message,
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
            style: _isWindows ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ) : null,
            child: Text(AppLocalizations.of(context).translate('refresh_messages')),
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
              Icon(Icons.campaign_rounded, size: 48, color: Colors.orange.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text(l10n.translate('no_broadcasts'), style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }
      return ListView.builder(
        controller: _scrollController,
        itemCount: _broadcastHistory.length,
        itemBuilder: (context, index) {
          final item = _broadcastHistory[index];
          final dt = DateTime.tryParse(item['timestamp'] ?? '') ?? DateTime.now();
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: Colors.orange.withOpacity(0.08),
            child: ListTile(
              leading: const Icon(Icons.campaign_rounded, color: Colors.orange),
              title: Text(item['message'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'),
            ),
          );
        },
      );
    } else {
      // Filtra as mensagens pelo canal selecionado
      final channelMessages = _messages.where(
        (msg) => msg.channel.replaceAll('chat_', '') == _selectedChannel
      ).toList();

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
  Widget _buildNoConnectionContent(BuildContext context, AppLocalizations l10n) {
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
            style: _isWindows ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              textStyle: const TextStyle(fontSize: 14),
            ) : null,
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
      _broadcastHistory = list.map((e) => json.decode(e) as Map<String, dynamic>).toList();
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
            icon: Icon(_isConnected ? Icons.wifi : Icons.wifi_off, size: _getAdaptiveIconSize(24)),
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
            tooltip: _isConnected ? l10n.translate('connected_tooltip') : l10n.translate('reconnect_tooltip'),
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
                  vertical: _getAdaptivePadding(8)
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: _isWindows ? 80 : 120
                        ),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(_isWindows ? 16 : 24),
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
                                  hintText: l10n.translate('type_message'),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.fromLTRB(
                                    _getAdaptivePadding(20), 
                                    _getAdaptivePadding(10), 
                                    _getAdaptivePadding(20), 
                                    _getAdaptivePadding(10)
                                  ),
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
                                bottom: _getAdaptivePadding(4)
                              ),
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
                                  padding: EdgeInsets.all(_getAdaptivePadding(10)),
                                  disabledBackgroundColor: theme.colorScheme.primary.withOpacity(0.4),
                                ),
                                icon: _isSending
                                    ? SizedBox(
                                        width: _getAdaptiveIconSize(20),
                                        height: _getAdaptiveIconSize(20),
                                        child: CircularProgressIndicator(
                                          strokeWidth: _isWindows ? 1.5 : 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withAlpha(255)),
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
