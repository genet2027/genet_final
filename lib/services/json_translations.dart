import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Loads translations from assets/locales/en.json and he.json.
/// Call [ensureLoaded] before runApp (e.g. in main() async).
/// Use [get] with the current [Locale] to look up strings by key.
class JsonTranslations {
  JsonTranslations._();

  static final Map<String, Map<String, String>> _cache = {};

  static bool get isLoaded => _cache.isNotEmpty;

  /// Load en.json and he.json. Call once at startup.
  static Future<void> ensureLoaded() async {
    if (_cache.isNotEmpty) return;
    await Future.wait([
      _load('en'),
      _load('he'),
    ]);
  }

  static Future<void> _load(String localeCode) async {
    final json = await rootBundle.loadString('assets/locales/$localeCode.json');
    final map = jsonDecode(json) as Map<String, dynamic>;
    _cache[localeCode] = map.map((k, v) => MapEntry(k, v as String));
  }

  /// Returns the string for [key] in [locale], or [key] if missing.
  static String get(Locale locale, String key) {
    final byLocale = _cache[locale.languageCode] ?? _cache['en'];
    return byLocale?[key] ?? key;
  }
}
