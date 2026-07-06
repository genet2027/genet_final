import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/daily_missions/models/daily_mission.dart' as feature;
import '../features/daily_missions/repositories/daily_missions_repository.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';

enum DailyMissionType {
  study,
  sport,
  home,
  sleep,
  screenTime,
  custom,
}

String missionTypeEmoji(DailyMissionType type) {
  switch (type) {
    case DailyMissionType.study:
      return '📚';
    case DailyMissionType.sport:
      return '🏃';
    case DailyMissionType.home:
      return '🏠';
    case DailyMissionType.sleep:
      return '😴';
    case DailyMissionType.screenTime:
      return '📱';
    case DailyMissionType.custom:
      return '⭐';
  }
}

String missionTypeLabel(DailyMissionType type) {
  switch (type) {
    case DailyMissionType.study:
      return 'לימודים';
    case DailyMissionType.sport:
      return 'ספורט';
    case DailyMissionType.home:
      return 'בית';
    case DailyMissionType.sleep:
      return 'שינה';
    case DailyMissionType.screenTime:
      return 'זמן מסך';
    case DailyMissionType.custom:
      return 'משימה אישית';
  }
}

/// Simple daily mission model — local screen state only; extensible for future
/// missions, rewards, streaks, and parent approval.
class DailyMission {
  const DailyMission({
    required this.id,
    required this.title,
    required this.description,
    required this.xpReward,
    required this.type,
    required this.completed,
  });

  final String id;
  final String title;
  final String description;
  final int xpReward;
  final DailyMissionType type;
  final bool completed;

  DailyMission copyWith({bool? completed}) {
    return DailyMission(
      id: id,
      title: title,
      description: description,
      xpReward: xpReward,
      type: type,
      completed: completed ?? this.completed,
    );
  }
}

/// Child daily mission screen ("המשימה שלי").
class ChildSleepHoursScreen extends StatefulWidget {
  const ChildSleepHoursScreen({super.key});

  @override
  State<ChildSleepHoursScreen> createState() => _ChildSleepHoursScreenState();
}

class _ChildSleepHoursScreenState extends State<ChildSleepHoursScreen> {
  final _dailyMissionsRepository = dailyMissionsRepository;

  List<DailyMission> _missions = [];
  String? _parentId;
  String? _childId;
  bool _contextReady = false;
  bool _isSubmittingDailyMission = false;

  int get _totalMissions => _missions.length;

  int get _completedMissions =>
      _missions.where((mission) => mission.completed).length;

  int get _totalAvailableXp =>
      _missions.fold(0, (sum, mission) => sum + mission.xpReward);

  String _completionKeyForMission(String missionId) {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'genet_daily_mission_completed_${missionId}_${year}_${month}_$day';
  }

  @override
  void initState() {
    super.initState();
    _missions = [
      const DailyMission(
        id: 'reading_15_min',
        title: '📚 לקרוא ספר 15 דקות',
        description: 'קריאה יומית משפרת את הדמיון, השפה והריכוז.',
        xpReward: 20,
        type: DailyMissionType.study,
        completed: false,
      ),
    ];
    _resolveMissionContext();
    _loadMissionStatus();
  }

  Future<void> _resolveMissionContext() async {
    final parentId = normalizeIdentifier(await getLinkedParentId());
    final childId = normalizeIdentifier(await getLinkedChildId());
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

  Stream<List<feature.DailyMission>>? get _dailyMissionsStream {
    if (!_hasMissionContext) return null;
    return _dailyMissionsRepository.watchDailyMissions(
      parentId: _parentId!,
      childId: _childId!,
    );
  }

  Future<void> _submitTodayDailyMission(String missionId) async {
    if (_isSubmittingDailyMission) return;
    if (!_hasMissionContext) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSubmittingDailyMission = true);

    try {
      await _dailyMissionsRepository.submitMission(
        parentId: _parentId!,
        childId: _childId!,
        missionId: missionId,
      );
    } catch (error, stackTrace) {
      debugPrint('[GENET][DAILY_MISSIONS][SUBMIT] ui error=$error');
      debugPrint('[GENET][DAILY_MISSIONS][SUBMIT] $stackTrace');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('לא ניתן היה לשלוח את המשימה. נסה שוב.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingDailyMission = false);
      }
    }
  }

  Future<void> _loadMissionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _missions = _missions
          .map(
            (mission) => mission.copyWith(
              completed:
                  prefs.getBool(_completionKeyForMission(mission.id)) ?? false,
            ),
          )
          .toList();
    });
  }

  Future<void> _completeMission(String missionId) async {
    final index = _missions.indexWhere((m) => m.id == missionId);
    if (index == -1 || _missions[index].completed) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completionKeyForMission(missionId), true);
    if (!mounted) return;
    setState(() {
      _missions = _missions
          .map(
            (mission) => mission.id == missionId
                ? mission.copyWith(completed: true)
                : mission,
          )
          .toList();
    });
  }

  Widget _buildMissionCard(DailyMission mission) {
    final completed = mission.completed;

    return Card(
      key: ValueKey(mission.id),
      elevation: 1,
      color: completed ? Colors.green.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: completed
            ? BorderSide(color: Colors.green.shade300, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${missionTypeEmoji(mission.type)} ${missionTypeLabel(mission.type)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              mission.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mission.description,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '+${mission.xpReward} XP',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: completed ? Colors.green.shade800 : AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              completed ? 'הושלמה ✅' : 'ממתינה להשלמה',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: completed ? Colors.green.shade700 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: completed ? null : () => _completeMission(mission.id),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                disabledBackgroundColor: Colors.green.shade600,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                completed ? 'כל הכבוד! 🎉' : 'סיימתי את המשימה',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyMissionCard({
    feature.DailyMission? mission,
    bool loading = false,
    String? errorMessage,
  }) {
    return Card(
      elevation: 1,
      color: AppTheme.lightBlue.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'המשימה היומית שלי',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (errorMessage != null)
              Text(
                errorMessage,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.red.shade700,
                ),
              )
            else if (mission == null)
              Text(
                'אין משימה יומית להיום',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              )
            else ...[
              Text(
                mission.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (mission.description != null &&
                  mission.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              const SizedBox(height: 16),
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
              if (mission.isWaitingForChild)
                FilledButton(
                  onPressed: _isSubmittingDailyMission
                      ? null
                      : () => _submitTodayDailyMission(mission.id),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _isSubmittingDailyMission
                        ? 'שולח...'
                        : 'ביצעתי את המשימה',
                  ),
                )
              else if (mission.isWaitingForParentApproval)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    'נשלח לאישור ההורה',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade900,
                    ),
                  ),
                )
              else if (mission.isApproved)
                Text(
                  'המשימה אושרה',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                )
              else if (mission.isRejected)
                Text(
                  'ההורה דחה את הביצוע',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
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
              'המשימות שלי היום',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 12),
            if (_missions.isEmpty)
              Text(
                'אין משימות להיום',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              )
            else ...[
              Text(
                'הושלמו: $_completedMissions מתוך $_totalMissions',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'תגמול אפשרי: $_totalAvailableXp XP',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyMissionsState() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '🎉 אין משימות להיום',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'כל הכבוד, אפשר לנוח בינתיים.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('המשימה שלי'),
        ),
        body: !_contextReady
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<List<feature.DailyMission>>(
                stream: _dailyMissionsStream,
                builder: (context, snapshot) {
                  final loading = _hasMissionContext &&
                      snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData;
                  final errorMessage = snapshot.hasError
                      ? 'לא הצלחנו לטעון את המשימה היומית. נסה שוב מאוחר יותר.'
                      : null;
                  final todayMission = _hasMissionContext
                      ? pickNewestMissionForDay(snapshot.data ?? const [])
                      : null;

                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text(
                        '⭐ המשימה שלי',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'הרגלים קטנים יוצרים הצלחות גדולות.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSummaryCard(),
                      const SizedBox(height: 16),
                      _buildDailyMissionCard(
                        mission: todayMission,
                        loading: loading,
                        errorMessage: errorMessage,
                      ),
                      const SizedBox(height: 16),
                      if (_missions.isEmpty)
                        _buildEmptyMissionsState()
                      else
                        ..._missions.map(_buildMissionCard),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
