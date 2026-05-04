import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/screens/child_home_screen.dart';

void main() {
  testWidgets('disconnect dialog cancel returns without popping route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await showChildMvpDisconnectConfirmation(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ניתוק חיבור'), findsOneWidget);
    expect(find.text('האם אתה בטוח שברצונך לנתק את החיבור להורה?'), findsOneWidget);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(find.text('ניתוק חיבור'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('disconnect dialog confirm closes dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await showChildMvpDisconnectConfirmation(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('נתק'));
    await tester.pumpAndSettle();

    expect(find.text('ניתוק חיבור'), findsNothing);
  });
}
