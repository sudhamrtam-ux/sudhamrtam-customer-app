import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/home/tomorrow_milk_card.dart';
import 'package:sudhamrtam_customer_app/services/milk_tomorrow_client.dart';

void main() {
  // 3:30 PM on Saturday 7 November (India).
  final now = DateTime(2026, 11, 7, 15, 30);
  late List<Map<String, dynamic>> shifts;
  late List<String> calls;
  late int refreshed;

  Map<String, dynamic> shift(
    String name,
    int usual, {
    int? ml,
    bool open = true,
    String closes = '2026-11-08T00:30:00.000Z',
  }) => {
    'plan_id': 'a1',
    'product_id': 'buffalo_milk',
    'product_name': 'Buffalo Milk',
    'shift': name,
    'usual_ml': usual,
    'quantity_ml': ml ?? usual,
    'skipped': false,
    'closes_at': closes,
    'open': open,
  };

  MilkTomorrowClient client() => MilkTomorrowClient(
    baseUrl: 'https://api.test',
    token: () => 'tok',
    httpClient: MockClient((request) async {
      calls.add('${request.method} ${request.url.path} ${request.body}');
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/skip')) {
          for (final s in shifts) {
            s['skipped'] = body['skip'];
          }
        } else {
          final s = shifts.firstWhere((s) => s['shift'] == body['shift']);
          s['quantity_ml'] = body['quantity_ml'] ?? s['usual_ml'];
        }
      }
      return http.Response(
        jsonEncode({'date': '2026-11-08', 'shifts': shifts}),
        200,
      );
    }),
  );

  setUp(() {
    calls = [];
    refreshed = 0;
    shifts = [
      shift('morning', 1000),
      shift('evening', 500, closes: '2026-11-08T12:30:00.000Z'),
    ];
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TomorrowMilkCard(
              client: client(),
              now: () => now,
              onChanged: () async => refreshed++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows tomorrow; + makes one day more; back to usual', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text("Tomorrow's milk"), findsOneWidget);
    expect(find.text('Sun, 8 Nov'), findsOneWidget);
    expect(find.text('Buffalo Milk'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('tomorrowQty-a1-morning'))).data,
      '1.00 L',
    );

    await tester.tap(find.byKey(const Key('tomorrowMore-a1-morning')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('tomorrowQty-a1-morning'))).data,
      '1.50 L',
    );
    expect(find.textContaining('Usually 1.00 L'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tomorrowUsual-a1-morning')));
    await tester.pumpAndSettle();
    expect(calls.last, contains('"quantity_ml":null'));
    expect(
      tester.widget<Text>(find.byKey(const Key('tomorrowQty-a1-morning'))).data,
      '1.00 L',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip tomorrow and undo; subscriptions refreshed', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('tomorrowSkip-a1')));
    await tester.pumpAndSettle();
    expect(find.text('No milk tomorrow on this subscription.'), findsOneWidget);
    expect(find.text('Undo skip'), findsOneWidget);
    expect(refreshed, 1);
    await tester.tap(find.byKey(const Key('tomorrowSkip-a1')));
    await tester.pumpAndSettle();
    expect(find.text('Skip tomorrow'), findsOneWidget);
  });

  testWidgets('a closed shift cannot change', (tester) async {
    shifts = [shift('early_morning', 1000, open: false)];
    await pump(tester);
    expect(find.text('Changes closed'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tomorrowMore-a1-early_morning')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.startsWith('PUT')), isEmpty);
  });

  testWidgets('no milk tomorrow: nothing shown', (tester) async {
    shifts = [];
    await pump(tester);
    expect(find.byKey(const Key('tomorrowMilk')), findsNothing);
  });

  test('closing times read naturally', () {
    expect(
      closesText(DateTime.utc(2026, 11, 7, 15, 30).toLocal(), now),
      contains('until'),
    );
  });
}
