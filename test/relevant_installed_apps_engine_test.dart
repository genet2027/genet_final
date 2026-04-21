import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/core/user_role.dart';
import 'package:genet_final/models/installed_app.dart';
import 'package:genet_final/models/package_change_event.dart';
import 'package:genet_final/repositories/parent_child_sync_repository.dart';
import 'package:genet_final/services/installed_apps_bridge.dart';
import 'package:genet_final/services/relevant_installed_apps_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _kInstalledAppsChannel = MethodChannel('genet/installed_apps');

Map<String, dynamic> _rawRow({
  required String packageName,
  String? appName,
  String category = 'social',
}) {
  return {
    'packageName': packageName,
    'appName': appName ?? packageName,
    'isSystemApp': false,
    'isLaunchable': true,
    'category': category,
    'versionName': '1',
    'versionCode': 1,
    'installerPackage': '',
    'installedTime': 1,
    'updatedTime': 1,
    'lastSeenAt': 1,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugSyncRelevantAppsForTests = null;
    InstalledAppsBridge.forceChannelForTests = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kInstalledAppsChannel, null);
    RelevantInstalledAppsEngine.instance.reset(mutationSource: 'test_teardown');
  });

  group('RelevantInstalledAppsEngine', () {
    test(
      'stale full-scan async completion does not overwrite state after newer reset',
      () async {
        final stalePayload = <dynamic>[
          _rawRow(packageName: 'com.stale.one', category: 'social'),
          _rawRow(packageName: 'com.stale.two', category: 'social'),
        ];
        final freshPayload = <dynamic>[
          _rawRow(packageName: 'com.fresh.only', appName: 'Fresh', category: 'social'),
        ];
        final firstScan = Completer<List<dynamic>>();

        var getInstalledAppsCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kInstalledAppsChannel, (call) async {
          switch (call.method) {
            case 'getInstalledApps':
              getInstalledAppsCalls++;
              if (getInstalledAppsCalls == 1) {
                return firstScan.future;
              }
              return freshPayload;
            default:
              return null;
          }
        });

        InstalledAppsBridge.forceChannelForTests = true;
        final engine = RelevantInstalledAppsEngine.instance;
        engine.reset(mutationSource: 'test_start');

        final refreshSlow = engine.refreshFromFullDeviceScanAndSync(
          childId: '',
          parentId: '',
          mutationSource: 'test_stale_scan',
          syncTrigger: 'test',
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        engine.reset(mutationSource: 'test_invalidate_generation');

        firstScan.complete(stalePayload);
        await refreshSlow;

        expect(
          engine.currentRelevantSorted.map((e) => e.packageName).toList(),
          isEmpty,
          reason: 'stale full inventory must not commit after generation moved forward',
        );

        await engine.refreshFromFullDeviceScanAndSync(
          childId: '',
          parentId: '',
          mutationSource: 'test_second_scan',
          syncTrigger: 'test',
        );

        expect(engine.currentRelevantSorted, hasLength(1));
        expect(engine.currentRelevantSorted.single.packageName, 'com.fresh.only');
      },
    );

    test(
      'realtime add when bridge returns null does not leave orphan relevant row',
      () async {
        const orphanPkg = 'com.orphan.null_raw';

        SharedPreferences.setMockInitialValues({
          kUserRoleKey: kUserRoleChild,
          'genet_linked_child_id': 'child_engine_test',
          'genet_linked_parent_id': 'parent_engine_test',
        });

        debugSyncRelevantAppsForTests =
            ({
          required String childId,
          required List<InstalledApp> relevantApps,
          required int rawInstalledAppCount,
          String trigger = 'unknown',
        }) async {
          expect(relevantApps.where((a) => a.packageName == orphanPkg), isEmpty);
          return 0;
        };

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kInstalledAppsChannel, (call) async {
          switch (call.method) {
            case 'getInstalledApps':
              return <dynamic>[];
            case 'getInstalledApp':
              return null;
            default:
              return null;
          }
        });

        InstalledAppsBridge.forceChannelForTests = true;
        final engine = RelevantInstalledAppsEngine.instance;
        engine.reset(mutationSource: 'test_start');

        await engine.handlePackageChangeEvent(
          const PackageChangeEvent(packageName: orphanPkg, action: 'added'),
        );

        expect(
          engine.currentRelevantSorted.where((a) => a.packageName == orphanPkg),
          isEmpty,
        );

        await engine.handlePackageChangeEvent(
          const PackageChangeEvent(packageName: orphanPkg, action: 'added'),
        );

        expect(
          engine.currentRelevantSorted.where((a) => a.packageName == orphanPkg),
          isEmpty,
        );
      },
    );
  });
}
