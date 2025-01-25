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
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  String _selectedChannel = 'global';
  StreamSubscription<ChatMessage>? _subscription;
  late WebSocketService _webSocketService;
  bool _initialized = false;

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _webSocketService = context.read<WebSocketService>();
        _webSocketService.manualReconnectMode = false;
        _webSocketService.startConnection();
        _webSocketService.subscribe([
          'chat_global',
          'chat_trade',
          'chat_help',
        ]);
        _setupMessageSubscription();
        _initialized = true;
      }
    });
  }

  void _setupMessageSubscription() {
    _subscription = _webSocketService.chatMessageStream.listen((message) {
      if (mounted) {
        setState(() {
          _messages.add(message);
        });
        if (message.channel == 'chat_$_selectedChannel') {
          _scrollToBottom();
        }
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
        ]);
        _webSocketService.closeCurrentConnection();
      }
      _webSocketService.manualReconnectMode = true;
    });
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Agora';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m atrás';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h atrás';
    } else {
      return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
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
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              backgroundColor: _channelColor.withOpacity(0.1),
              child: Text(
                message.player[0].toUpperCase(),
                style: TextStyle(color: _channelColor),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? _channelColor.withOpacity(0.1) : theme.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isMe ? _channelColor.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      message.player,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _channelColor,
                      ),
                    ),
                  Text(message.message),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(message.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: _channelColor.withOpacity(0.1),
              child: Text(
                message.player[0].toUpperCase(),
                style: TextStyle(color: _channelColor),
              ),
            ),
          ],
        ],
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // Filtra as mensagens do canal atual
    final channelMessages = _messages.where((msg) => msg.channel == 'chat_$_selectedChannel').toList();

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
            child: channelMessages.isEmpty
                ? _buildEmptyChannelMessage()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: channelMessages.length,
                    itemBuilder: (context, index) {
                      final message = channelMessages[index];
                      final isMe = message.player == 'Você';
                      return _buildMessageBubble(message, isMe);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
