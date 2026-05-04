import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/core/user_role.dart';
import 'package:genet_final/repositories/parent_child_sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _resetConnectionTestHooks() {
  debugReadCanonicalChildDataForTests = null;
  debugReadCanonicalChildDataWithBoundedRetryForTests = null;
  debugFetchCanonicalChildDocStateForTests = null;
  debugSetChildConnectionStatusFirebaseForTests = null;
  debugPreflightSavedChildCanonicalLinkResultForTests = null;
}

Map<String, dynamic> _connectedDoc({
  required String parentId,
  String connectionStatus = 'connected',
  String linkCode = '1111',
}) {
  return <String, dynamic>{
    'parentId': parentId,
    'connectionStatus': connectionStatus,
    'linkCode': linkCode,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    _resetConnectionTestHooks();
    SharedPreferences.setMockInitialValues({});
  });

  group('canonicalChildDataActiveForParent', () {
    test('true when parent matches and status connected', () {
      expect(
        canonicalChildDataActiveForParent(
          _connectedDoc(parentId: 'p_a'),
          'p_a',
        ),
        isTrue,
      );
    });

    test('false when parentId on doc does not match expected', () {
      expect(
        canonicalChildDataActiveForParent(
          _connectedDoc(parentId: 'p_other'),
          'p_a',
        ),
        isFalse,
      );
    });

    test('false when connectionStatus is disconnected', () {
      expect(
        canonicalChildDataActiveForParent(
          _connectedDoc(parentId: 'p_a', connectionStatus: 'disconnected'),
          'p_a',
        ),
        isFalse,
      );
    });

    test('false when doc parentId is null or empty', () {
      expect(
        canonicalChildDataActiveForParent(
          {'parentId': null, 'connectionStatus': 'connected'},
          'p_a',
        ),
        isFalse,
      );
      expect(
        canonicalChildDataActiveForParent(
          {'parentId': '', 'connectionStatus': 'connected'},
          'p_a',
        ),
        isFalse,
      );
    });

    test('normalizes whitespace on parent ids for equality', () {
      expect(
        canonicalChildDataActiveForParent(
          _connectedDoc(parentId: '  p_a  '),
          'p_a',
        ),
        isTrue,
      );
    });

    test('false when connectionStatus field is missing', () {
      expect(
        canonicalChildDataActiveForParent(
          {'parentId': 'p_a'},
          'p_a',
        ),
        isFalse,
      );
    });
  });

  group('preflightSavedChildCanonicalLink', () {
    test('missing saved ids → verifiedInvalidOrStale', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await preflightSavedChildCanonicalLink(timeout: const Duration(milliseconds: 50)),
        SavedChildLinkPreflightResult.verifiedInvalidOrStale,
      );
    });

    test('only child id saved → verifiedInvalidOrStale', () async {
      SharedPreferences.setMockInitialValues({'genet_linked_child_id': 'c1'});
      expect(
        await preflightSavedChildCanonicalLink(timeout: const Duration(milliseconds: 50)),
        SavedChildLinkPreflightResult.verifiedInvalidOrStale,
      );
    });

    test('healthy canonical fetch → verifiedConnected', () async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests = (String p, String c) async {
        expect(p, 'p1');
        expect(c, 'c1');
        return CanonicalChildDocFetchOutcome.presentActive;
      };
      expect(
        await preflightSavedChildCanonicalLink(timeout: const Duration(seconds: 1)),
        SavedChildLinkPreflightResult.verifiedConnected,
      );
    });

    test('disconnected canonical doc → verifiedInvalidOrStale', () async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.presentInactive;
      expect(
        await preflightSavedChildCanonicalLink(),
        SavedChildLinkPreflightResult.verifiedInvalidOrStale,
      );
    });

    test('missing canonical doc → verifiedInvalidOrStale', () async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.missing;
      expect(
        await preflightSavedChildCanonicalLink(timeout: const Duration(milliseconds: 200)),
        SavedChildLinkPreflightResult.verifiedInvalidOrStale,
      );
    });

    test('fetch inconclusive (network) → unverifiedTransient', () async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.networkFailure;
      expect(
        await preflightSavedChildCanonicalLink(timeout: const Duration(milliseconds: 200)),
        SavedChildLinkPreflightResult.unverifiedTransient,
      );
    });
  });

  group('childDeviceDurablyLinkedToParent', () {
    test('true only when both prefs match normalized pair', () async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': '  p_x  ',
        'genet_linked_child_id': 'c_y',
      });
      expect(await childDeviceDurablyLinkedToParent('p_x', 'c_y'), isTrue);
      expect(await childDeviceDurablyLinkedToParent('p_x', 'other'), isFalse);
      expect(await childDeviceDurablyLinkedToParent('other', 'c_y'), isFalse);
    });

    test('false when prefs incomplete', () async {
      SharedPreferences.setMockInitialValues({'genet_linked_child_id': 'c_y'});
      expect(await childDeviceDurablyLinkedToParent('p_x', 'c_y'), isFalse);
    });
  });

  group('reconcileFalseRemoteConnectedAfterIncompleteChildLink', () {
    test('skips disconnect when child already durably linked', () async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      final writes = <String>[];
      debugSetChildConnectionStatusFirebaseForTests = (p, c, s) async {
        writes.add('$p|$c|$s');
      };
      debugReadCanonicalChildDataForTests = (p, c) async => _connectedDoc(
            parentId: 'p1',
            linkCode: '1234',
          );
      await reconcileFalseRemoteConnectedAfterIncompleteChildLink(
        parentId: 'p1',
        childId: 'c1',
        linkCode: '1234',
      );
      expect(writes, isEmpty);
    });

    test('skips when linkCode no longer matches attempt', () async {
      SharedPreferences.setMockInitialValues({});
      final writes = <String>[];
      debugSetChildConnectionStatusFirebaseForTests = (p, c, s) async {
        writes.add(s);
      };
      debugReadCanonicalChildDataForTests = (p, c) async => _connectedDoc(
            parentId: 'p1',
            linkCode: '9999',
          );
      await reconcileFalseRemoteConnectedAfterIncompleteChildLink(
        parentId: 'p1',
        childId: 'c1',
        linkCode: '1234',
      );
      expect(writes, isEmpty);
    });

    test('skips when canonical not active for parent', () async {
      SharedPreferences.setMockInitialValues({});
      final writes = <String>[];
      debugSetChildConnectionStatusFirebaseForTests = (p, c, s) async {
        writes.add(s);
      };
      debugReadCanonicalChildDataForTests = (p, c) async => _connectedDoc(
            parentId: 'other',
            linkCode: '1234',
          );
      await reconcileFalseRemoteConnectedAfterIncompleteChildLink(
        parentId: 'p1',
        childId: 'c1',
        linkCode: '1234',
      );
      expect(writes, isEmpty);
    });

    test('applies disconnect when canonical matches attempt and not linked locally', () async {
      SharedPreferences.setMockInitialValues({});
      final writes = <String>[];
      debugSetChildConnectionStatusFirebaseForTests = (p, c, s) async {
        writes.add('$p|$c|$s');
      };
      debugReadCanonicalChildDataForTests = (p, c) async => _connectedDoc(
            parentId: 'p1',
            linkCode: '1234',
          );
      await reconcileFalseRemoteConnectedAfterIncompleteChildLink(
        parentId: 'p1',
        childId: 'c1',
        linkCode: '1234',
      );
      expect(writes, contains('p1|c1|disconnected'));
    });
  });

  group('clearChildLinkedPrefsIfSavedCanonicalInactive', () {
    test('network/timeout outcome does not clear linked prefs', () async {
      SharedPreferences.setMockInitialValues({
        kUserRoleKey: kUserRoleChild,
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.networkFailure;
      await clearChildLinkedPrefsIfSavedCanonicalInactive();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('genet_linked_parent_id'), 'p1');
      expect(prefs.getString('genet_linked_child_id'), 'c1');
    });

    test('missing canonical doc clears linked prefs', () async {
      SharedPreferences.setMockInitialValues({
        kUserRoleKey: kUserRoleChild,
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.missing;
      await clearChildLinkedPrefsIfSavedCanonicalInactive();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('genet_linked_parent_id'), isNull);
      expect(prefs.getString('genet_linked_child_id'), isNull);
    });

    test('inactive canonical doc clears linked prefs', () async {
      SharedPreferences.setMockInitialValues({
        kUserRoleKey: kUserRoleChild,
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.presentInactive;
      await clearChildLinkedPrefsIfSavedCanonicalInactive();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('genet_linked_parent_id'), isNull);
      expect(prefs.getString('genet_linked_child_id'), isNull);
    });

    test('active canonical doc does not clear prefs', () async {
      SharedPreferences.setMockInitialValues({
        kUserRoleKey: kUserRoleChild,
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.presentActive;
      await clearChildLinkedPrefsIfSavedCanonicalInactive();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('genet_linked_parent_id'), 'p1');
      expect(prefs.getString('genet_linked_child_id'), 'c1');
    });

    test('parent role skips sanitize (prefs unchanged even if canonical inactive)', () async {
      SharedPreferences.setMockInitialValues({
        kUserRoleKey: kUserRoleParent,
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugFetchCanonicalChildDocStateForTests =
          (p, c) async => CanonicalChildDocFetchOutcome.presentInactive;
      await clearChildLinkedPrefsIfSavedCanonicalInactive();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('genet_linked_parent_id'), 'p1');
      expect(prefs.getString('genet_linked_child_id'), 'c1');
    });
  });

  group('clearChildLinkedPrefsKeepLocalIdentity', () {
    test('clears linked parent/child prefs but keeps genet_local_child_id', () async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
        'genet_linked_child_name': 'N',
        'genet_local_child_id': 'persist_c',
      });
      await clearChildLinkedPrefsKeepLocalIdentity();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('genet_linked_parent_id'), isNull);
      expect(prefs.getString('genet_linked_child_id'), isNull);
      expect(prefs.getString('genet_linked_child_name'), isNull);
      expect(prefs.getString('genet_local_child_id'), 'persist_c');
    });
  });
}
