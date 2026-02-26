import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import '../services/night_mode_service.dart';
import '../repositories/night_mode_repository.dart';
import '../repositories/messages_repository.dart';
import 'report_problem_screen.dart';

/// Backup & Support: Export, Import, Report a problem, Contact support.
class BackupSupportScreen extends StatelessWidget {
  const BackupSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('גיבוי ותמיכה')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 16),
            _RoundedCard(
              icon: Icons.upload_file_rounded,
              title: 'ייצוא גיבוי',
              subtitle: 'שמירת נתונים (מצב לילה + הודעות) לקובץ JSON',
              onTap: () => _exportBackup(context),
            ),
            const SizedBox(height: 12),
            _RoundedCard(
              icon: Icons.folder_open_rounded,
              title: 'ייבוא / שחזור גיבוי',
              subtitle: 'טען קובץ גיבוי JSON',
              onTap: () => _importBackup(context),
            ),
            const SizedBox(height: 12),
            _RoundedCard(
              icon: Icons.bug_report_rounded,
              title: 'דיווח על בעיה',
              subtitle: 'גרסה, פרטי מכשיר ולוג לדיבוג',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReportProblemScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _RoundedCard(
              icon: Icons.mail_rounded,
              title: 'צור קשר',
              subtitle: 'שליחת מייל לתמיכה',
              onTap: () => _contactSupport(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    try {
      final nightRepo = NightModeRepository();
      final messagesRepo = MessagesRepository();
      final nightJson = await nightRepo.getConfigForBackup();
      final messagesList = await messagesRepo.getForBackup();
      final backup = {
        'version': 1,
        'nightMode': nightJson,
        'messages': messagesList,
      };
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/genet_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File(path);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(backup),
      );
      final xfile = XFile(path);
      await Share.shareXFiles([xfile], text: 'גיבוי Genet');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הגיבוי יוצא – שתף/שמור את הקובץ')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      final backup = jsonDecode(content) as Map<String, dynamic>;
      final nightRepo = NightModeRepository();
      final messagesRepo = MessagesRepository();
      if (backup['nightMode'] != null) {
        await nightRepo.restoreFromBackup(
            backup['nightMode'] as Map<String, dynamic>);
      }
      if (backup['messages'] != null) {
        await messagesRepo.restoreFromBackup(
            backup['messages'] as List<dynamic>);
      }
      if (!context.mounted) return;
      final service = context.read<NightModeService>();
      await service.refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('הגיבוי שוחזר בהצלחה'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשחזור: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _contactSupport(BuildContext context) {
    // mailto: support@genet.app – show dialog with address for user to copy/send
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('צור קשר'),
        content: const Text(
          'לשליחת מייל לתמיכה:\nsupport@genet.app',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }
}

class _RoundedCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _RoundedCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
