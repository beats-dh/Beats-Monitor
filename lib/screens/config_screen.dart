import 'dart:io';
import 'package:beats_monitor/l10n/app_localizations.dart';
import 'package:beats_monitor/services/download_service.dart';
import 'package:beats_monitor/services/platform_service.dart';
import 'package:beats_monitor/services/update_service.dart';
import 'package:beats_monitor/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/config_service.dart';
import '../providers/theme_provider.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late TextEditingController _baseUrlController;
  bool _isLoading = false;
  bool _autoReconnect = true;
  bool _showNotifications = true;
  int _reconnectAttempts = 5;
  bool _initialized = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    UpdateService.instance.init();
    DownloadService.cleanOldUpdates(); // Limpa APKs antigos
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    
    setState(() => _checkingUpdate = true);

    try {
      final updateInfo = await UpdateService.instance.checkForUpdates();
      
      if (!mounted) return;
      final currentContext = context;
      final l10n = AppLocalizations.of(currentContext);
      
      if (updateInfo == null) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('latest_version')),
          ),
        );
        return;
      }

      await _showUpdateDialog(currentContext, updateInfo.url);
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  Future<void> _showUpdateDialog(BuildContext parentContext, String url) async {
    final updateInfo = await UpdateService.instance.checkForUpdates();
    if (updateInfo == null || !mounted) return;

    final l10n = AppLocalizations.of(context);

    // Verifica permissão antes de tudo
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted && mounted) {
        // Mostra diálogo explicando a necessidade da permissão
        final shouldRequest = await showDialog<bool>(
          context: parentContext,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.translate('permission_required')),
            content: Text(l10n.translate('permission_explanation')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.translate('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.translate('continue')),
              ),
            ],
          ),
        );

        if (!mounted || shouldRequest != true) return;

        final permissionStatus = await Permission.requestInstallPackages.request();
        if (!mounted || !permissionStatus.isGranted) return;
      }
    }

    if (!mounted) return;

    // Mostra diálogo de confirmação
    final shouldDownload = await showDialog<bool>(
      context: parentContext,
      barrierDismissible: !updateInfo.required,
      builder: (dialogContext) => PopScope(
        canPop: !updateInfo.required,
        child: Theme(
          data: Theme.of(dialogContext).copyWith(
            dialogBackgroundColor: Theme.of(dialogContext).colorScheme.surface,
          ),
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.system_update),
                const SizedBox(width: 8),
                Text(
                  '${l10n.translate('new_version')} ${updateInfo.version}',
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 400,
                maxWidth: 500,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (updateInfo.required)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l10n.translate('required_update'),
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    l10n.translate('whats_new'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest.withAlpha(77),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(updateInfo.changelog),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: updateInfo.required ? null : () => Navigator.pop(dialogContext, false),
                child: Text(l10n.translate('later')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.translate('update_now')),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || shouldDownload != true) return;

    // Mostra o diálogo de download
    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: !updateInfo.required,
        child: _DownloadDialog(
          url: url,
          required: updateInfo.required,
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final config = context.read<ConfigService>();
      _baseUrlController.text = config.baseUrl;
      _autoReconnect = config.autoReconnect;
      _reconnectAttempts = config.reconnectAttempts;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (_baseUrlController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final config = context.read<ConfigService>();
      final webSocket = context.read<WebSocketService>();
      
      await config.setBaseUrl(_baseUrlController.text.trim());
      await config.setAutoReconnect(_autoReconnect);
      await config.setReconnectAttempts(_reconnectAttempts);
      
      await webSocket.closeCurrentConnection();
      await webSocket.reconnectManually();
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final l10n = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('config_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Seção de Aparência
          _buildCard(
            title: l10n.translate('appearance'),
            icon: Icons.palette,
            children: [
              SwitchListTile(
                title: Text(l10n.translate('dark_theme')),
                subtitle: Text(
                  l10n.translate('dark_theme_desc'),
                  style: theme.textTheme.bodySmall,
                ),
                value: themeProvider.isDarkMode,
                onChanged: (value) => themeProvider.toggleTheme(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Seção de Conexão
          _buildCard(
            title: l10n.translate('connection'),
            icon: Icons.link,
            children: [
              TextField(
                controller: _baseUrlController,
                decoration: InputDecoration(
                  labelText: l10n.translate('server_url'),
                  hintText: l10n.translate('server_url_hint'),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(l10n.translate('auto_reconnect')),
                subtitle: Text(
                  l10n.translate('auto_reconnect_desc'),
                  style: theme.textTheme.bodySmall,
                ),
                value: _autoReconnect,
                onChanged: (value) => setState(() => _autoReconnect = value),
              ),
              if (_autoReconnect) ...[
                const SizedBox(height: 8),
                ListTile(
                  title: Text(l10n.translate('reconnect_attempts')),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.translate('max_reconnect_attempts').replaceAll('{0}', _reconnectAttempts.toString()),
                        style: theme.textTheme.bodySmall,
                      ),
                      Slider(
                        value: _reconnectAttempts.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: _reconnectAttempts.toString(),
                        onChanged: (value) => setState(() => 
                          _reconnectAttempts = value.round()
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Seção de Notificações
          _buildCard(
            title: l10n.translate('notifications'),
            icon: Icons.notifications,
            children: [
              SwitchListTile(
                title: Text(l10n.translate('system_notifications')),
                subtitle: Text(
                  l10n.translate('system_notifications_desc'),
                  style: theme.textTheme.bodySmall,
                ),
                value: _showNotifications,
                onChanged: (value) => setState(() => _showNotifications = value),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Seção Sobre
          _buildCard(
            title: l10n.translate('about'),
            icon: Icons.info,
            children: [
              ListTile(
                title: Text(l10n.translate('version')),
                subtitle: Text(UpdateService.instance.currentVersion),
                trailing: IconButton(
                  icon: _checkingUpdate 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update),
                  onPressed: _checkingUpdate ? null : () async {
                    setState(() => _checkingUpdate = true);
                    try {
                      final updateInfo = await UpdateService.instance.checkForUpdates();
                      
                      if (!mounted) return;
                      
                      if (updateInfo == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.translate('latest_version')),
                          ),
                        );
                        return;
                      }

                      await _showUpdateDialog(context, updateInfo.url);
                    } finally {
                      if (mounted) {
                        setState(() => _checkingUpdate = false);
                      }
                    }
                  },
                ),
              ),
              const Divider(),
              ListTile(
                title: Text(l10n.translate('developed_by')),
                subtitle: const Text('Daniel Henrique [ Beats ]'),
                trailing: IconButton(
                  icon: const Icon(Icons.link),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.translate('github_soon')),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Botão Salvar
          FilledButton.icon(
            onPressed: _isLoading ? null : _saveConfig,
            icon: _isLoading 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.save),
            label: Text(l10n.translate('save_changes')),
          ),
          if (!_isLoading) ...[
            const SizedBox(height: 8),
            Text(
              l10n.translate('save_connection_restart'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _DownloadDialog extends StatefulWidget {
  final String url;
  final bool required;

  const _DownloadDialog({
    required this.url,
    required this.required,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  String _status = '';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    final l10n = AppLocalizations.of(context);
    _status = l10n.translate('starting_download');
    _startDownload();
  }

  Future<void> _startDownload() async {
    final l10n = AppLocalizations.of(context);
    try {
      final filePath = await DownloadService.downloadUpdate(
        widget.url,
        (received, total) {
          if (total != -1) {
            if (!mounted) return;
            setState(() {
              _progress = received / total;
              _status = l10n.translate('downloading').replaceAll('{0}', (_progress * 100).toStringAsFixed(1));
            });
          }
        },
      );

      if (!mounted) return;

      if (filePath == null) {
        setState(() {
          _error = true;
          _status = l10n.translate('download_error');
        });
        return;
      }

      setState(() => _status = l10n.translate('download_complete'));

      // Instala o APK
      if (Platform.isAndroid) {
        final file = File(filePath);
        if (await file.exists()) {
          if (!mounted) return;
          
          setState(() => _status = l10n.translate('starting_installation'));
          
          try {
            final success = await PlatformService.installApk(filePath);
            if (!mounted) return;
            
            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.translate('installation_started'))),
              );
              Navigator.of(context).pop(true);
            } else {
              throw 'Não foi possível iniciar a instalação';
            }
          } catch (e) {
            debugPrint('Erro ao instalar APK: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.translate('installation_error'))),
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Erro no download: $e');
      if (!mounted) return;
      setState(() {
        _error = true;
        _status = l10n.translate('download_error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_error ? l10n.translate('error') : l10n.translate('downloading_update')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_status),
          if (!_error) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
          ],
        ],
      ),
      actions: [
        if (!widget.required || _error)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_error ? l10n.translate('close') : l10n.translate('cancel')),
          ),
      ],
    );
  }
}
