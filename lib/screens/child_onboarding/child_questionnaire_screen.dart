import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../child_link_screen.dart';

enum _CinematicPhase {
  normal,
  fadingContent,
  movingToCenter,
  centeredPause,
  movingUp,
  showingMessage,
}

/// Child onboarding questionnaire — UI only, answers kept in memory.
class ChildQuestionnaireScreen extends StatefulWidget {
  const ChildQuestionnaireScreen({super.key});

  @override
  State<ChildQuestionnaireScreen> createState() =>
      _ChildQuestionnaireScreenState();
}

class _ChildQuestionnaireScreenState extends State<ChildQuestionnaireScreen>
    with TickerProviderStateMixin {
  static const Color _neonGreen = Color(0xFF39FF88);
  static const Color _cardBorder = Color(0xFF42A5F5);
  static const String _logoAsset = 'assets/images/genet_logo.png';
  static const ColorFilter _dimLogoFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  static const List<_Question> _questions = [
    _Question(
      text: 'מה אתה הכי אוהב לעשות בזמן הפנוי?',
      options: [
        _AnswerOption('⚽', 'כדורגל'),
        _AnswerOption('🏀', 'כדורסל'),
        _AnswerOption('🎮', 'משחקים'),
        _AnswerOption('🎵', 'מוזיקה'),
        _AnswerOption('📚', 'לקרוא'),
        _AnswerOption('🎨', 'לצייר'),
      ],
    ),
    _Question(
      text: 'איזה אוכל אתה הכי אוהב?',
      options: [
        _AnswerOption('🍕', 'פיצה'),
        _AnswerOption('🍔', 'המבורגר'),
        _AnswerOption('🍝', 'פסטה'),
        _AnswerOption('🥙', 'שווארמה'),
        _AnswerOption('🍣', 'סושי'),
      ],
    ),
    _Question(
      text: 'מה המקצוע שאתה הכי אוהב?',
      options: [
        _AnswerOption('➗', 'מתמטיקה'),
        _AnswerOption('🔬', 'מדעים'),
        _AnswerOption('💻', 'מחשבים'),
        _AnswerOption('🎨', 'אומנות'),
        _AnswerOption('📖', 'ספרות'),
      ],
    ),
    _Question(
      text: 'מה החיה האהובה עליך?',
      options: [
        _AnswerOption('🦁', 'אריה'),
        _AnswerOption('🐶', 'כלב'),
        _AnswerOption('🐱', 'חתול'),
        _AnswerOption('🐬', 'דולפין'),
        _AnswerOption('🦅', 'נשר'),
      ],
    ),
    _Question(
      text: 'מה החלום שלך?',
      options: [
        _AnswerOption('⚽', 'ספורטאי'),
        _AnswerOption('🎵', 'מוזיקאי'),
        _AnswerOption('💻', 'טכנולוגיה'),
        _AnswerOption('✈️', 'לטייל בעולם'),
        _AnswerOption('🚀', 'אסטרונאוט'),
      ],
    ),
  ];

  late final AnimationController _twinkleController;
  late final AnimationController _waveController;
  late final AnimationController _logoFillController;
  Animation<double>? _fillAnimation;
  late final List<_Star> _stars;

  int _currentIndex = 0;
  int? _selectedOptionIndex;
  double _displayedFillProgress = 0;
  bool _isLogoFillAnimating = false;
  _CinematicPhase _phase = _CinematicPhase.normal;

  static const Alignment _sideLogoAlign = Alignment(-0.94, -0.52);

  late final AnimationController _contentFadeController;
  late final AnimationController _logoMoveController;
  late final AnimationController _logoLiftController;
  late final AnimationController _textFadeController;
  late final AnimationController _buttonFadeController;

  static const Duration _fillDuration = Duration(milliseconds: 900);

  /// Answers stored in memory only: question index → option label.
  final Map<int, String> _answers = {};

  static const double _minColorStrength = 0.85;
  static const double _maxColorStrength = 1.0;
  static const double _maxMuteOverlay = 0.07;

  static ColorFilter _saturationFilter(double colorStrength) {
    const r = 0.2126;
    const g = 0.7152;
    const b = 0.0722;
    final s = colorStrength.clamp(_minColorStrength, _maxColorStrength);
    final inv = 1 - s;
    return ColorFilter.matrix(<double>[
      inv * r + s, inv * g, inv * b, 0, 0,
      inv * r, inv * g + s, inv * b, 0, 0,
      inv * r, inv * g, inv * b + s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  /// Completed answers / total questions, animated in sync with logo fill.
  double get _renderedFillProgress =>
      _fillAnimation?.value ?? _displayedFillProgress;

  double get _answerColorProgress => _renderedFillProgress;

  double get _colorStrength =>
      _minColorStrength +
      _answerColorProgress.clamp(0.0, 1.0) *
          (_maxColorStrength - _minColorStrength);

  double get _muteOverlayAlpha =>
      (1 - _answerColorProgress.clamp(0.0, 1.0)) * _maxMuteOverlay;

  int get _totalQuestions => _questions.length;
  bool get _hasSelection => _selectedOptionIndex != null;
  bool get _isLastQuestion => _currentIndex >= _totalQuestions - 1;

  @override
  void initState() {
    super.initState();
    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _logoFillController = AnimationController(
      vsync: this,
      duration: _fillDuration,
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();

    _contentFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _logoMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoLiftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _textFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _buttonFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    final rng = math.Random(71);
    _stars = List.generate(20, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: rng.nextDouble() * 0.75 + 0.25,
        opacity: rng.nextDouble() * 0.22 + 0.08,
        twinkleOffset: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _twinkleController.dispose();
    _waveController.dispose();
    _logoFillController.dispose();
    _contentFadeController.dispose();
    _logoMoveController.dispose();
    _logoLiftController.dispose();
    _textFadeController.dispose();
    _buttonFadeController.dispose();
    super.dispose();
  }

  Future<void> _animateLogoFillTo(double target) async {
    final begin = _displayedFillProgress;
    _logoFillController.duration = _fillDuration;
    _fillAnimation = Tween<double>(
      begin: begin,
      end: target,
    ).animate(CurvedAnimation(
      parent: _logoFillController,
      curve: Curves.easeInOutCubic,
    ));
    await _logoFillController.forward(from: 0);
    if (mounted) {
      _displayedFillProgress = target;
    }
  }

  Future<void> _runCinematicEnding() async {
    setState(() {
      _isLogoFillAnimating = false;
      _phase = _CinematicPhase.fadingContent;
    });
    await _contentFadeController.forward(from: 0);
    if (!mounted) return;

    setState(() => _phase = _CinematicPhase.movingToCenter);
    await _logoMoveController.forward(from: 0);
    if (!mounted) return;

    setState(() => _phase = _CinematicPhase.centeredPause);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    setState(() => _phase = _CinematicPhase.movingUp);
    await _logoLiftController.forward(from: 0);
    if (!mounted) return;

    setState(() => _phase = _CinematicPhase.showingMessage);
    await _textFadeController.forward(from: 0);
    if (!mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    await _buttonFadeController.forward(from: 0);
  }

  static const Alignment _centerLogoAlign = Alignment.center;

  double _topLogoAlignY(BoxConstraints constraints) {
    final short = constraints.maxHeight < 560;
    return short ? -0.80 : -0.76;
  }

  Alignment _cinematicLogoAlignment(BoxConstraints constraints) {
    final moveT =
        Curves.easeInOutCubic.transform(_logoMoveController.value.clamp(0.0, 1.0));
    final liftT =
        Curves.easeInOutCubic.transform(_logoLiftController.value.clamp(0.0, 1.0));

    if (liftT > 0) {
      return Alignment.lerp(
        _centerLogoAlign,
        Alignment(0, _topLogoAlignY(constraints)),
        liftT,
      )!;
    }

    return Alignment.lerp(_sideLogoAlign, _centerLogoAlign, moveT)!;
  }

  double _cinematicLogoScale() {
    final moveT =
        Curves.easeInOutCubic.transform(_logoMoveController.value.clamp(0.0, 1.0));
    return 1 + moveT * 0.12;
  }

  bool get _showCinematicSparkles {
    if (_phase.index < _CinematicPhase.movingToCenter.index) return false;
    if (_phase == _CinematicPhase.centeredPause) return true;
    if (_phase == _CinematicPhase.movingUp) {
      return _logoLiftController.value >= 0.4;
    }
    return _logoMoveController.value >= 0.75 ||
        _phase == _CinematicPhase.showingMessage;
  }

  double _messageAreaTop(BoxConstraints constraints) {
    final short = constraints.maxHeight < 560;
    final logoScale = short ? 1.06 : 1.12;
    const logoHeight = 124.0;
    return 8 + logoHeight * logoScale + (short ? 18 : 26);
  }

  bool get _showSideLogo =>
      _phase == _CinematicPhase.normal ||
      _phase == _CinematicPhase.fadingContent;

  bool get _showCinematicOverlay =>
      _phase.index >= _CinematicPhase.movingToCenter.index;
  void _selectOption(int index) {
    setState(() => _selectedOptionIndex = index);
  }

  Future<void> _onContinue() async {
    if (!_hasSelection || _isLogoFillAnimating) return;

    final question = _questions[_currentIndex];
    _answers[_currentIndex] = question.options[_selectedOptionIndex!].label;
    final targetFill = _answers.length / _totalQuestions;
    final finishing = _isLastQuestion;

    _isLogoFillAnimating = true;
    final fillFuture = _animateLogoFillTo(targetFill);
    if (mounted) setState(() {});
    await fillFuture;
    if (!mounted) return;

    if (finishing) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
      if (!mounted) return;
      await _runCinematicEnding();
      return;
    }

    setState(() {
      _isLogoFillAnimating = false;
      _currentIndex++;
      _selectedOptionIndex = null;
    });
  }

  void _finishQuestionnaire() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const ChildLinkScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final questionProgress = (_currentIndex + 1) / _totalQuestions;
    final inCinematic = _phase != _CinematicPhase.normal;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _QuestionnaireBackground(),
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
            AnimatedBuilder(
              animation: _logoFillController,
              builder: (context, _) {
                final colorStrength = _colorStrength;
                final muteOverlay = _muteOverlayAlpha;

                return ColorFiltered(
                  colorFilter: _saturationFilter(colorStrength),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FadeTransition(
                            opacity: Tween<double>(begin: 1, end: 0).animate(
                              CurvedAnimation(
                                parent: _contentFadeController,
                                curve: Curves.easeInOutCubic,
                              ),
                            ),
                            child: _QuestionnaireHeader(
                              current: _currentIndex + 1,
                              total: _totalQuestions,
                              progress: questionProgress,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                const sideWidth = 84.0;

                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 8,
                                      child: FadeTransition(
                                        opacity: Tween<double>(
                                          begin: 1,
                                          end: 0,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: _contentFadeController,
                                            curve: Curves.easeInOutCubic,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: Center(
                                                child: AnimatedSwitcher(
                                                  duration: const Duration(
                                                    milliseconds: 380,
                                                  ),
                                                  switchInCurve:
                                                      Curves.easeOutCubic,
                                                  switchOutCurve:
                                                      Curves.easeInCubic,
                                                  transitionBuilder:
                                                      (child, animation) {
                                                    final slide =
                                                        Tween<Offset>(
                                                      begin: const Offset(
                                                          0, 0.05),
                                                      end: Offset.zero,
                                                    ).animate(CurvedAnimation(
                                                      parent: animation,
                                                      curve:
                                                          Curves.easeOutCubic,
                                                    ));
                                                    return FadeTransition(
                                                      opacity: animation,
                                                      child: SlideTransition(
                                                        position: slide,
                                                        child: child,
                                                      ),
                                                    );
                                                  },
                                                  child: _QuestionCard(
                                                    key: ValueKey<int>(
                                                        _currentIndex),
                                                    question: _questions[
                                                        _currentIndex],
                                                    selectedIndex:
                                                        _selectedOptionIndex,
                                                    onSelect: _selectOption,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            _ContinueButton(
                                              enabled: _hasSelection &&
                                                  !_isLogoFillAnimating &&
                                                  !inCinematic,
                                              isLast: _isLastQuestion,
                                              onPressed: _onContinue,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    if (_showSideLogo)
                                      SizedBox(
                                        width: sideWidth,
                                        child: RepaintBoundary(
                                          child: AnimatedBuilder(
                                            animation: Listenable.merge([
                                              _waveController,
                                              _logoFillController,
                                            ]),
                                            builder: (context, _) {
                                              return _SideProgressColumn(
                                                fillProgress:
                                                    _renderedFillProgress,
                                                wavePhase: _waveController
                                                        .value *
                                                    math.pi *
                                                    2,
                                                showComplete:
                                                    _renderedFillProgress >=
                                                        1.0,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showCinematicOverlay)
                    Positioned.fill(
                      child: SafeArea(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _logoMoveController,
                                    _logoLiftController,
                                    _waveController,
                                    _twinkleController,
                                  ]),
                                  builder: (context, _) {
                                    return RepaintBoundary(
                                      child: Align(
                                        alignment: _cinematicLogoAlignment(
                                          constraints,
                                        ),
                                        child: Transform.scale(
                                          scale: _cinematicLogoScale(),
                                          child: _CinematicLogoHero(
                                            wavePhase: _waveController.value *
                                                math.pi *
                                                2,
                                            sparklePhase:
                                                _twinkleController.value *
                                                    math.pi *
                                                    2,
                                            showSparkles:
                                                _showCinematicSparkles,
                                            medium: true,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (_phase ==
                                    _CinematicPhase.showingMessage)
                                  Positioned(
                                    left: 20,
                                    right: 20,
                                    top: _messageAreaTop(constraints),
                                    bottom: 12,
                                    child: FadeTransition(
                                      opacity: CurvedAnimation(
                                        parent: _textFadeController,
                                        curve: Curves.easeOutCubic,
                                      ),
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.03),
                                          end: Offset.zero,
                                        ).animate(CurvedAnimation(
                                          parent: _textFadeController,
                                          curve: Curves.easeOutCubic,
                                        )),
                                        child: _CinematicEndingCopy(
                                          onContinue: _finishQuestionnaire,
                                          buttonOpacity: CurvedAnimation(
                                            parent: _buttonFadeController,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeInOutCubic,
                      color: const Color(0xFF02060C)
                          .withValues(alpha: muteOverlay),
                    ),
                  ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Question {
  const _Question({required this.text, required this.options});

  final String text;
  final List<_AnswerOption> options;
}

class _AnswerOption {
  const _AnswerOption(this.emoji, this.label);

  final String emoji;
  final String label;
}

class _QuestionnaireHeader extends StatelessWidget {
  const _QuestionnaireHeader({
    required this.current,
    required this.total,
    required this.progress,
  });

  final int current;
  final int total;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'בוא נכיר אותך',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.96),
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'כמה שאלות קצרות שיעזרו ל-Genet להבין מי אתה.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: 13.5,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Text(
          'שאלה $current מתוך $total',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.15,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 3,
            color: Colors.white.withValues(alpha: 0.05),
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryBlue.withValues(alpha: 0.65),
                        _ChildQuestionnaireScreenState._neonGreen
                            .withValues(alpha: 0.55),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _ChildQuestionnaireScreenState._neonGreen
                            .withValues(alpha: 0.18),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SideProgressColumn extends StatelessWidget {
  const _SideProgressColumn({
    required this.fillProgress,
    required this.wavePhase,
    required this.showComplete,
  });

  final double fillProgress;
  final double wavePhase;
  final bool showComplete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            'GENET',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.8,
            ),
          ),
          const SizedBox(height: 8),
          _GenetLogoWaterFill(
            fillProgress: fillProgress,
            wavePhase: wavePhase,
            showComplete: showComplete,
            showGreeting: false,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _CinematicLogoHero extends StatelessWidget {
  const _CinematicLogoHero({
    required this.wavePhase,
    required this.sparklePhase,
    required this.showSparkles,
    this.medium = false,
  });

  final double wavePhase;
  final double sparklePhase;
  final bool showSparkles;
  final bool medium;

  @override
  Widget build(BuildContext context) {
    final width = medium ? 106.0 : 106.0;
    final height = medium ? 124.0 : 124.0;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -21,
            top: -22,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
              opacity: showSparkles ? 1 : 0,
              child: CustomPaint(
                size: const Size(148, 168),
                painter: _LogoSparklePainter(phase: sparklePhase),
              ),
            ),
          ),
          _GenetLogoWaterFill(
            fillProgress: 1,
            wavePhase: wavePhase,
            showComplete: true,
            showGreeting: false,
            compact: true,
            cinematicGlow: true,
          ),
        ],
      ),
    );
  }
}

class _LogoSparklePainter extends CustomPainter {
  const _LogoSparklePainter({required this.phase});

  final double phase;

  static const Color _blue = Color(0xFF42A5F5);
  static const Color _green = Color(0xFF39FF88);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);
    const count = 7;

    for (var i = 0; i < count; i++) {
      final orbit = 52 + (i % 3) * 10;
      final angle = (i / count) * math.pi * 2 + phase * 0.35;
      final twinkle = (math.sin(phase * 1.6 + i * 1.15) + 1) * 0.5;
      if (twinkle < 0.28) continue;

      final pos = center +
          Offset(
            math.cos(angle) * orbit,
            math.sin(angle) * orbit * 0.72,
          );
      final color = i.isEven ? _blue : _green;
      final paint = Paint()
        ..color = color.withValues(alpha: twinkle * 0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
      canvas.drawCircle(pos, 1.1 + (i % 2) * 0.35, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LogoSparklePainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class _CinematicEndingCopy extends StatelessWidget {
  const _CinematicEndingCopy({
    required this.onContinue,
    required this.buttonOpacity,
  });

  final VoidCallback onContinue;
  final Animation<double> buttonOpacity;

  static const Color _neonGreen = Color(0xFF39FF88);
  static const Color _genetBlue = Color(0xFF42A5F5);

  TextStyle get _bodyStyle => TextStyle(
        color: Colors.white.withValues(alpha: 0.78),
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.72,
      );

  TextStyle get _closingStyle => TextStyle(
        color: Colors.white.withValues(alpha: 0.58),
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.68,
      );

  Widget _genetLine({
    required String suffix,
    required Color genetColor,
    TextStyle? style,
  }) {
    final base = style ?? _bodyStyle;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: 'Genet',
            style: base.copyWith(
              color: genetColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: suffix),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'נעים להכיר 😊',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.97),
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.38,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          _genetLine(
            suffix: ' לא כאן כדי להגיד לך מה לעשות.',
            genetColor: _neonGreen,
          ),
          const SizedBox(height: 16),
          Text(
            'היא כאן כדי לעזור לך למצוא איזון,\n'
            'בין הטלפון לבין הדברים שחשובים לך באמת.',
            style: _bodyStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'זמן למשחקים.\n'
            'זמן לחברים.\n'
            'זמן למשפחה.\n'
            'וזמן לנוח כמו שצריך.',
            style: _bodyStyle.copyWith(height: 1.82),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'ככל שנכיר אותך יותר,\n'
            'נוכל לעזור לך ליהנות מהטלפון בצורה חכמה ובריאה יותר.',
            style: _bodyStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text.rich(
            TextSpan(
              style: _closingStyle,
              children: [
                const TextSpan(
                  text: 'עכשיו נחבר אותך להורה בצורה בטוחה,\n'
                      'ונתחיל את המסע שלך עם ',
                ),
                TextSpan(
                  text: 'Genet',
                  style: _closingStyle.copyWith(
                    color: _genetBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FadeTransition(
            opacity: buttonOpacity,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(buttonOpacity),
              child: _ContinueButton(
                enabled: true,
                isLast: false,
                label: 'המשך לחיבור',
                height: 56,
                prominentGlow: true,
                onPressed: onContinue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo water-fill progress: dim base layer + rising wave-clipped color layer.
class _GenetLogoWaterFill extends StatelessWidget {
  const _GenetLogoWaterFill({
    required this.fillProgress,
    required this.wavePhase,
    required this.showComplete,
    this.showGreeting = false,
    this.compact = false,
    this.cinematicGlow = false,
  });

  final double fillProgress;
  final double wavePhase;
  final bool showComplete;
  final bool showGreeting;
  final bool compact;
  final bool cinematicGlow;

  double get _logoWidth => compact ? 106 : 108;
  double get _logoHeight => compact ? 124 : 126;

  double get _effectiveFill =>
      fillProgress <= 0 ? 0.05 : fillProgress.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final glowStrength = fillProgress.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: showComplete
                ? [
                    BoxShadow(
                      color: const Color(0xFF42A5F5).withValues(
                        alpha: cinematicGlow ? 0.34 : 0.28,
                      ),
                      blurRadius: cinematicGlow ? 32 : 28,
                      spreadRadius: cinematicGlow ? 2 : 1,
                    ),
                    BoxShadow(
                      color: _ChildQuestionnaireScreenState._neonGreen
                          .withValues(alpha: cinematicGlow ? 0.26 : 0.2),
                      blurRadius: cinematicGlow ? 36 : 32,
                    ),
                    if (cinematicGlow)
                      BoxShadow(
                        color: const Color(0xFF42A5F5)
                            .withValues(alpha: 0.1),
                        blurRadius: 48,
                        spreadRadius: 4,
                      ),
                  ]
                : [
                    BoxShadow(
                      color: _ChildQuestionnaireScreenState._neonGreen
                          .withValues(alpha: 0.03 + glowStrength * 0.08),
                      blurRadius: 16 + glowStrength * 8,
                    ),
                  ],
          ),
          child: SizedBox(
            width: _logoWidth,
            height: _logoHeight,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                ColorFiltered(
                  colorFilter: _ChildQuestionnaireScreenState._dimLogoFilter,
                  child: Opacity(
                    opacity: 0.42,
                    child: Image.asset(
                      _ChildQuestionnaireScreenState._logoAsset,
                      width: _logoWidth,
                      height: _logoHeight,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                ClipPath(
                  clipper: _WaveClipper(
                    fillProgress: _effectiveFill,
                    wavePhase: wavePhase,
                  ),
                  child: Image.asset(
                    _ChildQuestionnaireScreenState._logoAsset,
                    width: _logoWidth,
                    height: _logoHeight,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showGreeting)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOutSine,
            opacity: showComplete ? 1 : 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              offset: showComplete ? Offset.zero : const Offset(0, 0.12),
              child: Padding(
                padding: EdgeInsets.only(top: compact ? 6 : 10),
                child: Text(
                  'נעים להכיר 😊',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: compact ? 11 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }
}

/// Rising water edge for the logo fill mask.
class _WaveClipper extends CustomClipper<Path> {
  const _WaveClipper({required this.fillProgress, required this.wavePhase});

  final double fillProgress;
  final double wavePhase;

  @override
  Path getClip(Size size) {
    if (fillProgress <= 0) {
      return Path();
    }
    if (fillProgress >= 1) {
      return Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    }

    final waterTop = size.height * (1 - fillProgress);
    const primaryAmp = 3.6;
    const secondaryAmp = 1.4;
    const segments = 32;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, waterTop);

    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final x = size.width * t;
      final wave = math.sin(t * math.pi * 2 + wavePhase) * primaryAmp +
          math.sin(t * math.pi * 3.6 + wavePhase * 1.35) * secondaryAmp;
      path.lineTo(x, waterTop + wave);
    }

    path
      ..lineTo(size.width, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _WaveClipper oldClipper) {
    return oldClipper.fillProgress != fillProgress ||
        oldClipper.wavePhase != wavePhase;
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.question,
    required this.selectedIndex,
    required this.onSelect,
  });

  final _Question question;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF040A14).withValues(alpha: 0.94),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _ChildQuestionnaireScreenState._cardBorder.withValues(alpha: 0.06),
            blurRadius: 24,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              question.text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 25,
                fontWeight: FontWeight.w700,
                height: 1.42,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ...List.generate(question.options.length, (i) {
              final option = question.options[i];
              final selected = selectedIndex == i;
              return Padding(
                padding: EdgeInsets.only(bottom: i < question.options.length - 1 ? 12 : 0),
                child: _AnswerTile(
                  emoji: option.emoji,
                  label: option.label,
                  selected: selected,
                  onTap: () => onSelect(i),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? _ChildQuestionnaireScreenState._neonGreen.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.1);
    final fillColor = selected
        ? _ChildQuestionnaireScreenState._neonGreen.withValues(alpha: 0.1)
        : const Color(0xFF061018).withValues(alpha: 0.72);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: fillColor,
            border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _ChildQuestionnaireScreenState._neonGreen
                          .withValues(alpha: 0.14),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: selected ? 0.94 : 0.72),
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: selected ? 1 : 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: _ChildQuestionnaireScreenState._neonGreen.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.enabled,
    required this.isLast,
    required this.onPressed,
    this.label,
    this.height = 52,
    this.prominentGlow = false,
  });

  final bool enabled;
  final bool isLast;
  final VoidCallback onPressed;
  final String? label;
  final double height;
  final bool prominentGlow;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: enabled ? 1 : 0.42,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: enabled
                      ? [
                          _ChildQuestionnaireScreenState._neonGreen
                              .withValues(alpha: 0.92),
                          const Color(0xFF00C853),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.14),
                          Colors.white.withValues(alpha: 0.08),
                        ],
                ),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: _ChildQuestionnaireScreenState._neonGreen
                              .withValues(
                            alpha: prominentGlow ? 0.32 : 0.24,
                          ),
                          blurRadius: prominentGlow ? 20 : 16,
                          offset: const Offset(0, 4),
                        ),
                        if (prominentGlow)
                          BoxShadow(
                            color: _ChildQuestionnaireScreenState._neonGreen
                                .withValues(alpha: 0.12),
                            blurRadius: 28,
                            spreadRadius: 1,
                          ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  label ?? (isLast ? 'סיום' : 'המשך'),
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFF04210F)
                        : Colors.white.withValues(alpha: 0.5),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestionnaireBackground extends StatelessWidget {
  const _QuestionnaireBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF030810),
            Color(0xFF050D18),
            Color(0xFF06101C),
            Color(0xFF030810),
          ],
          stops: [0.0, 0.4, 0.75, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.55),
            radius: 1.2,
            colors: [
              AppTheme.primaryBlue.withValues(alpha: 0.04),
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
