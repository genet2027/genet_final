import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../core/user_role.dart';
import 'child_login_screen.dart';
import 'figma_login_screen.dart';

/// Figma-style welcome / role selection before the custom login screen.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const Color _neonGreen = Color(0xFF39FF88);
  static const Color _neonGreenDark = Color(0xFF00C853);

  bool _busy = false;
  late final AnimationController _pulseController;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    debugPrint('[GENET][WELCOME] screen opened');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    final rng = math.Random(17);
    _stars = List.generate(30, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: rng.nextDouble() * 1.1 + 0.35,
        opacity: rng.nextDouble() * 0.4 + 0.2,
        twinkleOffset: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _onParentTap() async {
    if (_busy) return;
    debugPrint('[GENET][WELCOME] parent tapped');
    setState(() => _busy = true);
    try {
      await GenetConfig.commitUserRole(kUserRoleParent);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const FigmaLoginScreen()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onChildTap() async {
    if (_busy) return;
    debugPrint('[GENET][WELCOME] child tapped');
    setState(() => _busy = true);
    try {
      await GenetConfig.commitUserRole(kUserRoleChild);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChildLoginScreen()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFeatureInfo(String logKey, String message) {
    debugPrint('[GENET][WELCOME] info tapped: $logKey');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0D2B5E).withValues(alpha: 0.95),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _WelcomeBackground(),
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
                        vertical: 20,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                return _WelcomeLogoBlock(
                                  pulse: _pulseController,
                                );
                              },
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'הטלפון נשאר חכם.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'הילד נשאר מוגן.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                height: 1.45,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: math.max(40, constraints.maxHeight * 0.08)),
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                return _ParentGlowButton(
                                  pulse: _pulseController,
                                  loading: _busy,
                                  onPressed: _onParentTap,
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            _ChildDarkButton(
                              loading: _busy,
                              onPressed: _onChildTap,
                            ),
                            SizedBox(height: math.max(36, constraints.maxHeight * 0.07)),
                            _WelcomeFeatureIcons(
                              onAppsTap: () => _showFeatureInfo(
                                'apps',
                                'שליטה באפליקציות מסיחות דעת.',
                              ),
                              onSleepTap: () => _showFeatureInfo(
                                'sleep',
                                'מצב שינה עוזר לילד להתנתק בלילה.',
                              ),
                              onScreenTimeTap: () => _showFeatureInfo(
                                'screen_time',
                                'ניהול זמן שימוש בצורה חכמה ובריאה.',
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
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
    );
  }
}

class _WelcomeBackground extends StatelessWidget {
  const _WelcomeBackground();

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
            center: const Alignment(0.15, -0.5),
            radius: 1.15,
            colors: [
              const Color(0xFF1E88E5).withValues(alpha: 0.2),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeLogoBlock extends StatelessWidget {
  const _WelcomeLogoBlock({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final glow = 0.55 + pulse.value * 0.25;
    return Column(
      children: [
        Container(
          width: 150,
          height: 150,
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
                blurRadius: 44,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: _WelcomeScreenState._neonGreen.withValues(alpha: 0.12 * glow),
                blurRadius: 52,
                spreadRadius: 2,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Image.asset(
            'assets/images/genet_logo.png',
            width: 128,
            height: 128,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 10),
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
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: 9,
              shadows: [
                Shadow(
                  color: const Color(0xFF42A5F5).withValues(alpha: 0.8 * glow),
                  blurRadius: 22,
                ),
                Shadow(
                  color: _WelcomeScreenState._neonGreen.withValues(alpha: 0.35 * glow),
                  blurRadius: 28,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ParentGlowButton extends StatelessWidget {
  const _ParentGlowButton({
    required this.pulse,
    required this.loading,
    required this.onPressed,
  });

  final Animation<double> pulse;
  final bool loading;
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
            color: _WelcomeScreenState._neonGreen.withValues(alpha: 0.45 * glow),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _WelcomeScreenState._neonGreenDark.withValues(alpha: 0.25 * glow),
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
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: loading
                    ? [
                        _WelcomeScreenState._neonGreen.withValues(alpha: 0.5),
                        _WelcomeScreenState._neonGreenDark.withValues(alpha: 0.5),
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
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF04210F),
                      ),
                    )
                  : const Text(
                      'אני הורה',
                      style: TextStyle(
                        color: Color(0xFF04210F),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildDarkButton extends StatelessWidget {
  const _ChildDarkButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.2,
            ),
          ),
          child: Center(
            child: Text(
              'אני ילד',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeatureIcons extends StatelessWidget {
  const _WelcomeFeatureIcons({
    required this.onAppsTap,
    required this.onSleepTap,
    required this.onScreenTimeTap,
  });

  final VoidCallback onAppsTap;
  final VoidCallback onSleepTap;
  final VoidCallback onScreenTimeTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _FeatureIconItem(
          icon: Icons.apps_rounded,
          label: 'אפליקציות',
          onTap: onAppsTap,
        ),
        _FeatureIconItem(
          icon: Icons.bedtime_rounded,
          label: 'שינה',
          onTap: onSleepTap,
        ),
        _FeatureIconItem(
          icon: Icons.hourglass_bottom_rounded,
          label: 'זמן מסך',
          onTap: onScreenTimeTap,
        ),
      ],
    );
  }
}

class _FeatureIconItem extends StatelessWidget {
  const _FeatureIconItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                  border: Border.all(
                    color: const Color(0xFF42A5F5).withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF90CAF9),
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          0.35 * math.sin(star.twinkleOffset + twinkle * math.pi * 2);
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
