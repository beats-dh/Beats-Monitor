import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:beats_monitor/services/auth_service.dart';
import 'package:beats_monitor/services/config_service.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 10);

  static Future<bool> _refreshTokenIfNeeded() async {
    if (AuthService.hasCredentials) {
      return await AuthService.refreshToken();
    }
    return false;
  }

  static Future<Map<String, String>> _getHeaders() async {
    await _refreshTokenIfNeeded();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${AuthService.token}',
    };
  }

  static Future<http.Response> get(String endpoint) async {
    final headers = await _getHeaders();
    try {
      final response = await http.get(
        Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
        headers: headers,
      ).timeout(_timeout);

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
      final response = await http.post(
        Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
        headers: headers,
        body: body != null ? json.encode(body) : null,
      ).timeout(_timeout);

      if (response.statusCode == 401) {
        // Token expirado, tenta renovar
        if (await AuthService.refreshToken()) {
          // Tenta novamente com o novo token
          return await post(endpoint, body: body);
        }
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
      final response = await http.put(
        Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
        headers: headers,
        body: body != null ? json.encode(body) : null,
      ).timeout(_timeout);
      return response;
    } catch (e) {
      debugPrint('PUT request error: $e');
      rethrow;
    }
  }

  static Future<http.Response> delete(String endpoint) async {
    final headers = await _getHeaders();
    try {
      final response = await http.delete(
        Uri.parse('${ConfigService().apiBaseUrl}/$endpoint'),
        headers: headers,
      ).timeout(_timeout);
      return response;
    } catch (e) {
      debugPrint('DELETE request error: $e');
      rethrow;
    }
  }
}
