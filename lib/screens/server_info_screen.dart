import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../models/server_status.dart';
import '../providers/theme_provider.dart';

class ServerInfoScreen extends StatefulWidget {
  const ServerInfoScreen({super.key});

  @override
  State<ServerInfoScreen> createState() => _ServerInfoScreenState();
}

class _ServerInfoScreenState extends State<ServerInfoScreen> {
  ServerStatus? _serverStatus;
  bool _isLoading = false;
  bool _isChangingState = false; // Novo estado para controlar mudança de estado
  String? _error;

  Future<void> _fetchServerStatus() async {
    if (_serverStatus == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await ApiService.get('server/status');
      
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
            _error = 'Erro ao buscar status do servidor';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Erro ${response.statusCode} ao buscar status do servidor';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erro de conexão: $e';
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

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['sucesso'] == true) {
          await Future.delayed(const Duration(milliseconds: 500));
          await _fetchServerStatus();
          _showStatusMessage('Servidor: ${newState.toUpperCase()}');
        } else {
          setState(() {
            _isChangingState = false;
          });
          _showStatusMessage('Falha ao atualizar servidor', isError: true);
        }
      } else {
        setState(() {
          _isChangingState = false;
        });
        _showStatusMessage('Erro na requisição', isError: true);
      }
    } catch (e) {
      setState(() {
        _isChangingState = false;
      });
      _showStatusMessage('Erro de conexão', isError: true);
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

  Future<bool> _showShutdownConfirmation() async {
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
            title: const Text(
              'ATENÇÃO!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tem certeza que deseja desligar o servidor?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(
                      alpha: (0.1 * 255).toDouble(),
                      red: Colors.red.r,
                      green: Colors.red.g,
                      blue: Colors.red.b,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(
                        alpha: (0.3 * 255).toDouble(),
                        red: Colors.red.r,
                        green: Colors.red.g,
                        blue: Colors.red.b,
                      ),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        '⚠️ Esta ação irá:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Desconectar todos os jogadores\n'
                        '• Garanta que tenha um auto start configurado',
                        style: TextStyle(color: Colors.white70),
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
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(fontWeight: FontWeight.bold),
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
                      child: const Text(
                        'DESLIGAR',
                        style: TextStyle(fontWeight: FontWeight.bold),
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

  @override
  void initState() {
    super.initState();
    _fetchServerStatus();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;
    
    return PopScope(
      canPop: !(_isLoading || _isChangingState),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Status do Servidor'),
          centerTitle: true,
          actions: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _fetchServerStatus,
                ),
                if (_isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDarkMode ? Colors.white70 : Colors.grey
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _serverStatus == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _serverStatus == null) {
      return Center(
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
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchServerStatus,
              child: const Text('Tentar Novamente'),
            ),
          ],
        ),
      );
    }

    if (_serverStatus == null) {
      return const Center(
        child: Text('Nenhuma informação disponível'),
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
    Color statusColor;
    switch (_serverStatus!.status.toLowerCase()) {
      case 'online':
        statusColor = Colors.green;
        break;
      case 'fechado':
        statusColor = Colors.red;
        break;
      case 'desligando':
        statusColor = Colors.orange;
        break;
      case 'manutenção':
        statusColor = Colors.blue;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
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
                  _serverStatus!.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${_serverStatus!.playersOnline} / ${_serverStatus!.maxPlayers}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Jogadores Online',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informações do Servidor',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Nome', _serverStatus!.serverName),
            _buildInfoRow('Versão', _serverStatus!.serverVersion),
            _buildInfoRow('IP', _serverStatus!.serverIp),
            _buildInfoRow('Localização', _serverStatus!.serverLocation),
            _buildInfoRow('Tempo Online', _serverStatus!.formattedUptime),
          ],
        ),
      ),
    );
  }

  Widget _buildStateControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controle de Estado',
              style: TextStyle(
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
                  child: _buildStateButton('fechado', Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStateButton('desligando', Colors.orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStateButton('manutenção', Colors.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateButton(String state, Color color) {
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
    final normalizedState = normalizeString(state);
    final isCurrentState = normalizedCurrent == normalizedState;
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;
    
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: (_isChangingState || isCurrentState) ? null : () async {
          if (state.toLowerCase() == 'desligando') {
            final confirm = await _showShutdownConfirmation();
            if (confirm) {
              await _updateServerState(state);
            }
          } else {
            await _updateServerState(state);
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
                    state.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrentState ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              )
            : Text(
                state.toUpperCase(),
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
