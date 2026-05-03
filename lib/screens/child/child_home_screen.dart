/// ⚠️ DEPRECATED FILE - DO NOT USE
/// This file is no longer part of the active app flow.
/// Use the root version in lib/screens/ instead.
/// Safe to delete after final cleanup phase.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../debug_firebase_state.dart';
import '../../core/config/genet_config.dart';
import '../../core/user_role.dart';
import '../../l10n/app_localizations.dart';
import '../../models/child_model.dart';
import '../../repositories/child_link_status_repository.dart';
import '../../repositories/children_repository.dart';
import '../../repositories/parent_child_sync_repository.dart';
import '../../repositories/pending_link_repository.dart';
import '../../services/night_mode_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/language_switcher.dart';
import '../parent/blocked_apps_times_screen.dart';
import '../content_library_screen.dart';
import '../role_select_screen.dart';
import '../common/school_schedule_screen.dart';

/// Child home: connection status from Firebase only. When parent disconnects, UI updates in place.
class ChildHomeScreen_Deprecated extends StatefulWidget {
  const ChildHomeScreen_Deprecated({super.key});

  @override
  State<ChildHomeScreen_Deprecated> createState() => _ChildHomeScreenState_Deprecated();
}

class _ChildHomeScreenState_Deprecated extends State<ChildHomeScreen_Deprecated> {
  StreamSubscription<SyncedChildData?>? _firebaseSyncSub;

  /// Single source of truth from Firebase: true = connected, false = disconnected, null = loading
  bool? _firebaseConnectionStatus;
  String? _linkedNameForDisplay;

  Timer? _nightCheckTimer;
  String? _lastBlockingStateFingerprint;

  @override
  void initState() {
    super.initState();
    _startFirebaseConnectionListener();
    // Keep schedule-based blocking state fresh without using a second route/overlay flow.
    getUserRole().then((role) {
      if (!mounted || role != kUserRoleChild) return;
      _nightCheckTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _refreshBlockingState(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshBlockingState());
    });
  }

  void _refreshBlockingState() {
    if (!mounted) return;
    setState(() {});
  }

  void _logBlockingState({
    required bool sleepLockActive,
    required bool isVpnActive,
    required bool showNetworkProtectionScreenResult,
  }) {
    final fingerprint =
        '$sleepLockActive|$isVpnActive|$showNetworkProtectionScreenResult';
    if (_lastBlockingStateFingerprint == fingerprint) return;
    _lastBlockingStateFingerprint = fingerprint;
    debugPrint('[GenetBlockLegacy] sleepLockActive=$sleepLockActive');
    debugPrint('[GenetBlockLegacy] isVpnActive=$isVpnActive');
    debugPrint(
      '[GenetBlockLegacy] showNetworkProtectionScreen=$showNetworkProtectionScreenResult',
    );
    if (!showNetworkProtectionScreenResult) {
      debugPrint(
        '[GenetBlockLegacy] screen displayed=none old_screen_triggered=false',
      );
    }
  }

  Future<void> _startFirebaseConnectionListener() async {
    final parentId = await getLinkedParentId();
    final childId = await getLinkedChildId();
    if (parentId == null || parentId.isEmpty || childId == null || childId.isEmpty) {
      developer.log('Child connection status: no parentId or childId, showing disconnected', name: 'Sync');
      if (mounted) setState(() => _firebaseConnectionStatus = false);
      return;
    }
    developer.log('CHILD_READ_PATH = genet_parents/$parentId/children/$childId', name: 'Sync');
    developer.log('CHILD_READ_CHILD_ID = $childId', name: 'Sync');
    if (mounted) setState(() => _firebaseConnectionStatus = null);
    _firebaseSyncSub = watchSyncedChildDataStream(parentId, childId).listen((data) async {
      if (!mounted) return;
      final role = await getUserRole();
      debugPrint('[GenetBlockLegacy] role=$role');
      developer.log('CHILD_LISTENER: child doc updated', name: 'Sync');
      // Only treat as disconnected when Firebase explicitly says so (doc exists and status/parentId indicate disconnect).
      // Do NOT treat null data as disconnect: doc may not exist yet right after connect (race).
      if (data == null) {
        developer.log('Child connection status: no doc yet (loading), not disconnecting', name: 'Sync');
        return;
      }
      final status = data.connectionStatus;
      final docParentId = data.parentId;
      developer.log('CHILD_LISTENER: parentId = $docParentId', name: 'Sync');
      developer.log('CHILD_LISTENER: connectionStatus = $status', name: 'Sync');
      final expectedParentNorm = normalizeIdentifier(parentId);
      final docParentNorm = normalizeIdentifier(data.parentId);
      final parentMatches =
          expectedParentNorm != null && docParentNorm == expectedParentNorm;
      final isConnected =
          isConnectionStatusConnected(data.connectionStatus) && parentMatches;
      if (isConnected) {
        developer.log('Child connected (from Firebase)', name: 'Sync');
        final name = await getLinkedChildName();
        if (mounted) {
          setState(() {
            _firebaseConnectionStatus = true;
            _linkedNameForDisplay = name;
          });
        }
      } else {
        developer.log('Child disconnected (from Firebase) status=$status parentId=$docParentId', name: 'Sync');
        await _handleDisconnected();
      }
    });
  }

  Future<void> _handleDisconnected() async {
    _firebaseSyncSub?.cancel();
    _firebaseSyncSub = null;
    await setLinkedChild(null, null);
    await setLinkedParentId(null);
    if (!mounted) return;
    setState(() {
      _firebaseConnectionStatus = false;
      _linkedNameForDisplay = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקישור להורה הוסר. ניתן להתחבר מחדש.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nightCheckTimer?.cancel();
    _firebaseSyncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final night = context.watch<NightModeService>();
    final sleepLockActive = night.isLoaded && night.config.enabled && night.isNightTimeNow();
    const isVpnActive = true;
    const showNetworkProtectionScreenResult = false;
    _logBlockingState(
      sleepLockActive: sleepLockActive,
      isVpnActive: isVpnActive,
      showNetworkProtectionScreenResult: showNetworkProtectionScreenResult,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.childHomeTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backToRoleSelect,
          onPressed: () async {
            await GenetConfig.commitUserRole(kUserRoleParent);
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const RoleSelectScreen()),
              (route) => false,
            );
          },
        ),
        actions: const [LanguageSwitcher()],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait([
          ChildModel.load(),
          getLinkedChildName(),
          getChildSelfProfile(),
        ]),
        builder: (context, snapshot) {
          final hasData = snapshot.connectionState == ConnectionState.done && snapshot.data != null && snapshot.data!.length >= 3;
          ChildModel? child;
          String? linkedName;
          Map<String, dynamic>? selfProfile;
          if (hasData) {
            child = snapshot.data![0] as ChildModel?;
            linkedName = snapshot.data![1] as String?;
            selfProfile = snapshot.data![2] as Map<String, dynamic>?;
            if (child == null && selfProfile != null && selfProfile.isNotEmpty) {
              final first = selfProfile[kChildSelfProfileFirstName] as String? ?? '';
              final last = selfProfile[kChildSelfProfileLastName] as String? ?? '';
              final name = [first, last].join(' ').trim();
              final age = (selfProfile[kChildSelfProfileAge] as num?)?.toInt() ?? 0;
              final schoolCode = selfProfile[kChildSelfProfileSchoolCode] as String? ?? '';
              if (name.isNotEmpty || age > 0 || schoolCode.isNotEmpty) {
                child = ChildModel(name: name, age: age, schoolCode: schoolCode);
              }
            }
          }
          final isConnected = _firebaseConnectionStatus == true;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isConnected) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Icon(Icons.link, color: AppTheme.primaryBlue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'מחובר להורה',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                              if ((_linkedNameForDisplay ?? linkedName) != null && (_linkedNameForDisplay ?? linkedName)!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    (_linkedNameForDisplay ?? linkedName)!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                    textDirection: TextDirection.rtl,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (!isConnected) ...[
                Card(
                  elevation: 2,
                  color: Colors.amber.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Icon(Icons.link_off, color: Colors.amber.shade800, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'לא מחובר להורה',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: Colors.amber.shade900,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'יש לחבר להורה כדי להפעיל את הניהול',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.amber.shade800,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChildLinkScreen_Deprecated(),
                              ),
                            ).then((_) {
                              if (mounted) setState(() {});
                            });
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('התחברות להורה'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (child != null &&
                  (child.name.isNotEmpty ||
                      child.age > 0 ||
                      child.grade.isNotEmpty ||
                      child.schoolCode.isNotEmpty)) ...[
                _ChildInfoCard(model: child),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              _MenuCard(
                title: l10n.scheduleTomorrow,
                icon: Icons.calendar_today_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SchoolScheduleScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                title: l10n.blockedAppsAndTimes,
                icon: Icons.block_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BlockedAppsTimesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                title: l10n.contentLibraryTitle,
                icon: Icons.menu_book_rounded,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const ContentLibraryScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// Child device: link to parent by scanning QR (payload = 4-digit code) or entering 4-digit manual code.
/// Child must have completed self-identify first; profile is sent to parent via Firestore.
/// (Defined in this library to avoid an import cycle with [ChildHomeScreen_Deprecated].)
class ChildLinkScreen_Deprecated extends StatefulWidget {
  const ChildLinkScreen_Deprecated({super.key});

  @override
  State<ChildLinkScreen_Deprecated> createState() => _ChildLinkScreenState_Deprecated();
}

class _ChildLinkScreenState_Deprecated extends State<ChildLinkScreen_Deprecated> {
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
        await clearChildLinkedPrefsKeepLocalIdentity();
        await GenetConfig.syncToNative();
        if (mounted) setState(() => _linking = false);
        return;
      }
      attemptParentId = parentId;
      attemptChildId = childId;
      attemptLinkCode = code;
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
        await clearChildLinkedPrefsKeepLocalIdentity();
        await GenetConfig.syncToNative();
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
      await setChildLinkStatusLinked(childId);
      GenetConfig.syncToNative();
      if (!mounted) return;
      developer.log('Manual code connection: navigating to child home (parent screen will update via Firebase)', name: 'Sync');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChildHomeScreen_Deprecated()),
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
      await clearChildLinkedPrefsKeepLocalIdentity();
      await GenetConfig.syncToNative();
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

class _ChildInfoCard extends StatelessWidget {
  const _ChildInfoCard({required this.model});
  final ChildModel model;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'פרטי משתמש',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'שם', value: model.name),
            _InfoRow(
              label: 'גיל',
              value: model.age > 0 ? model.age.toString() : '',
            ),
            _InfoRow(label: 'כיתה', value: model.grade),
            _InfoRow(label: 'קוד בית ספר', value: model.schoolCode),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
