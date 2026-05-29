import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/events.dart' as events;
import '../models/system_data.dart';
import '../models/websocket_events.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../widgets/page_transition.dart';
import '../widgets/penultima_branding.dart';
import 'banned_players_screen.dart';
import 'chat_screen.dart';
import 'config_screen.dart';
import 'live_screen.dart';
import 'logs_screen.dart';
import 'monitor_screen.dart';
import 'online_players_screen.dart';
import 'server_info_screen.dart';

const _purple = Color(0xFFD45CFF);
const _deepPurple = Color(0xFF8F35FF);
const _cyan = Color(0xFF00D9FF);
const _green = Color(0xFF63F05F);
const _orange = Color(0xFFFFA319);
const _red = Color(0xFFFF3C6A);
const _panel = Color(0xDE090610);
const _border = Color(0x664F1B79);
const _serverClientVersion = '15.23';
const _serverProtocolVersion = '1523';
const _dashboardRefreshInterval = Duration(seconds: 10);
const _dashboardRuntimeLineLimit = 80;
const _recentActivityLimit = 30;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _runtimeLines = <String>[];
  final List<_DashboardLogFile> _logFiles = <_DashboardLogFile>[];
  final List<_ActivityEvent> _activity = <_ActivityEvent>[];
  Timer? _clockTimer;
  Timer? _dashboardRefreshTimer;
  DateTime _now = DateTime.now();
  DateTime? _lastSaveAt;
  bool _streamsReady = false;
  bool _dashboardRefreshInProgress = false;
  bool _logsLoading = false;
  events.ServerStatus? _serverStatus;
  SystemData? _systemData;
  StreamSubscription<events.ServerStatus>? _serverStatusSubscription;
  StreamSubscription<SystemData>? _systemDataSubscription;
  StreamSubscription<events.ChatMessage>? _chatSubscription;
  StreamSubscription<events.RuntimeLogEvent>? _runtimeSubscription;
  WebSocketService? _webSocket;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_streamsReady) {
      _streamsReady = true;
      _setupStreams();
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _serverStatusSubscription?.cancel();
    _systemDataSubscription?.cancel();
    _chatSubscription?.cancel();
    _runtimeSubscription?.cancel();
    _dashboardRefreshTimer?.cancel();
    _webSocket?.unsubscribe([
      WebSocketEvents.chatHistory,
      WebSocketEvents.runtimeLog,
    ]);
    super.dispose();
  }

  void _setupStreams() {
    final webSocket = context.read<WebSocketService>();
    _webSocket = webSocket;
    webSocket.subscribe([
      WebSocketEvents.systemResources,
      WebSocketEvents.chatHelp,
      WebSocketEvents.chatPrivate,
      WebSocketEvents.chatHistory,
      WebSocketEvents.runtimeLog,
    ]);
    unawaited(_refreshDashboardData());
    _dashboardRefreshTimer = Timer.periodic(
      _dashboardRefreshInterval,
      (_) => unawaited(_refreshDashboardData()),
    );

    _serverStatusSubscription = webSocket.serverStatusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _serverStatus = status;
      });
    });

    _systemDataSubscription = webSocket.systemDataStream.listen((data) {
      if (!mounted) return;
      setState(() => _systemData = data);
    });

    _chatSubscription = webSocket.chatMessageStream.listen((message) {
      if (!mounted) return;
      final isHelp = message.channel == WebSocketEvents.chatHelp;
      final isPrivate = message.channel == WebSocketEvents.chatPrivate;
      if (!isHelp && !isPrivate) return;
      setState(() {
        _pushActivity(_chatActivity(message, isHelp: isHelp));
      });
    });

    _runtimeSubscription = webSocket.runtimeLogStream.listen((event) {
      if (!mounted) return;
      if (!event.snapshot) return;
      setState(() {
        _replaceRuntimeLines(event.lines);
      });
    });
  }

  Future<void> _refreshDashboardData() async {
    if (_dashboardRefreshInProgress) {
      return;
    }

    _dashboardRefreshInProgress = true;
    try {
      _requestRuntimeSnapshot();
      _requestRecentActivitySnapshot();
      await Future.wait([
        _refreshServerStatus(),
        _refreshDashboardLogs(),
      ]);
    } finally {
      _dashboardRefreshInProgress = false;
    }
  }

  void _requestRuntimeSnapshot() {
    final webSocket = _webSocket;
    if (webSocket != null && webSocket.connectionStatus) {
      webSocket.sendMessage({'type': 'runtime_log_snapshot'});
    }
  }

  void _requestRecentActivitySnapshot() {
    final webSocket = _webSocket;
    if (webSocket == null || !webSocket.connectionStatus) {
      return;
    }

    webSocket.sendMessage({
      'type': 'chat_history',
      'channels': const [
        WebSocketEvents.chatHelp,
        WebSocketEvents.chatPrivate,
      ],
    });
  }

  Future<void> _refreshServerStatus() async {
    try {
      final dados = _decodeDadosResponse(await ApiService.get('server/status'));
      final status = events.ServerStatus.fromJson(dados);
      if (!mounted) {
        return;
      }

      setState(() {
        _serverStatus = status;
      });
    } catch (_) {
      // The WebSocket stream remains the live fallback when REST is not reachable.
    }
  }

  Future<void> _refreshDashboardLogs() async {
    if (_logsLoading) {
      return;
    }

    _logsLoading = true;
    try {
      final list = await _fetchDashboardLogList();
      final runtimeFile = list.runtimeFile.isNotEmpty
          ? list.runtimeFile
          : (list.files.isNotEmpty ? list.files.first.file : 'runtime.log');
      final snapshot = await _fetchDashboardLogSnapshot(
        runtimeFile,
        usingBridge: list.usingBridge,
      );
      final lines = snapshot['lines'] is List
          ? (snapshot['lines'] as List).map((line) => line.toString()).toList()
          : <String>[];

      if (!mounted) {
        return;
      }
      setState(() {
        _logFiles
          ..clear()
          ..addAll(list.files);
        _replaceRuntimeLines(lines);
      });
    } catch (_) {
      // The dashboard still renders from the active WebSocket data when the
      // compatibility log bridge is not reachable.
    } finally {
      _logsLoading = false;
    }
  }

  Future<_DashboardLogList> _fetchDashboardLogList() async {
    try {
      final dados = _decodeDadosResponse(await ApiService.get('server/logs'));
      return _DashboardLogList.fromJson(dados, usingBridge: false);
    } catch (_) {
      final dados = _decodeDadosResponse(
        await _getLogsBridge({'action': 'list'}),
      );
      return _DashboardLogList.fromJson(dados, usingBridge: true);
    }
  }

  Future<Map<String, dynamic>> _fetchDashboardLogSnapshot(
    String file, {
    required bool usingBridge,
  }) async {
    if (usingBridge) {
      return _decodeDadosResponse(
        await _getLogsBridge({
          'action': 'file',
          'path': file,
        }),
      );
    }

    try {
      return _decodeDadosResponse(
        await ApiService.get('server/logs/file/${Uri.encodeComponent(file)}'),
      );
    } catch (_) {
      return _decodeDadosResponse(
        await _getLogsBridge({
          'action': 'file',
          'path': file,
        }),
      );
    }
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
        .timeout(const Duration(seconds: 10));
  }

  Map<String, dynamic> _decodeDadosResponse(http.Response response) {
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 || data is! Map || data['dados'] is! Map) {
      throw const FormatException('Invalid logs response');
    }

    return (data['dados'] as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  void _pushActivity(_ActivityEvent event) {
    final key = event.key;
    if (key != null) {
      final existingIndex = _activity.indexWhere((item) => item.key == key);
      if (existingIndex != -1) {
        _activity.removeAt(existingIndex);
      }
    }

    _activity.insert(0, event);
    if (_activity.length > _recentActivityLimit) {
      _activity.removeRange(_recentActivityLimit, _activity.length);
    }
  }

  void _replaceRuntimeLines(List<String> lines) {
    final tail = lines.length > _dashboardRuntimeLineLimit
        ? lines.sublist(lines.length - _dashboardRuntimeLineLimit)
        : lines;
    _runtimeLines
      ..clear()
      ..addAll(tail);
    _lastSaveAt = _detectLastSaveAt(tail) ?? _lastSaveAt;
  }

  _ActivityEvent _chatActivity(
    events.ChatMessage message, {
    required bool isHelp,
  }) {
    final timestamp = message.timestamp.millisecondsSinceEpoch;
    return _ActivityEvent(
      key:
          'chat:${message.channel}:${message.player}:$timestamp:${message.message}',
      icon: isHelp ? MdiIcons.helpBox : MdiIcons.messageLock,
      title: isHelp ? 'Help channel message' : 'Private message',
      detail:
          '${_formatActivityTime(message.timestamp)} ${message.player}: ${message.message}',
      accent: isHelp ? _orange : _purple,
      tag: isHelp ? 'Chat' : 'Private',
      tagColor: isHelp ? _orange : _purple,
    );
  }

  DateTime? _detectLastSaveAt(List<String> lines) {
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (!lower.contains('server save') &&
          !lower.contains('server saved') &&
          !lower.contains('saving server')) {
        continue;
      }

      return _parseLogTimestamp(line) ?? DateTime.now();
    }
    return null;
  }

  DateTime? _parseLogTimestamp(String line) {
    final match = RegExp(
      r'^\[(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(line);
    if (match == null) {
      return null;
    }

    final year = int.tryParse(match.group(1) ?? '');
    var month = int.tryParse(match.group(2) ?? '');
    var day = int.tryParse(match.group(3) ?? '');
    final hour = int.tryParse(match.group(4) ?? '');
    final minute = int.tryParse(match.group(5) ?? '');
    final second = int.tryParse(match.group(6) ?? '');
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }

    if (month > 12 && day <= 12) {
      final originalMonth = month;
      month = day;
      day = originalMonth;
    }

    try {
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    final webSocket = context.watch<WebSocketService>();
    final items = _homeItems(context);

    return Scaffold(
      body: PenultimaBackdrop(
        imageOpacity: 0.5,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 1180;
              final isPhone = constraints.maxWidth < 700;
              if (isDesktop) {
                return Row(
                  children: [
                    _CommandSidebar(
                      l10n: l10n,
                      items: items,
                      connected: webSocket.connectionStatus,
                    ),
                    Expanded(
                      child: _CommandCenterDashboard(
                        l10n: l10n,
                        localeProvider: localeProvider,
                        items: items,
                        now: _now,
                        connected: webSocket.connectionStatus,
                        status: _serverStatus,
                        systemData: _systemData,
                        lastSaveAt: _lastSaveAt,
                        runtimeLines: _runtimeLines,
                        logFiles: _logFiles,
                        activity: _activity,
                        compact: false,
                        onRefreshLogs: () => _refreshDashboardLogs(),
                        onSelectLanguage: _showLanguageDialog,
                        onLogout: () => context.read<AuthProvider>().logout(),
                      ),
                    ),
                  ],
                );
              }
              if (isPhone) {
                return _PhoneCommandCenter(
                  l10n: l10n,
                  localeProvider: localeProvider,
                  items: items,
                  now: _now,
                  connected: webSocket.connectionStatus,
                  status: _serverStatus,
                  systemData: _systemData,
                  lastSaveAt: _lastSaveAt,
                  runtimeLines: _runtimeLines,
                  logFiles: _logFiles,
                  activity: _activity,
                  onRefreshLogs: () => _refreshDashboardLogs(),
                  onSelectLanguage: _showLanguageDialog,
                  onLogout: () => context.read<AuthProvider>().logout(),
                );
              }
              return _CommandCenterDashboard(
                l10n: l10n,
                localeProvider: localeProvider,
                items: items,
                now: _now,
                connected: webSocket.connectionStatus,
                status: _serverStatus,
                systemData: _systemData,
                lastSaveAt: _lastSaveAt,
                runtimeLines: _runtimeLines,
                logFiles: _logFiles,
                activity: _activity,
                compact: true,
                onRefreshLogs: () => _refreshDashboardLogs(),
                onSelectLanguage: _showLanguageDialog,
                onLogout: () => context.read<AuthProvider>().logout(),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showLanguageDialog() async {
    final l10n = AppLocalizations.of(context);
    final localeProvider = context.read<LocaleProvider>();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('select_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.translate('portuguese')),
              leading: const Text('PT'),
              selected: localeProvider.isPortuguese,
              onTap: () {
                localeProvider.setLocale('pt');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(l10n.translate('english')),
              leading: const Text('EN'),
              selected: localeProvider.isEnglish,
              onTap: () {
                localeProvider.setLocale('en');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_HomeItem> _homeItems(BuildContext context) {
    return [
      _HomeItem(
        titleKey: 'monitor_title',
        shortTitle: 'Monitor',
        descriptionKey: 'monitor_desc',
        icon: MdiIcons.monitorDashboard,
        accent: _purple,
        open: () => _open(context, const MonitorScreen()),
      ),
      _HomeItem(
        titleKey: 'server_info_title',
        shortTitle: 'Server',
        descriptionKey: 'server_info_desc',
        icon: MdiIcons.serverNetwork,
        accent: _cyan,
        open: () => _open(context, const ServerInfoScreen()),
      ),
      _HomeItem(
        titleKey: 'chat_title',
        shortTitle: 'Chat',
        descriptionKey: 'chat_desc',
        icon: MdiIcons.messageText,
        accent: _orange,
        open: () => _open(context, const ChatScreen()),
      ),
      _HomeItem(
        titleKey: 'online_players_title',
        shortTitle: 'Players',
        descriptionKey: 'online_players_desc',
        icon: MdiIcons.accountGroup,
        accent: _green,
        open: () => _open(context, const OnlinePlayersScreen()),
      ),
      _HomeItem(
        titleKey: 'banned_players_title',
        shortTitle: 'Banned',
        descriptionKey: 'banned_players_desc',
        icon: MdiIcons.shieldOff,
        accent: _red,
        open: () => _open(context, const BannedPlayersScreen()),
      ),
      _HomeItem(
        titleKey: 'live_title',
        shortTitle: 'Live',
        descriptionKey: 'live_desc',
        icon: MdiIcons.videoWireless,
        accent: const Color(0xFF00E2D3),
        open: () => _open(context, const LiveScreen()),
      ),
      _HomeItem(
        titleKey: 'logs_title',
        shortTitle: 'Logs',
        descriptionKey: 'logs_desc',
        icon: MdiIcons.consoleLine,
        accent: const Color(0xFFFF4DFF),
        open: () => _open(context, const LogsScreen()),
      ),
      _HomeItem(
        titleKey: 'config_title',
        shortTitle: 'Settings',
        descriptionKey: 'config_desc',
        icon: MdiIcons.cog,
        accent: const Color(0xFFB774FF),
        open: () => _open(context, const ConfigScreen()),
      ),
    ];
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, PageTransition<void>(child: screen));
  }
}

class _CommandSidebar extends StatelessWidget {
  final AppLocalizations l10n;
  final List<_HomeItem> items;
  final bool connected;

  const _CommandSidebar({
    required this.l10n,
    required this.items,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 330,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: _ChromePanel(
          padding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                penultimaBackgroundAsset,
                fit: BoxFit.cover,
                alignment: Alignment.centerLeft,
                opacity: const AlwaysStoppedAnimation(0.38),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xEF05030A),
                      Color(0xB20B0612),
                      Color(0xF205030A),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                child: Column(
                  children: [
                    Image.asset(
                      penultimaLogoAsset,
                      height: 160,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Penultima Web',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: const Color(0xFFF7ECFF),
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Web Administration',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFBFA6D8),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _SideNavButton(
                            item: item,
                            selected: index == 0,
                            label: item.shortTitle,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    _OperatorCard(connected: connected),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandCenterDashboard extends StatelessWidget {
  final AppLocalizations l10n;
  final LocaleProvider localeProvider;
  final List<_HomeItem> items;
  final DateTime now;
  final bool connected;
  final events.ServerStatus? status;
  final SystemData? systemData;
  final DateTime? lastSaveAt;
  final List<String> runtimeLines;
  final List<_DashboardLogFile> logFiles;
  final List<_ActivityEvent> activity;
  final bool compact;
  final VoidCallback onRefreshLogs;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;

  const _CommandCenterDashboard({
    required this.l10n,
    required this.localeProvider,
    required this.items,
    required this.now,
    required this.connected,
    required this.status,
    required this.systemData,
    required this.lastSaveAt,
    required this.runtimeLines,
    required this.logFiles,
    required this.activity,
    required this.compact,
    required this.onRefreshLogs,
    required this.onSelectLanguage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final topCompact = compact || width < 1120;
        final tileColumns = math.max(2, math.min(8, (width / 168).floor()));
        final tileRows = (items.length / tileColumns).ceil();
        final tilesHeight = tileRows * 118.0 + (tileRows - 1) * 12.0;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 18,
                compact ? 10 : 16,
                compact ? 14 : 18,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _CommandTopBar(
                  now: now,
                  status: status,
                  connected: connected,
                  compact: topCompact,
                  localeProvider: localeProvider,
                  onSelectLanguage: onSelectLanguage,
                  onLogout: onLogout,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 18,
                14,
                compact ? 14 : 18,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _HeroAndStatusRow(
                  status: status,
                  systemData: systemData,
                  lastSaveAt: lastSaveAt,
                  connected: connected,
                  stack: width < 930,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 18,
                12,
                compact ? 14 : 18,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: tilesHeight,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: tileColumns,
                      mainAxisExtent: 118,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _CommandTile(
                      item: items[index],
                      dense: tileColumns > 5,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 18,
                12,
                compact ? 14 : 18,
                24,
              ),
              sliver: SliverToBoxAdapter(
                child: _OperationsGrid(
                  runtimeLines: runtimeLines,
                  logFiles: logFiles,
                  activity: activity,
                  stack: width < 1040,
                  onRefreshLogs: onRefreshLogs,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhoneCommandCenter extends StatelessWidget {
  final AppLocalizations l10n;
  final LocaleProvider localeProvider;
  final List<_HomeItem> items;
  final DateTime now;
  final bool connected;
  final events.ServerStatus? status;
  final SystemData? systemData;
  final DateTime? lastSaveAt;
  final List<String> runtimeLines;
  final List<_DashboardLogFile> logFiles;
  final List<_ActivityEvent> activity;
  final VoidCallback onRefreshLogs;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;

  const _PhoneCommandCenter({
    required this.l10n,
    required this.localeProvider,
    required this.items,
    required this.now,
    required this.connected,
    required this.status,
    required this.systemData,
    required this.lastSaveAt,
    required this.runtimeLines,
    required this.logFiles,
    required this.activity,
    required this.onRefreshLogs,
    required this.onSelectLanguage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          sliver: SliverToBoxAdapter(
            child: _PhoneHeader(
              now: now,
              connected: connected,
              onSelectLanguage: onSelectLanguage,
              onLogout: onLogout,
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
          sliver: SliverToBoxAdapter(
            child: _CommandHeroBanner(phone: true),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          sliver: SliverToBoxAdapter(
            child: _PhoneStatusStrip(
              status: status,
              systemData: systemData,
              lastSaveAt: lastSaveAt,
              connected: connected,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 150,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _CommandTile(
                item: items[index],
                phone: true,
              ),
              childCount: items.length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          sliver: SliverToBoxAdapter(
            child: _RuntimeLogPanel(
              lines: runtimeLines,
              phone: true,
              onRefresh: onRefreshLogs,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              height: 320,
              child: _LogFilesPanel(
                files: logFiles,
                onRefresh: onRefreshLogs,
                phone: true,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
          sliver: SliverToBoxAdapter(
            child: _RecentActivityPanel(activity: activity, phone: true),
          ),
        ),
      ],
    );
  }
}

class _CommandTopBar extends StatelessWidget {
  final DateTime now;
  final events.ServerStatus? status;
  final bool connected;
  final bool compact;
  final LocaleProvider localeProvider;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;

  const _CommandTopBar({
    required this.now,
    required this.status,
    required this.connected,
    required this.compact,
    required this.localeProvider,
    required this.onSelectLanguage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final uptime =
        status != null ? _formatUptime(status!.uptime) : '7d 12h 38m';
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Penultima Web',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          'Web Administration',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFC8B5D8),
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolbarIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Search',
          onPressed: () {},
        ),
        _NotificationButton(
          onPressed: () {
            Navigator.push(
              context,
              PageTransition<void>(child: const ConfigScreen()),
            );
          },
        ),
        _ToolbarIconButton(
          icon: Icons.language_rounded,
          tooltip: 'Language',
          onPressed: onSelectLanguage,
        ),
        _ToolbarIconButton(
          icon: Icons.logout_rounded,
          tooltip: 'Logout',
          onPressed: onLogout,
        ),
      ],
    );

    if (compact) {
      return _ChromePanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: title),
                actions,
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricCard(
                  icon: MdiIcons.clockOutline,
                  label: 'Server Time',
                  value: _timeText(now),
                  detail: _dateText(now),
                  accent: _purple,
                  compact: true,
                ),
                _MetricCard(
                  icon: MdiIcons.pulse,
                  label: 'Uptime',
                  value: uptime,
                  detail: connected ? 'online stream' : 'offline stream',
                  accent: _green,
                  compact: true,
                ),
                _MetricCard(
                  icon: MdiIcons.cubeOutline,
                  label: 'Version',
                  value: _serverClientVersion,
                  detail: 'protocol $_serverProtocolVersion',
                  accent: const Color(0xFFB774FF),
                  compact: true,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        _MetricCard(
          icon: MdiIcons.clockOutline,
          label: 'Server Time',
          value: _timeText(now),
          detail: _dateText(now),
          accent: _purple,
        ),
        const SizedBox(width: 10),
        _MetricCard(
          icon: MdiIcons.pulse,
          label: 'Uptime',
          value: uptime,
          detail: connected ? 'online stream' : 'offline stream',
          accent: _green,
        ),
        const SizedBox(width: 10),
        _MetricCard(
          icon: MdiIcons.cubeOutline,
          label: 'Version',
          value: _serverClientVersion,
          detail: 'protocol $_serverProtocolVersion',
          accent: const Color(0xFFB774FF),
        ),
        const SizedBox(width: 12),
        actions,
      ],
    );
  }
}

class _PhoneHeader extends StatelessWidget {
  final DateTime now;
  final bool connected;
  final VoidCallback onSelectLanguage;
  final VoidCallback onLogout;

  const _PhoneHeader({
    required this.now,
    required this.connected,
    required this.onSelectLanguage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return _ChromePanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Penultima Web',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_timeText(now)}  |  ${connected ? 'Online' : 'Offline'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC8B5D8),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          _NotificationButton(
            onPressed: () {
              Navigator.push(
                context,
                PageTransition<void>(child: const ConfigScreen()),
              );
            },
          ),
          _ToolbarIconButton(
            icon: Icons.language_rounded,
            tooltip: 'Language',
            onPressed: onSelectLanguage,
          ),
          _ToolbarIconButton(
            icon: Icons.logout_rounded,
            tooltip: 'Logout',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

class _HeroAndStatusRow extends StatelessWidget {
  final events.ServerStatus? status;
  final SystemData? systemData;
  final DateTime? lastSaveAt;
  final bool connected;
  final bool stack;

  const _HeroAndStatusRow({
    required this.status,
    required this.systemData,
    required this.lastSaveAt,
    required this.connected,
    required this.stack,
  });

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        children: [
          const _CommandHeroBanner(),
          const SizedBox(height: 12),
          _ServerStatusPanel(
            status: status,
            systemData: systemData,
            lastSaveAt: lastSaveAt,
            connected: connected,
          ),
        ],
      );
    }
    return SizedBox(
      height: 390,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: _CommandHeroBanner(),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 380,
            child: _ServerStatusPanel(
              status: status,
              systemData: systemData,
              lastSaveAt: lastSaveAt,
              connected: connected,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandHeroBanner extends StatelessWidget {
  final bool phone;

  const _CommandHeroBanner({this.phone = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: phone ? 280 : 300,
      child: _ChromePanel(
        padding: EdgeInsets.zero,
        borderColor: const Color(0xAA9838F5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                penultimaBackgroundAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      Color(0x331B002A),
                      Color(0x8A09020E),
                      Color(0xDD000000),
                    ],
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: phone ? 22 : 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        penultimaLogoAsset,
                        height: phone ? 150 : 185,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: phone ? 8 : 14),
                      Text(
                        'Web Administration',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFFF7ECFF),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                          shadows: const [
                            Shadow(color: _purple, blurRadius: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerStatusPanel extends StatelessWidget {
  final events.ServerStatus? status;
  final SystemData? systemData;
  final DateTime? lastSaveAt;
  final bool connected;

  const _ServerStatusPanel({
    required this.status,
    required this.systemData,
    required this.lastSaveAt,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final players = status?.playersOnline ?? 142;
    final maxPlayers = status?.maxPlayers ?? 1000;
    final cpu = systemData?.systemInfo.cpu.usagePercent ?? 18;
    final memory = systemData?.systemInfo.memory.usagePercent ?? 37;
    final statusText = connected ? 'Online' : 'Offline';
    final statusColor = connected ? _green : _red;

    return _ChromePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(MdiIcons.clipboardPulseOutline, color: Colors.white70),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Server Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              _StatusBadge(label: statusText, color: statusColor),
            ],
          ),
          const SizedBox(height: 14),
          _StatusMetricRow(
            icon: MdiIcons.accountGroup,
            label: 'Players Online',
            value: '$players',
            suffix: '/ $maxPlayers',
            accent: _purple,
            points: const [0.18, 0.31, 0.22, 0.4, 0.33, 0.48, 0.62, 0.39, 0.7],
          ),
          _StatusMetricRow(
            icon: MdiIcons.antenna,
            label: 'Ping',
            value: connected ? '42' : '--',
            suffix: 'ms',
            accent: _green,
            points: const [0.22, 0.24, 0.2, 0.35, 0.28, 0.42, 0.39, 0.48, 0.53],
          ),
          _StatusMetricRow(
            icon: MdiIcons.cpu64Bit,
            label: 'CPU Load',
            value: '${cpu.round()}',
            suffix: '%',
            accent: _green,
            points: const [0.16, 0.21, 0.18, 0.27, 0.19, 0.35, 0.31, 0.43, 0.5],
          ),
          _StatusMetricRow(
            icon: MdiIcons.memory,
            label: 'Memory',
            value: '${memory.round()}',
            suffix: '%',
            accent: _orange,
            points: const [0.32, 0.26, 0.44, 0.38, 0.5, 0.41, 0.57, 0.49, 0.7],
          ),
          const Divider(height: 18, color: Color(0x334F1B79)),
          Row(
            children: [
              Icon(MdiIcons.contentSaveCheck, size: 22, color: _purple),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Last Save',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFC8B5D8),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                _formatRelativeTime(lastSaveAt),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.check_circle_outline, color: _purple, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneStatusStrip extends StatelessWidget {
  final events.ServerStatus? status;
  final SystemData? systemData;
  final DateTime? lastSaveAt;
  final bool connected;

  const _PhoneStatusStrip({
    required this.status,
    required this.systemData,
    required this.lastSaveAt,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final players = status?.playersOnline ?? 142;
    final cpu = systemData?.systemInfo.cpu.usagePercent.round() ?? 18;
    final memory = systemData?.systemInfo.memory.usagePercent.round() ?? 37;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _PhoneStatChip(
            icon: MdiIcons.accountGroup,
            label: 'Players',
            value: '$players',
            accent: _purple,
          ),
          const SizedBox(width: 8),
          _PhoneStatChip(
            icon: MdiIcons.cpu64Bit,
            label: 'CPU',
            value: '$cpu%',
            accent: _green,
          ),
          const SizedBox(width: 8),
          _PhoneStatChip(
            icon: MdiIcons.memory,
            label: 'Memory',
            value: '$memory%',
            accent: _orange,
          ),
          const SizedBox(width: 8),
          _PhoneStatChip(
            icon: MdiIcons.cubeOutline,
            label: 'Version',
            value: _serverClientVersion,
            accent: const Color(0xFFB774FF),
          ),
          const SizedBox(width: 8),
          _PhoneStatChip(
            icon: MdiIcons.contentSaveCheck,
            label: 'Last Save',
            value: _formatRelativeTime(lastSaveAt),
            accent: _purple,
          ),
        ],
      ),
    );
  }
}

class _OperationsGrid extends StatelessWidget {
  final List<String> runtimeLines;
  final List<_DashboardLogFile> logFiles;
  final List<_ActivityEvent> activity;
  final bool stack;
  final VoidCallback onRefreshLogs;

  const _OperationsGrid({
    required this.runtimeLines,
    required this.logFiles,
    required this.activity,
    required this.stack,
    required this.onRefreshLogs,
  });

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        children: [
          SizedBox(
            height: 360,
            child: _RuntimeLogPanel(
              lines: runtimeLines,
              onRefresh: onRefreshLogs,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: _LogFilesPanel(
              files: logFiles,
              onRefresh: onRefreshLogs,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 430,
            child: _RecentActivityPanel(activity: activity),
          ),
        ],
      );
    }
    return SizedBox(
      height: 360,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 8,
            child: _RuntimeLogPanel(
              lines: runtimeLines,
              onRefresh: onRefreshLogs,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: _LogFilesPanel(
              files: logFiles,
              onRefresh: onRefreshLogs,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: _RecentActivityPanel(activity: activity),
          ),
        ],
      ),
    );
  }
}

class _RuntimeLogPanel extends StatelessWidget {
  final List<String> lines;
  final bool phone;
  final VoidCallback onRefresh;

  const _RuntimeLogPanel({
    required this.lines,
    required this.onRefresh,
    this.phone = false,
  });

  Future<void> _copyLines(BuildContext context) async {
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No runtime log lines to copy.')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${lines.length} runtime log lines.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: phone ? 310 : null,
      child: _ChromePanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(
              icon: MdiIcons.console,
              title: 'Runtime Log (tail - live)',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TinyIconButton(
                    key: const ValueKey('runtime_log_refresh'),
                    icon: MdiIcons.refresh,
                    tooltip: 'Refresh runtime log',
                    onPressed: onRefresh,
                  ),
                  SizedBox(width: 6),
                  _TinyIconButton(
                    key: const ValueKey('runtime_log_open_logs'),
                    icon: MdiIcons.folderOpenOutline,
                    tooltip: 'Open logs',
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageTransition<void>(
                          child: const LogsScreen(initialFile: 'runtime.log'),
                        ),
                      );
                    },
                  ),
                  SizedBox(width: 6),
                  _TinyIconButton(
                    key: const ValueKey('runtime_log_copy'),
                    icon: MdiIcons.contentCopy,
                    tooltip: 'Copy runtime log',
                    onPressed: lines.isEmpty ? null : () => _copyLines(context),
                  ),
                  SizedBox(width: 6),
                  _TinyIconButton(
                    key: const ValueKey('runtime_log_fullscreen'),
                    icon: MdiIcons.fullscreen,
                    tooltip: 'Fullscreen',
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageTransition<void>(
                          child: const LogsScreen(initialFile: 'runtime.log'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              liveDot: true,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE806040A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x333E164F)),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: lines.isEmpty ? 1 : lines.length,
                  itemBuilder: (context, index) {
                    if (lines.isEmpty) {
                      return const Text(
                        'Loading live runtime log...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.35,
                          color: Color(0xFF9F8DAE),
                        ),
                      );
                    }
                    final line = lines[index];
                    return Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: phone ? 11 : 12.5,
                        height: 1.35,
                        color: _logLineColor(line),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogFilesPanel extends StatelessWidget {
  final List<_DashboardLogFile> files;
  final VoidCallback onRefresh;
  final bool phone;

  const _LogFilesPanel({
    required this.files,
    required this.onRefresh,
    this.phone = false,
  });

  void _openLogFile(BuildContext context, _DashboardLogFile? file) {
    Navigator.push(
      context,
      PageTransition<void>(
        child: LogsScreen(initialFile: file?.file ?? 'runtime.log'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _DashboardLogFile? runtime;
    for (final file in files) {
      if (file.runtime) {
        runtime = file;
        break;
      }
    }
    final selected = runtime ?? (files.isNotEmpty ? files.first : null);
    final visibleFiles = files.take(phone ? 6 : 8).toList();

    return _ChromePanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            icon: MdiIcons.folderMultipleOutline,
            title: 'Log Files',
            trailing: _RefreshButton(onPressed: onRefresh),
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: selected == null
                  ? null
                  : () => _openLogFile(context, selected),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xD80B0711),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x554F1B79)),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected?.file ?? 'Loading logs...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (files.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${files.length} log files available',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF9F8DAE),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        selected == null ? '' : _formatBytes(selected.size),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFBDA7CE),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visibleFiles.isEmpty
                ? const Center(
                    child: Text(
                      'Waiting for log files...',
                      style: TextStyle(
                        color: Color(0xFFBDA7CE),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: visibleFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 3),
                    itemBuilder: (context, index) {
                      final file = visibleFiles[index];
                      return _FileRow(
                        name: file.file,
                        size: _formatBytes(file.size),
                        time: _formatLogTime(file.modifiedMs),
                        onTap: () => _openLogFile(context, file),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _openLogFile(context, selected),
            icon: Icon(MdiIcons.folderOpenOutline),
            label: const Text('Open Selected File'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xAA6F1EB7),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0x99D45CFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  final List<_ActivityEvent> activity;
  final bool phone;

  const _RecentActivityPanel({
    required this.activity,
    this.phone = false,
  });

  void _showAllActivity(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF08040D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(
                icon: MdiIcons.pulse,
                title: 'Recent Activity',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: activity.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _ActivityRow(item: activity[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: phone ? 430 : null,
      child: _ChromePanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(
              icon: MdiIcons.pulse,
              title: 'Recent Activity',
            ),
            const SizedBox(height: 10),
            Expanded(
              child: activity.isEmpty
                  ? const Center(
                      child: Text(
                        'Waiting for recent activity...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFBDA7CE),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: activity.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = activity[index];
                        return _ActivityRow(item: item);
                      },
                    ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed:
                  activity.isEmpty ? null : () => _showAllActivity(context),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: const Text('View All Activity'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF5E9FF),
                side: const BorderSide(color: Color(0x777B2DBD)),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandTile extends StatefulWidget {
  final _HomeItem item;
  final bool dense;
  final bool phone;

  const _CommandTile({
    required this.item,
    this.dense = false,
    this.phone = false,
  });

  @override
  State<_CommandTile> createState() => _CommandTileState();
}

class _CommandTileState extends State<_CommandTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.translate(widget.item.titleKey);
    final description = l10n.translate(widget.item.descriptionKey);
    final accent = widget.item.accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: _hovered ? 1.025 : 1,
        child: _ChromePanel(
          padding: EdgeInsets.zero,
          borderColor: accent.withAlpha(_hovered ? 190 : 95),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey('home_tile_${widget.item.shortTitle}'),
              onTap: widget.item.open,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.all(widget.phone ? 12 : 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GlowIcon(
                      icon: widget.item.icon,
                      accent: accent,
                      size: widget.phone ? 38 : (widget.dense ? 40 : 46),
                    ),
                    SizedBox(height: widget.phone ? 10 : 11),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: widget.phone ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      maxLines: widget.phone ? 1 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFC7B4D6),
                            height: 1.1,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavButton extends StatelessWidget {
  final _HomeItem item;
  final bool selected;
  final String label;

  const _SideNavButton({
    required this.item,
    required this.selected,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? const Color(0x882D073B) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xCCB744FF) : Colors.transparent,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: item.accent.withAlpha(90),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: item.open,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(item.icon, color: item.accent, size: 25),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFFF7ECFF),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OperatorCard extends StatelessWidget {
  final bool connected;

  const _OperatorCard({required this.connected});

  @override
  Widget build(BuildContext context) {
    return _ChromePanel(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0x664F1B79),
      child: Row(
        children: [
          ClipOval(
            child: Container(
              width: 58,
              height: 58,
              color: const Color(0x802D073B),
              child: Image.asset(penultimaLogoAsset, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waldir (Monitor)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.circle,
                        size: 8, color: connected ? _green : _red),
                    const SizedBox(width: 6),
                    Text(
                      connected ? 'Online' : 'Offline',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: connected ? _green : _red,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Penultima OT Server',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC8B5D8),
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

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color accent;
  final bool compact;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 185 : 210,
      child: _ChromePanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFC8B5D8),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFBFA6D8),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String suffix;
  final Color accent;
  final List<double> points;

  const _StatusMetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.suffix,
    required this.accent,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _GlowIcon(icon: icon, accent: accent, size: 42, compact: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC8B5D8),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      TextSpan(
                        text: '  $suffix',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFC8B5D8),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 118,
            height: 32,
            child: CustomPaint(
              painter: _SparklinePainter(points: points, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _PhoneStatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: _ChromePanel(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        borderColor: accent.withAlpha(100),
        child: Column(
          children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFC8B5D8),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final bool liveDot;

  const _PanelHeader({
    required this.icon,
    required this.title,
    this.trailing,
    this.liveDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFEED9FF), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              if (liveDot) ...[
                const SizedBox(width: 10),
                const Icon(Icons.circle, size: 8, color: _green),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final String name;
  final String size;
  final String time;
  final VoidCallback? onTap;

  const _FileRow({
    required this.name,
    required this.size,
    required this.time,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Row(
            children: [
              Icon(MdiIcons.fileDocumentOutline,
                  size: 18, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFE7DAF2),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                size,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9F8DAE),
                    ),
              ),
              const SizedBox(width: 12),
              Text(
                time,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9F8DAE),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final _ActivityEvent item;

  const _ActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x8608060C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: item.accent.withAlpha(45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Row(
          children: [
            Icon(item.icon, color: item.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFBDA7CE),
                        ),
                  ),
                ],
              ),
            ),
            _StatusBadge(label: item.tag, color: item.tagColor, small: true),
          ],
        ),
      ),
    );
  }
}

class _ChromePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const _ChromePanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor ?? _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x338F35FF),
            blurRadius: 18,
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _GlowIcon extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final double size;
  final bool compact;

  const _GlowIcon({
    required this.icon,
    required this.accent,
    required this.size,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withAlpha(compact ? 30 : 42),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(90),
            blurRadius: compact ? 10 : 18,
          ),
        ],
      ),
      child:
          Icon(icon, color: accent, size: compact ? size * 0.58 : size * 0.52),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFFF6EBFF),
            backgroundColor: const Color(0x66160921),
            hoverColor: const Color(0x558C35D7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0x554F1B79)),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _NotificationButton({
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _ToolbarIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: 'Notifications',
          onPressed: onPressed,
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: 19,
            height: 19,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _deepPurple,
              shape: BoxShape.circle,
            ),
            child: const Text(
              '3',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TinyIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _TinyIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 34,
      child: Tooltip(
        message: tooltip,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x77100917),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x554F1B79)),
          ),
          child: IconButton(
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            icon: Icon(icon, color: Colors.white70, size: 18),
          ),
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RefreshButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(MdiIcons.refresh, size: 16),
      label: const Text('Refresh'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFEED9FF),
        side: const BorderSide(color: Color(0x554F1B79)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool small;

  const _StatusBadge({
    required this.label,
    required this.color,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 11,
        vertical: small ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color;

  const _SparklinePainter({
    required this.points,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final glow = Paint()
      ..color = color.withAlpha(70)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final y = size.height - (points[i].clamp(0, 1) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

class _HomeItem {
  final String titleKey;
  final String shortTitle;
  final String descriptionKey;
  final IconData icon;
  final Color accent;
  final VoidCallback open;

  const _HomeItem({
    required this.titleKey,
    required this.shortTitle,
    required this.descriptionKey,
    required this.icon,
    required this.accent,
    required this.open,
  });
}

class _ActivityEvent {
  final String? key;
  final IconData icon;
  final String title;
  final String detail;
  final Color accent;
  final String tag;
  final Color tagColor;

  const _ActivityEvent({
    this.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.accent,
    required this.tag,
    required this.tagColor,
  });
}

class _DashboardLogFile {
  final String file;
  final int size;
  final int modifiedMs;
  final bool runtime;

  const _DashboardLogFile({
    required this.file,
    required this.size,
    required this.modifiedMs,
    required this.runtime,
  });

  factory _DashboardLogFile.fromJson(Map<String, dynamic> json) {
    return _DashboardLogFile(
      file: json['file']?.toString() ?? '',
      size: _parseDashboardInt(json['size']),
      modifiedMs: _parseDashboardInt(json['mtime_ms']),
      runtime: json['runtime'] == true,
    );
  }
}

class _DashboardLogList {
  final List<_DashboardLogFile> files;
  final String runtimeFile;
  final bool usingBridge;

  const _DashboardLogList({
    required this.files,
    required this.runtimeFile,
    required this.usingBridge,
  });

  factory _DashboardLogList.fromJson(
    Map<String, dynamic> json, {
    required bool usingBridge,
  }) {
    final rawFiles = json['files'];
    final files = rawFiles is List
        ? rawFiles
            .whereType<Map>()
            .map(
              (item) => _DashboardLogFile.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .where((entry) => entry.file.isNotEmpty)
            .toList()
        : <_DashboardLogFile>[];

    return _DashboardLogList(
      files: files,
      runtimeFile: json['runtime_file']?.toString() ?? 'runtime.log',
      usingBridge: usingBridge,
    );
  }
}

int _parseDashboardInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Color _logLineColor(String line) {
  final lower = line.toLowerCase();
  if (lower.contains('warning')) return _orange;
  if (lower.contains('error') || lower.contains('exception')) return _red;
  if (lower.contains('notice')) return _purple;
  if (lower.contains('[info]')) return const Color(0xFF80F1D3);
  if (line.length >= 8) return const Color(0xFFFFC044);
  return const Color(0xFFE5D6F2);
}

String _timeText(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _dateText(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _formatActivityTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatUptime(int seconds) {
  if (seconds <= 0) return '0m';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

String _formatRelativeTime(DateTime? value) {
  if (value == null) {
    return 'Waiting';
  }

  final elapsed = DateTime.now().difference(value);
  if (elapsed.inSeconds < 60) {
    return '${elapsed.inSeconds}s ago';
  }
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes}m ago';
  }
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours}h ago';
  }
  return '${elapsed.inDays}d ago';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

String _formatLogTime(int modifiedMs) {
  if (modifiedMs <= 0) {
    return '--';
  }
  final value = DateTime.fromMillisecondsSinceEpoch(modifiedMs).toLocal();
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}
