import 'package:beats_monitor/l10n/app_localizations.dart';
import 'package:beats_monitor/models/system_data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../widgets/cpu_usage_card.dart';
import '../widgets/processor_card.dart';
import '../widgets/system_cpu_info_card.dart';
import '../widgets/system_memory_card.dart';
import '../widgets/process_info_card.dart';
import '../widgets/system_cache_card.dart';
import '../widgets/connection_status_popup.dart';
import '../widgets/memory_usage_card.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
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
        _webSocketService.subscribe(['system_resources']);
        _initialized = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_webSocketService.manualReconnectMode) {
        _webSocketService.unsubscribe(['system_resources']);
        _webSocketService.closeCurrentConnection();
      }
      _webSocketService.manualReconnectMode = true;
    });
    super.dispose();
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
          websocketService.closeCurrentConnection();
        }
        websocketService.manualReconnectMode = true;
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
        ),
        body: Material(
          child: Stack(
            children: [
              StreamBuilder<bool>(
                stream: websocketService.connectionStatusStream,
                initialData: false,
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
                                'Carregando dados do sistema...',
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
                            const CpuUsageCard(),
                            const SizedBox(height: 16),
                            const MemoryUsageCard(),
                            const SizedBox(height: 16),
                            SystemCpuInfoCard(
                                systemInfo: systemData.systemInfo),
                            const SizedBox(height: 16),
                            const ProcessorCard(),
                            const SizedBox(height: 16),
                            SystemMemoryCard(
                                memoryInfo: systemData.systemInfo.memory),
                            const SizedBox(height: 16),
                            ProcessInfoCard(
                                processData: systemData.processData),
                            const SizedBox(height: 16),
                            SystemCacheCard(
                                memoryInfo: systemData.systemInfo.memory),
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
