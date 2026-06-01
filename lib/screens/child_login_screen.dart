import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'child_onboarding/did_you_know_screen.dart';

/// Official Genet child entry screen — routes into child onboarding.
class ChildLoginScreen extends StatefulWidget {
  const ChildLoginScreen({super.key});

  @override
  State<ChildLoginScreen> createState() => _ChildLoginScreenState();
}

class _ChildLoginScreenState extends State<ChildLoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _neonGreen = Color(0xFF39FF88);
  static const Color _neonGreenDark = Color(0xFF00C853);

  late final AnimationController _pulseController;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    final rng = math.Random(31);
    _stars = List.generate(32, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: rng.nextDouble() * 1.2 + 0.35,
        opacity: rng.nextDouble() * 0.42 + 0.2,
        twinkleOffset: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onStart() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const DidYouKnowScreen(),
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
            const _ChildLoginBackground(),
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
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                return _ChildLogoGlow(pulse: _pulseController);
                              },
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'ילד',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            // Soft Genet color wave inside fixed slogan text.
                            const _ExperimentalChaseSlogan(),
                            const SizedBox(height: 52),
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                return _ChildNeonButton(
                                  pulse: _pulseController,
                                  label: 'בוא נתחיל',
                                  onPressed: _onStart,
                                );
                              },
                            ),
                            SizedBox(
                              height: math.max(48, constraints.maxHeight * 0.08),
                            ),
                            const _ChildFeatureIcons(),
                            const SizedBox(height: 20),
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

/// Soft Genet light wave inside the fixed child-login slogan (color only).
class _ExperimentalChaseSlogan extends StatefulWidget {
  const _ExperimentalChaseSlogan();

  @override
  State<_ExperimentalChaseSlogan> createState() => _ExperimentalChaseSloganState();
}

class _ExperimentalChaseSloganState extends State<_ExperimentalChaseSlogan>
    with SingleTickerProviderStateMixin {
  static final List<Color> _waveColors = [
    Color.lerp(Colors.white, const Color(0xFF90CAF9), 0.78)!,
    Color.lerp(Colors.white, const Color(0xFF4DD0E1), 0.74)!,
    Color.lerp(Colors.white, const Color(0xFF69F0AE), 0.72)!,
    Color.lerp(Colors.white, const Color(0xFFDCE775), 0.68)!,
    Color.lerp(Colors.white, const Color(0xFF90CAF9), 0.78)!,
  ];

  late final AnimationController _waveController;
  late final Animation<double> _waveCurve;

  double _phase = 0;
  double _lastTick = 0;
  double _speed = 1;
  double _targetSpeed = 1;
  Timer? _boostTimer;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7000),
    )..repeat(reverse: true);
    _waveCurve = CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOutSine,
    );
    _waveController.addListener(_advanceWave);
  }

  void _advanceWave() {
    final tick = _waveCurve.value;
    var delta = tick - _lastTick;
    if (delta.abs() > 0.5) {
      delta = delta > 0 ? delta - 1 : delta + 1;
    }
    _lastTick = tick;
    _speed += (_targetSpeed - _speed) * 0.04;
    _phase = (_phase + delta.abs() * _speed) % 1.0;
    setState(() {});
  }

  void _nudgeWaveSpeed() {
    _targetSpeed = 1.18;
    _boostTimer?.cancel();
    _boostTimer = Timer(const Duration(milliseconds: 1200), () {
      _targetSpeed = 1;
    });
  }

  @override
  void dispose() {
    _boostTimer?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  Shader _buildSloganShader(Rect bounds) {
    final eased = Curves.easeInOutSine.transform(_phase);
    final slide = eased * 1.4 - 0.7;
    return LinearGradient(
      begin: Alignment(slide, -0.12),
      end: Alignment(slide + 1.0, 0.12),
      colors: _waveColors,
      stops: const [0.0, 0.3, 0.55, 0.78, 1.0],
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _nudgeWaveSpeed(),
      onPanUpdate: (_) => _nudgeWaveSpeed(),
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (context, _) {
          return ShaderMask(
            shaderCallback: _buildSloganShader,
            blendMode: BlendMode.srcIn,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'הטלפון נשאר חכם.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4),
                Text(
                  'הילד נשאר מוגן.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChildLoginBackground extends StatelessWidget {
  const _ChildLoginBackground();

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
            radius: 1.1,
            colors: [
              const Color(0xFF1E88E5).withValues(alpha: 0.17),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildLogoGlow extends StatelessWidget {
  const _ChildLogoGlow({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final glow = 0.55 + pulse.value * 0.25;
    return Container(
      width: 140,
      height: 140,
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
            color: const Color(0xFF42A5F5).withValues(alpha: 0.42 * glow),
            blurRadius: 44,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: _ChildLoginScreenState._neonGreen.withValues(alpha: 0.14 * glow),
            blurRadius: 52,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Image.asset(
        'assets/images/genet_logo.png',
        width: 112,
        height: 112,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _ChildNeonButton extends StatelessWidget {
  const _ChildNeonButton({
    required this.pulse,
    required this.label,
    required this.onPressed,
  });

  final Animation<double> pulse;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final glow = 0.7 + pulse.value * 0.3;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _ChildLoginScreenState._neonGreen.withValues(alpha: 0.45 * glow),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _ChildLoginScreenState._neonGreenDark.withValues(alpha: 0.25 * glow),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF5DFFA8),
                  Color(0xFF00E676),
                  Color(0xFF00C853),
                ],
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF04210F),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildFeatureIcons extends StatelessWidget {
  const _ChildFeatureIcons();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: const [
        _FeatureIconItem(
          icon: Icons.verified_user_rounded,
          label: 'אמינות',
        ),
        _FeatureIconItem(
          icon: Icons.bedtime_rounded,
          label: 'שינה',
        ),
        _FeatureIconItem(
          icon: Icons.hourglass_bottom_rounded,
          label: 'זמן מסך',
        ),
      ],
    );
  }
}

class _FeatureIconItem extends StatelessWidget {
  const _FeatureIconItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
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
            size: 22,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
