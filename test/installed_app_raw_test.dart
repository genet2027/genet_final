import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/models/installed_app_raw.dart';

void main() {
  test('tryParse + toLegacyNativeMap round-trip keys for InstalledApp.fromNativeMap', () {
    final row = InstalledAppRaw.tryParse({
      'packageName': 'com.example.app',
      'appName': 'Example',
      'isSystemApp': false,
      'category': 'game',
      'isLaunchable': true,
      'versionName': '1.0',
      'versionCode': 42,
      'installerPackage': 'com.android.vending',
      'installedTime': 100,
      'updatedTime': 200,
      'lastSeenAt': 300,
    });
    expect(row, isNotNull);
    final legacy = row!.toLegacyNativeMap();
    expect(legacy['package'], 'com.example.app');
    expect(legacy['name'], 'Example');
    expect(legacy['category'], 'game');
    expect(legacy['isLaunchable'], true);
    expect(legacy['versionCode'], 42);
  });
}
