import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_theme.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  String _version = '';
  String _debugLog = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final v = '${info.version}+${info.buildNumber}';
    final buf = StringBuffer();
    buf.writeln('Genet Debug Info');
    buf.writeln('App version: $v');
    buf.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('---');
    if (mounted) {
      setState(() {
        _version = v;
        _debugLog = buf.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('דיווח על בעיה')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Card(
              title: 'גרסת האפליקציה',
              child: Text(_version.isEmpty ? '...' : _version, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
            _Card(
              title: 'פרטי מכשיר',
              child: Text(
                Platform.operatingSystemVersion.isEmpty ? '...' : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('לוג לדיבוג (העתק)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.darkBlue)),
                        TextButton.icon(
                          onPressed: _debugLog.isEmpty ? null : () {
                            Clipboard.setData(ClipboardData(text: _debugLog));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('הועתק ללוח')));
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('העתק'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(_debugLog.isEmpty ? '...' : _debugLog, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade800)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.darkBlue)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
