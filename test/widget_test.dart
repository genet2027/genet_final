// Basic Flutter widget test for Genet app.

import 'package:flutter_test/flutter_test.dart';

import 'package:genet_final/main.dart';

void main() {
  testWidgets('Genet app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GenetApp());

    expect(find.text('Genet'), findsOneWidget);
  });
}
