import 'package:flutter/material.dart';

import '../../../features/child_questionnaire/child_questionnaire_repository.dart';
import '../../../repositories/children_repository.dart';
import '../child_questionnaire_profile_screen.dart';

/// Compact parent-dashboard card showing a short questionnaire summary.
class ChildQuestionnaireCard extends StatefulWidget {
  const ChildQuestionnaireCard({
    super.key,
    required this.childId,
    this.linkChildId,
    this.parentChildLinkDocData,
  });

  /// Questionnaire Firestore doc id (`c_<firebaseUid>` when resolved).
  final String? childId;

  /// Original parent link doc id (may be legacy `c_<timestamp>_<random>`).
  final String? linkChildId;

  /// Live parent-child doc for legacy id fallback (`authUid` fields).
  final Map<String, dynamic>? parentChildLinkDocData;

  @override
  State<ChildQuestionnaireCard> createState() => _ChildQuestionnaireCardState();
}

class _CardTokens {
  static const Color fieldFill = Color(0x1AFFFFFF);
  static const Color neonGreen = Color(0xFF39FF88);
  static const BorderRadius radius = BorderRadius.all(Radius.circular(18));
}

class _ChildQuestionnaireCardState extends State<ChildQuestionnaireCard> {
  String? _loggedChildId;
  String? _loggedLoadedDocId;

  void _logLoadingQuestionnaireOnce(String childId) {
    if (_loggedChildId == childId) return;
    _loggedChildId = childId;
    debugPrint(
      '[GENET][QUESTIONNAIRE_BINDING] card reads genet_children/$childId',
    );
    debugPrint(
      '[GENET][PARENT_DASHBOARD] card received childId: $childId',
    );
    final linkChildId = widget.linkChildId?.trim();
    if (linkChildId != null &&
        linkChildId.isNotEmpty &&
        linkChildId != childId) {
      debugPrint(
        '[GENET][QUESTIONNAIRE_BINDING] linkChildId=$linkChildId legacy=${isLegacyRandomChildId(linkChildId)}',
      );
    }
  }

  String? _resolveEffectiveQuestionnaireChildId() {
    final primary = widget.childId?.trim();
    final linkChildId = widget.linkChildId?.trim() ?? primary;
    final docData = widget.parentChildLinkDocData;

    if (linkChildId != null &&
        linkChildId.isNotEmpty &&
        docData != null &&
        docData.isNotEmpty) {
      final binding = resolveQuestionnaireChildIdBinding(
        docId: linkChildId,
        docData: docData,
      );
      if (binding.source == 'authUid' &&
          binding.questionnaireChildId != null) {
        return binding.questionnaireChildId;
      }
    }

    if (primary != null && primary.isNotEmpty) {
      if (!isLegacyRandomChildId(primary)) return primary;
    }

    if (linkChildId != null &&
        linkChildId.isNotEmpty &&
        !isLegacyRandomChildId(linkChildId)) {
      return linkChildId;
    }

    return primary ?? linkChildId;
  }

  void _logLoadedOnce(String resolvedDocId) {
    if (_loggedLoadedDocId == resolvedDocId) return;
    _loggedLoadedDocId = resolvedDocId;
    debugPrint(
      '[GENET][PARENT_DASHBOARD] questionnaire loaded for childId: $resolvedDocId',
    );
  }

  void _logNotCompletedOnce(String resolvedDocId) {
    if (_loggedLoadedDocId == 'not_completed:$resolvedDocId') return;
    _loggedLoadedDocId = 'not_completed:$resolvedDocId';
    debugPrint(
      '[GENET][PARENT_DASHBOARD] questionnaire not completed for childId: $resolvedDocId',
    );
  }

  String? _questionnaireValue(Map<String, dynamic>? questionnaire, String key) {
    final raw = questionnaire?[key];
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  Widget _buildInfoRow(String emoji, String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: Text(
              value ?? 'עדיין לא מולא',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardShell({
    required Widget child,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: _CardTokens.radius,
        splashColor: _CardTokens.neonGreen.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: _CardTokens.radius,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                _CardTokens.fieldFill,
                _CardTokens.neonGreen.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(
              color: _CardTokens.neonGreen.withValues(alpha: 0.28),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _CardTokens.neonGreen.withValues(alpha: 0.1),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({bool showChevron = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _CardTokens.neonGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('💫', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'הכר את הילד שלך',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'דברים קטנים שהילד בחר לספר',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: Colors.white.withValues(alpha: 0.48),
                ),
              ),
            ],
          ),
        ),
        if (showChevron)
          Icon(
            Icons.chevron_left_rounded,
            color: _CardTokens.neonGreen.withValues(alpha: 0.45),
            size: 20,
          ),
      ],
    );
  }

  Widget _buildActionHint() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.touch_app_outlined,
          size: 13,
          color: _CardTokens.neonGreen.withValues(alpha: 0.55),
        ),
        const SizedBox(width: 5),
        Text(
          'לחץ לצפייה בפרופיל המלא',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _CardTokens.neonGreen.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyQuestionnaireState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'השאלון עדיין לא מולא',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'ברגע שהילד ימלא אותו, תראה כאן תקציר אישי',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1.35,
            color: Colors.white.withValues(alpha: 0.38),
          ),
        ),
      ],
    );
  }

  void _onCardTap() {
    final childId = _resolveEffectiveQuestionnaireChildId();
    if (childId == null || childId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נבחר ילד להצגה')),
      );
      return;
    }

    debugPrint(
      '[GENET][CHILD_PROFILE] opening questionnaire profile for childId: $childId',
    );
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChildQuestionnaireProfileScreen(childId: childId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final childId = _resolveEffectiveQuestionnaireChildId();
    if (childId == null || childId.isEmpty) {
      return _buildCardShell(
        onTap: _onCardTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            Text(
              'לא נבחר ילד להצגה',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
          ],
        ),
      );
    }

    _logLoadingQuestionnaireOnce(childId);

    return StreamBuilder<GenetChildQuestionnaireViewState>(
      stream: watchGenetChildQuestionnaireForDashboard(childId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            '[GENET][PARENT_DASHBOARD][ERROR] failed to load questionnaire: ${snapshot.error}',
          );
          return _buildCardShell(
            onTap: _onCardTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                Text(
                  'לא הצלחנו לטעון את שאלון הילד',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildCardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                Text(
                  'טוען שאלון...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
          );
        }

        final state = snapshot.data;
        if (state == null || !state.questionnaireCompleted) {
          _logNotCompletedOnce(state?.resolvedDocId ?? childId);
          return _buildCardShell(
            onTap: _onCardTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                _buildEmptyQuestionnaireState(),
              ],
            ),
          );
        }

        _logLoadedOnce(state.resolvedDocId);
        final questionnaire = state.questionnaire;

        return _buildCardShell(
          onTap: _onCardTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(showChevron: true),
              const SizedBox(height: 10),
              _buildInfoRow(
                '🐾',
                'חיה אהובה',
                _questionnaireValue(questionnaire, 'favoriteAnimal'),
              ),
              const SizedBox(height: 6),
              _buildInfoRow(
                '🍽️',
                'מאכל אהוב',
                _questionnaireValue(questionnaire, 'favoriteFood'),
              ),
              const SizedBox(height: 6),
              _buildInfoRow(
                '✨',
                'אוהב לעשות',
                _questionnaireValue(questionnaire, 'favoriteActivity'),
              ),
              const SizedBox(height: 10),
              _buildActionHint(),
            ],
          ),
        );
      },
    );
  }
}
