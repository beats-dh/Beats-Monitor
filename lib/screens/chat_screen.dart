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

class _ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  String _selectedChannel = 'global';
  StreamSubscription<ChatMessage>? _subscription;
  late WebSocketService _webSocketService;
  bool _initialized = false;
  final Set<String> _messageKeys = {};
  final List<ChatMessage> _messages = [];
  bool _historyReceived = false;

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
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
    _subscription?.cancel();
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
    _scrollController.dispose();
    // Limpa as mensagens e as chaves ao fechar
    _messages.clear();
    _messageKeys.clear();
    _historyReceived = false;
    super.dispose();
  }

  String _formatChatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildChannelSelector() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildChannelButton('global', l10n.translate('global_chat'), Colors.blue),
          _buildChannelButton('trade', l10n.translate('trade_chat'), Colors.green),
          _buildChannelButton('help', l10n.translate('help_chat'), Colors.orange),
        ],
      ),
    );
  }

  Widget _buildChannelButton(String channel, String label, Color color) {
    final isSelected = _selectedChannel == channel;
    return InkWell(
      onTap: () {
        if (_selectedChannel != channel) {
          setState(() {
            _selectedChannel = channel;
          });
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
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
            color: _channelColor.withOpacity(0.5),
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

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
        ],
      ),
    );
  }
}
