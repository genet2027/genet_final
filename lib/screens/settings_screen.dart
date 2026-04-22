import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/genet_config.dart';
import '../core/genet_vpn.dart';
import '../core/vpn_remote_child.dart';
import '../core/pin_storage.dart';
import '../core/user_role.dart';
import '../features/blocked_apps/blocked_package_matching.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/rounded_card.dart';
import 'backup_support_screen.dart';
import 'night_mode_settings_screen.dart';
import 'pin_login_screen.dart';

/// Settings tab content: entries to Night Mode, VPN controls, Backup & Support, and Logout.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  List<String> _missingPermissions = [];
  bool _deviceAdminEnabled = false;
  bool _batteryOptimizationIgnored = true;
  bool? _vpnRunning;
  bool? _isParentRole;
  bool _requireVpn = false;
  StreamSubscription<Map<String, dynamic>?>? _parentVpnDocSub;
  StreamSubscription<String?>? _selectedChildIdSub;
  String? _boundSelectedChildId;
  /// Last [vpnStatus] from child doc (on|off|error); parent device does not use local VPN for this.
  String? _parentRemoteVpnStatus;

  Future<String?> _resolveSelectedChildId() async {
    final selectedChildId = normalizeIdentifier(await getSelectedChildId());
    debugPrint('[GenetDebug] SELECTED CHILD ID: ${selectedChildId ?? 'none'}');
    return selectedChildId;
  }

  Future<void> _refreshParentSelectionBindingsIfNeeded() async {
    if (_isParentRole != true) return;
    final selectedChildId = await _resolveSelectedChildId();
    if (!mounted || selectedChildId == _boundSelectedChildId) return;
    _boundSelectedChildId = selectedChildId;
    await _bindParentVpnStatusStream();
    await _loadRequireVpn();
  }

  Future<void> _bindParentVpnStatusStream() async {
    await _parentVpnDocSub?.cancel();
    _parentVpnDocSub = null;
    if (_isParentRole != true) return;
    final pid = normalizeIdentifier(await getOrCreateParentId());
    final cid = await _resolveSelectedChildId();
    _boundSelectedChildId = cid;
    if (pid == null || cid == null) {
      if (mounted) setState(() => _parentRemoteVpnStatus = 'off');
      return;
    }
    debugPrint('[GenetDebug] PARENT ID: $pid');
    debugPrint('[GenetDebug] READ PATH: genet_parents/$pid/children/$cid');
    _parentVpnDocSub = watchParentChildDocStream(pid, cid).listen((data) {
      if (!mounted) return;
      final raw = data?['vpnStatus'] as String?;
      setState(() => _parentRemoteVpnStatus = raw ?? 'off');
    });
  }

  Widget _buildParentVpnDot() {
    final s = _parentRemoteVpnStatus ?? 'off';
    final Color c;
    switch (s) {
      case 'on':
        c = Colors.green;
        break;
      case 'error':
        c = Colors.amber.shade700;
        break;
      default:
        c = Colors.red;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissionsSection();
    getUserRole().then((r) {
      if (!mounted) return;
      final isParent = r == kUserRoleParent;
      setState(() => _isParentRole = isParent);
      if (!isParent) {
        _loadVpnRunning();
      } else {
        _bindParentVpnStatusStream();
        _loadRequireVpn();
        _selectedChildIdSub = watchSelectedChildId().listen((selectedChildId) {
          if (!mounted || _isParentRole != true) return;
          final normalized = normalizeIdentifier(selectedChildId);
          if (normalized == _boundSelectedChildId) return;
          _boundSelectedChildId = normalized;
          unawaited(_bindParentVpnStatusStream());
          unawaited(_loadRequireVpn());
        });
      }
    });
  }

  @override
  void dispose() {
    _parentVpnDocSub?.cancel();
    _selectedChildIdSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadPermissionsSection();
        if (_isParentRole != true) {
          _loadVpnRunning();
        } else {
          _refreshParentSelectionBindingsIfNeeded();
        }
      });
    }
  }

  Future<void> _loadVpnRunning() async {
    if (!Platform.isAndroid) return;
    final v = await GenetVpn.isVpnRunning();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _vpnRunning = v);
    });
  }

  Future<void> _loadRequireVpn() async {
    if (_isParentRole != true) return;
    final cid = await _resolveSelectedChildId();
    if (cid == null) {
      if (mounted) setState(() => _requireVpn = false);
      return;
    }
    final value = await getRequireVpnFromFirebase(cid);
    if (mounted) setState(() => _requireVpn = value);
  }

  /// Linked child device → linked child id; parent device → [getSelectedChildId] (same as BlockedAppsScreen); else legacy key.
  Future<List<String>> _blockedPackagesForVpn() async {
    final prefs = await SharedPreferences.getInstance();
    final linkedChildId = await getLinkedChildId();
    if (linkedChildId != null && linkedChildId.isNotEmpty) {
      final list = await getBlockedPackagesForChild(linkedChildId);
      debugPrint('[GenetVpn] blocked_packages_for_vpn source=linkedChild id=$linkedChildId count=${list.length} $list');
      return list;
    }
    final selectedChildId = await _resolveSelectedChildId();
    if (selectedChildId != null) {
      final list = await getBlockedPackagesForChild(selectedChildId);
      debugPrint('[GenetVpn] blocked_packages_for_vpn source=selectedChild id=$selectedChildId count=${list.length} $list');
      return list;
    }
    final legacy = prefs.getStringList('genet_blocked_packages') ?? [];
    debugPrint('[GenetVpn] blocked_packages_for_vpn source=legacy count=${legacy.length} $legacy');
    return legacy;
  }

  Future<bool> _verifyParentPin(BuildContext context) async {
    final hasPin = await PinStorage.hasPin();
    if (!context.mounted) return false;
    if (!hasPin) {
      return _verifyOrCreatePin(context, isCreate: true);
    }
    final pinController = TextEditingController();
    bool? result;
    try {
      result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('אימות קוד PIN'),
            content: TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'קוד PIN'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
              FilledButton(
                onPressed: () async {
                  final pin = pinController.text;
                  if (pin.length < 4) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('לפחות 4 ספרות')));
                    return;
                  }
                  final ok = await PinStorage.verifyPin(pin);
                  if (!ctx.mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('סיסמת הורה שגויה')));
                    return;
                  }
                  if (mounted) await GenetConfig.setPin(pin);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('אישור'),
              ),
            ],
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        pinController.dispose();
      });
    }
    return result ?? false;
  }

  Future<void> _onStartBlockingVpn() async {
    if (!Platform.isAndroid) return;
    final ok = await _verifyParentPin(context);
    if (!ok || !mounted) return;

    final role = await getUserRole();
    if (role == kUserRoleParent) {
      final blocked = await _blockedPackagesForVpn();
      if (blocked.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('אין אפליקציות חסומות להפעלת חסימת רשת.')),
          );
        }
        return;
      }
      final parentId = await getOrCreateParentId();
      final cid = await getSelectedChildId();
      debugPrint('[GenetVpn] selectedChildId=$cid');
      if (cid == null || cid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('בחר ילד והגדר את רשימת החסימות.')),
          );
        }
        return;
      }
      await syncVpnPolicyToFirebase(parentId, cid, vpnEnabled: true);
      await writeRequireVpnToFirebase(cid, requireVpn: true);
      await _bindParentVpnStatusStream();
      await _loadRequireVpn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('העדכון נשלח למכשיר הילד.')),
        );
      }
      return;
    }

    if (await GenetVpn.isVpnRunning()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('החסימה כבר פעילה')),
        );
      }
      await _loadVpnRunning();
      return;
    }
    final blocked = await _blockedPackagesForVpn();
    final linkedForExt = await getLinkedChildId();
    final ext = (linkedForExt != null && linkedForExt.isNotEmpty)
        ? await getExtensionApprovedForChild(linkedForExt)
        : <String, int>{};
    final expanded = effectiveBlockedPackageIds(blocked);
    final effective = VpnRemoteChildPolicy.effectiveBlockedFromLists(
      blocked,
      ext,
      currentTimeMs: DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint(
      '[GenetVpn] nativePush path=settings_screen child role channel=genet/vpn '
      'rawBlocked=$blocked expandedCatalog=$expanded effectiveNative=$effective',
    );
    await GenetVpn.setBlockedApps(effective);
    final r = await GenetVpn.startVpn();
    debugPrint('[GenetVpn] startVpn native result=$r');
    if (!mounted) return;
    await _loadVpnRunning();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (r?['needsPermission'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('נפתחה בקשת אישור VPN. אשר אותה במסך שנפתח — החסימה תופעל אוטומטית אחרי האישור.')),
        );
        return;
      }
      if (r?['started'] != true && effective.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('אין אפליקציות חסומות להפעלת חסימת רשת.')),
        );
      }
    });
  }

  Future<void> _onStopBlockingVpn() async {
    if (!Platform.isAndroid) return;
    final ok = await _verifyParentPin(context);
    if (!ok || !mounted) return;

    final role = await getUserRole();
    if (role == kUserRoleParent) {
      final parentId = await getOrCreateParentId();
      final cid = await getSelectedChildId();
      debugPrint('[GenetVpn] selectedChildId=$cid');
      if (cid == null || cid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('בחר ילד.')),
          );
        }
        return;
      }
      await syncVpnPolicyToFirebase(parentId, cid, vpnEnabled: false);
      await writeRequireVpnToFirebase(cid, requireVpn: false);
      await _bindParentVpnStatusStream();
      await _loadRequireVpn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('העדכון נשלח למכשיר הילד.')),
        );
      }
      return;
    }

    if (!await GenetVpn.isVpnRunning()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('החסימה כבר כבויה')),
        );
      }
      await _loadVpnRunning();
      return;
    }
    await GenetVpn.stopVpn();
    if (mounted) await _loadVpnRunning();
  }

  Future<void> _loadPermissionsSection() async {
    if (!Platform.isAndroid) return;
    final missing = await GenetConfig.getMissingPermissions();
    final deviceAdmin = await GenetConfig.getIsDeviceAdminEnabled();
    final battery = await GenetConfig.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
      _missingPermissions = missing;
      _deviceAdminEnabled = deviceAdmin;
      _batteryOptimizationIgnored = battery;
    });
    }
  }

  Future<bool> _verifyOrCreatePin(BuildContext context, {required bool isCreate}) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isCreate ? 'יצירת קוד PIN' : 'אימות קוד PIN'),
          content: isCreate
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'קוד PIN חדש'),
                    ),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'אימות קוד PIN'),
                    ),
                  ],
                )
              : TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'קוד PIN'),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            FilledButton(
              onPressed: () async {
                final pin = pinController.text;
                if (pin.length < 4) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('לפחות 4 ספרות')));
                  return;
                }
                if (isCreate) {
                  if (pin != confirmController.text) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('הקודים לא תואמים')));
                    return;
                  }
                  await PinStorage.savePin(pin);
                  if (!ctx.mounted) return;
                  if (mounted) GenetConfig.setPin(pin);
                } else {
                  final ok = await PinStorage.verifyPin(pin);
                  if (!ctx.mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('קוד PIN שגוי')));
                    return;
                  }
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('אישור'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _onRequireVpnToggle(bool value) async {
    if (_isParentRole != true) return;
    if (value) {
      await _onStartBlockingVpn();
    } else {
      await _onStopBlockingVpn();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        RoundedCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NightModeSettingsScreen(),
            ),
          ),
          icon: Icons.bedtime_rounded,
          title: 'מצב לילה (חופשת שינה)',
          subtitle: 'שעות שינה ורמת התנהגות',
        ),
        const SizedBox(height: 12),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 8),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Text(
                    'חסימת רשת (VPN)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                if (_isParentRole == true) _buildParentVpnDot(),
              ],
            ),
          ),
          RoundedCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isParentRole == true
                        ? 'החסימה מתבצעת במכשיר הילד בלבד. ההפעלה והכיבוי נשלחים לילד הנבחר — לא מפעילים VPN במכשיר זה.'
                        : _vpnRunning == null
                            ? '…'
                            : (_vpnRunning! ? 'חסימת רשת פעילה' : 'חסימת רשת כבויה'),
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  if (_isParentRole == true)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('חייב הגנה (VPN)'),
                      value: _requireVpn,
                      onChanged: _onRequireVpnToggle,
                      activeThumbColor: AppTheme.primaryBlue,
                    ),
                  if (_isParentRole == true) const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _onStartBlockingVpn,
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('הפעל חסימה'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _onStopBlockingVpn,
                    icon: const Icon(Icons.shield_moon_outlined),
                    label: const Text('עצור חסימה'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 8),
            child: Text(
              'הרשאות מערכת',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          _PermissionRow(
            title: 'Usage Access',
            enabled: !_missingPermissions.contains('usage'),
            onOpenSettings: () async {
              await GenetConfig.openUsageAccessSettings();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            title: 'Display Over Other Apps (Overlay)',
            enabled: !_missingPermissions.contains('overlay'),
            onOpenSettings: () async {
              await GenetConfig.openOverlaySettings();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            title: 'Ignore Battery Optimization',
            enabled: _batteryOptimizationIgnored,
            onOpenSettings: () async {
              await GenetConfig.openBatteryOptimizationSettings();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            title: 'Device Admin',
            enabled: _deviceAdminEnabled,
            onOpenSettings: () async {
              await GenetConfig.enableDeviceAdmin();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        RoundedCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BackupSupportScreen(),
            ),
          ),
          icon: Icons.backup_rounded,
          title: 'גיבוי ותמיכה',
          subtitle: 'ייצוא/ייבוא גיבוי, דיווח בעיה, צור קשר',
        ),
        const SizedBox(height: 32),
        RoundedCard(
          onTap: () => _logout(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.logout_rounded,
                    color: Colors.red.shade400, size: 28),
                const SizedBox(width: 16),
                Text(
                  'יציאה',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.red.shade400,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PinLoginScreen()),
      (route) => false,
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.enabled,
    required this.onOpenSettings,
  });
  final String title;
  final bool enabled;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? 'Enabled' : 'Disabled',
                    style: TextStyle(
                      fontSize: 13,
                      color: enabled ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpenSettings,
              child: const Text('פתח הגדרות'),
            ),
          ],
        ),
      ),
    );
  }
}
