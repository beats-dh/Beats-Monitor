import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'dart:io' show Platform;
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/locale_provider.dart';
import 'services/websocket_service.dart';
import 'services/auth_service.dart';
import 'services/config_service.dart';
import 'services/stripe_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'l10n/app_localizations.dart';
import 'config/stripe_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Stripe apenas em plataformas móveis
  if (Platform.isAndroid || Platform.isIOS) {
    Stripe.publishableKey = StripeConfig.publishableKey;
  }

  // Inicializar serviços
  await AuthService.init();
  await StripeService.initialize();
  final prefs = await SharedPreferences.getInstance();
  final configService = ConfigService();
  await configService.init();
  
  final webSocketService = WebSocketService(configService);
  final themeProvider = ThemeProvider();
  final authProvider = AuthProvider();
  final localeProvider = LocaleProvider(prefs);
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
        ChangeNotifierProvider(create: (_) => themeProvider),
        ChangeNotifierProvider(create: (_) => authProvider),
        ChangeNotifierProvider<WebSocketService>.value(value: webSocketService),
        ChangeNotifierProvider<ConfigService>.value(value: configService),
        ChangeNotifierProvider(create: (_) => localeProvider),
      ],
      child: const BeatsMonitorApp(),
    ),
  );
}

class BeatsMonitorApp extends StatelessWidget {
  const BeatsMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Beats Monitor',
      locale: localeProvider.locale,
      supportedLocales: const [
        Locale('pt'),
        Locale('en'),
      ],
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: context.watch<ThemeProvider>().theme.copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isAuthenticated) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
