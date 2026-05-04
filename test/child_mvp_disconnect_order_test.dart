import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/repositories/children_repository.dart';
import 'package:genet_final/repositories/parent_child_sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugSetChildConnectionStatusFirebaseForTests = null;
    SharedPreferences.setMockInitialValues({});
  });

  test('canonical disconnected write runs before linked prefs are cleared', () async {
    SharedPreferences.setMockInitialValues({
      'genet_linked_parent_id': 'p1',
      'genet_linked_child_id': 'c1',
    });
    final writes = <String>[];
    debugSetChildConnectionStatusFirebaseForTests = (p, c, s) async {
      writes.add('$p|$c|$s');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('genet_linked_parent_id'), 'p1');
      expect(prefs.getString('genet_linked_child_id'), 'c1');
    };

    final p = normalizeIdentifier(await getLinkedParentId());
    final c = normalizeIdentifier(await getLinkedChildId());
    if (p != null && c != null) {
      try {
        await setChildConnectionStatusFirebase(p, c, 'disconnected');
      } catch (_) {}
    }
    await clearChildLinkedPrefsKeepLocalIdentity();

    expect(writes, ['p1|c1|disconnected']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('genet_linked_parent_id'), isNull);
    expect(prefs.getString('genet_linked_child_id'), isNull);
  });

  test('Firestore disconnect failure still allows prefs clear (MVP)', () async {
    SharedPreferences.setMockInitialValues({
      'genet_linked_parent_id': 'p1',
      'genet_linked_child_id': 'c1',
    });
    debugSetChildConnectionStatusFirebaseForTests = (p, c, s) async {
      throw Exception('network');
    };

    final p = normalizeIdentifier(await getLinkedParentId());
    final c = normalizeIdentifier(await getLinkedChildId());
    if (p != null && c != null) {
      try {
        await setChildConnectionStatusFirebase(p, c, 'disconnected');
      } catch (_) {}
    }
    await clearChildLinkedPrefsKeepLocalIdentity();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('genet_linked_parent_id'), isNull);
  });
}
