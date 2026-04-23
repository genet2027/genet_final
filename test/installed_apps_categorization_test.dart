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

    test('unknown / empty / unrecognized with human app name -> notRelevant', () {
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'a', appName: 'Photo Fun', category: 'unknown'),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'b', appName: 'My Calendar', category: ''),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
      expect(
        decideInstalledAppRelevance(
          _raw(packageName: 'c', appName: 'Notes Plus', category: 'bogus'),
        ),
        InstalledAppRelevanceDecision.notRelevant,
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

    test('noise display name excludes before approved category', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'p',
            appName: 'SIM Service',
            category: 'social',
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
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

    test('Chrome relevant when flagged system (browser before system_app)', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.android.chrome',
            appName: 'Chrome',
            category: 'unknown',
            isSystemApp: true,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Samsung Internet relevant when flagged system', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.sec.android.app.sbrowser',
            appName: 'Internet',
            category: 'unknown',
            isSystemApp: true,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Android System WebView not relevant', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.google.android.webview',
            appName: 'Android System WebView',
            category: 'unknown',
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('trichrome substring package excluded as engine/helper', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.google.android.trichrome.webview',
            appName: 'Trichrome WebView',
            category: 'unknown',
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('display name Pure Browser included when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.vendor.app',
            appName: 'Pure Browser',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Instagram included when category wrong and flagged system (social before system_app)', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.instagram.android',
            appName: 'Instagram',
            category: 'productivity',
            isSystemApp: true,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('TikTok family included when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.zhiliaoapp.musically',
            appName: 'TikTok',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Facebook Services excluded as social_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.facebook.services',
            appName: 'Facebook Services',
            category: 'unknown',
            isLaunchable: true,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('Reddit included via display name when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.vendor',
            appName: 'Reddit',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('LinkedIn package included when category missing', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.linkedin.android',
            appName: 'LinkedIn',
            category: '',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('YouTube included when category wrong and flagged system', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.google.android.youtube',
            appName: 'YouTube',
            category: 'productivity',
            isSystemApp: true,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Netflix included when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.netflix.mediaclient',
            appName: 'Netflix',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('VLC excluded as video_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'org.videolan.vlc',
            appName: 'VLC',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('MX Player excluded as video_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.mxtech.videoplayer.ad',
            appName: 'MX Player',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('Netflix included via display name when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.vendor',
            appName: 'Netflix',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Roblox included when category wrong and flagged system', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.roblox.client',
            appName: 'Roblox',
            category: 'productivity',
            isSystemApp: true,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Google Play Games excluded as game_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.google.android.play.games',
            appName: 'Play Games',
            category: 'game',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('game booster package excluded as game_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.gamebooster',
            appName: 'Game Booster',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('Minecraft included via display name when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.vendor',
            appName: 'Minecraft',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Clash Royale included via package when category wrong', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.supercell.clashroyale',
            appName: 'Clash Royale',
            category: 'productivity',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Unity engine package excluded as game_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.unity3d.player',
            appName: 'Unity',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('WhatsApp included when category wrong and flagged system', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.whatsapp',
            appName: 'WhatsApp',
            category: 'productivity',
            isSystemApp: true,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Google RCS IMS excluded as messaging_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.google.android.ims',
            appName: 'Carrier Services',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('Telegram included via display name when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.vendor',
            appName: 'Telegram',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Samsung stock Messages still included via stock_sms_ui', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.samsung.android.messaging',
            appName: 'Messages',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Viber family package included via messaging_package_match', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.viber.partner',
            appName: 'Viber Partner',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('WeChat family package included via messaging_package_match', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.tencent.mm.plugin',
            appName: 'WeChat Plugin',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Signal Private Messenger included via messaging_name_match', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.vendor',
            appName: 'Signal Private Messenger',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('Facebook Messenger stays on Social path not Messaging', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.facebook.orca',
            appName: 'Messenger',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('LINE title strict: unrelated name with line substring not Messaging', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.airline',
            appName: 'Airline',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('Spotify included when category wrong and flagged system', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.spotify.music',
            appName: 'Spotify',
            category: 'productivity',
            isSystemApp: true,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test('OEM equalizer excluded as music_false_positive', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.equalizer',
            appName: 'Sound Equalizer',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.notRelevant,
      );
    });

    test('Apple Music included via display name when category unknown', () {
      expect(
        decideInstalledAppRelevance(
          _raw(
            packageName: 'com.example.vendor',
            appName: 'Apple Music',
            category: 'unknown',
            isSystemApp: false,
          ),
        ),
        InstalledAppRelevanceDecision.clearlyRelevant,
      );
    });

    test(
      'YouTube Music package is Music (music_package_match; Music evaluated before Video)',
      () {
        expect(
          decideInstalledAppRelevance(
            _raw(
              packageName: 'com.google.android.apps.youtube.music',
              appName: 'YouTube Music',
              category: 'unknown',
              isSystemApp: false,
            ),
          ),
          InstalledAppRelevanceDecision.clearlyRelevant,
        );
      },
    );

    test(
      'Regular YouTube package stays Video not Music (video_package_match)',
      () {
        expect(
          decideInstalledAppRelevance(
            _raw(
              packageName: 'com.google.android.youtube',
              appName: 'YouTube',
              category: 'unknown',
              isSystemApp: false,
            ),
          ),
          InstalledAppRelevanceDecision.clearlyRelevant,
        );
      },
    );
  });

  group('categorizeInstalledApps', () {
    test('includes approved categories only; unknown omitted', () {
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
      });
      final byPkg = {for (final a in out) a.packageName: a};
      expect(byPkg['a']!.isUnknownCategory, false);
      expect(byPkg['gm']!.isUnknownCategory, false);
    });

    test('includes music/audio; excludes maps, productivity', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'au', category: 'audio'),
        _raw(packageName: 'm', category: 'maps'),
        _raw(packageName: 'pr', category: 'productivity'),
      ]);
      expect(out.map((e) => e.packageName).toSet(), {'au'});
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

  group('installedAppForRelevantRaw', () {
    test('null when raw null or notRelevant', () {
      expect(installedAppForRelevantRaw(null), isNull);
      expect(
        installedAppForRelevantRaw(_raw(packageName: 'm', category: 'maps')),
        isNull,
      );
    });

    test('heuristic browser win sets category browser not junk raw store category', () {
      final chrome = installedAppForRelevantRaw(
        _raw(
          packageName: 'com.android.chrome',
          appName: 'Chrome',
          category: 'junk_unknown_xyz',
        ),
      );
      expect(chrome, isNotNull);
      expect(chrome!.category, 'browser');
    });

    test('same outcome as categorizeInstalledApps for one row', () {
      final r = _raw(packageName: 'vid', appName: 'Clips', category: 'video');
      final one = installedAppForRelevantRaw(r);
      final list = categorizeInstalledApps([r]);
      expect(one, isNotNull);
      expect(list, hasLength(1));
      expect(one!.packageName, list.single.packageName);
      expect(one.isUnknownCategory, list.single.isUnknownCategory);
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

    test('unknown category with normal name is not in visible list', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'misc', appName: 'Photo Fun', category: 'unknown'),
      ]);
      expect(out, isEmpty);
    });

    test('technical-noise unknown does not appear in visible list', () {
      final out = categorizeInstalledApps([
        _raw(packageName: 'sim', appName: 'SIM Service', category: 'unknown'),
      ]);
      expect(out, isEmpty);
    });
  });
}
