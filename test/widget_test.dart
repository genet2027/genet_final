// Basic Flutter widget test for Genet app.

import 'package:flutter_test/flutter_test.dart';

import 'package:genet_final/main.dart';
import 'package:genet_final/services/night_mode_service.dart';

void main() {
  testWidgets('Genet app smoke test', (WidgetTester tester) async {
    final nightModeService = NightModeService();
    await tester.pumpWidget(GenetApp(nightModeService: nightModeService));

    expect(find.text('Genet'), findsOneWidget);
  });
}
