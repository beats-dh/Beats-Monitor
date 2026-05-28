import 'package:beats_monitor/providers/auth_provider.dart';
import 'package:beats_monitor/providers/locale_provider.dart';
import 'package:beats_monitor/providers/theme_provider.dart';
import 'package:beats_monitor/screens/home_screen.dart';
import 'package:beats_monitor/screens/live_screen.dart';
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
        child: const PenultimaMonitorApp(),
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

    expect(find.text('Penultima operations'), findsOneWidget);
    expect(find.text('Monitor'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);

    webSocketService.dispose();
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
    await tester.scrollUntilVisible(
      find.text('Live'),
      300,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Live local client view'), findsOneWidget);

    await tester.tap(find.text('Live').hitTestable());
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
