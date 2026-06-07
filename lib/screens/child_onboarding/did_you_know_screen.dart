import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../child_link_screen.dart';

/// Child onboarding: shows one random wellness fact before the next step.
class DidYouKnowScreen extends StatefulWidget {
  const DidYouKnowScreen({super.key});

  static const List<String> facts = [
    'שינה טובה עוזרת למוח לזכור דברים טוב יותר.',
    'ספורט יכול לשפר ריכוז ומצב רוח.',
    'הפסקות קצרות עוזרות למוח ללמוד טוב יותר.',
    'שתיית מים עוזרת לגוף ולמוח לעבוד טוב יותר.',
    'קריאה קבועה מחזקת דמיון ושפה.',
  ];

  @override
  State<DidYouKnowScreen> createState() => _DidYouKnowScreenState();
}

class _DidYouKnowScreenState extends State<DidYouKnowScreen>
    with SingleTickerProviderStateMixin {
  static const Color _neonGreen = Color(0xFF39FF88);

  late final String _fact;
  late final AnimationController _twinkleController;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _fact = DidYouKnowScreen.facts[math.Random().nextInt(DidYouKnowScreen.facts.length)];
    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    final rng = math.Random(53);
    _stars = List.generate(28, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: rng.nextDouble() * 1.0 + 0.35,
        opacity: rng.nextDouble() * 0.38 + 0.18,
        twinkleOffset: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _twinkleController.dispose();
    super.dispose();
  }

  void _onContinue() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const ChildLinkScreen(),
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
            const _DidYouKnowBackground(),
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
                    const SizedBox(height: 16),
                    Text(
                      'הידעת?',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'עובדה קטנה לפני שממשיכים',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    _FactCard(fact: _fact, onContinue: _onContinue),
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

class _DidYouKnowBackground extends StatelessWidget {
  const _DidYouKnowBackground();

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
            center: const Alignment(0.1, -0.45),
            radius: 1.1,
            colors: [
              AppTheme.primaryBlue.withValues(alpha: 0.14),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.fact,
    required this.onContinue,
  });

  final String fact;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(
          color: const Color(0xFF42A5F5).withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF42A5F5).withValues(alpha: 0.18),
            blurRadius: 36,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: _DidYouKnowScreenState._neonGreen.withValues(alpha: 0.08),
            blurRadius: 48,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: const Color(0xFF90CAF9).withValues(alpha: 0.45),
              ),
            ),
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: const Color(0xFF90CAF9).withValues(alpha: 0.95),
              size: 28,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            fact,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 20,
              fontWeight: FontWeight.w500,
              height: 1.55,
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
                        _DidYouKnowScreenState._neonGreen.withValues(alpha: 0.92),
                        const Color(0xFF00C853),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _DidYouKnowScreenState._neonGreen.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'המשך',
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
      final flicker = 0.7 +
          0.3 * math.sin(star.twinkleOffset + twinkle * math.pi * 2);
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
