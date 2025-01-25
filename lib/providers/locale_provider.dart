import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _localeKey = 'selected_locale';
  final SharedPreferences _prefs;
  Locale _locale;

  LocaleProvider(this._prefs) : _locale = Locale(_prefs.getString(_localeKey) ?? 'pt');

  Locale get locale => _locale;

  Future<void> setLocale(String languageCode) async {
    _locale = Locale(languageCode);
    await _prefs.setString(_localeKey, languageCode);
    notifyListeners();
  }

  bool get isPortuguese => _locale.languageCode == 'pt';
  bool get isEnglish => _locale.languageCode == 'en';
}
