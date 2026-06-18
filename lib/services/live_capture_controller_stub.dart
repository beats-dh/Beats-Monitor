import 'package:flutter/material.dart';

class LiveCaptureController extends ChangeNotifier {
  bool get isSupported => false;
  bool get isLive => false;
  bool get isStarting => false;
  String? get errorMessage => null;
  String? get sourceLabel => null;

  Future<void> start() async {}

  void stop() {}

  Widget buildPreview(BuildContext context) {
    return const SizedBox.expand();
  }
}
