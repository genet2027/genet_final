import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/models/installed_app.dart';

InstalledApp _app({
  required String packageName,
  String appName = 'App',
  bool isSystemApp = false,
  bool isLaunchable = true,
  String category = '',
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return InstalledApp(
    packageName: packageName,
    appName: appName,
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
  group('isLikelyBrowserPackage', () {
    test('recognizes major browsers', () {
      expect(InstalledApp.isLikelyBrowserPackage('com.android.chrome'), true);
      expect(InstalledApp.isLikelyBrowserPackage('org.mozilla.firefox'), true);
      expect(
        InstalledApp.isLikelyBrowserPackage('com.sec.android.app.sbrowser'),
        true,
      );
      expect(InstalledApp.isLikelyBrowserPackage('com.duckduckgo.mobile.android'), true);
    });

    test('rejects webview engines', () {
      expect(InstalledApp.isLikelyBrowserPackage('com.google.android.webview'), false);
      expect(InstalledApp.isLikelyBrowserPackage('com.android.webview'), false);
    });

    test('exact browser ids match case-insensitively', () {
      expect(InstalledApp.isLikelyBrowserPackage('com.ucmobile.x86'), true);
    });

    test('recognizes narrow OEM browser packages', () {
      expect(InstalledApp.isLikelyBrowserPackage('com.huawei.browser'), true);
      expect(InstalledApp.isLikelyBrowserPackage('com.mi.global.browser'), true);
    });

    test('recognizes Pure Browser store ids', () {
      expect(InstalledApp.isLikelyBrowserPackage('pure.lite.browser'), true);
      expect(InstalledApp.isLikelyBrowserPackage('com.pure.browser.plus'), true);
    });
  });

  group('isRelevantForParent', () {
    test('includes launchable browser even when flagged system', () {
      final chrome = _app(
        packageName: 'com.android.chrome',
        appName: 'Chrome',
        isSystemApp: true,
        isLaunchable: true,
      );
      expect(chrome.isRelevantForParent(), true);
    });

    test('includes launchable OEM browser when package is in browser list', () {
      final mi = _app(
        packageName: 'com.mi.global.browser',
        appName: 'Mi Browser',
        isSystemApp: true,
        isLaunchable: true,
      );
      expect(mi.isRelevantForParent(), true);
    });

    test('includes DuckDuckGo Privacy Browser name without name-term false exclude', () {
      final ddg = _app(
        packageName: 'com.duckduckgo.mobile.android',
        appName: 'DuckDuckGo Privacy Browser',
        isSystemApp: false,
      );
      expect(ddg.isRelevantForParent(), true);
    });

    test('excludes non-launchable chrome', () {
      final chrome = _app(
        packageName: 'com.android.chrome',
        isLaunchable: false,
        isSystemApp: false,
      );
      expect(chrome.isRelevantForParent(), false);
    });

    test('excludes webview', () {
      final wv = _app(packageName: 'com.google.android.webview', isSystemApp: true);
      expect(wv.isRelevantForParent(), false);
    });

    test('includes stock SMS when launchable', () {
      final sms = _app(
        packageName: 'com.google.android.apps.messaging',
        appName: 'Messages',
        isSystemApp: true,
        isLaunchable: true,
      );
      expect(sms.isRelevantForParent(), true);
    });

    test('still excludes core settings', () {
      final s = _app(
        packageName: 'com.android.settings',
        appName: 'Settings',
        isSystemApp: true,
      );
      expect(s.isRelevantForParent(), false);
    });

    test('category video still passes for non-system', () {
      final y = _app(
        packageName: 'com.example.stream',
        appName: 'Stream',
        category: 'video',
        isSystemApp: false,
      );
      expect(y.isRelevantForParent(), true);
    });
  });
}
