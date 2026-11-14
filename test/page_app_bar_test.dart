import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/core/widgets/page_app_bar.dart';

Widget page(String title, {Widget? next}) => Builder(
  builder: (context) => Scaffold(
    appBar: PageAppBar(title: Text(title)),
    body: next == null
        ? const SizedBox.shrink()
        : TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => next)),
            child: Text('Open from $title'),
          ),
  ),
);

void main() {
  testWidgets('Home closes every open page; the first page has none', (
    tester,
  ) async {
    final before = homeRequests.value;
    await tester.pumpWidget(
      MaterialApp(
        home: page('Tabs', next: page('Bills', next: page('Bill'))),
      ),
    );
    // The first page: no Back, no Home.
    expect(find.byKey(const Key('goHome')), findsNothing);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.text('Open from Tabs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open from Bills'));
    await tester.pumpAndSettle();
    // Two pages deep: Back and Home.
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byKey(const Key('goHome')), findsOneWidget);

    await tester.tap(find.byKey(const Key('goHome')));
    await tester.pumpAndSettle();
    expect(find.text('Open from Tabs'), findsOneWidget);
    expect(find.text('Bill'), findsNothing);
    // The tab frame is told to show Home.
    expect(homeRequests.value, before + 1);
  });
}
