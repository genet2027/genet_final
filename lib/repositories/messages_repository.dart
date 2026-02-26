import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_message.dart';

const String kMessagesListKey = 'genet_messages_list';

class MessagesRepository {
  Future<List<AppMessage>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kMessagesListKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AppMessage.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> add(AppMessage message) async {
    final list = await getAll();
    list.insert(0, message);
    await _save(list);
  }

  Future<void> _save(List<AppMessage> list) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(kMessagesListKey, encoded);
  }

  Future<void> replaceAll(List<AppMessage> messages) async {
    await _save(messages);
  }

  /// For backup: list of message maps.
  Future<List<Map<String, dynamic>>> getForBackup() async {
    final list = await getAll();
    return list.map((e) => e.toJson()).toList();
  }

  /// Restore from backup.
  Future<void> restoreFromBackup(List<dynamic> list) async {
    final messages = list
        .map((e) => AppMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    await replaceAll(messages);
  }
}
