import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/events.dart';
import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';

class ServerStatusScreen extends StatefulWidget {
  const ServerStatusScreen({super.key});

  @override
  State<ServerStatusScreen> createState() => _ServerStatusScreenState();
}

class _ServerStatusScreenState extends State<ServerStatusScreen> {
  late WebSocketService _webSocketService;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _webSocketService = context.read<WebSocketService>();
        _webSocketService.manualReconnectMode = false;
        _webSocketService.startConnection();
        _webSocketService.subscribe(['server_status']);
        _initialized = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_webSocketService.manualReconnectMode) {
        _webSocketService.unsubscribe(['server_status']);
        _webSocketService.closeCurrentConnection();
      }
      _webSocketService.manualReconnectMode = true;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final websocketService = context.watch<WebSocketService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.dns_rounded),
            const SizedBox(width: 12),
            Text(l10n.translate('server_status_title')),
          ],
        ),
      ),
      body: StreamBuilder<ServerStatus>(
        stream: websocketService.serverStatusStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final status = snapshot.data!;
          final uptimeHours = (status.uptime / 3600).floor();
          final uptimeMinutes = ((status.uptime % 3600) / 60).floor();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusCard(
                  theme,
                  l10n.translate('status'),
                  status.status,
                  Icons.power_settings_new_rounded,
                  _getStatusColor(status.status),
                ),
                const SizedBox(height: 16),
                _buildStatusCard(
                  theme,
                  l10n.translate('uptime'),
                  '$uptimeHours ${l10n.translate('hours')} $uptimeMinutes ${l10n.translate('minutes')}',
                  Icons.timer_rounded,
                  Colors.blue,
                ),
                const SizedBox(height: 16),
                _buildPlayerCard(
                  theme,
                  l10n,
                  status.playersOnline,
                  status.maxPlayers,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(
    ThemeData theme,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard(
    ThemeData theme,
    AppLocalizations l10n,
    int online,
    int max,
  ) {
    final percentage = (max == 0) ? 0 : (online / max * 100).round();
    final playerText = (max == 0) ? '$online' : '$online/$max ($percentage%)';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 8),
            Text(
              playerText,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (max == 0) ? 0 : online / max,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.red;
      case 'maintenance':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
