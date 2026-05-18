import '../models/events.dart';

class MonitorNotificationService {
  static const watchedPlayerName = 'Waldir';
  static bool _enabled = true;

  static Future<void> initialize() async {}

  static bool get enabled => _enabled;
  static bool get isSupported => false;
  static String get permission => 'unsupported';

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
  }

  static Future<bool> enableWithPermission() async {
    _enabled = false;
    return false;
  }

  static void notifyForChatMessage(ChatMessage message) {}
}
