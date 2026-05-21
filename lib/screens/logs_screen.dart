import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/events.dart';
import '../models/websocket_events.dart';
import '../services/websocket_service.dart';
import '../widgets/connection_status_popup.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with WidgetsBindingObserver {
  static const int _maxLines = 3000;

  final ScrollController _scrollController = ScrollController();
  final List<String> _lines = [];
  late WebSocketService _webSocketService;
  StreamSubscription<RuntimeLogEvent>? _logSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  bool _initialized = false;
  bool _isConnected = false;
  bool _autoScroll = true;
  String _fileName = 'runtime.log';
  String? _statusMessage;
  DateTime? _modifiedAt;
  int _size = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webSocketService = context.read<WebSocketService>();
    _isConnected = _webSocketService.connectionStatus;
    _setupSubscriptions();
    _ensureConnection();
    _subscribeRuntimeLog();
    _initialized = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logSubscription?.cancel();
    _connectionSubscription?.cancel();
    if (_initialized) {
      _webSocketService.unsubscribe([WebSocketEvents.runtimeLog]);
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _ensureConnection();
      _requestSnapshot();
    }
  }

  void _setupSubscriptions() {
    _logSubscription = _webSocketService.runtimeLogStream.listen((event) {
      if (!mounted) {
        return;
      }

      final wasNearBottom = _isNearBottom();
      setState(() {
        _fileName = event.file;
        _modifiedAt = event.modifiedAt;
        _size = event.size;
        _statusMessage = event.error ??
            (event.missing
                ? AppLocalizations.of(context).translate('runtime_log_missing')
                : event.truncated
                    ? AppLocalizations.of(context)
                        .translate('runtime_log_truncated')
                    : null);

        if (event.snapshot) {
          _lines.clear();
        }
        _lines.addAll(event.lines);
        if (_lines.length > _maxLines) {
          _lines.removeRange(0, _lines.length - _maxLines);
        }
      });

      if (_autoScroll && (wasNearBottom || event.snapshot)) {
        _scrollToBottom();
      }
    });

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
      _webSocketService.startConnection();
    }
  }

  void _subscribeRuntimeLog() {
    _webSocketService.subscribe([WebSocketEvents.runtimeLog]);
  }

  void _requestSnapshot() {
    _ensureConnection();
    _webSocketService.sendMessage({
      'type': 'runtime_log_snapshot',
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    return _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 120;
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _clearLines() {
    setState(() {
      _lines.clear();
      _statusMessage = null;
    });
    _requestSnapshot();
  }

  Color _lineColor(BuildContext context, String line) {
    final lower = line.toLowerCase();
    if (lower.contains('[error]') || lower.contains(' error')) {
      return Colors.redAccent;
    }
    if (lower.contains('[warning]') || lower.contains(' warning')) {
      return Colors.orangeAccent;
    }
    if (lower.contains('[debug]') || lower.contains('[trace]')) {
      return Theme.of(context).textTheme.bodySmall?.color?.withAlpha(170) ??
          Colors.grey;
    }
    return Theme.of(context).textTheme.bodyMedium?.color ?? Colors.white;
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.article_rounded),
            const SizedBox(width: 12),
            Text(l10n.translate('logs_title')),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_autoScroll
                ? Icons.vertical_align_bottom_rounded
                : Icons.vertical_align_center_rounded),
            tooltip: l10n.translate('runtime_log_autoscroll'),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
              if (_autoScroll) {
                _scrollToBottom();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.translate('refresh'),
            onPressed: _requestSnapshot,
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded),
            tooltip: l10n.translate('runtime_log_clear'),
            onPressed: _clearLines,
          ),
          IconButton(
            icon: Icon(_isConnected ? Icons.wifi : Icons.wifi_off),
            tooltip: _isConnected
                ? l10n.translate('connected_tooltip')
                : l10n.translate('reconnect_tooltip'),
            onPressed: _isConnected
                ? null
                : () {
                    _webSocketService.reconnectManually();
                    _subscribeRuntimeLog();
                  },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusBar(context, l10n),
              Expanded(
                child: _lines.isEmpty
                    ? _buildEmptyState(context, l10n)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: _lines.length,
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          return SelectableText(
                            line,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.25,
                              color: _lineColor(context, line),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          ConnectionStatusPopup(webSocketService: _webSocketService),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final modified = _modifiedAt == null
        ? ''
        : ' - ${_modifiedAt!.toLocal().toString().split(".").first}';
    final status = _statusMessage == null ? '' : ' - $_statusMessage';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withAlpha(120)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              _isConnected ? Icons.sync_rounded : Icons.sync_problem_rounded,
              size: 20,
              color: _isConnected ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${l10n.translate('runtime_log')}: $_fileName - ${_formatSize(_size)}$modified$status',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 56,
              color: theme.colorScheme.primary.withAlpha(180),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('runtime_log_empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('runtime_log_waiting'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
