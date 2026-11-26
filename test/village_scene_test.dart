import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/home/village_scene.dart';

/// The Home banner's village morning (owner request 2026-11-26).
void main() {
  testWidgets('the sun rises and the animals walk without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 400, height: 132, child: VillageScene(animate: true)),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
    // Removed while running: no ticker left behind.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('still when the phone asks for less motion', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SizedBox(width: 400, height: 132, child: VillageScene(animate: true)),
      ),
    );
    // Settles: nothing keeps moving.
    await tester.pumpAndSettle();
    expect(find.byType(VillageScene), findsOneWidget);
  });
}
