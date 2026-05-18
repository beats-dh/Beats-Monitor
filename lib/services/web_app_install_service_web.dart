import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('penultimaMonitorCanInstall')
external JSBoolean _penultimaMonitorCanInstall();

@JS('penultimaMonitorPromptInstall')
external JSPromise<JSBoolean> _penultimaMonitorPromptInstall();

class WebAppInstallService {
  static bool get isSupported =>
      web.window.has('penultimaMonitorPromptInstall');

  static bool get canInstall {
    if (!isSupported) {
      return false;
    }

    try {
      return _penultimaMonitorCanInstall().toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> promptInstall() async {
    if (!isSupported) {
      return false;
    }

    try {
      return (await _penultimaMonitorPromptInstall().toDart).toDart;
    } catch (_) {
      return false;
    }
  }
}
