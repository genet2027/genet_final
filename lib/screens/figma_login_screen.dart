import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/auth_flow_helpers.dart';
import '../core/safe_navigation.dart';
import '../core/user_role.dart';
import '../services/google_auth_service.dart';
import 'auth_screen.dart';
import 'role_select_screen.dart';

/// Premium futuristic login UI (Figma-inspired).
class FigmaLoginScreen extends StatefulWidget {
  const FigmaLoginScreen({super.key, this.popOnSuccess = false});

  /// When true, pops back to the caller after auth (e.g. child link gate).
  final bool popOnSuccess;

  @override
  State<FigmaLoginScreen> createState() => _FigmaLoginScreenState();
}

class _FigmaLoginScreenState extends State<FigmaLoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _neonGreen = Color(0xFF39FF88);
  static const Color _neonGreenDark = Color(0xFF00C853);
  static const Color _fieldFill = Color(0x1AFFFFFF);
  static const Color _fieldBorder = Color(0x33FFFFFF);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _loading = false;

  late final AnimationController _pulseController;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    debugPrint('[GENET][LOGIN_UI] custom login screen opened');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    final rng = math.Random(42);
    _stars = List.generate(48, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: rng.nextDouble() * 1.4 + 0.4,
        opacity: rng.nextDouble() * 0.5 + 0.25,
        twinkleOffset: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onLogin() async {
    debugPrint('[GENET][LOGIN_UI] email login tapped');
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('יש למלא אימייל וסיסמה.');
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = await authFlowReloadCurrentUser();
      if (user == null) {
        debugPrint('[GENET][LOGIN_UI] auth error: no current user after sign-in');
        _showError('לא נמצא משתמש מחובר. התחבר מחדש.');
        return;
      }
      if (user.emailVerified) {
        debugPrint('[GENET][LOGIN_UI] auth success');
        if (!mounted) return;
        await routeAfterVerifiedLogin(context, popOnSuccess: widget.popOnSuccess);
        return;
      }
      debugPrint('[GENET][LOGIN_UI] auth success (email verification required)');
      if (!mounted) return;
      await openEmailVerificationAuthScreen(context);
    } on FirebaseAuthException catch (e) {
      debugPrint('[GENET][LOGIN_UI] auth error: ${e.code} ${e.message}');
      _showError(authFlowHebrewAuthError(e));
    } catch (e) {
      debugPrint('[GENET][LOGIN_UI] auth error: $e');
      _showError('שגיאה בלתי צפויה. נסה שוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onForgotPassword() async {
    debugPrint('[GENET][LOGIN_UI] forgot password tapped');
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('הכנס אימייל כדי לאפס סיסמה');
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('שלחנו קישור לאיפוס סיסמה למייל');
    } on FirebaseAuthException catch (e) {
      debugPrint('[GENET][LOGIN_UI] auth error: ${e.code} ${e.message}');
      _showError(authFlowHebrewPasswordResetError(e));
    } catch (e) {
      debugPrint('[GENET][LOGIN_UI] auth error: $e');
      _showError('שגיאה בלתי צפויה. נסה שוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onRegisterTap() async {
    debugPrint('[GENET][LOGIN_UI] register tapped');
    final role = await getUserRole();
    if (!mounted) return;
    if (role != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AuthScreen(role: role, initialLoginMode: false),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const RoleSelectScreen(forRegistration: true),
      ),
    );
  }

  Future<void> _onGoogleSignIn() async {
    debugPrint('[GENET][LOGIN_UI] google login tapped');
    setState(() => _loading = true);
    try {
      await signInWithGoogle();
      final user = await authFlowReloadCurrentUser();
      if (user == null) {
        debugPrint(
          '[GENET][LOGIN_UI] google login failed: no current user after sign-in',
        );
        _showError('לא נמצא משתמש מחובר. התחבר מחדש.');
        return;
      }
      debugPrint('[GENET][LOGIN_UI] google login success');
      if (!mounted) return;
      await routeAfterVerifiedLogin(context, popOnSuccess: widget.popOnSuccess);
    } on GoogleSignInCanceledException {
      debugPrint('[GENET][LOGIN_UI] google login failed: canceled');
    } on FirebaseAuthException catch (e) {
      logGoogleSignInFailure(e);
      _showError(authFlowHebrewGoogleSignInError(e));
    } catch (e) {
      logGoogleSignInFailure(e);
      final message = authFlowHebrewGoogleSignInError(e);
      if (message.isNotEmpty) {
        _showError(message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.canPop(context),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _loading) return;
        safeBackToWelcome(context, 'FigmaLoginScreen');
      },
      child: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _SpaceBackground(),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _StarFieldPainter(
                    stars: _stars,
                    twinkle: _pulseController.value,
                  ),
                );
              },
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = math.min(constraints.maxWidth, 420.0);
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              _GenetLogoGlow(pulse: _pulseController),
                              const SizedBox(height: 24),
                              Text(
                                'ברוכים הבאים',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'התחברות לחשבון Genet',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              _FuturisticField(
                                controller: _emailController,
                                hint: 'אימייל',
                                icon: Icons.mail_outline_rounded,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'יש למלא אימייל';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _FuturisticField(
                                controller: _passwordController,
                                hint: 'סיסמה',
                                icon: Icons.lock_outline_rounded,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _onLogin(),
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    setState(
                                      () => _obscurePassword = !_obscurePassword,
                                    );
                                  },
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'יש למלא סיסמה';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: _loading ? null : _onForgotPassword,
                                  child: Text(
                                    'שכחתי סיסמה?',
                                    style: TextStyle(
                                      color: _neonGreen.withValues(alpha: 0.9),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _NeonLoginButton(
                                loading: _loading,
                                pulse: _pulseController,
                                onPressed: _onLogin,
                              ),
                              const SizedBox(height: 28),
                              TextButton(
                                onPressed: _loading ? null : _onRegisterTap,
                                child: RichText(
                                  textAlign: TextAlign.center,
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.65),
                                      fontSize: 14,
                                    ),
                                    children: const [
                                      TextSpan(text: 'אין לך חשבון? '),
                                      TextSpan(
                                        text: 'הרשמה',
                                        style: TextStyle(
                                          color: _neonGreen,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _OrDivider(),
                              const SizedBox(height: 24),
                              _GoogleSignInButton(
                                onPressed: _loading ? null : _onGoogleSignIn,
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _SpaceBackground extends StatelessWidget {
  const _SpaceBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF050B18),
            Color(0xFF0A1A3A),
            Color(0xFF0D2B5E),
            Color(0xFF061224),
          ],
          stops: [0.0, 0.35, 0.72, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.2, -0.55),
            radius: 1.1,
            colors: [
              const Color(0xFF1E88E5).withValues(alpha: 0.18),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _GenetLogoGlow extends StatelessWidget {
  const _GenetLogoGlow({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final glow = 0.55 + pulse.value * 0.25;
    return Column(
      children: [
        Container(
          width: 162,
          height: 162,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF42A5F5).withValues(alpha: 0.35 * glow),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF42A5F5).withValues(alpha: 0.45 * glow),
                blurRadius: 48,
                spreadRadius: 6,
              ),
              BoxShadow(
                color: const Color(0xFF39FF88).withValues(alpha: 0.12 * glow),
                blurRadius: 60,
                spreadRadius: 3,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Image.asset(
            'assets/images/genet_logo.png',
            width: 140,
            height: 140,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 12),
        ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white,
                Colors.white.withValues(alpha: 0.85),
                const Color(0xFF90CAF9),
              ],
            ).createShader(bounds);
          },
          child: Text(
            'GENET',
            style: TextStyle(
              fontSize: 47,
              fontWeight: FontWeight.w800,
              letterSpacing: 9,
              shadows: [
                Shadow(
                  color: const Color(0xFF42A5F5).withValues(alpha: 0.8 * glow),
                  blurRadius: 24,
                ),
                Shadow(
                  color: const Color(0xFF39FF88).withValues(alpha: 0.35 * glow),
                  blurRadius: 32,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FuturisticField extends StatelessWidget {
  const _FuturisticField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: _FigmaLoginScreenState._neonGreen,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 15,
            ),
            prefixIcon: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.55),
              size: 22,
            ),
            suffixIcon: suffix,
            filled: true,
            fillColor: _FigmaLoginScreenState._fieldFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _FigmaLoginScreenState._fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _FigmaLoginScreenState._neonGreen.withValues(alpha: 0.65),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: Colors.red.shade300.withValues(alpha: 0.8),
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.red.shade300),
            ),
            errorStyle: TextStyle(
              color: Colors.red.shade200,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _NeonLoginButton extends StatelessWidget {
  const _NeonLoginButton({
    required this.loading,
    required this.pulse,
    required this.onPressed,
  });

  final bool loading;
  final Animation<double> pulse;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final glow = 0.7 + pulse.value * 0.3;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _FigmaLoginScreenState._neonGreen.withValues(alpha: 0.45 * glow),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _FigmaLoginScreenState._neonGreenDark.withValues(alpha: 0.25 * glow),
            blurRadius: 12,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: loading
                    ? [
                        _FigmaLoginScreenState._neonGreen.withValues(alpha: 0.5),
                        _FigmaLoginScreenState._neonGreenDark.withValues(alpha: 0.5),
                      ]
                    : const [
                        Color(0xFF5DFFA8),
                        Color(0xFF00E676),
                        Color(0xFF00C853),
                      ],
              ),
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF04210F),
                      ),
                    )
                  : const Text(
                      'התחברות',
                      style: TextStyle(
                        color: Color(0xFF04210F),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final line = Colors.white.withValues(alpha: 0.18);
    return Row(
      children: [
        Expanded(child: Divider(color: line, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'או',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: Divider(color: line, thickness: 1)),
      ],
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: 0.96),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _GoogleLogo(size: 22),
              const SizedBox(width: 12),
              Text(
                'המשך עם Google',
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    const blue = Color(0xFF4285F4);
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);

    final paint = Paint()..style = PaintingStyle.fill;

    paint.color = blue;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 4,
      math.pi / 2,
      true,
      paint,
    );

    paint.color = green;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      math.pi / 4,
      math.pi / 2,
      true,
      paint,
    );

    paint.color = yellow;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      3 * math.pi / 4,
      math.pi / 2,
      true,
      paint,
    );

    paint.color = red;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      5 * math.pi / 4,
      math.pi / 2,
      true,
      paint,
    );

    paint.color = Colors.white;
    canvas.drawCircle(center, r * 0.58, paint);

    paint.color = blue;
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - r * 0.12, r * 0.95, r * 0.24),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.twinkleOffset,
  });

  final double x;
  final double y;
  final double radius;
  final double opacity;
  final double twinkleOffset;
}

class _StarFieldPainter extends CustomPainter {
  _StarFieldPainter({required this.stars, required this.twinkle});

  final List<_Star> stars;
  final double twinkle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final star in stars) {
      final flicker = 0.65 +
          0.35 *
              math.sin(star.twinkleOffset + twinkle * math.pi * 2);
      paint.color = Colors.white.withValues(alpha: star.opacity * flicker);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) {
    return oldDelegate.twinkle != twinkle;
  }
}
