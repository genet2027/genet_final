import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/models/parent_profile.dart';
import 'package:genet_final/repositories/parent_profile_repository.dart';

void main() {
  group('parentProfileDisplayLineForChildUi', () {
    test('null profile → null', () {
      expect(parentProfileDisplayLineForChildUi(null), isNull);
    });

    test('prefers non-empty displayName over computed', () {
      final p = ParentProfile(
        parentId: 'p1',
        firstName: 'A',
        lastName: 'B',
        displayName: 'Stored Name',
      );
      expect(parentProfileDisplayLineForChildUi(p), 'Stored Name');
    });

    test('falls back to computedDisplayName when displayName empty', () {
      final p = ParentProfile(
        parentId: 'p1',
        firstName: ' Moshe ',
        lastName: ' Levi ',
        displayName: '',
      );
      expect(parentProfileDisplayLineForChildUi(p), 'Moshe Levi');
    });

    test('missing names → null line', () {
      final p = ParentProfile(parentId: 'p1');
      expect(parentProfileDisplayLineForChildUi(p), isNull);
    });
  });

  group('connectedParentHeadlineForChild', () {
    test('not canonically connected → empty', () {
      expect(
        connectedParentHeadlineForChild(
          isCanonicallyConnected: false,
          parentProfileDisplayLine: 'Parent',
        ),
        '',
      );
    });

    test('connected + display line → Hebrew headline with name', () {
      expect(
        connectedParentHeadlineForChild(
          isCanonicallyConnected: true,
          parentProfileDisplayLine: 'David Cohen',
        ),
        'מחובר להורה: David Cohen',
      );
    });

    test('connected + null/empty line → short headline', () {
      expect(
        connectedParentHeadlineForChild(
          isCanonicallyConnected: true,
          parentProfileDisplayLine: null,
        ),
        'מחובר להורה',
      );
      expect(
        connectedParentHeadlineForChild(
          isCanonicallyConnected: true,
          parentProfileDisplayLine: '   ',
        ),
        'מחובר להורה',
      );
    });
  });
}
