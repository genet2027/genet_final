import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/safe_navigation.dart';
import '../debug_firebase_state.dart';
import '../core/config/genet_config.dart';
import '../core/firebase_auth_guard.dart';
import '../core/user_role.dart';
import '../models/child_entity.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/pending_link_repository.dart';
import 'figma_login_screen.dart';

/// Parent: create a pending link with 4-digit code, show QR and code, listen for child to connect.
/// When child links, add child to list and show success.
class AddChildByLinkScreen extends StatefulWidget {
  const AddChildByLinkScreen({super.key});

  @override
  State<AddChildByLinkScreen> createState() => _AddChildByLinkScreenState();
}

class _AddChildByLinkScreenState extends State<AddChildByLinkScreen> {
  static const Color _neonGreen = Color(0xFF39FF6A);

  String? _code;
  String? _parentId;
  String? _error;
  bool _creating = true;
  StreamSubscription? _subscription;
  bool _childAdded = false;
  bool _linkInProgress = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugFirebaseState();
    }
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
      try {
        requireFirebaseUser();
      } catch (_) {
        // Fall through to auth redirect.
      }
      if (!firebaseUserIsAuthenticated()) {
        debugPrint('[GENET][AUTH_GATE] parent_redirect_to_login');
        if (!mounted) return;
        await GenetConfig.commitUserRole(kUserRoleParent);
        if (!mounted) return;
        final authed = await Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(
            builder: (_) => const FigmaLoginScreen(popOnSuccess: true),
          ),
        );
        if (!mounted) return;
        if (authed != true) {
          setState(() {
            _creating = false;
            _error = 'נדרשת התחברות הורה ליצירת קוד חיבור.';
          });
          return;
        }
        return _createLink();
      }
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
      if (e is FirebaseException) {
        debugPrint('[GENET][LINK_CHILD][ERROR] code=${e.code} message=${e.message}');
      } else {
        debugPrint('[GENET][LINK_CHILD][ERROR] unknown=$e');
      }
      if (mounted) {
        setState(() {
          _creating = false;
          _error = kDebugMode
              ? 'Error: ${e is FirebaseException ? e.code : e.toString()}'
              : 'לא ניתן ליצור חיבור. בדוק חיבור לאינטרנט.';
        });
      }
    }
  }

  void _onChildLinked(ChildEntity child) {
    if (_childAdded || _linkInProgress) return;
    _linkInProgress = true;
    unawaited(_completeParentSideLink(child));
  }

  Future<void> _completeParentSideLink(ChildEntity child) async {
    final code = _code;
    if (code == null) {
      _linkInProgress = false;
      return;
    }
    final entity = child.copyWith(
      isConnected: true,
      connectionStatus: ChildConnectionStatus.connected,
    );
    try {
      final parentId = await getOrCreateParentId();
      await addOrUpdateChild(entity);
      await setSelectedChildId(child.childId);
      await upsertParentChildDoc(
        parentId: parentId,
        childId: child.childId,
        firstName: child.firstName,
        lastName: child.lastName,
        name: child.name,
        age: child.age,
        schoolCode: child.schoolCode,
        linkCode: code,
      );
      final ok = await waitForCanonicalChildConnected(
        parentId: parentId,
        childId: child.childId,
      );
      if (!ok) {
        final snap = await readCanonicalChildData(parentId, child.childId);
        final active = snap != null && canonicalChildDataActiveForParent(snap, parentId);
        if (!active) {
          await removeChild(child.childId);
          if (snap != null) {
            try {
              await setChildConnectionStatusFirebase(
                parentId,
                child.childId,
                'disconnected',
              );
            } catch (e, st) {
              debugPrint('[GENET][LINK_CHILD] orphan canonical disconnect: $e $st');
            }
          }
        }
        if (mounted) {
          setState(() {
            _error = kDebugMode
                ? 'Canonical link not confirmed (timeout). Try again.'
                : 'החיבור לא אושר. נסה שוב.';
          });
        }
        _subscription?.cancel();
        _linkInProgress = false;
        return;
      }
      debugPrint('[GENET][PAIRING] canonical_confirmed_parent_child');
      await setPendingLinkParentId(code, parentId);
      final blocked = await getBlockedPackagesForChild(child.childId);
      final approved = await getExtensionApprovedForChild(child.childId);
      if (blocked.isNotEmpty || approved.isNotEmpty) {
        await syncBlockedPackagesToFirebase(parentId, child.childId, blocked);
        await syncExtensionApprovedToFirebase(parentId, child.childId, approved);
      }
      if (!mounted) {
        _linkInProgress = false;
        return;
      }
      _subscription?.cancel();
      _childAdded = true;
      _linkInProgress = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הילד ${child.name} התחבר בהצלחה'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      try {
        await removeChild(child.childId);
      } catch (_) {}
      try {
        final pid = _parentId;
        if (pid != null) {
          final snap = await readCanonicalChildData(pid, child.childId);
          if (snap != null) {
            await setChildConnectionStatusFirebase(pid, child.childId, 'disconnected');
          }
        }
      } catch (e2, st2) {
        debugPrint('[GENET][LINK_CHILD] catch cleanup: $e2 $st2');
      }
      if (e is FirebaseException) {
        debugPrint('[GENET][LINK_CHILD][ERROR] code=${e.code} message=${e.message}');
      } else {
        debugPrint('[GENET][LINK_CHILD][ERROR] unknown=$e');
      }
      if (mounted) {
        setState(() {
          _error = kDebugMode
              ? 'Error: ${e is FirebaseException ? e.code : e.toString()}'
              : 'שגיאה בחיבור. נסה שוב.';
        });
      }
      _subscription?.cancel();
      _linkInProgress = false;
    }
  }

  Future<void> _copyCode() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'הקוד הועתק',
          textAlign: TextAlign.center,
        ),
        backgroundColor: const Color(0xFF041B52),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
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
        backgroundColor: const Color(0xFF020B2D),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.88),
            ),
            onPressed: () => safeBackToParentShell(context, 'AddChildByLinkScreen'),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _ParentLinkBackground(),
            SafeArea(
              child: _creating && _code == null
                  ? Center(
                      child: CircularProgressIndicator(
                        color: _neonGreen.withValues(alpha: 0.9),
                        strokeWidth: 2.5,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            _ErrorBanner(message: _error!),
                            const SizedBox(height: 20),
                          ],
                          if (_code != null) ...[
                            const _GenetLogoHeader(),
                            const SizedBox(height: 28),
                            Text(
                              'חבר מכשיר חדש',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.97),
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'בקש מהילד לסרוק את הקוד או להזין אותו ידנית',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.55,
                              ),
                            ),
                            const SizedBox(height: 32),
                            _QrGlassCard(code: _code!),
                            const SizedBox(height: 28),
                            Text(
                              'קוד חיבור',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ConnectionCodeDisplay(code: _code!),
                            const SizedBox(height: 28),
                            _CopyCodeButton(onPressed: _copyCode),
                            const SizedBox(height: 24),
                            if (_linkInProgress)
                              Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _neonGreen.withValues(alpha: 0.75),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              'הקוד תקף לזמן מוגבל מטעמי אבטחה',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.42),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                          ],
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

class _ParentLinkBackground extends StatelessWidget {
  const _ParentLinkBackground();

  static const List<Color> _gradientColors = [
    Color(0xFF020B2D),
    Color(0xFF041B52),
    Color(0xFF072E80),
  ];

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
              colors: _gradientColors,
            ),
          ),
        ),
        CustomPaint(
          painter: _LinkStarFieldPainter(
            stars: _linkStars,
          ),
        ),
      ],
    );
  }
}

final List<_LinkStar> _linkStars = List.generate(22, (i) {
  final rng = math.Random(42 + i);
  return _LinkStar(
    x: rng.nextDouble(),
    y: rng.nextDouble(),
    radius: rng.nextDouble() * 0.9 + 0.35,
    opacity: rng.nextDouble() * 0.22 + 0.06,
  );
});

class _LinkStar {
  const _LinkStar({
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

class _LinkStarFieldPainter extends CustomPainter {
  const _LinkStarFieldPainter({required this.stars});

  final List<_LinkStar> stars;

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
  bool shouldRepaint(covariant _LinkStarFieldPainter oldDelegate) => false;
}

class _GenetLogoHeader extends StatelessWidget {
  const _GenetLogoHeader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF42A5F5).withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: const Color(0xFF39FF6A).withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/genet_logo.png',
            width: 72,
            height: 84,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.red.shade100,
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }
}

class _QrGlassCard extends StatelessWidget {
  const _QrGlassCard({required this.code});

  final String code;

  static const Color _neonGreen = Color(0xFF39FF6A);
  static const Color _glowBlue = Color(0xFF42A5F5);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(
            color: _glowBlue.withValues(alpha: 0.38),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: _glowBlue.withValues(alpha: 0.16),
              blurRadius: 28,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _neonGreen.withValues(alpha: 0.72),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.12),
                  blurRadius: 32,
                ),
              ],
            ),
            child: QrImageView(
              data: code,
              version: QrVersions.auto,
              size: 208,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionCodeDisplay extends StatelessWidget {
  const _ConnectionCodeDisplay({required this.code});

  final String code;

  static const Color _neonGreen = Color(0xFF39FF6A);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: _neonGreen.withValues(alpha: 0.22),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          code,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.98),
            fontSize: 38,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
            fontFamily: 'monospace',
            shadows: [
              Shadow(
                color: _neonGreen.withValues(alpha: 0.45),
                blurRadius: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyCodeButton extends StatelessWidget {
  const _CopyCodeButton({required this.onPressed});

  final VoidCallback onPressed;

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
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_neonGreen, _neonGreenDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.42),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: _neonGreen.withValues(alpha: 0.18),
                  blurRadius: 36,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'העתק קוד',
                style: TextStyle(
                  color: Color(0xFF020B2D),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
