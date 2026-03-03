import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLocaleLanguageKey = 'genet_locale_language';
const String _kLocaleCountryKey = 'genet_locale_country';

/// Manages the app's locale state and persists the user's language choice.
class LanguageProvider extends ChangeNotifier {
  LanguageProvider() {
    _loadLocale();
  }

  Locale _locale = const Locale('he', 'IL');
  Locale get locale => _locale;

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('he'),
    Locale('ar'),
  ];

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(_kLocaleLanguageKey);
    final country = prefs.getString(_kLocaleCountryKey);
    if (language != null) {
      _locale = Locale(language, country);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale value) async {
    if (_locale == value) return;
    _locale = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleLanguageKey, value.languageCode);
    await prefs.setString(_kLocaleCountryKey, value.countryCode ?? '');
    notifyListeners();
  }

  /// Returns true if the current locale is RTL (Hebrew or Arabic).
  bool get isRtl {
    final code = _locale.languageCode;
    return code == 'he' || code == 'ar';
  }
}
