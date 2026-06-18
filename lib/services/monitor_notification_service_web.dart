import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../models/events.dart';
import '../models/websocket_events.dart';

class MonitorNotificationService {
  static const watchedPlayerName = 'Waldir';
  static const _enabledKey = 'monitor_chat_notifications_enabled';
  static const _notificationWorkerScript = 'monitor_notification_worker.js';
  static const _notificationWorkerScope = 'monitor-notifications/';

  static bool _initialized = false;
  static bool _enabled = true;
  static final Set<String> _shownNotificationTags = <String>{};

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _initialized = true;
  }

  static bool get enabled => _enabled;
  static bool get isSupported =>
      web.window.hasProperty('Notification'.toJS).toDart;
  static String get permission =>
      isSupported ? web.Notification.permission : 'unsupported';

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
      final result = (await web.Notification.requestPermission().toDart).toDart;
      if (result != 'granted') {
        await setEnabled(false);
        return false;
      }
    }

    await setEnabled(true);
    unawaited(_registerNotificationWorker());
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

  static Future<void> _show(String title, String body, String tag) async {
    if (!_rememberNotificationTag(tag)) {
      return;
    }

    try {
      if (await _showFromServiceWorker(title, body, tag)) {
        return;
      }

      _showFromPage(title, body, tag);
    } catch (_) {
      // Browser notification failures should not break live monitoring.
    }
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

  static Future<bool> _showFromServiceWorker(
    String title,
    String body,
    String tag,
  ) async {
    try {
      final navigator = web.window.navigator;
      if (!navigator.hasProperty('serviceWorker'.toJS).toDart) {
        return false;
      }

      final registration = await _registerNotificationWorker();

      await registration
          .showNotification(title, _notificationOptions(body, tag))
          .toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<web.ServiceWorkerRegistration> _registerNotificationWorker() {
    final options = web.RegistrationOptions(scope: _notificationWorkerScope);
    return web.window.navigator.serviceWorker
        .register(_notificationWorkerScript.toJS, options)
        .toDart
        .timeout(const Duration(seconds: 3));
  }

  static void _showFromPage(String title, String body, String tag) {
    web.Notification(title, _notificationOptions(body, tag));
  }

  static web.NotificationOptions _notificationOptions(String body, String tag) {
    return web.NotificationOptions(
      body: body,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: tag,
      renotify: true,
      data: web.window.location.href.toJS,
    );
  }
}
