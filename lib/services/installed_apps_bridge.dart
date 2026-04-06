import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/installed_app_raw.dart';
import '../models/package_change_event.dart';

/// Flutter side of [InstalledAppsChannel] — `genet/installed_apps` → `getInstalledApps`.
class InstalledAppsBridge {
  InstalledAppsBridge._();

  static const MethodChannel _channel = MethodChannel('genet/installed_apps');

  static final StreamController<PackageChangeEvent> _packageChangeController =
      StreamController<PackageChangeEvent>.broadcast();

  static bool _packageInboundAttached = false;

  /// Native → Dart [onPackageChanged] (Step 3). Call once on child home (idempotent).
  static void ensurePackageChangeInboundHandler() {
    if (_packageInboundAttached) return;
    _packageInboundAttached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onPackageChanged') return;
      final args = call.arguments;
      if (args is Map) {
        final ev = PackageChangeEvent.tryParse(Map<String, dynamic>.from(args));
        if (ev != null && !_packageChangeController.isClosed) {
          _packageChangeController.add(ev);
        }
      }
    });
  }

  /// Package add/remove from [BroadcastReceiver] (no full scan on native side).
  static Stream<PackageChangeEvent> get packageChangeStream =>
      _packageChangeController.stream;

  static Future<List<InstalledAppRaw>> fetchInstalledAppsRaw() async {
    if (!Platform.isAndroid) return [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (raw == null) return [];
      final out = <InstalledAppRaw>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final row = InstalledAppRaw.tryParse(Map<String, dynamic>.from(e));
        if (row != null) out.add(row);
      }
      return out;
    } on PlatformException catch (e, st) {
      debugPrint('[InstalledAppsBridge] getInstalledApps failed: $e $st');
      return [];
    }
  }

  /// Single package row from native (Step 3). Returns null if uninstalled / error.
  static Future<InstalledAppRaw?> fetchInstalledAppRaw(String packageName) async {
    if (!Platform.isAndroid) return null;
    final pkg = packageName.trim();
    if (pkg.isEmpty) return null;
    try {
      final row = await _channel.invokeMethod<dynamic>('getInstalledApp', {
        'packageName': pkg,
      });
      if (row == null) return null;
      if (row is! Map) return null;
      return InstalledAppRaw.tryParse(Map<String, dynamic>.from(row));
    } on PlatformException catch (e, st) {
      debugPrint('[InstalledAppsBridge] getInstalledApp failed: $e $st');
      return null;
    }
  }

  /// Maps for [InstalledApp.fromNativeList] / existing repositories (no extra filtering).
  static Future<List<Map<String, dynamic>>> fetchLegacyMapsForInstalledApp() async {
    final raw = await fetchInstalledAppsRaw();
    return raw.map((r) => r.toLegacyNativeMap()).toList();
  }

  /// Temporary Step 1 hook: total count + first 20 rows (debugPrint only).
  static Future<void> debugPrintSample() async {
    final apps = await fetchInstalledAppsRaw();
    debugPrint('[InstalledAppsBridge] total installed apps (raw scan): ${apps.length}');
    final n = apps.length < 20 ? apps.length : 20;
    for (var i = 0; i < n; i++) {
      final a = apps[i];
      debugPrint(
        '[InstalledAppsBridge] [$i] pkg=${a.packageName} name=${a.appName} category=${a.category} isLaunchable=${a.isLaunchable}',
      );
    }
  }
}
