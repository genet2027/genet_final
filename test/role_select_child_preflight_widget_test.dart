import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/l10n/app_localizations.dart';
import 'package:genet_final/repositories/parent_child_sync_repository.dart';
import 'package:genet_final/screens/child_link_screen.dart';
import 'package:genet_final/screens/child_self_identify_screen.dart';
import 'package:genet_final/screens/role_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugPreflightSavedChildCanonicalLinkResultForTests = null;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'child OutlinedButton + invalid canonical preflight does not open durable linked home',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
      });
      debugPreflightSavedChildCanonicalLinkResultForTests =
          () async => SavedChildLinkPreflightResult.verifiedInvalidOrStale;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('he'),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: RoleSelectScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OutlinedButton).first);
      await tester.pumpAndSettle();

      expect(find.byType(ChildSelfIdentifyScreen), findsOneWidget);
    },
  );

  testWidgets(
    'child invalid canonical preflight + profile opens pairing (ChildLinkScreen)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'genet_linked_parent_id': 'p1',
        'genet_linked_child_id': 'c1',
        'genet_child_self_profile':
            '{"firstName":"A","lastName":"B","age":0,"schoolCode":""}',
      });
      debugPreflightSavedChildCanonicalLinkResultForTests =
          () async => SavedChildLinkPreflightResult.verifiedInvalidOrStale;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('he'),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: RoleSelectScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OutlinedButton).first);
      await tester.pumpAndSettle();

      expect(find.byType(ChildLinkScreen), findsOneWidget);
    },
  );
}
