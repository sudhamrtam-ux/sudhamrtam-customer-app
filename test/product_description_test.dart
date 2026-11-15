import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/shop/product_description.dart';
import 'package:sudhamrtam_customer_app/models/product_descriptions.dart';

void main() {
  test('splits a description into paragraphs, headings and points', () {
    final blocks = parseDescription(
      'Fresh milk from our farm, delivered every morning to your door.\n'
      'Why Sudhamrtam Milk?\n'
      '• Farm-fresh purity: Free from antibiotics.\n'
      '• Packed with care\n'
      '1. Hair Care & Scalp Health\n'
      'Zero Chemicals: No solvents, bleaching agents, or preservatives, just pure oil.',
    );
    expect(blocks[0], isA<DescriptionParagraph>());
    expect((blocks[1] as DescriptionHeading).text, 'Why Sudhamrtam Milk?');
    final point = blocks[2] as DescriptionPoint;
    expect(
      (point.label, point.text),
      ('Farm-fresh purity', 'Free from antibiotics.'),
    );
    expect((blocks[3] as DescriptionPoint).label, isNull);
    expect((blocks[4] as DescriptionHeading).text, 'Hair Care & Scalp Health');
    expect((blocks[5] as DescriptionPoint).label, 'Zero Chemicals');
  });

  testWidgets('short at first; Read more opens it all, Show less closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductDescription(description: cowGheeDescription),
          ),
        ),
      ),
    );
    expect(find.text('About this product'), findsOneWidget);
    expect(find.text('Why Sudhamrtam Cow Ghee?'), findsNothing);
    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    expect(find.text('Why Sudhamrtam Cow Ghee?'), findsOneWidget);
    expect(
      find.textContaining('Authentic preparation: ', findRichText: true),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Show less'));
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('Why Sudhamrtam Cow Ghee?'), findsNothing);
  });
}
