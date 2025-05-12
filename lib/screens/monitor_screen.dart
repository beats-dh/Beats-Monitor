import 'dart:async';
import 'package:beats_monitor/l10n/app_localizations.dart';
import 'package:beats_monitor/models/system_data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../widgets/cpu_usage_card.dart';
import '../widgets/processor_card.dart';
import '../widgets/system_cpu_info_card.dart';
import '../widgets/memory_usage_card.dart';
import '../widgets/connection_status_popup.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> with WidgetsBindingObserver {
  late WebSocketService _webSocketService;
  bool _initialized = false;
  bool _isConnected = false;
  StreamSubscription<bool>? _connectionSubscription;

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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
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
        
        // Apenas se inscreve nos eventos necessários, sem iniciar nova conexão
        _webSocketService.subscribe(['system_resources']);
        _initialized = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionSubscription?.cancel();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Apenas cancela a inscrição dos eventos, sem fechar a conexão
      _webSocketService.unsubscribe(['system_resources']);
    });
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Se o aplicativo voltar ao primeiro plano, verifica a conexão
    if (state == AppLifecycleState.resumed) {
      _ensureConnection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final websocketService = context.watch<WebSocketService>();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!websocketService.manualReconnectMode) {
          websocketService.unsubscribe(['system_resources']);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.monitor_heart_rounded),
              const SizedBox(width: 12),
              Text(l10n.translate('monitor_title')),
            ],
          ),
          actions: [
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
                    }
                  });
                } else {
                  // Mostra status da conexão
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.translate('monitor_connection_status')),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              tooltip: _isConnected ? l10n.translate('monitor_connected_tooltip') : l10n.translate('monitor_reconnect_tooltip'),
            ),
          ],
        ),
        body: Material(
          child: Stack(
            children: [
              StreamBuilder<bool>(
                stream: websocketService.connectionStatusStream,
                initialData: websocketService.connectionStatus,
                builder: (context, connectionSnapshot) {
                  if (!connectionSnapshot.data!) {
                    return Container(
                      alignment: Alignment.center,
                      margin: EdgeInsets.only(
                          bottom: MediaQuery.of(context).size.height * 0.1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: MediaQuery.of(context).size.width * 0.15,
                            color: Colors.grey,
                          ),
                          SizedBox(
                              height:
                                  MediaQuery.of(context).size.height * 0.02),
                          Text(
                            l10n.translate('no_server_connection'),
                            style: TextStyle(
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.045,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _ensureConnection,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.translate('try_connect')),
                          ),
                        ],
                      ),
                    );
                  }

                  return StreamBuilder<SystemData>(
                    stream: websocketService.systemDataStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.1,
                                height: MediaQuery.of(context).size.width * 0.1,
                                child: const CircularProgressIndicator(),
                              ),
                              SizedBox(
                                  height: MediaQuery.of(context).size.height *
                                      0.02),
                              Text(
                                l10n.translate('loading_system_data'),
                                style: TextStyle(
                                  fontSize:
                                      MediaQuery.of(context).size.width * 0.04,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final systemData = snapshot.data!;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      AppLocalizations.of(context).translate('monitor_warning'),
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const CpuUsageCard(),
                            const SizedBox(height: 16),
                            const MemoryUsageCard(),
                            const SizedBox(height: 16),
                            SystemCpuInfoCard(systemInfo: systemData.systemInfo),
                            const SizedBox(height: 16),
                            const ProcessorCard(),
                            const SizedBox(height: 16),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              ConnectionStatusPopup(webSocketService: websocketService),
            ],
          ),
        ),
      ),
    );
  }
}
