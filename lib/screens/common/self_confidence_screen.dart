import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// אח גדול – נושאים: אלימות, פגיעה מינית, חרמות.
class SelfConfidenceScreen extends StatelessWidget {
  const SelfConfidenceScreen({super.key});

  static const List<Map<String, String>> _topics = [
    {'title': 'אלימות', 'icon': 'warning'},
    {'title': 'פגיעה מינית', 'icon': 'shield'},
    {'title': 'חרמות', 'icon': 'group'},
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('אח גדול'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            ..._topics.map((topic) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    title: Text(
                      topic['title']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    trailing: Icon(Icons.arrow_forward_ios,
                        size: 14, color: Colors.grey.shade400),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                '${topic['title']} – תוכן יגיע בקרוב')),
                      );
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
