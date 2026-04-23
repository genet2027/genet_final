import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../debug_firebase_state.dart';
import '../core/config/genet_config.dart';
import '../repositories/child_link_status_repository.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/pending_link_repository.dart';
import '../services/relevant_installed_apps_engine.dart';
import 'child_home_screen.dart';

/// Child device: link to parent by scanning QR (payload = 4-digit code) or entering 4-digit manual code.
/// Child must have completed self-identify first; profile is sent to parent via Firestore.
class ChildLinkScreen extends StatefulWidget {
  const ChildLinkScreen({super.key});

  @override
  State<ChildLinkScreen> createState() => _ChildLinkScreenState();
}

class _ChildLinkScreenState extends State<ChildLinkScreen> {
  final _codeController = TextEditingController();
  String? _error;
  bool _linking = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugFirebaseState();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _connectWithCode(String code) async {
    developer.log('Manual code connection: entered code=$code', name: 'Sync');
    if (code.length != 4 || int.tryParse(code) == null) {
      setState(() => _error = 'יש להזין קוד בן 4 ספרות');
      return;
    }
    final pending = await isPendingLink(code);
    developer.log('Manual code connection: matched parent pending=$pending', name: 'Sync');
    if (!pending) {
      setState(() => _error = 'קוד לא תקין או שכבר נוצל');
      return;
    }
    setState(() => _error = null);
    developer.log('Manual code connection: connect function called (NOT remove/delete)', name: 'Sync');
    final profile = await getChildSelfProfile();
    final firstName = profile[kChildSelfProfileFirstName] as String? ?? '';
    final lastName = profile[kChildSelfProfileLastName] as String? ?? '';
    final age = (profile[kChildSelfProfileAge] as num?)?.toInt() ?? 0;
    final schoolCode = profile[kChildSelfProfileSchoolCode] as String? ?? '';
    final existingId = await getLocalChildId();
    final childId = existingId ?? generateChildId();
    final name = [firstName, lastName].join(' ').trim();
    String? attemptParentId;
    String? attemptChildId;
    String? attemptLinkCode;
    setState(() => _linking = true);
    try {
      await writeChildProfileToPendingLink(
        code,
        childId,
        firstName,
        lastName,
        age,
        schoolCode,
      );
      String? parentId;
      await for (final id in watchPendingLinkParentId(code)) {
        if (id != null && id.isNotEmpty) {
          parentId = id;
          break;
        }
      }
      if (parentId == null || !mounted) {
        developer.log('Manual code connection: parentId not received (timeout?)', name: 'Sync');
        if (mounted) setState(() => _linking = false);
        return;
      }
      attemptParentId = parentId;
      attemptChildId = childId;
      attemptLinkCode = code;
      // Update the SAME child document the Child screen reads (genet_parents/{parentId}/children/{childId}).
      // This ensures connection state is written even if parent device did not run _onChildLinked yet.
      final childDocPath = 'genet_parents/$parentId/children/$childId';
      developer.log('CHILD_DOC_ID = $childId', name: 'Sync');
      developer.log('CHILD_DOC_PATH = $childDocPath', name: 'Sync');
      developer.log('CHILD_DOC_BEFORE_CONNECT = $childDocPath (will write parentId + connected)', name: 'Sync');
      developer.log('CHILD_CONNECT_WRITE_PARENT_ID = $parentId', name: 'Sync');
      developer.log('CHILD_CONNECT_WRITE_STATUS = connected', name: 'Sync');
      await upsertParentChildDoc(
        parentId: parentId,
        childId: childId,
        firstName: firstName,
        lastName: lastName,
        name: name.isEmpty ? 'ילד' : name,
        age: age,
        schoolCode: schoolCode,
        linkCode: code,
      );
      developer.log('CHILD_DOC_AFTER_CONNECT = written (parentId + connectionStatus)', name: 'Sync');
      final canonicalOk = await waitForCanonicalChildConnected(
        parentId: parentId,
        childId: childId,
      );
      if (!canonicalOk) {
        developer.log(
          'Manual code connection: canonical child doc not confirmed (timeout or invalid)',
          name: 'Sync',
        );
        await reconcileFalseRemoteConnectedAfterIncompleteChildLink(
          parentId: parentId,
          childId: childId,
          linkCode: code,
        );
        if (mounted) {
          setState(() {
            _linking = false;
            _error = kDebugMode
                ? 'Canonical link not confirmed (timeout). Try again.'
                : 'החיבור לא אושר אצל ההורה. נסה שוב.';
          });
        }
        return;
      }
      if (!mounted) return;
      await setLinkedParentId(parentId);
      await setLinkedChild(
        childId,
        name.isEmpty ? 'ילד' : name,
        firstName: firstName,
        lastName: lastName,
      );
      debugPrint('[RELEVANT_APPS] parentId=$parentId');
      debugPrint('[RELEVANT_APPS] childId=$childId');
      if (Platform.isAndroid) {
        await RelevantInstalledAppsEngine.instance.refreshFromFullDeviceScanAndSync(
          childId: childId,
          parentId: parentId,
          mutationSource: 'child_link',
          syncTrigger: 'child_linked',
        );
      }
      await setChildLinkStatusLinked(childId);
      GenetConfig.syncToNative();
      if (!mounted) return;
      developer.log('Manual code connection: navigating to child home (parent screen will update via Firebase)', name: 'Sync');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
      );
    } catch (e) {
      if (attemptParentId != null &&
          attemptChildId != null &&
          attemptLinkCode != null) {
        await reconcileFalseRemoteConnectedAfterIncompleteChildLink(
          parentId: attemptParentId,
          childId: attemptChildId,
          linkCode: attemptLinkCode,
        );
      }
      if (e is FirebaseException) {
        debugPrint('[GENET][LINK_CHILD][ERROR] code=${e.code} message=${e.message}');
      } else {
        debugPrint('[GENET][LINK_CHILD][ERROR] unknown=$e');
      }
      if (mounted) {
        setState(() {
          _linking = false;
          _error = kDebugMode
              ? 'Error: ${e is FirebaseException ? e.code : e.toString()}'
              : 'שגיאה בחיבור. נסה שוב.';
        });
      }
    }
  }

  Future<void> _submitManualCode() async {
    final input = _codeController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (input.length != 4) {
      setState(() => _error = 'יש להזין קוד בן 4 ספרות');
      return;
    }
    await _connectWithCode(input);
  }

  void _onQrDetected(String raw) {
    String code = raw.trim();
    if (code.length == 4 && int.tryParse(code) != null) {
      _connectWithCode(code);
      return;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      code = (map['k'] ?? map['code'] ?? '').toString().trim();
      if (code.length == 4 && int.tryParse(code) != null) {
        _connectWithCode(code);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('חיבור להורה'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _linking
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'חבר את המכשיר לחשבון ההורה',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'סרוק את קוד ה-QR שההורה מציג, או הזן את הקוד הידני.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'סריקת QR',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: MobileScanner(
                          onDetect: (capture) {
                            final barcodes = capture.barcodes;
                            for (final b in barcodes) {
                              final raw = b.rawValue;
                              if (raw != null && raw.isNotEmpty) {
                                _onQrDetected(raw);
                                return;
                              }
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'הזנת קוד ידני',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        hintText: 'הזן 4 ספרות',
                        border: const OutlineInputBorder(),
                        errorText: _error,
                        counterText: '',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) => _submitManualCode(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'קוד בן 4 ספרות בלבד',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _submitManualCode,
                      child: const Text('חבר להורה'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
