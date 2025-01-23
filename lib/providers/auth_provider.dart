import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  String? _token;

  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;

  Future<void> init() async {
    final success = await AuthService.init();
    _token = AuthService.token;
    _isAuthenticated = success && _token != null;
    notifyListeners();
  }

  Future<(bool, String?)> login(String username, String password) async {
    final result = await AuthService.login(username, password);
    if (result.$1) {
      _token = AuthService.token;
      _isAuthenticated = true;
      notifyListeners();
    }
    return result;
  }

  Future<void> logout() async {
    await AuthService.logout();
    _token = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
