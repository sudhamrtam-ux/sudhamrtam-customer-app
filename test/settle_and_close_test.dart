import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/milk_bills/settle_and_close.dart';
import 'package:sudhamrtam_customer_app/services/milk_bill_api_client.dart';

/// Settle bill and close subscription (owner request 2026-11-26).
void main() {
  Map<String, dynamic> info({
    Map<String, dynamic>? closing,
    int openPlans = 1,
    bool canClose = true,
    int unpaid = 0,
    int soFar = 45000,
    List<Map<String, dynamic>> unpaidBills = const [],
  }) => {
    'closing': closing,
    'open_plans': openPlans,
    'can_close': canClose,
    'last_delivery_date': '2026-11-27',
    'unpaid_bills': unpaidBills,
    'unpaid_paise': unpaid,
    'so_far_paise': soFar,
    'total_paise': unpaid + soFar,
  };

  late Map<String, dynamic> state;
  late List<String> requests;

  MilkBillApiClient api() => MilkBillApiClient(
    baseUrl: 'https://api.test',
    token: () => 'tok',
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path == '/v1/milk-plans/close') {
        state = info(
          closing: {
            'status': 'waiting',
            'last_delivery_date': '2026-11-27',
            'bill_ids': <String>[],
          },
          openPlans: 0,
          canClose: false,
        );
      }
      return http.Response(
        jsonEncode(state),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() {
    state = info();
    requests = [];
  });

  Future<void> show(WidgetTester tester, {void Function(String)? open}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettleAndCloseCard(api: api(), onOpenBill: open),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offer, confirm with the amounts, then closed', (tester) async {
    await show(tester);
    expect(find.byKey(const Key('closing-offer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settle-and-close')));
    await tester.pumpAndSettle();
    expect(find.text('27 Nov 2026'), findsOneWidget);
    expect(find.text('₹450'), findsNWidgets(2));
    expect(find.textContaining('morning of 28 Nov 2026'), findsOneWidget);
    expect(
      find.textContaining('as soon as your last delivery'),
      findsOneWidget,
    );

    // Back changes nothing.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(requests, ['GET /v1/milk-plans/closing']);

    await tester.tap(find.byKey(const Key('settle-and-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-confirm')));
    await tester.pumpAndSettle();
    expect(requests.last, 'POST /v1/milk-plans/close');
    expect(find.byKey(const Key('closing-waiting')), findsOneWidget);
    expect(
      find.textContaining('Last milk delivery: 27 Nov 2026'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('closing-so-far')), findsOneWidget);
    expect(find.textContaining('about ₹450'), findsOneWidget);
  });

  testWidgets(
    'waiting: earlier bills payable now; Check finds the final bill',
    (tester) async {
      final waiting = {
        'status': 'waiting',
        'last_delivery_date': '2026-11-27',
        'bill_ids': <String>[],
      };
      state = info(
        closing: waiting,
        openPlans: 0,
        canClose: false,
        unpaid: 30000,
        unpaidBills: [
          {'id': 'b8', 'month': '2026-10', 'total_paise': 30000},
        ],
      );
      final opened = <String>[];
      var reloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettleAndCloseCard(
                api: api(),
                onOpenBill: opened.add,
                onClosed: () => reloads++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('closing-waiting')), findsOneWidget);
      expect(find.text('October 2026 bill · ₹300'), findsOneWidget);
      await tester.tap(find.byKey(const Key('closing-pay-b8')));
      expect(opened, ['b8']);

      // Not marked yet: still waiting.
      await tester.tap(find.byKey(const Key('closing-check')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not yet'), findsOneWidget);
      expect(reloads, 0);

      // Marked: the final bill is there, each bill with its Pay button.
      state = info(
        closing: {
          ...waiting,
          'status': 'billed',
          'bill_ids': ['b9'],
        },
        openPlans: 0,
        canClose: false,
        unpaid: 82000,
        soFar: 0,
        unpaidBills: [
          {'id': 'b8', 'month': '2026-10', 'total_paise': 30000},
          {'id': 'b9', 'month': '2026-11', 'total_paise': 52000},
        ],
      );
      await tester.tap(find.byKey(const Key('closing-check')));
      await tester.pumpAndSettle();
      expect(reloads, 1);
      expect(find.text('Final bill ready: ₹820 to pay'), findsOneWidget);
      expect(find.text('Final bill, November 2026 · ₹520'), findsOneWidget);
      expect(find.text('October 2026 bill · ₹300'), findsOneWidget);
      await tester.tap(find.byKey(const Key('closing-pay-b9')));
      expect(opened, ['b8', 'b9']);
    },
  );

  testWidgets('billed and unpaid: Pay final bill opens it', (tester) async {
    state = info(
      closing: {
        'status': 'billed',
        'last_delivery_date': '2026-11-27',
        'bill_ids': ['b9'],
      },
      openPlans: 0,
      canClose: false,
      unpaid: 52000,
      soFar: 0,
      unpaidBills: [
        {'id': 'b9', 'month': '2026-11', 'total_paise': 52000},
      ],
    );
    final opened = <String>[];
    await show(tester, open: opened.add);
    expect(find.text('Final bill ready: ₹520 to pay'), findsOneWidget);
    await tester.tap(find.byKey(const Key('closing-pay-b9')));
    expect(opened, ['b9']);
  });

  testWidgets('settled, and nothing to show without a subscription', (
    tester,
  ) async {
    state = info(
      closing: {
        'status': 'billed',
        'last_delivery_date': '2026-11-27',
        'bill_ids': ['b9'],
      },
      openPlans: 0,
      canClose: false,
      soFar: 0,
    );
    await show(tester);
    expect(find.byKey(const Key('closing-settled')), findsOneWidget);

    state = info(openPlans: 0, canClose: false);
    await show(tester);
    expect(find.byKey(const Key('closing-offer')), findsNothing);
  });
}
