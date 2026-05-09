import 'package:beats_monitor/providers/auth_provider.dart';
import 'package:beats_monitor/providers/locale_provider.dart';
import 'package:beats_monitor/providers/theme_provider.dart';
import 'package:beats_monitor/services/config_service.dart';
import 'package:beats_monitor/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beats_monitor/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders the unauthenticated Penultima monitor login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final configService = ConfigService();
    final webSocketService = WebSocketService(configService)..manualReconnectMode = true;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider(prefs)),
          ChangeNotifierProvider<ConfigService>.value(value: configService),
          ChangeNotifierProvider<WebSocketService>.value(value: webSocketService),
        ],
        child: const PenultimaMonitorApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);

    webSocketService.dispose();
  });
}
