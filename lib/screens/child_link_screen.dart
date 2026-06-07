import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/safe_navigation.dart';
import '../debug_firebase_state.dart';
import '../core/config/genet_config.dart';
import '../core/firebase_auth_guard.dart';
import '../repositories/child_link_status_repository.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/pending_link_repository.dart';
import '../services/relevant_installed_apps_engine.dart';
import '../features/child_questionnaire/child_questionnaire_repository.dart';
import 'child/child_questionnaire_screen.dart';
import 'child_home_screen.dart';

enum _LinkView { qr, manual, success, error }

enum _ConnectionErrorKind {
  invalidCodeInline,
  invalidQr,
  codeExpired,
}

/// Child device: link to parent by scanning QR (payload = 4-digit code) or entering 4-digit manual code.
/// Child must have completed self-identify first; profile is sent to parent via Firestore.
class ChildLinkScreen extends StatefulWidget {
  const ChildLinkScreen({super.key});

  @override
  State<ChildLinkScreen> createState() => _ChildLinkScreenState();
}

class _ChildLinkScreenState extends State<ChildLinkScreen>
    with TickerProviderStateMixin {
  static const Color _neonGreen = Color(0xFF39FF6A);

  String? _error;
  _ConnectionErrorKind? _errorKind;
  bool _linking = false;
  bool _successHandled = false;
  bool _navigatingAway = false;
  _LinkView _view = _LinkView.qr;

  late final List<TextEditingController> _digitControllers;
  late final List<FocusNode> _digitFocusNodes;
  late final AnimationController _manualEntranceController;
  late final AnimationController _shakeController;
  late final AnimationController _successEntranceController;
  late final AnimationController _errorEntranceController;
  late final Animation<double> _manualFade;
  late final Animation<Offset> _manualSlide;
  late final Animation<double> _successFade;
  late final Animation<double> _successIconScale;
  late final Animation<double> _successGlowPulse;

  @override
  void initState() {
    super.initState();
    _digitControllers = List.generate(4, (_) => TextEditingController());
    _digitFocusNodes = List.generate(4, (_) => FocusNode());

    _manualEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _successEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _successFade = CurvedAnimation(
      parent: _successEntranceController,
      curve: Curves.easeOutCubic,
    );
    _successIconScale = Tween<double>(begin: 0.72, end: 1).animate(
      CurvedAnimation(
        parent: _successEntranceController,
        curve: Curves.easeOutBack,
      ),
    );
    _successGlowPulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.35, end: 1),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1, end: 0.62),
        weight: 55,
      ),
    ]).animate(CurvedAnimation(
      parent: _successEntranceController,
      curve: Curves.easeInOutCubic,
    ));

    _errorEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _manualFade = CurvedAnimation(
      parent: _manualEntranceController,
      curve: Curves.easeOutCubic,
    );
    _manualSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _manualEntranceController,
      curve: Curves.easeOutCubic,
    ));

    if (kDebugMode) {
      try {
        debugFirebaseState();
      } catch (_) {
        // Widget tests / environments without [Firebase.initializeApp]; ignore.
      }
    }
  }

  @override
  void dispose() {
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    _manualEntranceController.dispose();
    _shakeController.dispose();
    _successEntranceController.dispose();
    _errorEntranceController.dispose();
    super.dispose();
  }

  String get _assembledCode =>
      _digitControllers.map((c) => c.text).join();

  bool get _showsInvalidCodeMessage =>
      _error == 'קוד לא תקין או שכבר נוצל';

  bool get _showsManualInlineInvalidCode =>
      _view == _LinkView.manual &&
      (_errorKind == _ConnectionErrorKind.invalidCodeInline ||
          _showsInvalidCodeMessage);

  void _clearError() {
    if (_error == null && _errorKind == null) return;
    setState(() {
      _error = null;
      _errorKind = null;
    });
  }

  void _showFullScreenError(_ConnectionErrorKind kind) {
    setState(() {
      _errorKind = kind;
      _view = _LinkView.error;
      _linking = false;
    });
    _errorEntranceController.forward(from: 0);
  }

  void _dismissFullScreenError({required _LinkView returnTo, bool clearDigits = false}) {
    if (clearDigits) {
      for (final c in _digitControllers) {
        c.clear();
      }
    }
    setState(() {
      _error = null;
      _errorKind = null;
      _view = returnTo;
      _linking = false;
    });
    if (returnTo == _LinkView.manual) {
      _manualEntranceController.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _digitFocusNodes.first.requestFocus();
      });
    }
  }

  Widget _buildConnectionErrorState({
    required String title,
    required String description,
    required String primaryLabel,
    required VoidCallback onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    final fade = CurvedAnimation(
      parent: _errorEntranceController,
      curve: Curves.easeOutCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(fade);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Center(child: _ConnectionErrorIcon()),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.98),
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 40),
              _ConnectParentButton(
                linking: false,
                label: primaryLabel,
                onPressed: onPrimary,
              ),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: onSecondary,
                  child: Text(
                    secondaryLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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

  Widget _buildFullScreenErrorView() {
    switch (_errorKind) {
      case _ConnectionErrorKind.invalidQr:
        return _buildConnectionErrorState(
          title: 'קוד QR לא תקין',
          description: 'נראה שזה לא קוד חיבור של Genet.',
          primaryLabel: 'סרוק שוב',
          onPrimary: () => _dismissFullScreenError(returnTo: _LinkView.qr),
          secondaryLabel: 'הזן קוד ידנית',
          onSecondary: () => _openManualEntry(clearDigits: true),
        );
      case _ConnectionErrorKind.codeExpired:
        return _buildConnectionErrorState(
          title: 'הקוד כבר לא פעיל',
          description: 'בקש מההורה ליצור קוד חיבור חדש ונסה שוב.',
          primaryLabel: 'נסה שוב',
          onPrimary: () => _dismissFullScreenError(returnTo: _LinkView.qr),
          secondaryLabel: 'הזן קוד חדש',
          onSecondary: () => _dismissFullScreenError(
            returnTo: _LinkView.manual,
            clearDigits: true,
          ),
        );
      case _ConnectionErrorKind.invalidCodeInline:
      case null:
        return _buildConnectionErrorState(
          title: 'הקוד שהוזן לא תקין',
          description: 'בדוק את הקוד שקיבלת מההורה ונסה שוב.',
          primaryLabel: 'נסה שוב',
          onPrimary: () => _dismissFullScreenError(returnTo: _LinkView.manual),
          secondaryLabel: 'חזור לסריקת QR',
          onSecondary: () => _dismissFullScreenError(returnTo: _LinkView.qr),
        );
    }
  }

  void _triggerCodeShake() {
    if (_view != _LinkView.manual) return;
    _shakeController.forward(from: 0);
  }

  void _openManualEntry({bool clearDigits = false}) {
    if (clearDigits) {
      for (final c in _digitControllers) {
        c.clear();
      }
    }
    setState(() {
      _error = null;
      _errorKind = null;
      _view = _LinkView.manual;
      _linking = false;
    });
    _manualEntranceController.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _digitFocusNodes.first.requestFocus();
    });
  }

  void _onDigitChanged(int index, String value) {
    _clearError();
    final digit = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digit.length > 1) {
      _digitControllers[index].text = digit[digit.length - 1];
      _digitControllers[index].selection = const TextSelection.collapsed(offset: 1);
    }
    if (digit.isNotEmpty && index < 3) {
      _digitFocusNodes[index + 1].requestFocus();
    }
  }

  KeyEventResult _onDigitKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_digitControllers[index].text.isEmpty && index > 0) {
        _digitFocusNodes[index - 1].requestFocus();
        _digitControllers[index - 1].selection = const TextSelection.collapsed(offset: 1);
      }
    }
    return KeyEventResult.ignored;
  }

  Future<bool> _ensureFirebaseUserForPairing() async {
    if (firebaseUserExists()) return true;
    debugPrint('[GENET][AUTH_GATE] child_missing_firebase_user');
    return false;
  }

  Future<void> _connectWithCode(String code) async {
    developer.log('Manual code connection: entered code=$code', name: 'Sync');
    if (_successHandled || _navigatingAway || _linking) return;
    if (!await _ensureFirebaseUserForPairing()) {
      if (mounted) {
        setState(() => _error = 'לא ניתן להתחבר להורה כרגע. נסה שוב.');
      }
      return;
    }
    if (code.length != 4 || int.tryParse(code) == null) {
      setState(() => _error = 'יש להזין קוד בן 4 ספרות');
      _triggerCodeShake();
      return;
    }
    final pending = await isPendingLink(code);
    developer.log('Manual code connection: matched parent pending=$pending', name: 'Sync');
    if (!pending) {
      setState(() {
        _error = 'קוד לא תקין או שכבר נוצל';
        _linking = false;
        if (_view == _LinkView.manual) {
          _errorKind = _ConnectionErrorKind.invalidCodeInline;
        }
      });
      if (_view == _LinkView.manual) {
        _triggerCodeShake();
      } else {
        _showFullScreenError(_ConnectionErrorKind.codeExpired);
      }
      return;
    }
    setState(() => _error = null);
    developer.log('Manual code connection: connect function called (NOT remove/delete)', name: 'Sync');
    final profile = await getChildSelfProfile();
    final firstName = profile[kChildSelfProfileFirstName] as String? ?? '';
    final lastName = profile[kChildSelfProfileLastName] as String? ?? '';
    final age = (profile[kChildSelfProfileAge] as num?)?.toInt() ?? 0;
    final schoolCode = profile[kChildSelfProfileSchoolCode] as String? ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final childId = (uid == null || uid.trim().isEmpty)
        ? null
        : (uid.trim().startsWith('c_') ? uid.trim() : 'c_${uid.trim()}');
    debugPrint('[GENET][QR_FIX] auth uid: $uid');
    debugPrint('[GENET][QR_FIX] canonical childId for link: $childId');
    if (childId == null || childId.isEmpty) {
      debugPrint('[GENET][PAIRING] child_requires_authenticated_user');
      if (mounted) {
        if (_view == _LinkView.qr) {
          _showFullScreenError(_ConnectionErrorKind.invalidQr);
        } else {
          setState(() {
            _linking = false;
            _error = kDebugMode
                ? 'child_requires_authenticated_user (missing auth-bound childId)'
                : 'לא ניתן לזהות את מכשיר הילד. נסה שוב.';
          });
        }
      }
      return;
    }
    debugPrint('[GENET][PAIRING_FIX] auth uid: $uid');
    debugPrint(
      '[GENET][PAIRING_FIX] canonical childId used for QR link: $childId',
    );
    await persistAuthBoundLocalChildId(childId);
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
      debugPrint(
        '[GENET][PAIRING_FIX] canonical parent child path: $childDocPath',
      );
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
      debugPrint('[GENET][PAIRING] child_link_prefs_saved_after_canonical');
      final canonicalData = await readCanonicalChildData(parentId, childId);
      debugPrint(
        '[GENET][QUESTIONNAIRE_DEBUG][LINK] parentId=$parentId',
      );
      debugPrint(
        '[GENET][QUESTIONNAIRE_DEBUG][LINK] childIdWrittenToCanonical=$childId',
      );
      debugPrint(
        '[GENET][QUESTIONNAIRE_DEBUG][LINK] canonicalPath=genet_parents/$parentId/children/$childId',
      );
      debugPrint(
        '[GENET][QUESTIONNAIRE_DEBUG][LINK] canonicalData=$canonicalData',
      );
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
      debugPrint('[GENET][ONBOARDING] child_pairing_completed');
      developer.log('Manual code connection: success, navigating to child home', name: 'Sync');
      await _showSuccessAndNavigate();
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
    } finally {
      if (mounted &&
          _linking &&
          !_successHandled &&
          _view != _LinkView.success) {
        setState(() => _linking = false);
      }
    }
  }

  Future<void> _showSuccessAndNavigate() async {
    if (_successHandled || _navigatingAway) return;
    _successHandled = true;
    if (!mounted) return;

    setState(() {
      _linking = false;
      _view = _LinkView.success;
    });

    await _successEntranceController.forward(from: 0);
    if (!mounted || _navigatingAway) return;

    await Future<void>.delayed(const Duration(milliseconds: 1350));
    if (!mounted || _navigatingAway) return;

    _navigatingAway = true;
    final childId = await resolveAuthBoundChildQuestionnaireId();
    final questionnaireCompleted = childId != null
        ? await isChildQuestionnaireCompleted(childId)
        : false;
    if (!mounted) return;

    if (questionnaireCompleted) {
      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildHomeScreen');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const ChildHomeScreen()),
        (route) => false,
      );
      return;
    }

    debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildQuestionnaireScreen');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (ctx) => ChildQuestionnaireScreen(
          onCompleted: () {
            if (!ctx.mounted) return;
            debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildHomeScreen');
            Navigator.pushReplacement(
              ctx,
              MaterialPageRoute<void>(builder: (_) => const ChildHomeScreen()),
            );
          },
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _submitManualCode() async {
    final input = _assembledCode.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (input.length != 4) {
      setState(() => _error = 'יש להזין קוד בן 4 ספרות');
      _triggerCodeShake();
      return;
    }
    await _connectWithCode(input);
  }

  String? _parseLinkCodeFromQrPayload(String payload) {
    final trimmed = payload.trim();
    if (trimmed.length == 4 && int.tryParse(trimmed) != null) {
      return trimmed;
    }
    try {
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      final code = (map['k'] ??
              map['code'] ??
              map['linkCode'] ??
              '')
          .toString()
          .trim();
      if (code.length == 4 && int.tryParse(code) != null) {
        return code;
      }
    } catch (_) {}
    return null;
  }

  void _onQrDetected(String raw, {String? displayValue}) {
    if (_successHandled || _navigatingAway || _linking) return;

    debugPrint('[GENET][QR_FIX] raw qr value: $raw');
    debugPrint('[GENET][QR_FIX] display qr value: $displayValue');

    final linkCode = _parseLinkCodeFromQrPayload(raw);
    debugPrint('[GENET][QR_FIX] parsed linkCode: $linkCode');

    if (linkCode == null) {
      _showFullScreenError(_ConnectionErrorKind.invalidQr);
      return;
    }

    debugPrint('[GENET][QR_FIX] calling _connectWithCode');
    unawaited(_connectWithCode(linkCode));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF020B2D),
        extendBodyBehindAppBar: true,
        appBar: _view == _LinkView.success
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: Icon(
                    _view == _LinkView.manual
                        ? Icons.arrow_back_rounded
                        : Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                  onPressed: () {
                    if (_view == _LinkView.manual) {
                      _clearError();
                      setState(() => _view = _LinkView.qr);
                      return;
                    }
                    if (_view == _LinkView.error) {
                      _dismissFullScreenError(returnTo: _LinkView.qr);
                      return;
                    }
                    safeBackToWelcome(context, 'ChildLinkScreen');
                  },
                ),
                title: Text(
                  _view == _LinkView.manual
                      ? 'הזנת קוד'
                      : _view == _LinkView.error
                          ? 'שגיאת חיבור'
                          : 'חיבור להורה',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _ChildLinkBackground(),
            SafeArea(
              child: _view == _LinkView.success
                  ? _buildSuccessView()
                  : _view == _LinkView.error
                      ? _buildFullScreenErrorView()
                      : _linking && _view == _LinkView.qr
                      ? Center(
                          child: CircularProgressIndicator(
                            color: _neonGreen.withValues(alpha: 0.9),
                            strokeWidth: 2.5,
                          ),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _view == _LinkView.manual
                              ? _buildManualEntryView(
                                  key: const ValueKey('manual'),
                                )
                              : _buildQrScanView(key: const ValueKey('qr')),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return FadeTransition(
      opacity: _successFade,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _successEntranceController,
                builder: (context, _) {
                  return Transform.scale(
                    scale: _successIconScale.value,
                    child: _LinkSuccessIcon(
                      glowStrength: _successGlowPulse.value,
                    ),
                  );
                },
              ),
              const SizedBox(height: 36),
              Text(
                'החיבור הושלם בהצלחה',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.98),
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'המכשיר מחובר כעת להורה',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrScanView({Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'חבר את המכשיר לחשבון ההורה',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'סרוק את קוד ה-QR שההורה מציג',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.62),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _neonGreen.withValues(alpha: 0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.14),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: MobileScanner(
                onDetect: (capture) {
                  if (_successHandled || _navigatingAway || _linking) return;
                  final barcodes = capture.barcodes;
                  for (final b in barcodes) {
                    final raw = b.rawValue;
                    final display = b.displayValue;
                    final payload = (raw != null && raw.isNotEmpty)
                        ? raw
                        : display;
                    if (payload == null || payload.isEmpty) continue;
                    _onQrDetected(payload, displayValue: display);
                    return;
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 28),
          TextButton(
            onPressed: _openManualEntry,
            child: Text(
              'הזנת קוד ידני',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntryView({Key? key}) {
    final shakeOffset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));

    return FadeTransition(
      key: key,
      opacity: _manualFade,
      child: SlideTransition(
        position: _manualSlide,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'הזן קוד חיבור',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.98),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'בקש מההורה את קוד החיבור והזן אותו כאן',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 40),
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(shakeOffset.value, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    return Padding(
                      padding: EdgeInsets.only(left: index < 3 ? 12 : 0),
                      child: _CodeDigitBox(
                        controller: _digitControllers[index],
                        focusNode: _digitFocusNodes[index],
                        hasError: _error != null,
                        onChanged: (v) => _onDigitChanged(index, v),
                        onKeyEvent: (node, event) => _onDigitKey(index, event),
                      ),
                    );
                  }),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                if (_showsManualInlineInvalidCode) ...[
                  Text(
                    'הקוד שהוזן לא תקין',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'בדוק את הקוד שקיבלת מההורה ונסה שוב.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade300.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ] else
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
              ],
              const SizedBox(height: 36),
              _ConnectParentButton(
                linking: _linking,
                onPressed: _linking ? null : _submitManualCode,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _linking
                    ? null
                    : () {
                        _clearError();
                        setState(() => _view = _LinkView.qr);
                      },
                child: Text(
                  'חזור לסריקת QR',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildLinkBackground extends StatelessWidget {
  const _ChildLinkBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF020B2D),
                Color(0xFF041B52),
                Color(0xFF072E80),
              ],
            ),
          ),
        ),
        CustomPaint(
          painter: _ChildLinkStarPainter(stars: _childLinkStars),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, 0.75),
              radius: 1.1,
              colors: [
                const Color(0xFF39FF6A).withValues(alpha: 0.06),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final List<_ChildLinkStar> _childLinkStars = List.generate(22, (i) {
  final rng = math.Random(17 + i);
  return _ChildLinkStar(
    x: rng.nextDouble(),
    y: rng.nextDouble(),
    radius: rng.nextDouble() * 0.9 + 0.35,
    opacity: rng.nextDouble() * 0.22 + 0.06,
  );
});

class _ChildLinkStar {
  const _ChildLinkStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
  });

  final double x;
  final double y;
  final double radius;
  final double opacity;
}

class _ChildLinkStarPainter extends CustomPainter {
  const _ChildLinkStarPainter({required this.stars});

  final List<_ChildLinkStar> stars;

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: star.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChildLinkStarPainter oldDelegate) => false;
}

class _CodeDigitBox extends StatelessWidget {
  const _CodeDigitBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onKeyEvent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final FocusOnKeyEventCallback onKeyEvent;

  static const Color _neonGreen = Color(0xFF39FF6A);

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    final borderColor = hasError
        ? Colors.red.shade300.withValues(alpha: 0.85)
        : focused
            ? _neonGreen.withValues(alpha: 0.9)
            : _neonGreen.withValues(alpha: 0.42);

    return SizedBox(
      width: 62,
      height: 72,
      child: Focus(
        onKeyEvent: onKeyEvent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: borderColor, width: 1.6),
            boxShadow: [
              BoxShadow(
                color: (hasError ? Colors.red : _neonGreen)
                    .withValues(alpha: focused ? 0.28 : 0.14),
                blurRadius: focused ? 18 : 12,
              ),
            ],
          ),
          child: Center(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.98),
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionErrorIcon extends StatelessWidget {
  const _ConnectionErrorIcon();

  static const Color _neonGreen = Color(0xFF39FF6A);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              boxShadow: [
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.16),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(
                color: _neonGreen.withValues(alpha: 0.28),
                width: 1.2,
              ),
            ),
          ),
          Icon(
            Icons.warning_amber_rounded,
            size: 40,
            color: Colors.white.withValues(alpha: 0.88),
          ),
        ],
      ),
    );
  }
}

class _LinkSuccessIcon extends StatelessWidget {
  const _LinkSuccessIcon({required this.glowStrength});

  final double glowStrength;

  static const Color _neonGreen = Color(0xFF39FF6A);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.38 * glowStrength),
                  blurRadius: 36 * glowStrength + 12,
                  spreadRadius: 4 * glowStrength,
                ),
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.18 * glowStrength),
                  blurRadius: 56,
                ),
              ],
            ),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF39FF6A),
                  Color(0xFF1BE85B),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              size: 52,
              color: Colors.white.withValues(alpha: 0.98),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectParentButton extends StatelessWidget {
  const _ConnectParentButton({
    required this.linking,
    required this.onPressed,
    this.label,
  });

  final bool linking;
  final VoidCallback? onPressed;
  final String? label;

  static const Color _neonGreen = Color(0xFF39FF6A);
  static const Color _neonGreenDark = Color(0xFF1BE85B);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: onPressed == null
                    ? [
                        _neonGreen.withValues(alpha: 0.45),
                        _neonGreenDark.withValues(alpha: 0.45),
                      ]
                    : const [_neonGreen, _neonGreenDark],
              ),
              boxShadow: onPressed == null
                  ? null
                  : [
                      BoxShadow(
                        color: _neonGreen.withValues(alpha: 0.38),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: Center(
              child: linking
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: const Color(0xFF020B2D).withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'מאמת קוד...',
                          style: TextStyle(
                            color: const Color(0xFF020B2D).withValues(alpha: 0.9),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label ?? 'התחבר להורה',
                      style: const TextStyle(
                        color: Color(0xFF020B2D),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
