import 'package:flutter/material.dart';

import '../features/daily_missions/models/daily_mission.dart' as feature;
import '../features/daily_missions/repositories/daily_missions_repository.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';

/// Parent daily missions screen (Firestore read + create).
class ParentDailyMissionsScreen extends StatefulWidget {
  const ParentDailyMissionsScreen({super.key});

  @override
  State<ParentDailyMissionsScreen> createState() =>
      _ParentDailyMissionsScreenState();
}

class _ParentDailyMissionsScreenState extends State<ParentDailyMissionsScreen> {
  final _dailyMissionsRepository = dailyMissionsRepository;

  String? _parentId;
  String? _childId;
  bool _contextReady = false;
  String? _updatingMissionId;

  @override
  void initState() {
    super.initState();
    _resolveMissionContext();
  }

  Future<void> _resolveMissionContext() async {
    final parentId = normalizeIdentifier(await getOrCreateParentId());
    final childId = normalizeIdentifier(await getSelectedChildId());
    if (!mounted) return;
    setState(() {
      _parentId = parentId;
      _childId = childId;
      _contextReady = true;
    });
  }

  bool get _hasMissionContext =>
      _parentId != null &&
      _childId != null &&
      _parentId!.isNotEmpty &&
      _childId!.isNotEmpty;

  Stream<List<feature.DailyMission>>? get _missionsStream {
    if (!_hasMissionContext) return null;
    return _dailyMissionsRepository.watchDailyMissions(
      parentId: _parentId!,
      childId: _childId!,
    );
  }

  Future<void> _showCreateMissionSheet() async {
    if (!_hasMissionContext) return;

    final messenger = ScaffoldMessenger.of(context);
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final rewardXpController = TextEditingController(text: '10');
    var selectedCategory = feature.DailyMissionCategory.studies;
    String? errorText;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'משימה חדשה',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'כותרת',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'תיאור (אופציונלי)',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<feature.DailyMissionCategory>(
                        key: ValueKey(selectedCategory),
                        initialValue: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'קטגוריה',
                        ),
                        items: feature.DailyMissionCategory.values
                            .map(
                              (category) => DropdownMenuItem(
                                value: category,
                                child: Text(category.label),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setSheetState(() => selectedCategory = value);
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: rewardXpController,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'תגמול XP (1–100)',
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(sheetContext),
                              child: const Text('בטל'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final title = titleController.text.trim();
                                      if (title.isEmpty) {
                                        setSheetState(() {
                                          errorText = 'יש להזין כותרת למשימה';
                                        });
                                        return;
                                      }

                                      final parsedXp = int.tryParse(
                                        rewardXpController.text.trim(),
                                      );
                                      if (parsedXp == null ||
                                          parsedXp < 1 ||
                                          parsedXp > 100) {
                                        setSheetState(() {
                                          errorText =
                                              'תגמול XP חייב להיות בין 1 ל-100';
                                        });
                                        return;
                                      }

                                      setSheetState(() {
                                        saving = true;
                                        errorText = null;
                                      });

                                      try {
                                        final now = DateTime.now();
                                        final mission = feature.DailyMission(
                                          id:
                                              'mission_${now.millisecondsSinceEpoch}',
                                          title: title,
                                          description: descriptionController
                                                  .text
                                                  .trim()
                                                  .isEmpty
                                              ? null
                                              : descriptionController.text
                                                  .trim(),
                                          category: selectedCategory,
                                          rewardXp: parsedXp,
                                          assignedDate: now,
                                          createdAt: now,
                                          updatedAt: now,
                                        );

                                        await _dailyMissionsRepository
                                            .createMission(
                                          parentId: _parentId!,
                                          childId: _childId!,
                                          mission: mission,
                                        );

                                        if (sheetContext.mounted) {
                                          Navigator.pop(sheetContext);
                                        }
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'המשימה נוצרה בהצלחה.',
                                            ),
                                          ),
                                        );
                                      } on DailyMissionLimitException {
                                        setSheetState(() {
                                          saving = false;
                                          errorText =
                                              'אפשר ליצור עד 3 משימות ביום.';
                                        });
                                      } catch (error, stackTrace) {
                                        debugPrint(
                                          '[GENET][DAILY_MISSIONS][CREATE] '
                                          'ui error=$error',
                                        );
                                        debugPrint(
                                          '[GENET][DAILY_MISSIONS][CREATE] '
                                          '$stackTrace',
                                        );
                                        setSheetState(() {
                                          saving = false;
                                          errorText =
                                              'לא הצלחנו לשמור את המשימה. נסה שוב.';
                                        });
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                              ),
                              child: saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('שמור משימה'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    titleController.dispose();
    descriptionController.dispose();
    rewardXpController.dispose();
  }

  Future<void> _approveMission(String missionId) async {
    if (_updatingMissionId != null) return;
    if (!_hasMissionContext) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updatingMissionId = missionId);

    try {
      await _dailyMissionsRepository.approveMission(
        parentId: _parentId!,
        childId: _childId!,
        missionId: missionId,
      );
    } catch (error, stackTrace) {
      debugPrint('[GENET][DAILY_MISSIONS][APPROVE] ui error=$error');
      debugPrint('[GENET][DAILY_MISSIONS][APPROVE] $stackTrace');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('לא ניתן היה לעדכן את המשימה. נסה שוב.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingMissionId = null);
      }
    }
  }

  Future<void> _rejectMission(String missionId) async {
    if (_updatingMissionId != null) return;
    if (!_hasMissionContext) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updatingMissionId = missionId);

    try {
      await _dailyMissionsRepository.rejectMission(
        parentId: _parentId!,
        childId: _childId!,
        missionId: missionId,
      );
    } catch (error, stackTrace) {
      debugPrint('[GENET][DAILY_MISSIONS][REJECT] ui error=$error');
      debugPrint('[GENET][DAILY_MISSIONS][REJECT] $stackTrace');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('לא ניתן היה לעדכן את המשימה. נסה שוב.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingMissionId = null);
      }
    }
  }

  Widget _buildStatusBadge({
    required String label,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildMissionCard(feature.DailyMission mission) {
    final isUpdating = _updatingMissionId == mission.id;

    return Card(
      key: ValueKey(mission.id),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              mission.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (mission.description != null &&
                mission.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                mission.description!,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                mission.category.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '+${mission.rewardXp} XP',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mission.displayStatusLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: mission.isWaitingForParentApproval
                    ? Colors.orange.shade800
                    : mission.isApproved
                        ? Colors.green.shade700
                        : mission.isRejected
                            ? Colors.red.shade700
                            : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            if (mission.isWaitingForParentApproval)
              isUpdating
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'מעדכן...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _approveMission(mission.id),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('אשר ביצוע'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _rejectMission(mission.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('דחה'),
                          ),
                        ),
                      ],
                    )
            else if (mission.isWaitingForChild)
              _buildStatusBadge(
                label: 'ממתינה לילד',
                backgroundColor: Colors.blue.shade50,
                textColor: Colors.blue.shade800,
              )
            else if (mission.isApproved)
              _buildStatusBadge(
                label: 'אושרה',
                backgroundColor: Colors.green.shade50,
                textColor: Colors.green.shade800,
              )
            else if (mission.isRejected)
              _buildStatusBadge(
                label: 'נדחתה',
                backgroundColor: Colors.red.shade50,
                textColor: Colors.red.shade800,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayStatusCard(List<feature.DailyMission> missions) {
    return Card(
      elevation: 1,
      color: AppTheme.lightBlue.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'היום',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              missions.isEmpty
                  ? 'אין עדיין משימות פעילות להיום'
                  : 'יש ${missions.length} משימות פעילות להיום',
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendlyMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          height: 1.45,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildMissionsContent({
    required List<feature.DailyMission> missions,
    required bool loading,
    String? errorMessage,
    bool showCreateButton = false,
  }) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'כאן אפשר ליצור משימות יומיות, לעקוב אחרי ביצוע, ולאשר תגמול רק אחרי שהילד באמת ביצע.',
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 20),
        _buildTodayStatusCard(missions),
        if (showCreateButton) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _showCreateMissionSheet,
            icon: const Icon(Icons.add_rounded),
            label: const Text('צור משימה חדשה'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (errorMessage != null)
          _buildFriendlyMessage(errorMessage)
        else if (missions.isEmpty)
          _buildFriendlyMessage('אין משימות להצגה')
        else
          ...missions.map(_buildMissionCard),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('משימות הילד'),
        ),
        body: !_contextReady
            ? const Center(child: CircularProgressIndicator())
            : !_hasMissionContext
                ? _buildMissionsContent(
                    missions: const [],
                    loading: false,
                    errorMessage: 'יש לבחור ילד מחובר כדי לראות משימות.',
                  )
                : StreamBuilder<List<feature.DailyMission>>(
                    stream: _missionsStream,
                    builder: (context, snapshot) {
                      final loading =
                          snapshot.connectionState == ConnectionState.waiting &&
                              !snapshot.hasData;
                      final errorMessage = snapshot.hasError
                          ? 'לא הצלחנו לטעון משימות כרגע. נסה שוב מאוחר יותר.'
                          : null;

                      return _buildMissionsContent(
                        missions: snapshot.data ?? const [],
                        loading: loading,
                        errorMessage: errorMessage,
                        showCreateButton: errorMessage == null,
                      );
                    },
                  ),
      ),
    );
  }
}
