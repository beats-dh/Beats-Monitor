import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'services/websocket_service.dart';
import 'services/auth_service.dart';
import 'services/config_service.dart';
import 'screens/login_screen.dart';
import 'screens/server_info_screen.dart';
import 'screens/config_screen.dart';
import 'widgets/cpu_usage_card.dart';
import 'widgets/processor_card.dart';
import 'widgets/system_cpu_info_card.dart';
import 'widgets/system_memory_card.dart';
import 'widgets/process_info_card.dart';
import 'widgets/system_cache_card.dart';
import 'widgets/connection_status_popup.dart';
import 'widgets/page_transition.dart';
import 'widgets/memory_usage_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar serviços
  await AuthService.init();
  final configService = ConfigService();
  await configService.init();
  
  final webSocketService = WebSocketService(configService);
  final themeProvider = ThemeProvider();
  final authProvider = AuthProvider();
  await authProvider.init();

  // Definir orientação preferida
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configurar SystemUI para edge-to-edge
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Habilitar edge-to-edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConfigService>.value(value: configService),
        ChangeNotifierProvider<WebSocketService>.value(value: webSocketService),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: const BeatsMonitorApp(),
    ),
  );
}

class BeatsMonitorApp extends StatelessWidget {
  const BeatsMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beats Monitor',
      theme: context.watch<ThemeProvider>().theme,
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          return authProvider.isAuthenticated
              ? const MyHomePage()
              : const LoginScreen();
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Inicia a conexão WebSocket quando a página é carregada
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebSocketService>().startConnection();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webSocket = Provider.of<WebSocketService>(context);
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beats Monitor'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const ServerInfoScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    const curve = Curves.easeInOutQuart;

                    var tween = Tween(begin: begin, end: end)
                        .chain(CurveTween(curve: curve));

                    var offsetAnimation = animation.drive(tween);

                    return SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final needsReconnect = await Navigator.push<bool>(
                context,
                PageTransition<bool>(child: const ConfigScreen()),
              );
              
              if (needsReconnect == true && mounted) {
                webSocket.startConnection();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Para o reconnect e fecha a conexão
              webSocket.manualReconnectMode = true;
              await webSocket.closeCurrentConnection();
              
              // Faz logout
              await auth.logout();
            },
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          return StreamBuilder<bool>(
            stream: webSocket.connectionStatus,
            initialData: false,
            builder: (context, connectionSnapshot) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Se não está conectado, mostra mensagem
                  if (!connectionSnapshot.data!)
                    Positioned.fill(
                      child: Container(
                        alignment: Alignment.center,
                        margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: MediaQuery.of(context).size.width * 0.15, // 15% da largura da tela
                              color: Colors.grey,
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.02), // 2% da altura
                            Text(
                              'Sem conexão com o servidor',
                              style: TextStyle(
                                fontSize: MediaQuery.of(context).size.width * 0.045, // 4.5% da largura
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              'Tentando reconectar...',
                              style: TextStyle(
                                fontSize: MediaQuery.of(context).size.width * 0.035, // 3.5% da largura
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // Se está conectado, mostra o conteúdo
                  if (connectionSnapshot.data!)
                    SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16.0),
                      child: StreamBuilder(
                        stream: webSocket.systemDataStream,
                        builder: (context, snapshot) {
                          // Se não tem dados ainda, mostra loading central
                          if (!snapshot.hasData) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: MediaQuery.of(context).size.width * 0.1, // 10% da largura
                                    height: MediaQuery.of(context).size.width * 0.1,
                                    child: const CircularProgressIndicator(),
                                  ),
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                                  Text(
                                    'Carregando dados do sistema...',
                                    style: TextStyle(
                                      fontSize: MediaQuery.of(context).size.width * 0.04,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // Se tem dados, mostra os cards
                          final systemData = snapshot.data!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const CpuUsageCard(),
                              const SizedBox(height: 16),
                              const MemoryUsageCard(),
                              const SizedBox(height: 16),
                              SystemCpuInfoCard(systemInfo: systemData.systemInfo),
                              const SizedBox(height: 16),
                              const ProcessorCard(),
                              const SizedBox(height: 16),
                              SystemMemoryCard(memoryInfo: systemData.systemInfo.memory),
                              const SizedBox(height: 16),
                              ProcessInfoCard(processData: systemData.processData),
                              const SizedBox(height: 16),
                              SystemCacheCard(memoryInfo: systemData.systemInfo.memory),
                            ],
                          );
                        },
                      ),
                    ),
                  
                  // Popup de reconexão sempre visível quando necessário
                  Consumer<WebSocketService>(
                    builder: (context, service, child) => ConnectionStatusPopup(
                      webSocketService: service,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
