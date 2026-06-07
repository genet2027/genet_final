import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/child_questionnaire/child_questionnaire_repository.dart';
import '../../repositories/children_repository.dart';
import '../../theme/app_theme.dart';

/// Genet child onboarding questionnaire — step-by-step with Firestore persistence.
class ChildQuestionnaireScreen extends StatefulWidget {
  const ChildQuestionnaireScreen({super.key, this.onCompleted});

  final VoidCallback? onCompleted;

  @override
  State<ChildQuestionnaireScreen> createState() =>
      _ChildQuestionnaireScreenState();
}

class _QuestionnaireTokens {
  static const Color neonGreen = Color(0xFF39FF88);
  static const Color neonGreenDark = Color(0xFF00C853);
  static const Color cardBorder = Color(0xFF42A5F5);

  static const List<Color> backgroundGradient = [
    Color(0xFF050B18),
    Color(0xFF0A1A3A),
    Color(0xFF0D2B5E),
    Color(0xFF061224),
  ];

  static const List<double> backgroundStops = [0.0, 0.35, 0.72, 1.0];
}

class _ChoiceOption {
  const _ChoiceOption(this.emoji, this.label);

  final String emoji;
  final String label;
}

class _ChoiceStepDef {
  const _ChoiceStepDef({
    required this.key,
    required this.question,
    required this.options,
  });

  final String key;
  final String question;
  final List<_ChoiceOption> options;

  List<String> get labels => options.map((o) => o.label).toList();
}

class _ChildQuestionnaireScreenState extends State<ChildQuestionnaireScreen> {
  static const String _otherLabel = 'אחר';

  static const List<_ChoiceStepDef> _choiceSteps = [
    _ChoiceStepDef(
      key: 'favoriteActivity',
      question: 'מה אתה הכי אוהב לעשות בזמן הפנוי?',
      options: [
        _ChoiceOption('⚽', 'כדורגל'),
        _ChoiceOption('🏀', 'כדורסל'),
        _ChoiceOption('🎮', 'משחקים'),
        _ChoiceOption('🎵', 'מוזיקה'),
        _ChoiceOption('🎨', 'ציור'),
        _ChoiceOption('✏️', 'אחר'),
      ],
    ),
    _ChoiceStepDef(
      key: 'favoriteAnimal',
      question: 'מה החיה האהובה עליך?',
      options: [
        _ChoiceOption('🐶', 'כלב'),
        _ChoiceOption('🐱', 'חתול'),
        _ChoiceOption('🦁', 'אריה'),
        _ChoiceOption('🐬', 'דולפין'),
        _ChoiceOption('🐴', 'סוס'),
        _ChoiceOption('✏️', 'אחר'),
      ],
    ),
    _ChoiceStepDef(
      key: 'favoriteFood',
      question: 'איזה אוכל אתה הכי אוהב?',
      options: [
        _ChoiceOption('🍕', 'פיצה'),
        _ChoiceOption('🍔', 'המבורגר'),
        _ChoiceOption('🍝', 'פסטה'),
        _ChoiceOption('🍗', 'שניצל'),
        _ChoiceOption('🫓', 'אינג\'רה'),
        _ChoiceOption('✏️', 'אחר'),
      ],
    ),
    _ChoiceStepDef(
      key: 'favoriteGameOrApp',
      question: 'איזה משחק או אפליקציה אתה הכי אוהב?',
      options: [
        _ChoiceOption('🎮', 'Roblox'),
        _ChoiceOption('⛏️', 'Minecraft'),
        _ChoiceOption('🎯', 'Fortnite'),
        _ChoiceOption('▶️', 'YouTube'),
        _ChoiceOption('🎵', 'TikTok'),
        _ChoiceOption('✏️', 'אחר'),
      ],
    ),
    _ChoiceStepDef(
      key: 'dream',
      question: 'מה החלום שלך?',
      options: [
        _ChoiceOption('⚽', 'להיות ספורטאי'),
        _ChoiceOption('🎬', 'להיות יוצר תוכן'),
        _ChoiceOption('🩺', 'להיות רופא'),
        _ChoiceOption('✈️', 'להיות טייס'),
        _ChoiceOption('💻', 'להיות מתכנת'),
        _ChoiceOption('✏️', 'אחר'),
      ],
    ),
    _ChoiceStepDef(
      key: 'strength',
      question: 'במה אתה מרגיש שאתה טוב?',
      options: [
        _ChoiceOption('⚽', 'אני טוב בספורט'),
        _ChoiceOption('📚', 'אני טוב בלימודים'),
        _ChoiceOption('🤝', 'אני טוב בלעזור לאחרים'),
        _ChoiceOption('🎨', 'אני יצירתי'),
        _ChoiceOption('😄', 'אני מצחיק'),
        _ChoiceOption('✏️', 'אחר'),
      ],
    ),
  ];

  static const int _totalSteps = 7;

  final Map<String, TextEditingController> _otherControllers = {};
  final TextEditingController _freeTextController = TextEditingController();
  final Map<String, String> _answers = {};
  final Map<String, String?> _selectedOptionByKey = {};

  int _stepIndex = 0;
  bool _isSaving = false;
  bool _isLoading = true;
  Object? _existingCompletedAt;
  String _savedName = '';
  String _savedAge = '';

  @override
  void initState() {
    super.initState();
    for (final step in _choiceSteps) {
      _otherControllers[step.key] = TextEditingController();
      _selectedOptionByKey[step.key] = null;
    }
    unawaited(_bootstrapQuestionnaire());
  }

  @override
  void dispose() {
    for (final controller in _otherControllers.values) {
      controller.dispose();
    }
    _freeTextController.dispose();
    super.dispose();
  }

  bool get _isLastStep => _stepIndex >= _totalSteps - 1;
  bool get _isFreeTextStep => _stepIndex == _choiceSteps.length;

  _ChoiceStepDef? get _currentChoiceStep =>
      _stepIndex < _choiceSteps.length ? _choiceSteps[_stepIndex] : null;

  Future<String?> _resolveCanonicalChildId() async {
    return resolveAuthBoundChildQuestionnaireId();
  }

  Future<void> _bootstrapQuestionnaire() async {
    await _loadNameAgeFromProfile();

    final childId = await _resolveCanonicalChildId();
    if (childId != null) {
      try {
        final questionnaire = await loadChildQuestionnaire(childId);
        if (questionnaire != null && questionnaire.isNotEmpty) {
          _applyExistingQuestionnaire(questionnaire);
          _existingCompletedAt = questionnaire['completedAt'];
        }
      } catch (e) {
        debugPrint(
          '[GENET][CHILD_QUESTIONNAIRE][ERROR] failed to load questionnaire: $e',
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _stepIndex = _resolveInitialStepIndex();
      _isLoading = false;
    });
  }

  Future<void> _loadNameAgeFromProfile() async {
    final profile = await getChildSelfProfile();
    final first =
        (profile[kChildSelfProfileFirstName] as String? ?? '').trim();
    final last = (profile[kChildSelfProfileLastName] as String? ?? '').trim();
    _savedName = [first, last].join(' ').trim();
    final ageRaw = profile[kChildSelfProfileAge];
    _savedAge = ageRaw == null ? '' : ageRaw.toString();
  }

  void _applyExistingQuestionnaire(Map<String, dynamic> questionnaire) {
    final name = questionnaire['name']?.toString().trim();
    final age = questionnaire['age']?.toString().trim();
    if (name != null && name.isNotEmpty) _savedName = name;
    if (age != null && age.isNotEmpty) _savedAge = age;

    for (final step in _choiceSteps) {
      final value = questionnaire[step.key]?.toString().trim();
      if (value == null || value.isEmpty) continue;
      _answers[step.key] = value;
      if (step.labels.contains(value)) {
        _selectedOptionByKey[step.key] = value;
      } else {
        _selectedOptionByKey[step.key] = _otherLabel;
        _otherControllers[step.key]?.text = value;
      }
    }

    final freeText = questionnaire['freeText']?.toString().trim();
    if (freeText != null && freeText.isNotEmpty) {
      _freeTextController.text = freeText;
      _answers['freeText'] = freeText;
    }
  }

  int _resolveInitialStepIndex() {
    for (var i = 0; i < _choiceSteps.length; i++) {
      final key = _choiceSteps[i].key;
      final value = _answers[key]?.trim();
      if (value == null || value.isEmpty) return i;
    }
    return _choiceSteps.length;
  }

  Map<String, dynamic> _buildQuestionnairePayload() {
    final now = FieldValue.serverTimestamp();
    return {
      'name': _savedName,
      'age': _savedAge,
      'favoriteAnimal': _answers['favoriteAnimal'] ?? '',
      'favoriteFood': _answers['favoriteFood'] ?? '',
      'favoriteActivity': _answers['favoriteActivity'] ?? '',
      'favoriteGameOrApp': _answers['favoriteGameOrApp'] ?? '',
      'dream': _answers['dream'] ?? '',
      'strength': _answers['strength'] ?? '',
      'freeText': _freeTextController.text.trim(),
      'completedAt': _existingCompletedAt ?? now,
      'updatedAt': now,
    };
  }

  bool _validateAllChoiceAnswers() {
    for (final step in _choiceSteps) {
      final value = _answers[step.key]?.trim();
      if (value == null || value.isEmpty) return false;
    }
    return true;
  }

  Future<void> _saveQuestionnaire() async {
    if (_isSaving) return;

    if (!_validateAllChoiceAnswers()) {
      _showSnackBar('צריך למלא את השדות החשובים לפני שממשיכים');
      return;
    }

    final childId = await _resolveCanonicalChildId();
    if (childId == null) {
      _showSnackBar('צריך להתחבר לפני שמירת השאלון');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('[GENET][CHILD_QUESTIONNAIRE] auth uid: $authUid');
      debugPrint(
        '[GENET][CHILD_QUESTIONNAIRE] saving questionnaire docId: $childId',
      );
      final payload = _buildQuestionnairePayload();
      await saveChildQuestionnaire(
        childId: childId,
        questionnaire: payload,
      );
      if (!mounted) return;

      _existingCompletedAt ??= payload['completedAt'];
      debugPrint(
        '[GENET][CHILD_QUESTIONNAIRE] saved successfully for childId: $childId',
      );
      _showSnackBar('השאלון נשמר בהצלחה');
      widget.onCompleted?.call();
    } catch (e) {
      debugPrint(
        '[GENET][CHILD_QUESTIONNAIRE][ERROR] failed to save questionnaire: $e',
      );
      if (!mounted) return;
      _showSnackBar('לא הצלחנו לשמור את השאלון, נסה שוב');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _selectOption(String key, String label) {
    if (_isSaving) return;
    setState(() => _selectedOptionByKey[key] = label);
  }

  Future<void> _onContinue() async {
    if (_isSaving || _isLoading) return;

    if (_isFreeTextStep) {
      _answers['freeText'] = _freeTextController.text.trim();
      await _saveQuestionnaire();
      return;
    }

    final step = _currentChoiceStep;
    if (step == null) return;

    final selected = _selectedOptionByKey[step.key];
    if (selected == null) {
      _showSnackBar('בחר תשובה כדי להמשיך');
      return;
    }

    if (selected == _otherLabel) {
      final other = _otherControllers[step.key]?.text.trim() ?? '';
      if (other.isEmpty) {
        _showSnackBar('כתוב תשובה קצרה כדי להמשיך');
        return;
      }
      _answers[step.key] = other;
    } else {
      _answers[step.key] = selected;
    }

    if (_isLastStep) {
      await _saveQuestionnaire();
      return;
    }

    setState(() => _stepIndex++);
  }

  Widget _buildHeader() {
    final current = _stepIndex + 1;
    final progress = current / _totalSteps;

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
          'כמה שאלות קצרות שיעזרו ל-Genet להכיר מי אתה.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: 13.5,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Text(
          'שאלה $current מתוך $_totalSteps',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w500,
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
                        _QuestionnaireTokens.neonGreen.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceStep(_ChoiceStepDef step) {
    final selected = _selectedOptionByKey[step.key];
    final showOtherField = selected == _otherLabel;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF040A14).withValues(alpha: 0.94),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _QuestionnaireTokens.cardBorder.withValues(alpha: 0.06),
            blurRadius: 24,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              step.question,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.42,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ...step.options.map((option) {
              final isSelected = selected == option.label;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AnswerTile(
                  emoji: option.emoji,
                  label: option.label,
                  selected: isSelected,
                  onTap: () => _selectOption(step.key, option.label),
                ),
              );
            }),
            if (showOtherField) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _otherControllers[step.key],
                enabled: !_isSaving,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'כתוב כאן...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF061018).withValues(alpha: 0.72),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _QuestionnaireTokens.neonGreen.withValues(alpha: 0.45),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _QuestionnaireTokens.neonGreen.withValues(alpha: 0.75),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFreeTextStep() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF040A14).withValues(alpha: 0.94),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'משהו נוסף שתרצה לספר?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.42,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _freeTextController,
            enabled: !_isSaving,
            maxLines: 3,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: 'כל דבר שחשוב לך לספר (אופציונלי)',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.32),
              ),
              filled: true,
              fillColor: const Color(0xFF061018).withValues(alpha: 0.72),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: _QuestionnaireTokens.neonGreen.withValues(alpha: 0.75),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    final enabled = !_isSaving && !_isLoading;
    final label = _isSaving
        ? 'שומר...'
        : (_isLastStep ? 'שמור וסיים' : 'המשך');

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: enabled
                ? const [
                    _QuestionnaireTokens.neonGreen,
                    _QuestionnaireTokens.neonGreenDark,
                  ]
                : [
                    _QuestionnaireTokens.neonGreen.withValues(alpha: 0.45),
                    _QuestionnaireTokens.neonGreenDark.withValues(alpha: 0.45),
                  ],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color:
                        _QuestionnaireTokens.neonGreen.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => unawaited(_onContinue()) : null,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: _isSaving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: const Color(0xFF041018).withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF041018),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF041018),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepContent = _isLoading
        ? Center(
            child: Text(
              'טוען שאלון...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          )
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _isFreeTextStep
                ? KeyedSubtree(
                    key: const ValueKey<String>('freeText'),
                    child: _buildFreeTextStep(),
                  )
                : KeyedSubtree(
                    key: ValueKey<String>(_currentChoiceStep!.key),
                    child: _buildChoiceStep(_currentChoiceStep!),
                  ),
          );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF050B18),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _QuestionnaireTokens.backgroundGradient,
                  stops: _QuestionnaireTokens.backgroundStops,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 22),
                    Expanded(child: Center(child: stepContent)),
                    const SizedBox(height: 18),
                    _buildContinueButton(),
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
        ? _QuestionnaireTokens.neonGreen.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.1);
    final fillColor = selected
        ? _QuestionnaireTokens.neonGreen.withValues(alpha: 0.1)
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
                      color: _QuestionnaireTokens.neonGreen
                          .withValues(alpha: 0.14),
                      blurRadius: 12,
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
                  color: _QuestionnaireTokens.neonGreen.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
