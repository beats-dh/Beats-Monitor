import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class LiveCaptureController extends ChangeNotifier {
  late final web.HTMLVideoElement _videoElement;
  late final String _viewType;
  web.MediaStream? _stream;
  bool _isLive = false;
  bool _isStarting = false;
  bool _disposed = false;
  String? _errorMessage;
  String? _sourceLabel;

  LiveCaptureController() {
    _viewType =
        'beats-monitor-live-video-${DateTime.now().microsecondsSinceEpoch}';
    _videoElement = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..controls = false
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000000';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _videoElement,
    );
  }

  bool get isSupported {
    try {
      return web.window.navigator.mediaDevices.has('getDisplayMedia');
    } catch (_) {
      return false;
    }
  }

  bool get isLive => _isLive;
  bool get isStarting => _isStarting;
  String? get errorMessage => _errorMessage;
  String? get sourceLabel => _sourceLabel;

  Future<void> start() async {
    if (_isStarting) {
      return;
    }

    final mediaDevices = web.window.navigator.mediaDevices;
    if (!mediaDevices.has('getDisplayMedia')) {
      _setError('Screen capture is not available in this browser.');
      return;
    }

    _isStarting = true;
    _errorMessage = null;
    _notify();

    try {
      _stopCurrentStream(notify: false);
      final stream = await mediaDevices
          .getDisplayMedia(
            web.DisplayMediaStreamOptions(
              video: true.toJS,
              audio: false.toJS,
            ),
          )
          .toDart;

      if (_disposed) {
        for (final track in stream.getTracks().toDart) {
          track.stop();
        }
        return;
      }

      _stream = stream;
      _videoElement.srcObject = stream;
      await _videoElement.play().toDart;

      final videoTracks = stream.getVideoTracks().toDart;
      _sourceLabel = videoTracks.isNotEmpty ? videoTracks.first.label : null;
      for (final track in videoTracks) {
        track.onended = ((web.Event event) => stop()).toJS;
      }

      _isLive = true;
    } catch (error) {
      _stopCurrentStream(notify: false);
      _errorMessage = _friendlyError(error);
    } finally {
      _isStarting = false;
      _notify();
    }
  }

  void stop() {
    _stopCurrentStream();
  }

  Widget buildPreview(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

  void _stopCurrentStream({bool notify = true}) {
    final current = _stream;
    if (current != null) {
      for (final track in current.getTracks().toDart) {
        track.onended = null;
        track.stop();
      }
    }

    _stream = null;
    _videoElement.srcObject = null;
    _isLive = false;
    _sourceLabel = null;

    if (notify) {
      _notify();
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    _notify();
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('NotAllowedError') ||
        text.contains('Permission denied')) {
      return 'Screen capture was cancelled or blocked.';
    }
    if (text.contains('NotFoundError')) {
      return 'No screen or window source was available.';
    }
    return 'Could not start the live view.';
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopCurrentStream(notify: false);
    super.dispose();
  }
}
