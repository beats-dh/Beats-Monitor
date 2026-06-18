import 'package:beats_monitor/providers/auth_provider.dart';
import 'package:beats_monitor/providers/locale_provider.dart';
import 'package:beats_monitor/providers/theme_provider.dart';
import 'package:beats_monitor/screens/banned_players_screen.dart';
import 'package:beats_monitor/screens/chat_screen.dart';
import 'package:beats_monitor/screens/config_screen.dart';
import 'package:beats_monitor/screens/home_screen.dart';
import 'package:beats_monitor/screens/live_screen.dart';
import 'package:beats_monitor/screens/logs_screen.dart';
import 'package:beats_monitor/screens/monitor_screen.dart';
import 'package:beats_monitor/screens/online_players_screen.dart';
import 'package:beats_monitor/screens/server_info_screen.dart';
import 'package:beats_monitor/services/config_service.dart';
import 'package:beats_monitor/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beats_monitor/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:beats_monitor/l10n/app_localizations.dart';

void setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void setDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('renders the unauthenticated Penultima monitor login screen',
      (tester) async {
    setPhoneViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final configService = ConfigService();
    final webSocketService = WebSocketService(configService)
      ..manualReconnectMode = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider(prefs)),
          ChangeNotifierProvider<ConfigService>.value(value: configService),
          ChangeNotifierProvider<WebSocketService>.value(
              value: webSocketService),
        ],
        child: const PenultimaWebApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);

    webSocketService.dispose();
  });

  testWidgets('renders the compact Penultima home layout at phone size',
      (tester) async {
    setPhoneViewport(tester);
    SharedPreferences.setMockInitialValues({'selected_locale': 'en'});
    final prefs = await SharedPreferences.getInstance();
    final configService = ConfigService();
    final webSocketService = WebSocketService(configService)
      ..manualReconnectMode = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider(prefs)),
          ChangeNotifierProvider<ConfigService>.value(value: configService),
          ChangeNotifierProvider<WebSocketService>.value(
              value: webSocketService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [
            Locale('pt'),
            Locale('en'),
          ],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Penultima Web'), findsOneWidget);
    expect(find.text('Monitor'), findsOneWidget);
    expect(find.byKey(const ValueKey('home_tile_Monitor')), findsOneWidget);
    expect(find.text('15.23'), findsOneWidget);
    expect(find.text('12.98'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pump();
    expect(find.text('Runtime Log (tail - live)'), findsOneWidget);
    expect(find.byKey(const ValueKey('runtime_log_copy')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('runtime_log_fullscreen')), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -360));
    await tester.pump();

    expect(find.text('Log Files'), findsOneWidget);
    expect(find.text('Open Selected File'), findsOneWidget);
    expect(find.text('Server is starting up...'), findsNothing);

    webSocketService.dispose();
  });

  testWidgets('logs screen starts on the selected runtime file',
      (tester) async {
    setPhoneViewport(tester);
    SharedPreferences.setMockInitialValues({'selected_locale': 'en'});
    final prefs = await SharedPreferences.getInstance();
    final configService = ConfigService();
    final webSocketService = WebSocketService(configService)
      ..manualReconnectMode = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider(prefs)),
          ChangeNotifierProvider<ConfigService>.value(value: configService),
          ChangeNotifierProvider<WebSocketService>.value(
              value: webSocketService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [
            Locale('pt'),
            Locale('en'),
          ],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: LogsScreen(initialFile: 'runtime.log'),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Logs'), findsOneWidget);
    expect(find.textContaining('runtime.log'), findsWidgets);
    expect(find.byTooltip('Copy visible log lines'), findsOneWidget);

    webSocketService.dispose();
  });

  testWidgets('core feature screens render their first frame', (tester) async {
    setDesktopViewport(tester);

    final cases = <({Widget screen, String title})>[
      (screen: const MonitorScreen(), title: 'Monitor'),
      (screen: const ServerInfoScreen(), title: 'Server Info'),
      (screen: const ChatScreen(), title: 'Chat'),
      (screen: const OnlinePlayersScreen(), title: 'Online Players'),
      (screen: const BannedPlayersScreen(), title: 'Banned Players'),
      (screen: const LiveScreen(), title: 'Live'),
      (screen: const LogsScreen(initialFile: 'runtime.log'), title: 'Logs'),
      (screen: const ConfigScreen(), title: 'Settings'),
    ];

    for (final item in cases) {
      SharedPreferences.setMockInitialValues({'selected_locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final configService = ConfigService();
      final webSocketService = WebSocketService(configService)
        ..manualReconnectMode = true;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider(prefs)),
            ChangeNotifierProvider<ConfigService>.value(value: configService),
            ChangeNotifierProvider<WebSocketService>.value(
                value: webSocketService),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [
              Locale('pt'),
              Locale('en'),
            ],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: item.screen,
          ),
        ),
      );

      await tester.pump();

      expect(find.textContaining(item.title), findsWidgets);
      webSocketService.dispose();
    }
  });

  testWidgets('renders the Live entry and opens the Live screen',
      (tester) async {
    setDesktopViewport(tester);
    SharedPreferences.setMockInitialValues({'selected_locale': 'en'});
    final prefs = await SharedPreferences.getInstance();
    final configService = ConfigService();
    final webSocketService = WebSocketService(configService)
      ..manualReconnectMode = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider(prefs)),
          ChangeNotifierProvider<ConfigService>.value(value: configService),
          ChangeNotifierProvider<WebSocketService>.value(
              value: webSocketService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [
            Locale('pt'),
            Locale('en'),
          ],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();
    expect(find.byKey(const ValueKey('home_tile_Live')), findsOneWidget);
    expect(find.text('Live local client view'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -280));
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('home_tile_Live')).hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Ready - Character: Waldir'), findsOneWidget);
    expect(find.text('Live capture is not available here'), findsOneWidget);

    webSocketService.dispose();
  });

  testWidgets('renders the native fallback state for the Live screen',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [
          Locale('pt'),
          Locale('en'),
        ],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: LiveScreen(),
      ),
    );

    await tester.pump();

    expect(find.text('Ready - Character: Waldir'), findsOneWidget);
    expect(find.text('Live capture is not available here'), findsOneWidget);
    expect(find.text('Start Live View'), findsOneWidget);
  });
}
