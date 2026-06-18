import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../models/server_status.dart';
import '../models/events.dart' as events;
import '../services/websocket_service.dart';
import '../providers/theme_provider.dart';
import '../l10n/app_localizations.dart';
import 'dart:async';
import '../widgets/connection_status_popup.dart';

class ServerInfoScreen extends StatefulWidget {
  const ServerInfoScreen({super.key});

  @override
  State<ServerInfoScreen> createState() => _ServerInfoScreenState();
}

class _ServerInfoScreenState extends State<ServerInfoScreen> with WidgetsBindingObserver {
  ServerStatus? _serverStatus;
  bool _isLoading = false;
  bool _isChangingState = false;
  String? _error;
  late WebSocketService _webSocketService;
  bool _webSocketInitialized = false;
  events.ServerStatus? _liveServerStatus;
  bool _isConnected = false;
  StreamSubscription<bool>? _connectionSubscription;

  Future<void> _fetchServerStatus() async {
    if (_serverStatus == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await ApiService.get('server/status');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      
      if (response.statusCode == 200) {
        // Decodifica a resposta usando UTF-8
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['sucesso'] == true) {
          setState(() {
            _serverStatus = ServerStatus.fromJson(jsonResponse);
            _isLoading = false;
            _error = null;
          });
        } else {
          setState(() {
            _error = l10n.translate('error_fetching_status');
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = l10n.translate('error_status_code').replaceAll('{0}', response.statusCode.toString());
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      
      String errorMessage;
      if (e.toString().contains('TimeoutException') || e.toString().contains('SocketException')) {
        errorMessage = l10n.translate('server_timeout');
      } else {
        errorMessage = l10n.translate('error_connection').replaceAll('{0}', e.toString());
      }
      
      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateServerState(String newState) async {
    setState(() {
      _isChangingState = true;
    });

    try {
      final response = await ApiService.post('server/state', body: {'state': newState});
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['sucesso'] == true) {
          await Future.delayed(const Duration(milliseconds: 500));
          await _fetchServerStatus();
          _showStatusMessage('${l10n.translate('server')}: ${newState.toUpperCase()}');
        } else {
          setState(() {
            _isChangingState = false;
          });
          _showStatusMessage(l10n.translate('update_failed'), isError: true);
        }
      } else {
        setState(() {
          _isChangingState = false;
        });
        _showStatusMessage(l10n.translate('request_error'), isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _isChangingState = false;
      });
      _showStatusMessage(l10n.translate('connection_error'), isError: true);
    }

    setState(() {
      _isChangingState = false;
    });
  }

  void _showStatusMessage(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + MediaQuery.of(context).size.height * 0.02,
                  left: MediaQuery.of(context).size.width * 0.04,
                  right: MediaQuery.of(context).size.width * 0.04,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width * 0.04,
                  vertical: MediaQuery.of(context).size.height * 0.015,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(25, 28, 32, 1.0),
                  borderRadius: BorderRadius.circular(25.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.1 * 255).round()),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isError) ...[
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.withAlpha(128),
                        size: MediaQuery.of(context).size.width * 0.05,
                      ),
                    ] else ...[
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green.withAlpha(128),
                        size: MediaQuery.of(context).size.width * 0.05,
                      ),
                    ],
                    SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                    Flexible(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: MediaQuery.of(context).size.width * 0.04,
                        ),
                        maxLines: 2,
                        softWrap: true,
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

    overlay.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  String _getApiState(String state) {
    String normalizeString(String str) {
      return str
          .toLowerCase()
          .trim()
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll('_', '');
    }

    final normalizedState = normalizeString(state);
    
    if (normalizedState == 'online' || normalizedState == 'fechado' || 
        normalizedState == 'desligando' || normalizedState == 'manutenção') {
      return state.toLowerCase();
    }

    switch (normalizedState) {
      case 'offline':
        return 'fechado';
      case 'maintenance':
        return 'manutenção';
      case 'shuttingdown':
        return 'desligando';
      default:
        return state;
    }
  }

  // ignore: unused_element
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'offline':
      case 'fechado':
        return Colors.red;
      case 'maintenance':
      case 'manutenção':
        return Colors.blue;
      case 'shutting_down':
      case 'desligando':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<bool> _showShutdownConfirmation() async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark(),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber,
              size: 48,
            ),
            title: Text(
              l10n.translate('warning'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.translate('confirm_shutdown'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        l10n.translate('warning_action'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.translate('shutdown_consequences'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        l10n.translate('cancel_button'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        l10n.translate('shutdown'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ) ?? false;
  }

  Widget _buildErrorMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _fetchServerStatus,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).translate('try_again')),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureConnection() {
    if (!_webSocketService.connectionStatus) {
      // Se não estiver conectado, tenta iniciar a conexão
      _webSocketService.startConnection();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _fetchServerStatus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_webSocketInitialized) {
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
          }
        });
        
        // Garante que temos uma conexão WebSocket
        _ensureConnection();
        
        _webSocketService.subscribe(['server_status']);
        _webSocketInitialized = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionSubscription?.cancel();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _webSocketService.unsubscribe(['server_status']);
    });
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Se o aplicativo voltar ao primeiro plano, verifica a conexão
    if (state == AppLifecycleState.resumed) {
      _ensureConnection();
      _fetchServerStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final websocketService = context.watch<WebSocketService>();
    
    return PopScope(
      canPop: !(_isLoading || _isChangingState),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dns_rounded),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  l10n.translate('server_info_title'),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            if (_isChangingState)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(Icons.refresh),
                onPressed: _isLoading ? null : _fetchServerStatus,
                tooltip: l10n.translate('refresh'),
              ),
            IconButton(
              icon: Icon(_isConnected ? Icons.wifi : Icons.wifi_off),
              onPressed: () {
                if (!_isConnected) {
                  _webSocketService.reconnectManually();
                  
                  // Força atualização do estado após um breve delay
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      setState(() {
                        _isConnected = _webSocketService.connectionStatus;
                      });
                      _fetchServerStatus();
                    }
                  });
                } else {
                  // Mostra status da conexão
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.translate('server_info_connection_status')),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              tooltip: _isConnected ? l10n.translate('server_info_connected_tooltip') : l10n.translate('server_info_reconnect_tooltip'),
            ),
          ],
        ),
        body: Stack(
          children: [
            StreamBuilder<events.ServerStatus>(
              stream: websocketService.serverStatusStream,
              builder: (context, snapshot) {
                // Se temos dados do WebSocket, atualiza o status em tempo real
                if (snapshot.hasData) {
                  _liveServerStatus = snapshot.data!;
                }
                return _buildBody();
              },
            ),
            // Adiciona o componente de status da conexão
            Consumer<WebSocketService>(
              builder: (context, webSocketService, _) {
                return ConnectionStatusPopup(webSocketService: webSocketService);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context);
    
    if (_isLoading && _serverStatus == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _serverStatus == null) {
      return _buildErrorMessage();
    }

    if (_serverStatus == null) {
      return Center(
        child: Text(l10n.translate('no_info')),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchServerStatus,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildServerInfoCard(),
            const SizedBox(height: 16),
            _buildStateControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    
    // Combine dados do HTTP e WebSocket, dando preferência aos do WebSocket (em tempo real)
    final String status = _liveServerStatus?.status ?? _serverStatus!.status;
    final int playersOnline = _liveServerStatus?.playersOnline ?? _serverStatus!.playersOnline;
    final int maxPlayers = _liveServerStatus?.maxPlayers ?? _serverStatus!.maxPlayers;
    final int uptime = _liveServerStatus?.uptime ?? _serverStatus!.uptime;
    
    Color statusColor;
    String translatedStatus;
    switch (status.toLowerCase()) {
      case 'online':
        statusColor = Colors.green;
        translatedStatus = l10n.translate('state_online');
        break;
      case 'fechado':
      case 'offline':
        statusColor = Colors.orange;
        translatedStatus = l10n.translate('state_offline');
        break;
      case 'desligando':
      case 'shutting_down':
        statusColor = Colors.red;
        translatedStatus = l10n.translate('state_shutting_down');
        break;
      case 'manutenção':
      case 'maintenance':
        statusColor = Colors.blue;
        translatedStatus = l10n.translate('state_maintenance');
        break;
      default:
        statusColor = Colors.grey;
        translatedStatus = status.toUpperCase();
    }

    final uptimeHours = (uptime / 3600).floor();
    final uptimeMinutes = ((uptime % 3600) / 60).floor();
    final uptimeSeconds = uptime % 60;
    final uptimeText = l10n.translate('state_uptime')
        .replaceAll('{0}', uptimeHours.toString())
        .replaceAll('{1}', uptimeMinutes.toString())
        .replaceAll('{2}', uptimeSeconds.toString());

    return Column(
      children: [
        // Status do servidor
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      translatedStatus,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.timer_rounded, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      uptimeText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Card de jogadores
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_rounded, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('players'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    l10n.translate('state_players')
                        .replaceAll('{0}', playersOnline.toString())
                        .replaceAll('{1}', maxPlayers.toString()),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                Text(
                  l10n.translate('players_online'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (maxPlayers == 0) ? 0 : playersOnline / maxPlayers,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServerInfoCard() {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('server_info_title'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(l10n.translate('name'), _serverStatus!.serverName),
            _buildInfoRow(l10n.translate('version'), _serverStatus!.serverVersion),
            _buildInfoRow('IP', _serverStatus!.serverIp),
            _buildInfoRow(l10n.translate('location'), _serverStatus!.serverLocation),
            _buildInfoRow(l10n.translate('uptime'), _serverStatus!.formattedUptime),
          ],
        ),
      ),
    );
  }

  Widget _buildStateControls() {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('state_control'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStateButton('online', Colors.green),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStateButton('offline', Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStateButton('shutting_down', Colors.red),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStateButton('maintenance', Colors.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateButton(String state, Color color) {
    final l10n = AppLocalizations.of(context);
    final buttonKey = 'state_button_$state';
    final buttonText = l10n.translate(buttonKey);
    final stateKey = 'state_$state';
    final stateText = l10n.translate(stateKey);
    
    String normalizeString(String str) {
      String fixEncoding(String input) {
        return input
            .replaceAll('Ã§', 'ç')
            .replaceAll('Ã£', 'ã')
            .replaceAll('Ãµ', 'õ')
            .replaceAll('Ã¡', 'á')
            .replaceAll('Ã©', 'é')
            .replaceAll('Ã­', 'í')
            .replaceAll('Ã³', 'ó')
            .replaceAll('Ãº', 'ú');
      }

      return fixEncoding(str)
          .toLowerCase()
          .trim()
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll('_', '')
          .replaceAll('ç', 'c')
          .replaceAll('ã', 'a')
          .replaceAll('õ', 'o')
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u');
    }

    final currentStatus = _serverStatus?.status ?? '';
    final normalizedCurrent = normalizeString(currentStatus);
    final normalizedState = normalizeString(stateText);
    final isCurrentState = normalizedCurrent == normalizedState;
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;
    
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: (_isChangingState || isCurrentState) ? null : () async {
          if (state == 'shutting_down') {
            final confirm = await _showShutdownConfirmation();
            if (confirm) {
              await _updateServerState(_getApiState(state));
            }
          } else {
            await _updateServerState(_getApiState(state));
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isCurrentState 
              ? (isDarkMode ? Colors.grey[800] : Colors.grey[200])
              : color,
          foregroundColor: isCurrentState ? color : Colors.white,
          elevation: isCurrentState ? 0 : 2,
          side: isCurrentState 
              ? BorderSide(color: color, width: 2)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: _isChangingState 
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDarkMode ? Colors.white70 : Colors.grey
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    buttonText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrentState ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              )
            : Text(
                buttonText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isCurrentState ? FontWeight.bold : FontWeight.normal,
                ),
              ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
