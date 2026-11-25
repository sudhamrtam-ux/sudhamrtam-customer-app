import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/home/even_row.dart';

Widget _box(String key, double height) =>
    SizedBox(key: Key(key), height: height);

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 424, child: child),
      ),
    ),
  );

  testWidgets('EvenRow: shown cards share the row, one height', (tester) async {
    await pump(
      tester,
      EvenRow(
        spacing: 12,
        children: [
          _box('a', 40),
          const SizedBox.shrink(),
          _box('b', 70),
          _box('c', 50),
        ],
      ),
    );
    for (final k in ['a', 'b', 'c']) {
      expect(tester.getSize(find.byKey(Key(k))), const Size(400 / 3, 70));
    }
    expect(tester.getTopLeft(find.byKey(const Key('b'))).dx, 400 / 3 + 12);
    expect(tester.getTopLeft(find.byKey(const Key('c'))).dx, 800 / 3 + 24);
    expect(tester.getSize(find.byType(EvenRow)).height, 70);
  });

  testWidgets('EvenRow: nothing shown takes no room', (tester) async {
    await pump(
      tester,
      const EvenRow(children: [SizedBox.shrink(), SizedBox.shrink()]),
    );
    expect(tester.getSize(find.byType(EvenRow)).height, 0);
  });

  testWidgets('GapBelow: a gap only under a card that shows', (tester) async {
    await pump(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GapBelow(child: _box('a', 40)),
          const GapBelow(child: SizedBox.shrink()),
          GapBelow(child: _box('b', 30)),
        ],
      ),
    );
    expect(tester.getTopLeft(find.byKey(const Key('b'))).dy, 50);
    expect(tester.getSize(find.byKey(const Key('a'))).width, 424);
  });
}
