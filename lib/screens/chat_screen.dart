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

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
  }

  void _setupMessageSubscription() {
    _subscription = _webSocketService.chatMessageStream.listen((message) {
      debugPrint('Recebida mensagem no canal: ${message.channel}');
      debugPrint('Canal atual: $_selectedChannel');
      if (message.channel == 'chat_$_selectedChannel') {
        debugPrint('Adicionando mensagem: ${message.player}: ${message.message}');
        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    if (!_webSocketService.manualReconnectMode) {
      _webSocketService.unsubscribe([
        'chat_global',
        'chat_trade',
        'chat_help',
      ]);
      _webSocketService.closeCurrentConnection();
    }
    _webSocketService.manualReconnectMode = true;
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
            Text(l10n.translate('chat')),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<String>(
              value: _selectedChannel,
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedChannel = newValue;
                    _messages.clear(); // Limpa as mensagens ao trocar de canal
                  });
                }
              },
              items: [
                DropdownMenuItem(
                  value: 'global',
                  child: Text(l10n.translate('global_chat')),
                ),
                DropdownMenuItem(
                  value: 'trade',
                  child: Text(l10n.translate('trade_chat')),
                ),
                DropdownMenuItem(
                  value: 'help',
                  child: Text(l10n.translate('help_chat')),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      message.player,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message.message),
                        Text(
                          message.timestamp.toLocal().toString(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
