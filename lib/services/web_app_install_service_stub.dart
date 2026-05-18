class WebAppInstallService {
  static bool get isSupported => false;
  static bool get canInstall => false;

  static Future<bool> promptInstall() async {
    return false;
  }
}
