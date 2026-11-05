import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudhamrtam_customer_app/app/sudhamrtam_app.dart';

void main() {
  testWidgets('Sudhamrtam app displays customer navigation', (tester) async {
    await tester.pumpWidget(const SudhamrtamApp());

    expect(find.text('Sudhamrtam'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
  });
}
