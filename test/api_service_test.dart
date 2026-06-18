import 'package:beats_monitor/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('resolves chat bridge beside the web app base path', () {
    final uri = ApiService.chatBridgeFallbackUriForBase(
      Uri.parse('https://ultimaotserv.online/beats-monitor/'),
    );

    expect(
      uri.toString(),
      'https://ultimaotserv.online/beats-monitor/beats_monitor_chat.php',
    );
  });

  test('uses chat bridge for disabled production chat and command responses', () {
    final disabled = http.Response(
      '{"mensagem":"Chat sending is disabled in this production adapter."}',
      403,
    );
    final disabledGod = http.Response(
      '{"mensagem":"God commands are disabled in this production adapter."}',
      403,
    );

    expect(
      ApiService.shouldUseChatBridgeFallbackForResponse(
        'server/chat-message',
        disabled,
        isWeb: true,
      ),
      isTrue,
    );
    expect(
      ApiService.shouldUseChatBridgeFallbackForResponse(
        'server/god-command',
        disabledGod,
        isWeb: true,
      ),
      isTrue,
    );
    expect(
      ApiService.shouldUseChatBridgeFallbackForResponse(
        'server/chat-message',
        disabledGod,
        isWeb: true,
      ),
      isTrue,
    );
    expect(
      ApiService.shouldUseChatBridgeFallbackForResponse(
        'server/chat-message',
        http.Response('{"mensagem":"Unauthorized."}', 401),
        isWeb: true,
      ),
      isFalse,
    );
  });
}
