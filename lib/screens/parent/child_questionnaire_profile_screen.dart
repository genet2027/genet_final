import 'package:flutter/material.dart';

import '../../features/child_questionnaire/child_questionnaire_repository.dart';

/// Full parent view of the child's onboarding questionnaire answers.
class ChildQuestionnaireProfileScreen extends StatefulWidget {
  const ChildQuestionnaireProfileScreen({super.key, required this.childId});

  final String childId;

  @override
  State<ChildQuestionnaireProfileScreen> createState() =>
      _ChildQuestionnaireProfileScreenState();
}

class _ProfileTokens {
  static const Color neonGreen = Color(0xFF39FF88);
  static const Color fieldFill = Color(0x1AFFFFFF);

  static const List<Color> backgroundGradient = [
    Color(0xFF050B18),
    Color(0xFF0A1A3A),
    Color(0xFF0D2B5E),
    Color(0xFF061224),
  ];

  static const List<double> backgroundStops = [0.0, 0.35, 0.72, 1.0];
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(16));
}

class _QuestionnaireFieldSpec {
  const _QuestionnaireFieldSpec({
    required this.key,
    required this.label,
    required this.emoji,
  });

  final String key;
  final String label;
  final String emoji;
}

class _QuestionnaireGroupSpec {
  const _QuestionnaireGroupSpec({
    required this.title,
    required this.fields,
  });

  final String title;
  final List<_QuestionnaireFieldSpec> fields;
}

class _ChildQuestionnaireProfileScreenState
    extends State<ChildQuestionnaireProfileScreen> {
  String? _loggedLoadedDocId;
  String? _loggedNotCompletedDocId;

  static const List<_QuestionnaireGroupSpec> _groupSpecs = [
    _QuestionnaireGroupSpec(
      title: 'מי אני',
      fields: [
        _QuestionnaireFieldSpec(key: 'name', label: 'שם', emoji: '👋'),
        _QuestionnaireFieldSpec(key: 'age', label: 'גיל', emoji: '🎂'),
      ],
    ),
    _QuestionnaireGroupSpec(
      title: 'הדברים שאני אוהב',
      fields: [
        _QuestionnaireFieldSpec(
          key: 'favoriteAnimal',
          label: 'חיה אהובה',
          emoji: '🐾',
        ),
        _QuestionnaireFieldSpec(
          key: 'favoriteFood',
          label: 'מאכל אהוב',
          emoji: '🍽️',
        ),
        _QuestionnaireFieldSpec(
          key: 'favoriteActivity',
          label: 'אוהב לעשות',
          emoji: '✨',
        ),
        _QuestionnaireFieldSpec(
          key: 'favoriteGameOrApp',
          label: 'משחק או אפליקציה אהובה',
          emoji: '🎮',
        ),
      ],
    ),
    _QuestionnaireGroupSpec(
      title: 'החלומות והחוזקות שלי',
      fields: [
        _QuestionnaireFieldSpec(key: 'dream', label: 'החלום שלי', emoji: '🌟'),
        _QuestionnaireFieldSpec(key: 'strength', label: 'במה אני טוב', emoji: '💪'),
        _QuestionnaireFieldSpec(
          key: 'freeText',
          label: 'משהו נוסף עליי',
          emoji: '💬',
        ),
      ],
    ),
  ];

  Map<String, dynamic>? _readQuestionnaireMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['questionnaire'];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  String _value(Map<String, dynamic>? questionnaire, String key) {
    final raw = questionnaire?[key];
    if (raw == null) return 'לא מולא';
    final text = raw.toString().trim();
    return text.isEmpty ? 'לא מולא' : text;
  }

  String? _childName(Map<String, dynamic>? questionnaire) {
    final name = _value(questionnaire, 'name');
    return name == 'לא מולא' ? null : name;
  }

  void _logLoadedOnce(String resolvedDocId) {
    if (_loggedLoadedDocId == resolvedDocId) return;
    _loggedLoadedDocId = resolvedDocId;
    debugPrint(
      '[GENET][CHILD_PROFILE] questionnaire profile loaded for childId: $resolvedDocId',
    );
  }

  void _logNotCompletedOnce(String resolvedDocId) {
    if (_loggedNotCompletedDocId == resolvedDocId) return;
    _loggedNotCompletedDocId = resolvedDocId;
    debugPrint(
      '[GENET][CHILD_PROFILE] questionnaire profile not completed for childId: $resolvedDocId',
    );
  }

  Widget _buildStateMessage(String message, {String? subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerCard(_QuestionnaireFieldSpec field, String answer) {
    final isEmpty = answer == 'לא מולא';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _ProfileTokens.fieldFill,
        borderRadius: _ProfileTokens.cardRadius,
        border: Border.all(
          color: _ProfileTokens.neonGreen.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(field.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text(
                field.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _ProfileTokens.neonGreen.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            answer,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: isEmpty
                  ? Colors.white.withValues(alpha: 0.38)
                  : Colors.white.withValues(alpha: 0.92),
              fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic>? questionnaire) {
    final name = _childName(questionnaire);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name != null ? 'הפרופיל של $name' : 'הכר את הילד שלך',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.97),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'כל הדברים שהילד בחר לספר על עצמו',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.35,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupSection(
    _QuestionnaireGroupSpec group,
    Map<String, dynamic>? questionnaire,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: _ProfileTokens.neonGreen.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              group.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < group.fields.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildAnswerCard(
            group.fields[i],
            _value(questionnaire, group.fields[i].key),
          ),
        ],
      ],
    );
  }

  Widget _buildGroupedAnswers(Map<String, dynamic>? questionnaire) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _groupSpecs.length; i++) ...[
          if (i > 0) const SizedBox(height: 24),
          _buildGroupSection(_groupSpecs[i], questionnaire),
        ],
      ],
    );
  }

  Widget _buildBodyContent(String childId) {
    if (childId.isEmpty) {
      return _buildStateMessage('לא נבחר ילד');
    }

    return StreamBuilder<GenetChildQuestionnaireViewState>(
      stream: watchGenetChildQuestionnaireForDashboard(childId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            '[GENET][CHILD_PROFILE][ERROR] failed to load questionnaire profile: ${snapshot.error}',
          );
          return _buildStateMessage('לא הצלחנו לטעון את פרופיל הילד');
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildStateMessage('טוען את פרופיל הילד...');
        }

        final state = snapshot.data;
        if (state == null || !state.questionnaireCompleted) {
          _logNotCompletedOnce(state?.resolvedDocId ?? childId);
          return _buildStateMessage(
            'הילד עדיין לא מילא את שאלון ההיכרות',
            subtitle: 'כשהוא יסיים, כל התשובות יופיעו כאן בצורה מסודרת',
          );
        }

        _logLoadedOnce(state.resolvedDocId);
        final questionnaire = _readQuestionnaireMap({
          kQuestionnaireField: state.questionnaire,
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileHeader(questionnaire),
            const SizedBox(height: 24),
            _buildGroupedAnswers(questionnaire),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final childId = widget.childId.trim();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF050B18),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white.withValues(alpha: 0.9),
          title: Text(
            'פרופיל השאלון',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _ProfileTokens.backgroundGradient,
                  stops: _ProfileTokens.backgroundStops,
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: _buildBodyContent(childId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
