import 'dart:html' as html;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/events.dart';
import '../models/websocket_events.dart';

class MonitorNotificationService {
  static const watchedPlayerName = 'Waldir';
  static const _enabledKey = 'monitor_chat_notifications_enabled';

  static bool _initialized = false;
  static bool _enabled = true;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _initialized = true;
  }

  static bool get enabled => _enabled;
  static bool get isSupported => html.Notification.supported;
  static String get permission =>
      isSupported ? html.Notification.permission ?? 'default' : 'unsupported';

  static bool get _canNotify =>
      _enabled && isSupported && permission == 'granted';

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<bool> enableWithPermission() async {
    if (!isSupported) {
      await setEnabled(false);
      return false;
    }

    if (permission != 'granted') {
      final result = await html.Notification.requestPermission();
      if (result != 'granted') {
        await setEnabled(false);
        return false;
      }
    }

    await setEnabled(true);
    return true;
  }

  static void notifyForChatMessage(ChatMessage message) {
    if (!_canNotify) {
      return;
    }

    if (message.channel == WebSocketEvents.chatHelp) {
      _show(
        'Help Channel',
        '${message.player}: ${message.message}',
        'help-${message.timestamp.millisecondsSinceEpoch}-${message.message.hashCode}',
      );
      return;
    }

    if (message.channel == WebSocketEvents.chatPrivate &&
        _isPrivateMessageToWatchedPlayer(message)) {
      _show(
        'Private message to $watchedPlayerName',
        '${message.player}: ${_privateMessageBody(message.message)}',
        'private-$watchedPlayerName-${message.timestamp.millisecondsSinceEpoch}-${message.message.hashCode}',
      );
    }
  }

  static bool _sameName(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();

  static bool _isPrivateMessageToWatchedPlayer(ChatMessage message) {
    final text = message.message.trimLeft();
    final directMatch = RegExp(r'^to\s+([^:]+):\s*(.*)$', caseSensitive: false)
        .firstMatch(text);
    if (directMatch != null) {
      return _sameName(directMatch.group(1) ?? '', watchedPlayerName);
    }

    final legacyMatch =
        RegExp(r'^(.+?)\s+to\s+([^:]+):\s*(.*)$', caseSensitive: false)
            .firstMatch(text);
    if (legacyMatch != null) {
      return _sameName(legacyMatch.group(2) ?? '', watchedPlayerName);
    }

    return false;
  }

  static String _privateMessageBody(String text) {
    final directMatch = RegExp(r'^to\s+([^:]+):\s*(.*)$', caseSensitive: false)
        .firstMatch(text.trimLeft());
    if (directMatch != null) {
      return directMatch.group(2)?.trimLeft() ?? text;
    }

    final legacyMatch =
        RegExp(r'^(.+?)\s+to\s+([^:]+):\s*(.*)$', caseSensitive: false)
            .firstMatch(text.trimLeft());
    if (legacyMatch != null) {
      return legacyMatch.group(3)?.trimLeft() ?? text;
    }

    return text;
  }

  static void _show(String title, String body, String tag) {
    try {
      html.Notification(
        title,
        body: body,
        icon: 'icons/Icon-192.png',
        tag: tag,
      );
    } catch (_) {
      // Browser notification failures should not break live monitoring.
    }
  }
}
