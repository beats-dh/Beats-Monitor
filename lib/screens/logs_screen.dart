import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/events.dart';
import '../models/websocket_events.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../widgets/connection_status_popup.dart';
import '../widgets/penultima_branding.dart';

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
  static const Duration _logsBridgeTimeout = Duration(seconds: 10);

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
  bool _usingRuntimeFallback = false;
  bool _usingLogsBridge = false;
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
    for (final entry in _logFiles) {
      if (entry.file == selected) {
        return entry.runtime;
      }
    }
    return selected == 'runtime.log';
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
      if (!mounted || !_selectedRuntimeLog || _usingLogsBridge) {
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
      if (!_usingRuntimeFallback) {
        _statusMessage = null;
      }
    });

    try {
      _applyLogFileList(await _fetchApiLogList(), usingBridge: false);
      await _loadSelectedLogSnapshot();
    } catch (_) {
      try {
        _applyLogFileList(await _fetchBridgeLogList(), usingBridge: true);
        await _loadSelectedLogSnapshot();
      } catch (_) {
        if (!mounted) {
          return;
        }
        _activateRuntimeFallback();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFiles = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _fetchApiLogList() async {
    return _decodeDadosResponse(await ApiService.get('server/logs'));
  }

  Future<Map<String, dynamic>> _fetchBridgeLogList() async {
    return _decodeDadosResponse(
      await _getLogsBridge({'action': 'list'}),
    );
  }

  void _applyLogFileList(
    Map<String, dynamic> dados, {
    required bool usingBridge,
  }) {
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

    final runtimeFile = dados['runtime_file']?.toString() ?? 'runtime.log';
    String? nextSelection = _selectedLogFile;
    if (nextSelection == null ||
        !files.any((entry) => entry.file == nextSelection)) {
      nextSelection = files.any((entry) => entry.file == runtimeFile)
          ? runtimeFile
          : (files.isNotEmpty ? files.first.file : runtimeFile);
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _usingRuntimeFallback = false;
      _usingLogsBridge = usingBridge;
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
  }

  void _activateRuntimeFallback() {
    final fallbackEntry = _LogFileEntry(
      file: 'runtime.log',
      size: _size,
      modifiedMs: _modifiedAt?.millisecondsSinceEpoch ?? 0,
      runtime: true,
    );
    setState(() {
      _usingRuntimeFallback = true;
      _usingLogsBridge = false;
      _isLoadingSnapshot = false;
      _logFiles
        ..clear()
        ..add(fallbackEntry);
      _logRoot = null;
      _selectedLogFile = 'runtime.log';
      _fileName = 'runtime.log';
      _statusMessage =
          AppLocalizations.of(context).translate('log_files_api_unavailable');
    });
    _requestRuntimeSnapshot();
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

    if (_selectedRuntimeLog && !_usingLogsBridge) {
      _requestRuntimeSnapshot();
      return;
    }

    setState(() {
      _isLoadingSnapshot = true;
      _statusMessage = null;
    });

    try {
      final snapshot = _usingLogsBridge
          ? await _fetchBridgeLogSnapshot(selected)
          : await _fetchApiLogSnapshot(selected);
      _applySnapshot(snapshot);
    } catch (error) {
      if (!_usingLogsBridge) {
        try {
          final snapshot = await _fetchBridgeLogSnapshot(selected);
          if (mounted) {
            setState(() {
              _usingLogsBridge = true;
            });
          }
          _applySnapshot(snapshot);
          return;
        } catch (_) {
          // Keep the original API error visible below.
        }
      }
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

  Future<Map<String, dynamic>> _fetchApiLogSnapshot(String selected) async {
    final endpoint = 'server/logs/file/${Uri.encodeComponent(selected)}';
    return _decodeDadosResponse(await ApiService.get(endpoint));
  }

  Future<Map<String, dynamic>> _fetchBridgeLogSnapshot(String selected) async {
    return _decodeDadosResponse(
      await _getLogsBridge({
        'action': 'file',
        'path': selected,
      }),
    );
  }

  Future<http.Response> _getLogsBridge(Map<String, String> query) async {
    if (AuthService.hasCredentials) {
      await AuthService.refreshToken();
    }
    final uri = Uri.base
        .resolve('beats_monitor_logs.php')
        .replace(queryParameters: query);
    return http
        .get(uri, headers: AuthService.authHeaders)
        .timeout(_logsBridgeTimeout);
  }

  Map<String, dynamic> _decodeDadosResponse(http.Response response) {
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 || data is! Map || data['dados'] is! Map) {
      throw Exception(_responseMessage(data, response.statusCode));
    }
    return (data['dados'] as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
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

    final status = snapshot['error']?.toString() ??
        (snapshot['missing'] == true
            ? AppLocalizations.of(context).translate('runtime_log_missing')
            : snapshot['truncated'] == true
                ? AppLocalizations.of(context)
                    .translate('runtime_log_truncated')
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

  void _requestRuntimeSnapshot() {
    _ensureConnection();
    _subscribeRuntimeLog();
    _webSocketService.sendMessage({'type': 'runtime_log_snapshot'});
  }

  void _requestSnapshot() {
    if (_selectedRuntimeLog && !_usingLogsBridge) {
      _requestRuntimeSnapshot();
      return;
    }
    unawaited(_loadSelectedLogSnapshot());
  }

  Future<void> _selectLogFile(String file) async {
    setState(() {
      _selectedLogFile = file;
      _fileName = file;
      _lines.clear();
      _statusMessage = null;
    });

    if (_selectedRuntimeLog && !_usingLogsBridge) {
      _requestRuntimeSnapshot();
      return;
    }

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
    if (lower.contains('[error]') ||
        lower.contains(' error') ||
        lower.contains('exception')) {
      return const Color(0xFFFF6A75);
    }
    if (lower.contains('[warning]') || lower.contains(' warning')) {
      return const Color(0xFFFFB347);
    }
    if (lower.contains('[debug]') || lower.contains('[trace]')) {
      return const Color(0xFF8E7B9F);
    }
    return const Color(0xFFE9DFF4);
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
      body: PenultimaBackdrop(
        imageOpacity: 0.18,
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context, l10n),
                    const SizedBox(height: 12),
                    Expanded(
                      child: PenultimaPanel(
                        padding: EdgeInsets.zero,
                        borderColor: const Color(0x557932B8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildStatusBar(context, l10n),
                            Expanded(child: _buildLogBody(context, l10n)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ConnectionStatusPopup(webSocketService: _webSocketService),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final title = Row(
          children: [
            _LogActionButton(
              icon: Icons.arrow_back_rounded,
              tooltip: l10n.translate('back'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 10),
            if (!compact) ...[
              Image.asset(
                penultimaLogoAsset,
                width: 46,
                height: 46,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.translate('logs_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _usingRuntimeFallback
                        ? 'runtime.log websocket stream'
                        : 'server logs command console',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFCDB7DD),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        );

        final actions = _buildActionButtons(context, l10n);
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: actions),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            ...actions,
          ],
        );
      },
    );
  }

  List<Widget> _buildActionButtons(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return [
      _LogActionButton(
        icon: _autoScroll
            ? Icons.vertical_align_bottom_rounded
            : Icons.vertical_align_center_rounded,
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
      _LogActionButton(
        icon: MdiIcons.folderSearch,
        tooltip: l10n.translate('log_files_refresh'),
        onPressed: _isLoadingFiles ? null : _loadLogFiles,
      ),
      _LogActionButton(
        icon: Icons.refresh_rounded,
        tooltip: l10n.translate('refresh'),
        onPressed: _isLoadingSnapshot ? null : _requestSnapshot,
      ),
      _LogActionButton(
        icon: Icons.cleaning_services_rounded,
        tooltip: l10n.translate('runtime_log_clear'),
        onPressed: _clearLines,
      ),
      _LogActionButton(
        icon: _isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
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
    ];
  }

  Widget _buildLogBody(BuildContext context, AppLocalizations l10n) {
    if (_isLoadingSnapshot && _lines.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFD35CFF)),
      );
    }

    if (_lines.isEmpty) {
      return _buildEmptyState(context, l10n);
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xD607030C)),
      child: Scrollbar(
        controller: _scrollController,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          itemCount: _lines.length,
          itemBuilder: (context, index) {
            final line = _lines[index];
            return SelectableText(
              line,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: MediaQuery.sizeOf(context).width < 520 ? 11 : 12,
                height: 1.28,
                color: _lineColor(context, line),
              ),
            );
          },
        ),
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
    final meta =
        '${_formatSize(_size)}$modified$status${_logRoot == null ? '' : ' - ${_logFiles.length} files'}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE120817),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withAlpha(140)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 650;
            final selector = Row(
              children: [
                Icon(
                  _selectedRuntimeLog ? MdiIcons.consoleLine : Icons.article,
                  size: 21,
                  color: _selectedRuntimeLog
                      ? (_isConnected
                          ? const Color(0xFF55F28E)
                          : const Color(0xFFFFB347))
                      : const Color(0xFFD35CFF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedValue,
                      isExpanded: true,
                      menuMaxHeight: 420,
                      dropdownColor: const Color(0xFF160B21),
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
              ],
            );

            final metaText = Text(
              meta,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFE8D9F4),
                fontWeight: FontWeight.w700,
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  selector,
                  const SizedBox(height: 6),
                  metaText,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: selector),
                const SizedBox(width: 12),
                Flexible(child: metaText),
              ],
            );
          },
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
              MdiIcons.textBoxSearchOutline,
              size: 58,
              color: const Color(0xFFD35CFF).withAlpha(205),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.translate('runtime_log_empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage ?? l10n.translate('runtime_log_waiting'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFCDB7DD),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _LogActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFFF6EBFF),
            disabledForegroundColor: const Color(0x777E6A8D),
            backgroundColor: const Color(0x77160921),
            disabledBackgroundColor: const Color(0x33160921),
            hoverColor: const Color(0x558C35D7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0x44B44CFF)),
            ),
          ),
        ),
      ),
    );
  }
}
