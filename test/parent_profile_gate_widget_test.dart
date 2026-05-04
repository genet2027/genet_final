import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/l10n/app_localizations.dart';
import 'package:genet_final/models/parent_profile.dart';
import 'package:genet_final/repositories/parent_profile_repository.dart';
import 'package:genet_final/screens/parent_profile_setup_screen.dart';
import 'package:genet_final/screens/parent_shell.dart';
import 'package:genet_final/screens/pin_login_screen.dart';
import 'package:genet_final/screens/role_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugGetParentProfileForTests = null;
    debugSaveParentProfileForTests = null;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('parent PIN success + missing profile opens ParentProfileSetupScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugGetParentProfileForTests = (_) async => null;

    await tester.pumpWidget(
      const MaterialApp(
        home: PinLoginScreen(),
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('כניסה'));
    await tester.pumpAndSettle();

    expect(find.byType(ParentProfileSetupScreen), findsOneWidget);
  });

  testWidgets('parent PIN success + incomplete profile opens ParentProfileSetupScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugGetParentProfileForTests = (id) async => ParentProfile(
          parentId: id,
          firstName: 'Only',
          lastName: '',
        );

    await tester.pumpWidget(
      const MaterialApp(
        home: PinLoginScreen(),
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('כניסה'));
    await tester.pumpAndSettle();

    expect(find.byType(ParentProfileSetupScreen), findsOneWidget);
  });

  testWidgets('parent PIN success + complete profile opens ParentShell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugGetParentProfileForTests = (id) async => ParentProfile(
          parentId: id,
          firstName: 'David',
          lastName: 'Levi',
        );

    await tester.pumpWidget(
      const MaterialApp(
        home: PinLoginScreen(),
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('כניסה'));
    await tester.pumpAndSettle();

    expect(find.byType(ParentShell), findsOneWidget);
  });

  testWidgets('ParentProfileSetupScreen save passes trimmed names to repository hook', (tester) async {
    SharedPreferences.setMockInitialValues({
      'genet_parent_id': 'p_hook',
    });
    String? capturedFn;
    String? capturedLn;
    debugSaveParentProfileForTests =
        ({required String parentId, required String firstName, required String lastName}) async {
      capturedFn = firstName;
      capturedLn = lastName;
    };

    await tester.pumpWidget(
      MaterialApp(
        home: ParentProfileSetupScreen(
          completedBuilder: (_) => const Scaffold(body: Text('dest')),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), '  Moshe  ');
    await tester.enterText(find.byType(TextField).at(1), ' Cohen ');
    await tester.tap(find.text('המשך'));
    await tester.pumpAndSettle();

    expect(capturedFn, 'Moshe');
    expect(capturedLn, 'Cohen');
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('child role tap does not open ParentProfileSetupScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});

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

    expect(find.byType(ParentProfileSetupScreen), findsNothing);
  });

  testWidgets('ParentProfileSetupScreen shows Hebrew validation when names empty', (tester) async {
    SharedPreferences.setMockInitialValues({'genet_parent_id': 'p1'});
    debugSaveParentProfileForTests =
        ({required String parentId, required String firstName, required String lastName}) async {};

    await tester.pumpWidget(
      MaterialApp(
        home: ParentProfileSetupScreen(
          completedBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );

    await tester.tap(find.text('המשך'));
    await tester.pumpAndSettle();

    expect(find.textContaining('יש למלא'), findsWidgets);
  });
}
