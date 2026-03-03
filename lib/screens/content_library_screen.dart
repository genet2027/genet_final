import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/child_model.dart';
import '../theme/app_theme.dart';

const String _kContentViewLogKey = 'genet_content_view_log';

/// ספריית תכנים: תכנים לימודיים וספרי קריאה (עם לוג צפייה) + תיקיית "אח גדול".
class ContentLibraryScreen extends StatefulWidget {
  const ContentLibraryScreen({super.key});

  @override
  State<ContentLibraryScreen> createState() => _ContentLibraryScreenState();
}

class _ContentLibraryScreenState extends State<ContentLibraryScreen> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('ספריית תכנים')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('תכנים לימודיים וספרי קריאה'),
            const SizedBox(height: 8),
            FutureBuilder<ChildModel?>(
              future: ChildModel.load(),
              builder: (context, snapshot) {
                final child = snapshot.data;
                final childAge = child?.age ?? 0;
                final childGender = _childGender(child);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLearningAndReadingSection(childGender),
                    const SizedBox(height: 24),
                    _contentCard(
                      title: 'אח גדול',
                      subtitle: 'תכנים חינוכיים רגישים מותאמי גיל',
                      icon: Icons.psychology_rounded,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (context) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: Scaffold(
                                appBar: AppBar(
                                  title: const Text('אח גדול'),
                                  leading: IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                                body: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: _buildBigBrotherSection(childAge, childGender),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      textDirection: TextDirection.rtl,
    );
  }

  /// מין הילד סינון תכנים (ברירת מחדל male).
  static String _childGender(ChildModel? child) => 'male';

  /// targetGender: "all" | "male" | "female". מוצג אם all או תואם למין הילד.
  static bool _visibleByGender(String targetGender, String childGender) {
    return targetGender == 'all' || targetGender == childGender;
  }

  Widget _buildLearningAndReadingSection(String childGender) {
    const items = [
      ('ספרים לימודיים', 'מקצועות הלימוד', 'all'),
      ('ספרי קריאה', 'סיפורים וספרים מותאמים לגיל', 'all'),
      ('ספרי קריאה לבנות', 'סיפורים מותאמים לנקבה', 'female'),
      ('ספרי קריאה לבנים', 'סיפורים מותאמים לזכר', 'male'),
    ];
    return Column(
      children: items
          .where((e) => _visibleByGender(e.$3, childGender))
          .map((e) => _contentCard(
                title: e.$1,
                subtitle: e.$2,
                icon: Icons.menu_book_rounded,
                onTap: () => _logViewAndShow(e.$1),
              ))
          .toList(),
    );
  }

  /// קבוצות גיל ב"אח גדול" – כל topic: (title, targetGender).
  static const List<({int minAge, int maxAge, String label, List<(String, String)> topics})> _bigBrotherAgeGroups = [
    (minAge: 7, maxAge: 10, label: 'גיל 7-10 (כיתות א׳-ד׳)', topics: [
      ('חברות טובה', 'all'),
      ('התמודדות עם חרם', 'all'),
      ('גבולות אישיים בסיסיים', 'all'),
      ('אלימות (הסברה בסיסית)', 'all'),
      ('בטיחות אישית', 'all'),
      ('בטיחות אישית – לבנות', 'female'),
      ('גבולות בסיסיים – לבנים', 'male'),
    ]),
    (minAge: 11, maxAge: 13, label: 'גיל 11-13 (כיתות ה׳-ז׳)', topics: [
      ('חרם חברתי מתקדם', 'all'),
      ('אלימות פיזית ומילולית', 'all'),
      ('רמאות ולחץ חברתי', 'all'),
      ('גבולות גוף והגנה עצמית', 'all'),
      ('אחריות אישית', 'all'),
      ('התמודדות חברתית – לבנות', 'female'),
      ('התמודדות חברתית – לבנים', 'male'),
    ]),
    (minAge: 13, maxAge: 14, label: 'גיל 13-14 (כיתות ז׳-ח׳)', topics: [
      ('יחסים חברתיים מורכבים', 'all'),
      ('לחץ חברתי', 'all'),
      ('אלימות במערכות יחסים', 'all'),
      ('פגיעה מינית (הסברה והגנה)', 'all'),
      ('קבלת החלטות', 'all'),
      ('הסברה מינית – לבנות', 'female'),
      ('הסברה מינית – לבנים', 'male'),
    ]),
    (minAge: 15, maxAge: 20, label: 'גיל 15-20', topics: [
      ('חינוך מיני מותאם גיל', 'all'),
      ('מס הכנסה (הסבר בסיסי)', 'all'),
      ('ביטוח לאומי', 'all'),
      ('צבא', 'all'),
      ('שירות לאומי', 'all'),
      ('אחריות אזרחית', 'all'),
      ('הכנה לצבא – לבנים', 'male'),
      ('שירות לאומי – לבנות', 'female'),
    ]),
  ];

  Widget _buildBigBrotherSection(int childAge, String childGender) {
    final visibleGroups = _bigBrotherAgeGroups
        .where((g) => childAge >= g.minAge && childAge <= g.maxAge)
        .toList();
    if (visibleGroups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'אין תכנים מוגדרים לגיל שלך. עדכן את גילך בהגדרת ילד.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          textDirection: TextDirection.rtl,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: visibleGroups.expand((group) {
        final visibleTopics = group.topics
            .where((t) => _visibleByGender(t.$2, childGender))
            .toList();
        if (visibleTopics.isEmpty) return <Widget>[];
        return [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              group.label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
          ...visibleTopics.map((t) => _contentCard(
                title: t.$1,
                subtitle: 'תוכן חינוכי מותאם גיל',
                icon: Icons.psychology_rounded,
                onTap: () {},
              )),
        ];
      }).toList(),
    );
  }

  Widget _contentCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logViewAndShow(String bookTitle) async {
    final now = DateTime.now();
    final entry = {
      'book': bookTitle,
      'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    };
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kContentViewLogKey);
    List<Map<String, dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
      } catch (_) {}
    }
    list.add(entry);
    await prefs.setString(_kContentViewLogKey, jsonEncode(list));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('נשמר: $bookTitle – ${entry['date']} ${entry['time']}')),
      );
    }
  }
}
