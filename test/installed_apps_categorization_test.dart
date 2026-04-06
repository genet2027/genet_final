import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/models/installed_app_raw.dart';
import 'package:genet_final/services/installed_apps_categorization.dart';

InstalledAppRaw _raw({
  required String packageName,
  String? appName,
  String category = 'unknown',
  bool isSystemApp = false,
  bool isLaunchable = true,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return InstalledAppRaw(
    packageName: packageName,
    appName: appName ?? packageName,
    isSystemApp: isSystemApp,
    isLaunchable: isLaunchable,
    category: category,
    versionName: '1',
    versionCode: 1,
    installerPackage: '',
    installedTime: now,
    updatedTime: now,
    lastSeenAt: now,
  );
}

void main() {
  group('normalizeInstalledAppCategory', () {
    test('trims and lowercases known tokens', () {
      expect(normalizeInstalledAppCategory('  VIDEO '), 'video');
      expect(normalizeInstalledAppCategory('Social'), 'social');
      expect(normalizeInstalledAppCategory('Communication'), 'communication');
    });

    test('unknown for empty or unrecognized', () {
      expect(normalizeInstalledAppCategory(null), 'unknown');
      expect(normalizeInstalledAppCategory(''), 'unknown');
      expect(normalizeInstalledAppCategory('  '), 'unknown');
      expect(normalizeInstalledAppCategory('not-a-real-category'), 'unknown');
    });
  });

  group('decideInstalledAppRelevance', () {
    test('social -> clearlyRelevant', () {
      expect(
        decideInstalledAppRelevance(_raw(packageName: 'p', category: 'social')),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('communication -> clearlyRelevant', () {
      expect(
        decideInstalledAppRelevance(_raw(packageName: 'p', category: 'communication')),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('game -> clearlyRelevant', () {
      expect(
        decideInstalledAppRelevance(_raw(packageName: 'p', category: 'game')),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('unknown / empty / unrecognized with human app name -> possiblyRelevant', () {
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'a', appName: 'Photo Fun', category: 'unknown'),
        ),
        InstalledAppRelevanceDecision.possiblyRelevant,
      );
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'b', appName: 'My Calendar', category: ''),
        ),
        InstalledAppRelevanceDecision.possiblyRelevant,
      );
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'c', appName: 'Notes Plus', category: 'bogus'),
        ),
        InstalledAppRelevanceDecision.possiblyRelevant,
      );
    });

    test('unknown SIM Service -> notRelevant (noise)', () {
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'sim.pkg', appName: 'SIM Service', category: 'unknown'),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('unknown Package Installer -> notRelevant (noise)', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'installer',
            appName: 'Package Installer',
            category: 'unknown',
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('unknown System UI -> notRelevant (noise)', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'sysui',
            appName: 'System UI',
            category: 'unknown',
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('clearlyRelevant not filtered by noise name', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'p',
            appName: 'SIM Service',
            category: 'social',
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('non-launchable -> notRelevant', () {
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'p', category: 'social', isLaunchable: false),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('system app -> notRelevant', () {
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'p', category: 'social', isSystemApp: true),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });
  });

  group('categorizeInstalledApps', () {
    test('includes clearlyRelevant and possiblyRelevant', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'a', category: 'social'),
        _raw(packageName: 'b', category: 'video'),
        _raw(packageName: 'c', category: 'entertainment'),
        _raw(packageName: 'comm', category: 'communication'),
        _raw(packageName: 'gm', category: 'game'),
        _raw(packageName: 'd', category: 'unknown'),
        _raw(packageName: 'e', category: 'bogus'),
      ]);
      expect(out.map((e) => e.packageName).toSet(), {
        'a',
        'b',
        'c',
        'comm',
        'gm',
        'd',
        'e',
      });
      final byPkg = {for (final a in out) a.packageName: a};
      expect(byPkg['d']!.isUnknownCategory, true);
      expect(byPkg['e']!.isUnknownCategory, true);
      expect(byPkg['a']!.isUnknownCategory, false);
      expect(byPkg['gm']!.isUnknownCategory, false);
    });

    test('excludes audio, maps, productivity, etc.', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'au', category: 'audio'),
        _raw(packageName: 'm', category: 'maps'),
        _raw(packageName: 'pr', category: 'productivity'),
      ]);
      expect(out, isEmpty);
    });

    test('dedupes by packageName', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'x', category: 'social'),
        _raw(packageName: 'x', category: 'video'),
      ]);
      expect(out.length, 1);
    });

    test('excludes non-launchable', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final out = categorizeInstalledApps([
        InstalledAppRaw(
          packageName: 'svc',
          appName: 'Service',
          isSystemApp: false,
          isLaunchable: false,
          category: 'social',
          versionName: '1',
          versionCode: 1,
          installerPackage: '',
          installedTime: now,
          updatedTime: now,
          lastSeenAt: now,
        ),
      ]);
      expect(out, isEmpty);
    });

    test('excludes system apps', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final out = categorizeInstalledApps([
        InstalledAppRaw(
          packageName: 'sys',
          appName: 'System UI',
          isSystemApp: true,
          isLaunchable: true,
          category: 'unknown',
          versionName: '1',
          versionCode: 1,
          installerPackage: '',
          installedTime: now,
          updatedTime: now,
          lastSeenAt: now,
        ),
      ]);
      expect(out, isEmpty);
    });
  });

  group('visible list integration (Step 3)', () {
    test('clearlyRelevant rows are visible with isUnknownCategory false', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'soc.pkg', appName: 'Social App', category: 'social'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.isUnknownCategory, false);
    });

    test('possiblyRelevant normal-name rows are visible with isUnknownCategory true', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'misc', appName: 'Photo Fun', category: 'unknown'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.isUnknownCategory, true);
    });

    test('technical-noise unknown does not appear in visible list', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'sim', appName: 'SIM Service', category: 'unknown'),
      ]);
      expect(out, isEmpty);
    });
  });
}
