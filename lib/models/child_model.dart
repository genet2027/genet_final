import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _kChildProfileKey = 'genet_child_profile';

/// Child profile: name, age, grade, school code. Stored in SharedPreferences.
class ChildModel {
  const ChildModel({
    this.name = '',
    this.age = 0,
    this.grade = '',
    this.schoolCode = '',
  });

  final String name;
  final int age;
  final String grade;
  final String schoolCode;

  Map<String, dynamic> toJson() => {
        'name': name,
        'age': age,
        'grade': grade,
        'schoolCode': schoolCode,
      };

  static ChildModel fromJson(Map<String, dynamic> json) {
    return ChildModel(
      name: json['name'] as String? ?? '',
      age: (json['age'] as num?)?.toInt() ?? 0,
      grade: json['grade'] as String? ?? '',
      schoolCode: json['schoolCode'] as String? ?? '',
    );
  }

  static Future<ChildModel?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kChildProfileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ChildModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(ChildModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kChildProfileKey, jsonEncode(model.toJson()));
  }
}
