import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/models/parent_profile.dart';
import 'package:genet_final/repositories/parent_profile_repository.dart';

void main() {
  group('ParentProfile', () {
    test('isComplete requires non-empty trimmed first and last name', () {
      expect(
        const ParentProfile(parentId: 'p1').isComplete,
        isFalse,
      );
      expect(
        const ParentProfile(parentId: 'p1', firstName: '  ', lastName: 'Doe').isComplete,
        isFalse,
      );
      expect(
        const ParentProfile(parentId: 'p1', firstName: 'Jane', lastName: '').isComplete,
        isFalse,
      );
      expect(
        const ParentProfile(parentId: 'p1', firstName: ' Jane ', lastName: ' Doe ').isComplete,
        isTrue,
      );
    });

    test('computedDisplayName joins trimmed parts', () {
      expect(
        const ParentProfile(parentId: 'p1').computedDisplayName,
        '',
      );
      expect(
        const ParentProfile(parentId: 'p1', firstName: 'Adam', lastName: 'Cohen').computedDisplayName,
        'Adam Cohen',
      );
      expect(
        const ParentProfile(parentId: 'p1', firstName: '  Lee  ', lastName: '  Park ').computedDisplayName,
        'Lee Park',
      );
    });

    test('fromMap / toMap round-trip core fields', () {
      final original = ParentProfile.fromMap('p_x', {
        'firstName': 'A',
        'lastName': 'B',
        'displayName': 'A B',
      });
      expect(original.parentId, 'p_x');
      expect(original.firstName, 'A');
      expect(original.lastName, 'B');
      expect(original.displayName, 'A B');

      final map = original.toMap();
      expect(map['firstName'], 'A');
      expect(map['lastName'], 'B');
      expect(map['displayName'], 'A B');
    });
  });

  group('isParentProfileComplete', () {
    test('null or incomplete profile → false', () {
      expect(isParentProfileComplete(null), isFalse);
      expect(
        isParentProfileComplete(const ParentProfile(parentId: 'p1', firstName: 'Only')),
        isFalse,
      );
    });

    test('complete profile → true', () {
      expect(
        isParentProfileComplete(
          const ParentProfile(parentId: 'p1', firstName: 'X', lastName: 'Y'),
        ),
        isTrue,
      );
    });
  });
}
