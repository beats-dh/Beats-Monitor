import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('penultimaWebCanInstall')
external JSBoolean _penultimaWebCanInstall();

@JS('penultimaWebPromptInstall')
external JSPromise<JSBoolean> _penultimaWebPromptInstall();

class WebAppInstallService {
  static bool get isSupported =>
      web.window.has('penultimaWebPromptInstall');

  static bool get canInstall {
    if (!isSupported) {
      return false;
    }

    try {
      return _penultimaWebCanInstall().toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> promptInstall() async {
    if (!isSupported) {
      return false;
    }

    try {
      return (await _penultimaWebPromptInstall().toDart).toDart;
    } catch (_) {
      return false;
    }
  }
}
