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
      await UpdateService.instance.checkForUpdates();
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
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

  Future<void> _showUpdateDialog(BuildContext context, String url) async {
    final updateInfo = await UpdateService.instance.checkForUpdates();
    if (updateInfo == null || !mounted) return;

    // Verifica permissão antes de tudo
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        if (!mounted) return;
        
        // Mostra diálogo explicando a necessidade da permissão
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissão Necessária'),
            content: const Text(
              'Para instalar atualizações automaticamente, é necessário permitir a instalação de aplicativos desconhecidos por este app.\n\n'
              'Na próxima tela, ative a opção "Permitir desta fonte".'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continuar'),
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
      context: context,
      barrierDismissible: !updateInfo.required,
      builder: (context) => WillPopScope(
        onWillPop: () async => !updateInfo.required,
        child: Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: Theme.of(context).colorScheme.surface,
          ),
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.system_update),
                const SizedBox(width: 8),
                Text(
                  'Nova Versão ${updateInfo.version}',
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
                      child: const Text(
                        'Esta é uma atualização obrigatória!',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Text(
                    'Novidades:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(updateInfo.changelog),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: updateInfo.required ? null : () => Navigator.pop(context, false),
                child: const Text('Depois'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Atualizar Agora'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || shouldDownload != true) return;

    // Mostra o diálogo de download
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => !updateInfo.required,
        child: _DownloadDialog(
          url: url,
          required: updateInfo.required,
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
            title: 'Aparência',
            icon: Icons.palette,
            children: [
              SwitchListTile(
                title: const Text('Tema Escuro'),
                subtitle: Text(
                  'Alterna entre tema claro e escuro',
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
            title: 'Conexão',
            icon: Icons.link,
            children: [
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'URL do Servidor',
                  hintText: 'http://exemplo.com:3000',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Reconexão Automática'),
                subtitle: Text(
                  'Tentar reconectar automaticamente quando perder conexão',
                  style: theme.textTheme.bodySmall,
                ),
                value: _autoReconnect,
                onChanged: (value) => setState(() => _autoReconnect = value),
              ),
              if (_autoReconnect) ...[
                const SizedBox(height: 8),
                ListTile(
                  title: const Text('Tentativas de Reconexão'),
                  subtitle: Slider(
                    value: _reconnectAttempts.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _reconnectAttempts.toString(),
                    onChanged: (value) => setState(() => 
                      _reconnectAttempts = value.round()
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Seção de Notificações
          _buildCard(
            title: 'Notificações',
            icon: Icons.notifications,
            children: [
              SwitchListTile(
                title: const Text('Notificações do Sistema'),
                subtitle: Text(
                  'Receber alertas sobre o estado do servidor',
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
            title: 'Sobre',
            icon: Icons.info,
            children: [
              ListTile(
                title: const Text('Versão'),
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
                          const SnackBar(
                            content: Text('Você está usando a versão mais recente'),
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
                title: const Text('Desenvolvido por'),
                subtitle: const Text('Daniel Henrique [ Beats ]'),
                trailing: IconButton(
                  icon: const Icon(Icons.link),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Em breve: Link para o GitHub'),
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
            label: const Text('Salvar Alterações'),
          ),
          if (!_isLoading) ...[
            const SizedBox(height: 8),
            Text(
              'Ao salvar, a conexão será reiniciada automaticamente.',
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
  String _status = 'Iniciando download...';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final filePath = await DownloadService.downloadUpdate(
        widget.url,
        (received, total) {
          if (total != -1) {
            if (!mounted) return;
            setState(() {
              _progress = received / total;
              _status = 'Baixando... ${(_progress * 100).toStringAsFixed(1)}%';
            });
          }
        },
      );

      if (!mounted) return;

      if (filePath == null) {
        setState(() {
          _error = true;
          _status = 'Erro ao fazer download';
        });
        return;
      }

      setState(() => _status = 'Download concluído!');

      // Instala o APK
      if (Platform.isAndroid) {
        final file = File(filePath);
        if (await file.exists()) {
          if (!mounted) return;
          
          setState(() => _status = 'Iniciando instalação...');
          
          try {
            final success = await PlatformService.installApk(filePath);
            if (!mounted) return;
            
            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Instalação iniciada')),
              );
              Navigator.of(context).pop(true);
            } else {
              throw 'Não foi possível iniciar a instalação';
            }
          } catch (e) {
            debugPrint('Erro ao instalar APK: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erro ao iniciar instalação')),
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
        _status = 'Erro ao fazer download';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_error ? 'Erro' : 'Baixando Atualização'),
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
            child: Text(_error ? 'Fechar' : 'Cancelar'),
          ),
      ],
    );
  }
}
