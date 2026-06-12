import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:beats_monitor/services/auth_service.dart';
import 'package:beats_monitor/services/config_service.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 10);
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };
  static const Set<String> _chatBridgeFallbackEndpoints = {
    'players/message',
    'server/broadcast',
    'server/chat-message',
  };

  static Future<bool> _refreshTokenIfNeeded() async {
    if (AuthService.hasCredentials) {
      return await AuthService.refreshToken();
    }
    return false;
  }

  static Future<Map<String, String>> _getHeaders() async {
    await _refreshTokenIfNeeded();
    return {
      ..._jsonHeaders,
      'Authorization': 'Bearer ${AuthService.token}',
    };
  }

  static List<int>? _encodeJsonBody(dynamic body) {
    return body != null ? utf8.encode(json.encode(body)) : null;
  }

  @visibleForTesting
  static Uri chatBridgeFallbackUriForBase(Uri base) {
    return base.resolve('beats_monitor_chat.php');
  }

  static Uri _chatBridgeFallbackUri() {
    return chatBridgeFallbackUriForBase(Uri.base);
  }

  @visibleForTesting
  static bool shouldUseChatBridgeFallbackForResponse(
    String endpoint,
    http.Response response, {
    bool isWeb = kIsWeb,
  }) {
    if (!isWeb ||
        response.statusCode != 403 ||
        !_chatBridgeFallbackEndpoints.contains(endpoint)) {
      return false;
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    return text
        .toLowerCase()
        .contains('chat sending is disabled in this production adapter');
  }

  static Future<http.Response> _postChatBridgeFallback(
    String endpoint,
    Map<String, String> headers,
    dynamic body,
  ) {
    return http
        .post(
          _chatBridgeFallbackUri(),
          headers: headers,
          body: _encodeJsonBody({
            'endpoint': endpoint,
            'body': body ?? <String, dynamic>{},
          }),
        )
        .timeout(_timeout);
  }

  static Future<http.Response> get(String endpoint) async {
    final headers = await _getHeaders();
    try {
      final response = await http
          .get(
            Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
            headers: headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        // Token expirado, tenta renovar
        if (await AuthService.refreshToken()) {
          // Tenta novamente com o novo token
          return await get(endpoint);
        }
      }

      return response;
    } catch (e) {
      debugPrint('GET request error: $e');
      rethrow;
    }
  }

  static Future<http.Response> post(String endpoint, {dynamic body}) async {
    final headers = await _getHeaders();
    try {
      final response = await http
          .post(
            Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
            headers: headers,
            body: _encodeJsonBody(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        // Token expirado, tenta renovar
        if (await AuthService.refreshToken()) {
          // Tenta novamente com o novo token
          return await post(endpoint, body: body);
        }
      }

      if (shouldUseChatBridgeFallbackForResponse(endpoint, response)) {
        return await _postChatBridgeFallback(endpoint, headers, body);
      }

      return response;
    } catch (e) {
      debugPrint('POST request error: $e');
      rethrow;
    }
  }

  static Future<http.Response> put(String endpoint, {dynamic body}) async {
    final headers = await _getHeaders();
    try {
      final response = await http
          .put(
            Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
            headers: headers,
            body: _encodeJsonBody(body),
          )
          .timeout(_timeout);
      return response;
    } catch (e) {
      debugPrint('PUT request error: $e');
      rethrow;
    }
  }

  static Future<http.Response> delete(String endpoint) async {
    final headers = await _getHeaders();
    try {
      final response = await http
          .delete(
            Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
            headers: headers,
          )
          .timeout(_timeout);
      return response;
    } catch (e) {
      debugPrint('DELETE request error: $e');
      rethrow;
    }
  }
}
