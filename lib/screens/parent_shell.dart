import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/genet_config.dart';
import '../core/user_role.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/parent_profile_repository.dart';
import 'parent_dashboard_tab.dart';
import 'parent_profile_setup_screen.dart';
import 'required_permissions_screen.dart';
import 'settings_screen.dart';

/// Parent-only shell with BottomNavigationBar: Dashboard | Settings.
class ParentShell extends StatefulWidget {
  const ParentShell({super.key});

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _showingRequiredPermissions = false;
  Timer? _permissionCheckTimer;
  bool _parentProfileCheckInFlight = false;

  @override
  void initState() {
    super.initState();
    GenetConfig.commitUserRole(kUserRoleParent);
    getOrCreateParentId();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureParentProfileIfNeeded();
      if (mounted) await _checkPermissionsAndShowIfNeeded();
    });
    _permissionCheckTimer = Timer.periodic(const Duration(seconds: 45), (_) => _checkPermissionsAndShowIfNeeded());
  }

  Future<void> _ensureParentProfileIfNeeded() async {
    if (!mounted || _parentProfileCheckInFlight) return;
    _parentProfileCheckInFlight = true;
    try {
      final parentId = await getOrCreateParentId();
      final profile = await getParentProfile(parentId);
      if (!mounted) return;
      if (!isParentProfileComplete(profile)) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ParentProfileSetupScreen(
              completedBuilder: (_) => const ParentShell(),
            ),
          ),
        );
      }
    } finally {
      _parentProfileCheckInFlight = false;
    }
  }

  @override
  void dispose() {
    _permissionCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissionsAndShowIfNeeded();
  }

  Future<void> _checkPermissionsAndShowIfNeeded() async {
    if (_showingRequiredPermissions || !mounted) return;
    final missing = await GenetConfig.getMissingPermissions();
    if (!mounted) return;
    final missingForMainFlow = missing.where((e) => e != 'accessibility').toList();
    if (missingForMainFlow.isEmpty) return;
    setState(() => _showingRequiredPermissions = true);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RequiredPermissionsScreen(
          onDismiss: () => setState(() => _showingRequiredPermissions = false),
        ),
      ),
    );
    if (mounted) setState(() => _showingRequiredPermissions = false);
  }

  static const List<_TabInfo> _tabs = [
    _TabInfo(icon: Icons.dashboard_rounded, label: 'הורה'),
    _TabInfo(icon: Icons.settings_rounded, label: 'הגדרות'),
  ];

  @override
  Widget build(BuildContext context) {
    final topInset =
        MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFF050B18),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          centerTitle: true,
          title: Text(
            'הורה',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _ParentPremiumBackground(),
            Padding(
              padding: EdgeInsets.only(top: topInset),
              child: IndexedStack(
                index: _selectedIndex,
                children: const [
                  ParentDashboardTab(),
                  SettingsScreen(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF020B2D),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  _tabs.length,
                  (i) => _NavItem(
                    icon: _tabs[i].icon,
                    label: _tabs[i].label,
                    selected: _selectedIndex == i,
                    onTap: () => setState(() => _selectedIndex = i),
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

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo({required this.icon, required this.label});
}

class _ParentPremiumBackground extends StatelessWidget {
  const _ParentPremiumBackground();

  static const List<Color> _gradientColors = [
    Color(0xFF050B18),
    Color(0xFF0A1A3A),
    Color(0xFF0D2B5E),
    Color(0xFF061224),
  ];

  static const List<double> _gradientStops = [0.0, 0.35, 0.72, 1.0];

  static final List<_ShellStar> _stars = _buildStars();

  static List<_ShellStar> _buildStars() {
    final rng = math.Random(42);
    return List.generate(28, (_) {
      return _ShellStar(
        x: rng.nextDouble(),
        y: rng.nextDouble() * 0.42,
        radius: rng.nextDouble() * 0.9 + 0.35,
        opacity: rng.nextDouble() * 0.22 + 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _gradientColors,
          stops: _gradientStops,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.2, -0.55),
            radius: 1.1,
            colors: [
              const Color(0xFF1E88E5).withValues(alpha: 0.18),
              Colors.transparent,
            ],
          ),
        ),
        child: CustomPaint(
          painter: _ShellStarFieldPainter(stars: _stars),
        ),
      ),
    );
  }
}

class _ShellStar {
  const _ShellStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
  });

  final double x;
  final double y;
  final double radius;
  final double opacity;
}

class _ShellStarFieldPainter extends CustomPainter {
  const _ShellStarFieldPainter({required this.stars});

  final List<_ShellStar> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final star in stars) {
      paint.color = Colors.white.withValues(alpha: star.opacity);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShellStarFieldPainter oldDelegate) => false;
}

class _NavItem extends StatelessWidget {
  static const Color _neonGreen = Color(0xFF39FF6A);

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = Colors.white.withValues(alpha: 0.45);
    final activeColor = _neonGreen;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      splashColor: _neonGreen.withValues(alpha: 0.12),
      highlightColor: Colors.white.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? _neonGreen.withValues(alpha: 0.14)
                    : Colors.transparent,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: _neonGreen.withValues(alpha: 0.22),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(
                  icon,
                  size: 26,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? activeColor : inactiveColor,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
