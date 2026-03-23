import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/child_entity.dart';
import '../../repositories/children_repository.dart';
import '../../repositories/parent_child_sync_repository.dart';
import '../../repositories/pending_link_repository.dart';
import '../../theme/app_theme.dart';

/// Parent: create a pending link with 4-digit code, show QR and code, listen for child to connect.
/// When child links, add child to list and show success.
class AddChildByLinkScreen extends StatefulWidget {
  const AddChildByLinkScreen({super.key});

  @override
  State<AddChildByLinkScreen> createState() => _AddChildByLinkScreenState();
}

class _AddChildByLinkScreenState extends State<AddChildByLinkScreen> {
  String? _code;
  String? _parentId;
  String? _error;
  bool _creating = true;
  StreamSubscription? _subscription;
  bool _childAdded = false;

  @override
  void initState() {
    super.initState();
    _createLink();
  }

  Future<void> _createLink() async {
    setState(() {
      _creating = true;
      _error = null;
      _code = null;
      _parentId = null;
    });
    try {
      final parentId = await getOrCreateParentId();
      final code = await createPendingLink(parentId: parentId);
      if (!mounted) return;
      _subscription = listenPendingLink(code, _onChildLinked);
      setState(() {
        _code = code;
        _parentId = parentId;
        _creating = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = 'לא ניתן ליצור חיבור. בדוק חיבור לאינטרנט.';
        });
      }
    }
  }

  void _onChildLinked(ChildEntity child) {
    if (_childAdded) return;
    _childAdded = true;
    _subscription?.cancel();
    final parentId = _parentId;
    final code = _code;
    if (parentId == null || code == null) return;
    final entity = child.copyWith(
      isConnected: true,
      connectionStatus: ChildConnectionStatus.connected,
    );
    addOrUpdateChild(entity).then((_) async {
      await setSelectedChildId(child.childId);
    });
    upsertParentChildDoc(
      parentId: parentId,
      childId: child.childId,
      firstName: child.firstName,
      lastName: child.lastName,
      name: child.name,
      age: child.age,
      schoolCode: child.schoolCode,
      linkCode: code,
    ).then((_) async {
      await setPendingLinkParentId(code, parentId);
      final blocked = await getBlockedPackagesForChild(child.childId);
      final approved = await getExtensionApprovedForChild(child.childId);
      if (blocked.isNotEmpty || approved.isNotEmpty) {
        await syncBlockedPackagesToFirebase(parentId, child.childId, blocked);
        await syncExtensionApprovedToFirebase(parentId, child.childId, approved);
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('הילד ${child.name} התחבר בהצלחה'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('חבר ילד'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _creating && _code == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_code != null) ...[
                      const Text(
                        'הילד יסרוק את ה-QR או יזין את הקוד בן 4 הספרות במכשיר שלו.',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: QrImageView(
                          data: _code!,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'קוד חיבור: $_code',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primaryBlue, width: 2),
                          ),
                          child: Text(
                            _code!,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Card(
                        color: Colors.blue.shade50,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'ממתין שהילד יסרוק או יזין את הקוד...',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
