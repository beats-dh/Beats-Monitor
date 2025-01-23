import 'dart:io';
import 'package:flutter/services.dart';

class PlatformService {
  static const platform = MethodChannel('com.example.beats_monitor/platform');

  static Future<bool> installApk(String filePath) async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await platform.invokeMethod('installApk', {'filePath': filePath});
      return result == true;
    } on PlatformException catch (e) {
      print('Error installing APK: ${e.message}');
      return false;
    }
  }
}
