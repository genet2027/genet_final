import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPinHash = 'genet_pin_hash';
const String _kPinSalt = 'genet_pin_salt';
const String _kPinLegacy = 'genet_parent_pin';

/// אחסון PIN מאובטח: hash + salt (לא טקסט גלוי). תאימות לאחור: אם קיים רק PIN ישן – אימות לפי him ומעבר ל-hash.
class PinStorage {
  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPinHash) != null || prefs.getString(_kPinLegacy)?.isNotEmpty == true;
  }

  static Future<bool> verifyPin(String entered) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_kPinHash);
    final salt = prefs.getString(_kPinSalt);
    if (hash != null && salt != null) {
      final computed = _hash(salt, entered);
      return computed == hash;
    }
    final legacy = prefs.getString(_kPinLegacy) ?? '';
    if (legacy.isNotEmpty && entered == legacy) {
      await savePin(entered);
      await prefs.remove(_kPinLegacy);
      return true;
    }
    if (hash == null && legacy.isEmpty && entered == '1234') {
      await savePin('1234');
      return true;
    }
    return false;
  }

  static Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = base64UrlEncode(List.generate(16, (_) => Random.secure().nextInt(256)));
    final hash = _hash(salt, pin);
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, hash);
  }

  static String _hash(String salt, String pin) {
    final bytes = utf8.encode(salt + pin);
    return sha256.convert(bytes).toString();
  }
}
