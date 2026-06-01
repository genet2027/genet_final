import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../child_home_screen.dart';

/// Final child onboarding screen after the questionnaire — UI only.
class ChildQuestionnaireCompleteScreen extends StatefulWidget {
  const ChildQuestionnaireCompleteScreen({super.key});

  @override
  State<ChildQuestionnaireCompleteScreen> createState() =>
      _ChildQuestionnaireCompleteScreenState();
}

class _ChildQuestionnaireCompleteScreenState
    extends State<ChildQuestionnaireCompleteScreen>
    with TickerProviderStateMixin {
  static const Color _neonGreen = Color(0xFF39FF88);
  static const Color _cardBorder = Color(0xFF42A5F5);

  late final AnimationController _twinkleController;
  late final AnimationController _entranceController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();

    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _fadeIn = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));
    _entranceController.forward();

    final rng = math.Random(89);
    _stars = List.generate(26, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: rng.nextDouble() * 0.95 + 0.32,
        opacity: rng.nextDouble() * 0.36 + 0.17,
        twinkleOffset: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _twinkleController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _onContinueToGenet() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const ChildHomeScreen(),
      ),
      (_) => false,
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
            const _CompleteBackground(),
            AnimatedBuilder(
              animation: _twinkleController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _StarFieldPainter(
                    stars: _stars,
                    twinkle: _twinkleController.value,
                  ),
                );
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  children: [
                    const Spacer(),
                    FadeTransition(
                      opacity: _fadeIn,
                      child: SlideTransition(
                        position: _slideUp,
                        child: _SuccessCard(onContinue: _onContinueToGenet),
                      ),
                    ),
                    const Spacer(flex: 2),
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

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(26, 32, 26, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(
          color: _ChildQuestionnaireCompleteScreenState._cardBorder
              .withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: _ChildQuestionnaireCompleteScreenState._cardBorder
                .withValues(alpha: 0.16),
            blurRadius: 38,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: _ChildQuestionnaireCompleteScreenState._neonGreen
                .withValues(alpha: 0.1),
            blurRadius: 48,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: const Color(0xFF90CAF9).withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: _ChildQuestionnaireCompleteScreenState._neonGreen
                      .withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              color: _ChildQuestionnaireCompleteScreenState._neonGreen
                  .withValues(alpha: 0.95),
              size: 30,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'הכול מוכן 🚀',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.96),
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'התשובות שלך נשמרו כחלק מהסיפור שלך ב-Genet.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'עכשיו ההורה שלך יכיר אותך קצת יותר טוב.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onContinue,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _ChildQuestionnaireCompleteScreenState._neonGreen
                            .withValues(alpha: 0.92),
                        const Color(0xFF00C853),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _ChildQuestionnaireCompleteScreenState._neonGreen
                            .withValues(alpha: 0.26),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'המשך ל-Genet',
                      style: TextStyle(
                        color: Color(0xFF04210F),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteBackground extends StatelessWidget {
  const _CompleteBackground();

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
            center: const Alignment(0.0, -0.35),
            radius: 1.08,
            colors: [
              AppTheme.primaryBlue.withValues(alpha: 0.15),
              Colors.transparent,
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
      final flicker =
          0.7 + 0.3 * math.sin(star.twinkleOffset + twinkle * math.pi * 2);
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
