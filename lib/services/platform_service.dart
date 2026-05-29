import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlatformService {
  static const platform = MethodChannel('com.example.beats_monitor/platform');

  static Future<bool> installApk(String filePath) async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await platform.invokeMethod('installApk', {'filePath': filePath});
      return result == true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error installing APK: ${e.message}');
      }
      return false;
    }
  }

  static Future<bool> showNotification({
    required String title,
    required String body,
    required String tag,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await platform.invokeMethod('showNotification', {
        'title': title,
        'body': body,
        'tag': tag,
      });
      return result == true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Error showing notification: ${e.message}');
      }
      return false;
    }
  }
}
