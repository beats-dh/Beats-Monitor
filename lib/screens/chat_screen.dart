import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/events.dart';
import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  String _selectedChannel = 'global';
  StreamSubscription<ChatMessage>? _subscription;
  late WebSocketService _webSocketService;
  bool _initialized = false;
  final Set<String> _messageKeys = {};
  final List<ChatMessage> _messages = [];
  bool _historyReceived = false;
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  Color get _channelColor {
    switch (_selectedChannel) {
      case 'global':
        return Colors.blue;
      case 'trade':
        return Colors.green;
      case 'help':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _getMessageKey(ChatMessage message) {
    return '${message.channel}_${message.player}_${message.timestamp.millisecondsSinceEpoch}_${message.message}';
  }

  void _addMessage(ChatMessage message) {
    final key = _getMessageKey(message);
    if (_messageKeys.add(key)) { // Retorna true se a key não existia
      setState(() {
        _messages.add(message);
        // Ordena as mensagens por timestamp
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
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
        final wasNearBottom = _isNearBottom();
        
        // Se for uma mensagem do histórico
        if (message.timestamp.isBefore(DateTime.now().subtract(const Duration(seconds: 5)))) {
          _addMessage(message);
          
          // Agenda um único scroll após receber todo o histórico
          if (!_historyReceived) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                setState(() {
                  _historyReceived = true;
                });
                _scrollToBottom();
              }
            });
          }
        } else {
          // Se for uma mensagem nova
          _addMessage(message);
          
          // Verifica se a mensagem é do canal atual
          if (message.channel.replaceAll('chat_', '') == _selectedChannel) {
            // Se estava próximo do final, faz o scroll
            if (wasNearBottom) {
              _scrollToBottom();
            }
          }
        }
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    try {
      setState(() => _isSending = true);

      // Envia a mensagem usando o canal selecionado atual
      _webSocketService.sendMessage({
        'type': 'chat_message',
        'data': {
          'message': text.trim(),
          'channel': 'chat_$_selectedChannel' // Usa o canal selecionado
        }
      });

      // Limpa o campo de texto
      _messageController.clear();
      
      // Rola para o final da lista
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      // Mostra erro para o usuário
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
        _webSocketService.manualReconnectMode = false;
        
        // Inscreve-se no stream de status da conexão
        _webSocketService.connectionStatusStream.listen((isConnected) {
          if (isConnected) {
            // Solicita o histórico do chat apenas quando conectado
            _webSocketService.sendMessage({
              'type': 'chat_history',
              'channel': 'chat_$_selectedChannel'
            });
          }
        });

        // Inicia a conexão
        _webSocketService.startConnection();
        
        // Se inscreve nos canais de chat
        _webSocketService.subscribe([
          'chat_global',
          'chat_trade',
          'chat_help',
          'chat_history'  // Precisa subscrever para receber o histórico
        ]);
        
        _setupMessageSubscription();
        _initialized = true;
      }
    });
  }

  @override
  void dispose() {
    // Remove o observer do teclado
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _subscription?.cancel();
    _scrollController.dispose();

    // Remove inscrição dos canais e fecha conexão
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_webSocketService.manualReconnectMode) {
        _webSocketService.unsubscribe([
          'chat_global',
          'chat_trade',
          'chat_help',
          'chat_history'
        ]);
        _webSocketService.closeCurrentConnection();
      }
      _webSocketService.manualReconnectMode = true;
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton(
            onPressed: () => _selectChannel('global'),
            style: TextButton.styleFrom(
              backgroundColor: _selectedChannel == 'global' ? _channelColor.withAlpha(25) : null,
              foregroundColor: _selectedChannel == 'global' ? _channelColor : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedChannel == 'global' ? _channelColor : Colors.transparent,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(l10n.translate('global_chat')),
          ),
          TextButton(
            onPressed: () => _selectChannel('trade'),
            style: TextButton.styleFrom(
              backgroundColor: _selectedChannel == 'trade' ? _channelColor.withAlpha(25) : null,
              foregroundColor: _selectedChannel == 'trade' ? _channelColor : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedChannel == 'trade' ? _channelColor : Colors.transparent,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(l10n.translate('trade_chat')),
          ),
          TextButton(
            onPressed: () => _selectChannel('help'),
            style: TextButton.styleFrom(
              backgroundColor: _selectedChannel == 'help' ? _channelColor.withAlpha(25) : null,
              foregroundColor: _selectedChannel == 'help' ? _channelColor : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedChannel == 'help' ? _channelColor : Colors.transparent,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(l10n.translate('help_chat')),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyLarge?.color,
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
                    fontSize: 15,
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
            size: 48,
            color: _channelColor.withAlpha(128),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma mensagem no canal ainda',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    // Filtra as mensagens pelo canal selecionado
    final channelMessages = _messages.where(
      (msg) => msg.channel.replaceAll('chat_', '') == _selectedChannel
    ).toList();

    return ListView.builder(
      controller: _scrollController,
      itemCount: channelMessages.length,
      itemBuilder: (context, index) {
        final message = channelMessages[index];
        return _buildMessageBubble(message, false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.chat_rounded),
            const SizedBox(width: 12),
            Text(l10n.translate('chat_title')),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildChannelSelector(),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyChannelMessage()
                : _buildMessageList(),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(24),
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
                              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                              hintStyle: TextStyle(
                                color: theme.hintColor.withAlpha(153),
                              ),
                            ),
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            style: theme.textTheme.bodyMedium,
                            enabled: !_isSending,
                            onSubmitted: (text) {
                              if (text.isNotEmpty) {
                                _sendMessage(text);
                              }
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                          child: IconButton(
                            onPressed: _isSending 
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
                              padding: const EdgeInsets.all(10),
                            ),
                            icon: _isSending
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withAlpha(255)),
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
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
    );
  }
}
