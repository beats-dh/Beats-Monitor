import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/events.dart';
import '../models/websocket_events.dart';
import 'platform_service.dart';

class MonitorNotificationService {
  static const watchedPlayerName = 'Waldir';
  static const _enabledKey = 'monitor_chat_notifications_enabled';

  static bool _initialized = false;
  static bool _enabled = true;
  static String _permission = 'unknown';
  static final Set<String> _shownNotificationTags = <String>{};

  static bool get _nativeNotificationsSupported => Platform.isAndroid;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;

    if (!_nativeNotificationsSupported) {
      _permission = 'unsupported';
      _initialized = true;
      return;
    }

    final status = await Permission.notification.status;
    _permission = status.isGranted ? 'granted' : status.name;
    _initialized = true;
  }

  static bool get enabled => _enabled;
  static bool get isSupported => _nativeNotificationsSupported;
  static String get permission => _permission;

  static bool get _canNotify =>
      _enabled && _nativeNotificationsSupported && _permission == 'granted';

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<bool> enableWithPermission() async {
    await initialize();
    if (!_nativeNotificationsSupported) {
      await setEnabled(false);
      return false;
    }

    final status = await Permission.notification.request();
    _permission = status.isGranted ? 'granted' : status.name;
    if (!status.isGranted) {
      await setEnabled(false);
      return false;
    }

    await setEnabled(true);
    return true;
  }

  static void notifyForChatMessage(ChatMessage message) {
    if (!_canNotify) {
      return;
    }

    if (message.channel == WebSocketEvents.chatHelp) {
      unawaited(_show(
        'Help Channel',
        '${message.player}: ${message.message}',
        'help-${message.timestamp.millisecondsSinceEpoch}-${message.message.hashCode}',
      ));
      return;
    }

    if (message.channel == WebSocketEvents.chatPrivate &&
        _isPrivateMessageToWatchedPlayer(message)) {
      unawaited(_show(
        'Private message to $watchedPlayerName',
        '${message.player}: ${_privateMessageBody(message.message)}',
        'private-$watchedPlayerName-${message.timestamp.millisecondsSinceEpoch}-${message.message.hashCode}',
      ));
    }
  }

  static Future<void> _show(String title, String body, String tag) async {
    if (!_rememberNotificationTag(tag)) {
      return;
    }
    await PlatformService.showNotification(title: title, body: body, tag: tag);
  }

  static bool _rememberNotificationTag(String tag) {
    if (_shownNotificationTags.contains(tag)) {
      return false;
    }

    _shownNotificationTags.add(tag);
    if (_shownNotificationTags.length > 64) {
      _shownNotificationTags.remove(_shownNotificationTags.first);
    }
    return true;
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

    return !_sameName(message.player, watchedPlayerName);
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
}
