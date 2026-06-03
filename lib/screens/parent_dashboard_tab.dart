import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../models/child_entity.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../widgets/parent_message_history_section.dart';
import 'add_child_by_link_screen.dart';
import 'blocked_apps_screen.dart';
import 'children_management_screen.dart';
import 'content_library_screen.dart';
import 'settings_screen.dart';
import 'sleep_lock_screen.dart';

/// Parent Dashboard — Genet premium dark layout wired to existing routes.
class ParentDashboardTab extends StatefulWidget {
  const ParentDashboardTab({super.key});

  @override
  State<ParentDashboardTab> createState() => _ParentDashboardTabState();
}

/// Visual tokens aligned with [FigmaLoginScreen] / [_SpaceBackground].
class _DashboardTokens {
  static const Color neonGreen = Color(0xFF39FF88);
  static const Color fieldFill = Color(0x1AFFFFFF);
  static const Color fieldBorder = Color(0x33FFFFFF);
  static const double sectionGap = 10;
  static const double cardGap = 8;
  static const double horizontalPad = 16;
  static const double cardRadius = 18;
  static const BorderRadius cardRadiusBR =
      BorderRadius.all(Radius.circular(cardRadius));

  static BoxDecoration panelDecoration() => BoxDecoration(
        borderRadius: cardRadiusBR,
        color: fieldFill,
        border: Border.all(color: fieldBorder, width: 1),
      );

  static BoxDecoration primaryPanelDecoration() => BoxDecoration(
        borderRadius: cardRadiusBR,
        color: fieldFill,
        border: Border.all(
          color: neonGreen.withValues(alpha: 0.5),
          width: 1.5,
        ),
      );

  static BoxDecoration heroPanelDecoration() => BoxDecoration(
        borderRadius: cardRadiusBR,
        color: fieldFill,
        border: Border.all(
          color: fieldBorder,
          width: 1,
        ),
      );
}

class _ParentDashboardTabState extends State<ParentDashboardTab> {
  int _messageRefreshKey = 0;
  bool _navigationLocked = false;

  bool _loading = true;
  String? _parentId;
  String? _selectedChildId;
  List<ChildEntity> _connectedChildren = const [];
  List<ChildEntity> _localChildren = const [];
  ChildEntity? _displayChild;
  bool _isConnected = false;
  String? _deviceName;
  int _blockedCount = 0;
  bool _sleepLockActive = false;
  String? _genetPackageName;

  bool _childrenStreamReady = false;
  bool _childDocReady = false;
  bool _sleepLockReady = false;

  StreamSubscription<List<ChildEntity>>? _childrenSub;
  StreamSubscription<String?>? _selectedChildSub;
  StreamSubscription<Map<String, dynamic>?>? _childDocSub;
  StreamSubscription<Map<String, dynamic>?>? _sleepLockSub;

  // TODO(GENET): Wire daily screen-time when usage stats exist in the app.
  static const String _screenTimeValue = '--';

  @override
  void initState() {
    super.initState();
    _bootstrapDashboardData();
  }

  @override
  void dispose() {
    _childrenSub?.cancel();
    _selectedChildSub?.cancel();
    _childDocSub?.cancel();
    _sleepLockSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapDashboardData() async {
    _genetPackageName = await GenetConfig.getPackageName();
    _localChildren = await getChildren();
    _selectedChildId = normalizeIdentifier(await getSelectedChildId());
    _parentId = normalizeIdentifier(await getOrCreateParentId());

    _selectedChildSub = watchSelectedChildId().listen((childId) {
      if (!mounted) return;
      final normalized = normalizeIdentifier(childId);
      if (normalized == _selectedChildId) return;
      setState(() => _selectedChildId = normalized);
      _resolveDisplayChild();
      _attachChildListeners();
    });

    if (_parentId == null || _parentId!.isEmpty) {
      _finishInitialLoad(noChild: true);
      return;
    }

    _childrenSub = watchParentChildrenStream(_parentId!).listen((connected) {
      if (!mounted) return;
      setState(() => _connectedChildren = connected);
      _childrenStreamReady = true;
      _resolveDisplayChild();
      _attachChildListeners();
      _maybeFinishInitialLoad();
    });
  }

  void _resolveDisplayChild() {
    ChildEntity? child;
    final selected = _selectedChildId;
    if (selected != null && selected.isNotEmpty) {
      child = _findChildById(selected);
    }
    child ??= _connectedChildren.isNotEmpty ? _connectedChildren.first : null;
    child ??= _localChildren.isNotEmpty ? _localChildren.first : null;

    final connectedIds = _connectedChildren.map((c) => c.childId).toSet();
    final isConnected = child != null && connectedIds.contains(child.childId);

    if (_displayChild?.childId != child?.childId ||
        _isConnected != isConnected) {
      _childDocReady = false;
      _sleepLockReady = false;
    }

    _displayChild = child;
    _isConnected = isConnected;

    if (child != null && isConnected) {
      debugPrint(
        '[GENET][PARENT_DASHBOARD] Child Loaded childId=${child.childId} name=${child.name}',
      );
    }
  }

  ChildEntity? _findChildById(String childId) {
    for (final c in _connectedChildren) {
      if (c.childId == childId) return c;
    }
    for (final c in _localChildren) {
      if (c.childId == childId) return c;
    }
    return null;
  }

  void _attachChildListeners() {
    _childDocSub?.cancel();
    _sleepLockSub?.cancel();

    final childId = normalizeIdentifier(_displayChild?.childId);
    final parentId = _parentId;
    if (!_isConnected ||
        childId == null ||
        childId.isEmpty ||
        parentId == null ||
        parentId.isEmpty) {
      _deviceName = null;
      _blockedCount = 0;
      _sleepLockActive = false;
      _childDocReady = true;
      _sleepLockReady = true;
      _maybeFinishInitialLoad();
      return;
    }

    _childDocSub =
        watchParentChildDocStream(parentId, childId).listen((data) async {
      if (!mounted) return;
      final blocked = _blockedPackagesFromDoc(data);
      final device = _deviceNameFromDoc(data);
      setState(() {
        _deviceName = device;
        _blockedCount = blocked;
        if (data != null) {
          final status = data['connectionStatus'] as String?;
          _isConnected = isConnectionStatusConnected(status);
        }
      });
      if (!_childDocReady) {
        _childDocReady = true;
        debugPrint(
          '[GENET][PARENT_DASHBOARD] Blocked Apps Loaded count=$blocked childId=$childId',
        );
        _maybeFinishInitialLoad();
      }
    });

    _sleepLockSub = watchChildSleepLockStream(childId).listen((data) {
      if (!mounted) return;
      final active = data?['isActive'] == true;
      setState(() => _sleepLockActive = active);
      if (!_sleepLockReady) {
        _sleepLockReady = true;
        debugPrint(
          '[GENET][PARENT_DASHBOARD] Sleep Lock Loaded active=$active childId=$childId',
        );
        _maybeFinishInitialLoad();
      }
    });
  }

  int _blockedPackagesFromDoc(Map<String, dynamic>? data) {
    final raw = (data?['blockedPackages'] as List?)?.cast<String>() ?? const [];
    final genetPkg = _genetPackageName ?? '';
    return raw.where((p) => genetPkg.isEmpty || p != genetPkg).length;
  }

  String? _deviceNameFromDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in const ['deviceName', 'deviceModel', 'device', 'model']) {
      final top = data[key];
      if (top is String && top.trim().isNotEmpty) return top.trim();
    }
    final profile = data['profile'];
    if (profile is Map) {
      for (final key in const ['deviceName', 'deviceModel', 'device', 'model']) {
        final value = profile[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  void _maybeFinishInitialLoad() {
    if (!_childrenStreamReady) return;
    final hasConnectedChild = _connectedChildren.isNotEmpty;
    if (!hasConnectedChild) {
      _finishInitialLoad(noChild: true);
      return;
    }
    if (_childDocReady && _sleepLockReady) {
      _finishInitialLoad(noChild: false);
    }
  }

  void _finishInitialLoad({required bool noChild}) {
    if (!_loading) return;
    if (noChild) {
      debugPrint('[GENET][PARENT_DASHBOARD] No Child Connected');
    }
    setState(() => _loading = false);
  }

  bool get _showNoChildState =>
      !_loading && _connectedChildren.isEmpty;

  Future<void> _pushExistingScreen(Widget screen, {VoidCallback? onReturn}) async {
    if (_navigationLocked || !mounted) return;
    _navigationLocked = true;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => screen),
      );
      if (!mounted) return;
      onReturn?.call();
    } finally {
      if (mounted) _navigationLocked = false;
    }
  }

  void _openChildrenManagement() {
    _pushExistingScreen(
      const ChildrenManagementScreen(),
      onReturn: () {
        if (!mounted) return;
        setState(() => _messageRefreshKey++);
        unawaited(_reloadChildrenSnapshot());
      },
    );
  }

  void _openContentLibrary() {
    _pushExistingScreen(const ContentLibraryScreen());
  }

  void _openSleepLock() {
    _pushExistingScreen(const SleepLockScreen());
  }

  void _openBlockedApps() {
    _pushExistingScreen(const BlockedAppsScreen());
  }

  void _openSettings() {
    _pushExistingScreen(const SettingsScreen());
  }

  void _openMessagesScreen() {
    final refreshKey = _messageRefreshKey;
    _pushExistingScreen(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF050B18),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A1A3A),
            foregroundColor: Colors.white,
            title: const Text('הודעות'),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_DashboardTokens.horizontalPad),
              child: ParentMessageHistorySection(
                refreshKeyValue: refreshKey,
              ),
            ),
          ),
        ),
      ),
      onReturn: () => setState(() => _messageRefreshKey++),
    );
  }

  void _openAddChild() {
    _pushExistingScreen(
      const AddChildByLinkScreen(),
      onReturn: () {
        if (!mounted) return;
        setState(() {
          _loading = true;
          _childrenStreamReady = false;
          _childDocReady = false;
          _sleepLockReady = false;
        });
        unawaited(_reloadChildrenSnapshot());
      },
    );
  }

  Future<void> _reloadChildrenSnapshot() async {
    _localChildren = await getChildren();
    _selectedChildId = normalizeIdentifier(await getSelectedChildId());
    if (!mounted) return;
    setState(() => _resolveDisplayChild());
    _attachChildListeners();
    if (_connectedChildren.isEmpty) {
      _finishInitialLoad(noChild: true);
    } else {
      _maybeFinishInitialLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sleepValue = _sleepLockActive ? 'ON' : 'OFF';
    final blockedValue = _blockedCount.toString();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _DashboardTokens.horizontalPad,
            2,
            _DashboardTokens.horizontalPad,
            4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DashboardHeader(onSettings: _openSettings),
              const SizedBox(height: 4),
              Expanded(
                flex: 40,
                child: _showNoChildState
                    ? _NoChildConnectedCard(onAddChild: _openAddChild)
                    : _ChildStatusCard(
                        loading: _loading,
                        childName: _displayChild?.name ?? '',
                        isConnected: _isConnected,
                        deviceName: _deviceName,
                      ),
              ),
              const SizedBox(height: _DashboardTokens.sectionGap),
              Expanded(
                flex: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _QuickStatCard(
                        emoji: '⏱',
                        label: 'שעות מסך',
                        value: _screenTimeValue,
                        loading: _loading && !_showNoChildState,
                      ),
                    ),
                    const SizedBox(width: _DashboardTokens.cardGap),
                    Expanded(
                      child: _QuickStatCard(
                        emoji: '🚫',
                        label: 'אפליקציות חסומות',
                        value: _showNoChildState ? '--' : blockedValue,
                        loading: _loading && !_showNoChildState,
                      ),
                    ),
                    const SizedBox(width: _DashboardTokens.cardGap),
                    Expanded(
                      child: _QuickStatCard(
                        emoji: '🌙',
                        label: 'מצב שינה',
                        value: _showNoChildState ? '--' : sleepValue,
                        loading: _loading && !_showNoChildState,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _DashboardTokens.sectionGap),
              _ManagementButton(onTap: _openChildrenManagement),
              const SizedBox(height: _DashboardTokens.sectionGap),
              Expanded(
                flex: 17,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        emoji: '🎓',
                        title: 'תכנים חיוביים',
                        onTap: _openContentLibrary,
                      ),
                    ),
                    const SizedBox(width: _DashboardTokens.cardGap),
                    Expanded(
                      child: _QuickActionCard(
                        emoji: '⏰',
                        title: 'שעות מסך ושינה',
                        onTap: _openSleepLock,
                      ),
                    ),
                    const SizedBox(width: _DashboardTokens.cardGap),
                    Expanded(
                      child: _QuickActionCard(
                        emoji: '🔒',
                        title: 'אפליקציות נעולות',
                        onTap: _openBlockedApps,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _DashboardTokens.sectionGap),
              _MessageLaunchCard(onTap: _openMessagesScreen),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          _HeaderIconButton(
            icon: Icons.settings_rounded,
            tooltip: 'הגדרות',
            onPressed: onSettings,
          ),
          Expanded(child: _GenetLogoMark()),
          const _HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'התראות',
          ),
        ],
      ),
    );
  }
}

class _GenetLogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'GENET',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.2,
        color: Colors.white.withValues(alpha: 0.82),
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onPressed,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 175),
          curve: Curves.easeOut,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _DashboardTokens.fieldFill,
              border: Border.all(
                color: _DashboardTokens.fieldBorder,
                width: 1,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 20,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildStatusCard extends StatelessWidget {
  const _ChildStatusCard({
    required this.loading,
    required this.childName,
    required this.isConnected,
    required this.deviceName,
  });

  final bool loading;
  final String childName;
  final bool isConnected;
  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    final statusColor = isConnected
        ? _DashboardTokens.neonGreen
        : Colors.white.withValues(alpha: 0.45);
    final statusLabel = isConnected ? 'מחובר' : 'לא מחובר';

    return _HeroDarkCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const _SkeletonBar(width: 140, height: 28)
          else
            Row(
              children: [
                const Text('👦', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    childName.isNotEmpty ? childName : 'ילד',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.98),
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (loading)
            const _SkeletonBar(width: 96, height: 16)
          else
            Row(
              children: [
                _StatusDot(
                  color: statusColor,
                  glowing: isConnected,
                ),
                const SizedBox(width: 8),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          if (!loading &&
              deviceName != null &&
              deviceName!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              deviceName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.48),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.glowing});

  final Color color;
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: glowing
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
    );
  }
}

class _NoChildConnectedCard extends StatelessWidget {
  const _NoChildConnectedCard({required this.onAddChild});

  final VoidCallback onAddChild;

  @override
  Widget build(BuildContext context) {
    return _HeroDarkCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👦', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 10),
          Text(
            'לא מחובר ילד',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.96),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'הוסף ילד כדי להתחיל',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.52),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: _PrimaryOutlineButton(
              label: 'הוסף ילד',
              onTap: onAddChild,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withValues(alpha: 0.14),
      ),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  const _QuickStatCard({
    required this.emoji,
    required this.label,
    required this.value,
    this.loading = false,
  });

  final String emoji;
  final String label;
  final String value;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _PremiumDarkCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const _SkeletonBar(width: 48, height: 22)
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.97),
                height: 1,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              height: 1.15,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagementButton extends StatelessWidget {
  const _ManagementButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: _DashboardTapTarget(
        onTap: onTap,
        borderRadius: _DashboardTokens.cardRadiusBR,
        child: Container(
          decoration: _DashboardTokens.primaryPanelDecoration(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(
                Icons.people_alt_rounded,
                color: _DashboardTokens.neonGreen.withValues(alpha: 0.95),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ניהול ילדים',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.97),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: Colors.white.withValues(alpha: 0.45),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.emoji,
    required this.title,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DashboardTapTarget(
      onTap: onTap,
      borderRadius: _DashboardTokens.cardRadiusBR,
      child: _PremiumDarkCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.15,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageLaunchCard extends StatelessWidget {
  const _MessageLaunchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: _DashboardTapTarget(
        onTap: onTap,
        borderRadius: _DashboardTokens.cardRadiusBR,
        child: Container(
          decoration: _DashboardTokens.panelDecoration(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'שלח הודעה לילד',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'ההודעה תופיע במכשיר של הילד',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: Colors.white.withValues(alpha: 0.35),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryOutlineButton extends StatelessWidget {
  const _PrimaryOutlineButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DashboardTapTarget(
      onTap: onTap,
      borderRadius: _DashboardTokens.cardRadiusBR,
      child: Container(
        alignment: Alignment.center,
        decoration: _DashboardTokens.primaryPanelDecoration(),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _DashboardTokens.neonGreen.withValues(alpha: 0.95),
          ),
        ),
      ),
    );
  }
}

class _HeroDarkCard extends StatelessWidget {
  const _HeroDarkCard({
    required this.child,
    required this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: padding,
      decoration: _DashboardTokens.heroPanelDecoration(),
      child: child,
    );
  }
}

class _PremiumDarkCard extends StatelessWidget {
  const _PremiumDarkCard({
    required this.child,
    required this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: padding,
      decoration: _DashboardTokens.panelDecoration(),
      child: child,
    );
  }
}

class _DashboardTapTarget extends StatefulWidget {
  const _DashboardTapTarget({
    required this.onTap,
    required this.borderRadius,
    required this.child,
  });

  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<_DashboardTapTarget> createState() => _DashboardTapTargetState();
}

class _DashboardTapTargetState extends State<_DashboardTapTarget> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: _setPressed,
        borderRadius: widget.borderRadius,
        splashColor: Colors.white.withValues(alpha: 0.14),
        highlightColor: Colors.white.withValues(alpha: 0.07),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 175),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
