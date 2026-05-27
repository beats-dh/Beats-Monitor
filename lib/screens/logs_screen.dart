import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/events.dart';
import '../models/websocket_events.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/connection_status_popup.dart';

class _LogFileEntry {
  final String file;
  final int size;
  final int modifiedMs;
  final bool runtime;

  const _LogFileEntry({
    required this.file,
    required this.size,
    required this.modifiedMs,
    required this.runtime,
  });

  factory _LogFileEntry.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _LogFileEntry(
      file: json['file']?.toString() ?? '',
      size: parseInt(json['size']),
      modifiedMs: parseInt(json['mtime_ms']),
      runtime: json['runtime'] == true,
    );
  }
}

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with WidgetsBindingObserver {
  static const int _maxLines = 3000;

  final ScrollController _scrollController = ScrollController();
  final List<String> _lines = [];
  final List<_LogFileEntry> _logFiles = [];
  late WebSocketService _webSocketService;
  StreamSubscription<RuntimeLogEvent>? _logSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  bool _initialized = false;
  bool _isConnected = false;
  bool _autoScroll = true;
  bool _isLoadingFiles = false;
  bool _isLoadingSnapshot = false;
  String _fileName = 'runtime.log';
  String? _selectedLogFile = 'runtime.log';
  String? _statusMessage;
  String? _logRoot;
  DateTime? _modifiedAt;
  int _size = 0;

  bool get _selectedRuntimeLog {
    final selected = _selectedLogFile;
    if (selected == null) {
      return true;
    }
    final match = _logFiles.where((entry) => entry.file == selected).toList();
    return match.isEmpty ? selected == 'runtime.log' : match.first.runtime;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webSocketService = context.read<WebSocketService>();
    _isConnected = _webSocketService.connectionStatus;
    _setupSubscriptions();
    _ensureConnection();
    _subscribeRuntimeLog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLogFiles();
    });
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
      if (!mounted || !_selectedRuntimeLog) {
        return;
      }

      final selected = _selectedLogFile;
      if (selected != null && selected != event.file) {
        return;
      }

      final wasNearBottom = _isNearBottom();
      setState(() {
        _selectedLogFile = event.file;
        _fileName = event.file;
        _modifiedAt = event.modifiedAt;
        _size = event.size;
        _statusMessage =
            event.error ??
            (event.missing
                ? AppLocalizations.of(context).translate('runtime_log_missing')
                : event.truncated
                ? AppLocalizations.of(
                    context,
                  ).translate('runtime_log_truncated')
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

    _connectionSubscription = _webSocketService.connectionStatusStream.listen((
      isConnected,
    ) {
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

  Future<void> _loadLogFiles() async {
    if (_isLoadingFiles) {
      return;
    }

    setState(() {
      _isLoadingFiles = true;
      _statusMessage = null;
    });

    try {
      final response = await ApiService.get('server/logs');
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['dados'] is! Map) {
        throw Exception(_responseMessage(data, response.statusCode));
      }

      final dados = data['dados'] as Map;
      final rawFiles = dados['files'];
      final files = rawFiles is List
          ? rawFiles
                .whereType<Map>()
                .map(
                  (item) => _LogFileEntry.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                )
                .where((entry) => entry.file.isNotEmpty)
                .toList()
          : <_LogFileEntry>[];

      String? nextSelection = _selectedLogFile;
      if (nextSelection == null ||
          !files.any((entry) => entry.file == nextSelection)) {
        final runtimeFile = dados['runtime_file']?.toString() ?? 'runtime.log';
        nextSelection = files.any((entry) => entry.file == runtimeFile)
            ? runtimeFile
            : (files.isNotEmpty ? files.first.file : runtimeFile);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _logFiles
          ..clear()
          ..addAll(files);
        _logRoot = dados['root']?.toString();
        _selectedLogFile = nextSelection;
        _fileName = nextSelection ?? 'runtime.log';
        _statusMessage = files.isEmpty
            ? AppLocalizations.of(context).translate('log_files_empty')
            : null;
      });

      await _loadSelectedLogSnapshot();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFiles = false;
        });
      }
    }
  }

  String _responseMessage(dynamic data, int statusCode) {
    if (data is Map &&
        data['mensagem'] is String &&
        (data['mensagem'] as String).isNotEmpty) {
      return data['mensagem'] as String;
    }
    return 'HTTP $statusCode';
  }

  Future<void> _loadSelectedLogSnapshot() async {
    final selected = _selectedLogFile;
    if (selected == null || selected.isEmpty || _isLoadingSnapshot) {
      return;
    }

    setState(() {
      _isLoadingSnapshot = true;
      _statusMessage = null;
    });

    try {
      final endpoint = 'server/logs/file/${Uri.encodeComponent(selected)}';
      final response = await ApiService.get(endpoint);
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['dados'] is! Map) {
        throw Exception(_responseMessage(data, response.statusCode));
      }

      final snapshot = (data['dados'] as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      _applySnapshot(snapshot);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lines.clear();
        _statusMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSnapshot = false;
        });
      }
    }
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    if (!mounted) {
      return;
    }

    int parseInt(dynamic value) {
      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    DateTime? parseModifiedAt(dynamic value) {
      final parsed = parseInt(value);
      if (parsed <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(parsed);
    }

    final lines = snapshot['lines'] is List
        ? (snapshot['lines'] as List).map((line) => line.toString()).toList()
        : <String>[];

    final status =
        snapshot['error']?.toString() ??
        (snapshot['missing'] == true
            ? AppLocalizations.of(context).translate('runtime_log_missing')
            : snapshot['truncated'] == true
            ? AppLocalizations.of(context).translate('runtime_log_truncated')
            : null);

    setState(() {
      _fileName = snapshot['file']?.toString() ?? _selectedLogFile ?? _fileName;
      _selectedLogFile = _fileName;
      _modifiedAt = parseModifiedAt(snapshot['mtime_ms']);
      _size = parseInt(snapshot['size']);
      _statusMessage = status;
      _lines
        ..clear()
        ..addAll(
          lines.length > _maxLines
              ? lines.sublist(lines.length - _maxLines)
              : lines,
        );
    });

    if (_autoScroll) {
      _scrollToBottom();
    }
  }

  void _requestSnapshot() {
    _ensureConnection();
    unawaited(_loadSelectedLogSnapshot());
    if (_selectedRuntimeLog) {
      _webSocketService.sendMessage({'type': 'runtime_log_snapshot'});
    }
  }

  Future<void> _selectLogFile(String file) async {
    setState(() {
      _selectedLogFile = file;
      _fileName = file;
      _lines.clear();
      _statusMessage = null;
    });
    await _loadSelectedLogSnapshot();
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
            icon: Icon(
              _autoScroll
                  ? Icons.vertical_align_bottom_rounded
                  : Icons.vertical_align_center_rounded,
            ),
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
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: l10n.translate('log_files_refresh'),
            onPressed: _isLoadingFiles ? null : _loadLogFiles,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.translate('refresh'),
            onPressed: _isLoadingSnapshot ? null : _requestSnapshot,
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
                child: _isLoadingSnapshot && _lines.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _lines.isEmpty
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
    final selectedValue =
        _logFiles.any((entry) => entry.file == _selectedLogFile)
        ? _selectedLogFile
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withAlpha(120)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(
              _selectedRuntimeLog ? Icons.sync_rounded : Icons.article_rounded,
              size: 20,
              color: _selectedRuntimeLog
                  ? (_isConnected ? Colors.green : Colors.orange)
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedValue,
                  isExpanded: true,
                  menuMaxHeight: 420,
                  hint: Text(_fileName),
                  items: _logFiles.map((entry) {
                    final modifiedAt = entry.modifiedMs > 0
                        ? DateTime.fromMillisecondsSinceEpoch(
                            entry.modifiedMs,
                          ).toLocal().toString().split('.').first
                        : '';
                    final suffix = modifiedAt.isEmpty
                        ? _formatSize(entry.size)
                        : '${_formatSize(entry.size)} - $modifiedAt';
                    return DropdownMenuItem<String>(
                      value: entry.file,
                      child: Text(
                        '${entry.file}  ($suffix)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _isLoadingSnapshot || _isLoadingFiles
                      ? null
                      : (value) {
                          if (value != null) {
                            unawaited(_selectLogFile(value));
                          }
                        },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${_formatSize(_size)}$modified$status${_logRoot == null ? '' : ' - ${_logFiles.length} files'}',
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
