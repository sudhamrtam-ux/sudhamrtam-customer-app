import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/milk_bills/bill_pdf.dart';
import 'package:sudhamrtam_customer_app/features/milk_bills/milk_bills_screen.dart';
import 'package:sudhamrtam_customer_app/features/payment/payment_launcher.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription.dart';
import 'package:sudhamrtam_customer_app/models/milk_subscription_manager.dart';
import 'package:sudhamrtam_customer_app/services/milk_bill_api_client.dart';
import 'package:sudhamrtam_customer_app/services/order_api_client.dart';

Map<String, dynamic> billJson({
  String id = 'b1',
  String month = '2026-10',
  String status = 'issued',
  int total = 23000,
  String due = '2026-11-08',
  String? method,
  bool overdue = false,
  bool withLines = true,
}) => {
  'id': id,
  'month': month,
  'status': status,
  'total_paise': total,
  'total_ml': 2500,
  'due_date': due,
  'payment_method': method,
  'overdue': overdue,
  'milk': [
    {
      'product_id': 'buffalo_milk',
      'product_name': 'Buffalo Milk',
      'quantity_ml': 1500,
      'amount_paise': 13500,
    },
    {
      'product_id': 'cow_milk',
      'product_name': 'Cow Milk',
      'quantity_ml': 1000,
      'amount_paise': 9500,
    },
  ],
  if (withLines)
    'lines': [
      {
        'delivery_date': '2026-10-05',
        'shift': 'morning',
        'product_id': 'buffalo_milk',
        'product_name': 'Buffalo Milk',
        'quantity_ml': 1500,
        'unit_price_paise': 9000,
        'amount_paise': 13500,
      },
      {
        'delivery_date': '2026-10-05',
        'shift': 'evening',
        'product_id': 'cow_milk',
        'product_name': 'Cow Milk',
        'quantity_ml': 1000,
        'unit_price_paise': 9500,
        'amount_paise': 9500,
      },
    ],
};

/// One delivery in the milk history: 0.5 L buffalo at ₹90 by default.
Map<String, dynamic> deliveryJson(
  String date, {
  String shift = 'morning',
  String? outcome = 'delivered',
  String? reason,
  int ml = 500,
}) => {
  'date': date,
  'shift': shift,
  'outcome': outcome,
  'reason': reason,
  'items': [
    {
      'product_id': 'buffalo_milk',
      'name': 'Buffalo Milk',
      'quantity_ml': ml,
      'unit_price_paise': 9000,
      'amount_paise': outcome == 'delivered' ? ml * 9 : 0,
    },
  ],
};

Map<String, dynamic> historyJson(
  String month,
  List<Map<String, dynamic>> deliveries, {
  Map<String, dynamic>? bill,
}) {
  final delivered = deliveries.where((d) => d['outcome'] == 'delivered');
  int sum(Iterable<Map<String, dynamic>> list, String key) => list.fold(
    0,
    (s, d) => s + ((d['items'] as List).first as Map)[key] as int,
  );
  return {
    'month': month,
    'deliveries': deliveries,
    'totals': {
      'delivered': delivered.length,
      'not_delivered': deliveries
          .where((d) => d['outcome'] == 'not_delivered')
          .length,
      'paused': deliveries.where((d) => d['outcome'] == 'paused').length,
      'not_marked': deliveries.where((d) => d['outcome'] == null).length,
      'delivered_ml': sum(delivered, 'quantity_ml'),
      'amount_paise': sum(delivered, 'amount_paise'),
    },
    'bill': bill,
  };
}

class FakeBillServer {
  List<Map<String, dynamic>> bills = [billJson()];

  /// Milk history by month; months not listed have none.
  final history = <String, Map<String, dynamic>>{};
  bool down = false;
  bool expired = false;

  /// How many checks answer "not paid" before [paid] takes effect.
  bool paid = false;
  int checksUntilPaid = 0;
  int checks = 0;
  Map<String, dynamic>? startError;
  final requests = <String>[];

  late final client = MockClient((request) async {
    requests.add('${request.method} ${request.url.path}');
    if (down) throw http.ClientException('down');
    http.Response json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (expired) return json(401, {'error': 'UNAUTHORIZED'});

    if (request.url.path == '/v1/milk-bills') {
      return json(200, {'bills': bills});
    }
    if (request.url.path == '/v1/milk-deliveries') {
      final month = request.url.queryParameters['month']!;
      return json(200, history[month] ?? historyJson(month, []));
    }
    if (request.url.path.endsWith('/print')) {
      return json(200, {
        'bill': bills.first,
        'customer': {
          'name': 'Asha',
          'phone': '+919876543210',
          'address': 'Flat 101, Hyderabad',
        },
        'plans': <Object>[],
        'deliveries': <Object>[],
        'settings': {
          'account_name': 'Test Account',
          'account_number': '12345678901',
          'bank_name': 'Test Bank',
          'ifsc': 'ABCD0123456',
          'payee_phone': '9876500000',
          'upi_id': 'test.payee@ybl',
          'gstin': null,
        },
      });
    }
    if (request.url.path.endsWith('/payment')) {
      if (startError != null) return json(409, startError!);
      return json(200, {
        'order_id': 'bill_b1_1',
        'payment_session_id': 'session_1',
        'environment': 'sandbox',
      });
    }
    if (request.url.path.endsWith('/payment/check')) {
      checks++;
      final done = paid && checks > checksUntilPaid;
      if (done) {
        bills = [billJson(status: 'paid', method: 'online')];
      }
      return json(200, {
        'bill': done
            ? billJson(status: 'paid', method: 'online', withLines: false)
            : billJson(withLines: false),
      });
    }
    return json(404, {'error': 'NOT_FOUND', 'message': 'Not found'});
  });
}

class FakeLauncher implements PaymentLauncher {
  FakeLauncher(this.result);

  final PaymentLaunchResult result;
  final sessions = <PaymentSession>[];

  @override
  Future<PaymentLaunchResult> launch(PaymentSession session) async {
    sessions.add(session);
    return result;
  }
}

void main() {
  late FakeBillServer server;
  late MilkBillApiClient api;
  String? token;

  setUp(() {
    server = FakeBillServer();
    token = 'tok';
    api = MilkBillApiClient(
      baseUrl: 'https://api.test',
      token: () => token,
      httpClient: server.client,
    );
  });

  /// Tall enough for the calendar and the bills below it.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Future<void> openBill(WidgetTester tester, PaymentLauncher launcher) async {
    final bill = (await api.fetchBills()).first;
    await tester.pumpWidget(
      MaterialApp(
        home: MilkBillScreen(
          bill: bill,
          api: api,
          launcher: launcher,
          confirmDelay: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('labels', () {
    test('months, dates, money and litres', () {
      expect(billMonthLabel('2026-10'), 'October 2026');
      expect(billDateLabel('2026-11-08'), '8 Nov 2026');
      expect(billRupees(23000), '₹230');
      expect(billRupees(23050), '₹230.50');
      expect(billRupees(23005), '₹230.05');
      expect(billRupees(139500), '₹1,395');
      expect(billRupees(12345650), '₹1,23,456.50');
      expect(billRupees(99900), '₹999');
      expect(billLitres(1500), '1.5 L');
      expect(billLitres(2000), '2 L');
    });
  });

  group('reminder on the Milk Plan tab', () {
    testWidgets('shows nothing when signed out or with no bills', (
      tester,
    ) async {
      token = null;
      await show(tester, MilkBillsReminder(api: api));
      expect(find.byKey(const Key('milkBillsReminder')), findsNothing);
      expect(server.requests, isEmpty);

      token = 'tok';
      server.bills = [];
      await tester.pumpWidget(const SizedBox());
      await show(tester, MilkBillsReminder(api: api));
      expect(find.byKey(const Key('milkBillsReminder')), findsNothing);
    });

    testWidgets('a connection problem shows no error here', (tester) async {
      server.down = true;
      await show(tester, MilkBillsReminder(api: api));
      expect(find.byKey(const Key('milkBillsReminder')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one unpaid bill: amount and due date', (tester) async {
      await show(tester, MilkBillsReminder(api: api));
      expect(find.text('October 2026 milk bill: ₹230'), findsOneWidget);
      expect(find.text('Due by 8 Nov 2026. Tap to pay.'), findsOneWidget);
    });

    testWidgets('overdue says so; milk is not mentioned as stopped', (
      tester,
    ) async {
      server.bills = [billJson(overdue: true)];
      await show(tester, MilkBillsReminder(api: api));
      expect(find.text('Was due by 8 Nov 2026. Tap to pay.'), findsOneWidget);
    });

    testWidgets('several unpaid bills are added up', (tester) async {
      server.bills = [
        billJson(),
        billJson(id: 'b2', month: '2026-09', total: 10000),
      ];
      await show(tester, MilkBillsReminder(api: api));
      expect(find.text('2 unpaid milk bills: ₹330'), findsOneWidget);
    });

    testWidgets('all paid is a quiet link', (tester) async {
      server.bills = [billJson(status: 'paid', method: 'cash')];
      await show(tester, MilkBillsReminder(api: api));
      expect(find.text('All paid. Tap to see your bills.'), findsOneWidget);
    });

    testWidgets('opens the bills and refreshes on return', (tester) async {
      tall(tester);
      await show(
        tester,
        MilkBillsReminder(
          api: api,
          launcher: FakeLauncher(const PaymentLaunchFinished()),
        ),
      );
      await tester.tap(find.byKey(const Key('milkBillsReminder')));
      await tester.pumpAndSettle();
      expect(find.text('Milk Bills'), findsOneWidget);
      expect(find.text('October 2026 · ₹230'), findsOneWidget);

      server.bills = [billJson(status: 'paid', method: 'online')];
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('All paid. Tap to see your bills.'), findsOneWidget);
    });
  });

  group('milk calendar', () {
    /// 10 November 2026, a Tuesday.
    DateTime today() => DateTime(2026, 11, 10, 9);

    void november() {
      server.history['2026-11'] = historyJson('2026-11', [
        deliveryJson('2026-11-01'),
        deliveryJson('2026-11-02', ml: 1000),
        deliveryJson('2026-11-02', shift: 'evening'),
        deliveryJson(
          '2026-11-03',
          outcome: 'not_delivered',
          reason: 'customer_refused',
        ),
        deliveryJson('2026-11-05', outcome: 'paused'),
        deliveryJson(
          '2026-11-06',
          outcome: 'not_delivered',
          reason: 'not_marked',
        ),
        deliveryJson('2026-11-10', outcome: null),
      ]);
    }

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(400, 1800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MilkBillsScreen(api: api, today: today),
        ),
      );
      await tester.pumpAndSettle();
    }

    String cell(WidgetTester tester, String date) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key('day-$date')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join(' ');

    testWidgets('each date shows litres and amount; totals like the bill', (
      tester,
    ) async {
      november();
      await open(tester);

      expect(find.text('November 2026'), findsOneWidget);
      expect(cell(tester, '2026-11-01'), '1 0.5 L ₹45');
      // Two deliveries on the 2nd: added up.
      expect(cell(tester, '2026-11-02'), '2 1.5 L ₹135');
      expect(cell(tester, '2026-11-03'), '3 Missed');
      expect(cell(tester, '2026-11-10'), '10 Pending');
      expect(cell(tester, '2026-11-04'), '4');
      expect(cell(tester, '2026-11-05'), '5 Paused');
      // Nobody marked the 6th: not delivered, not charged.
      expect(cell(tester, '2026-11-06'), '6 Missed');

      expect(
        find.text('3 delivered · 2 missed · 1 paused · 1 not marked yet'),
        findsOneWidget,
      );
      expect(find.text('2 L'), findsOneWidget);
      expect(find.text('₹90 per litre'), findsOneWidget);
      expect(find.text('Amount so far'), findsOneWidget);
      expect(find.text('₹180'), findsOneWidget);
      // The bills follow.
      expect(find.text('October 2026 · ₹230'), findsOneWidget);

      // A missed date says why.
      await tester.tap(find.byKey(const Key('day-2026-11-03')));
      await tester.pumpAndSettle();
      expect(find.text('3 Nov 2026'), findsOneWidget);
      expect(find.text('Refused at the door'), findsOneWidget);
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();

      // Not marked that day: not delivered.
      await tester.tap(find.byKey(const Key('day-2026-11-06')));
      await tester.pumpAndSettle();
      expect(find.text('Not delivered'), findsOneWidget);
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();

      // The 2nd: each delivery with its rate.
      await tester.tap(find.byKey(const Key('day-2026-11-02')));
      await tester.pumpAndSettle();
      expect(find.text('Buffalo Milk 1 L × ₹90/L = ₹90'), findsOneWidget);
      expect(find.text('Buffalo Milk 0.5 L × ₹90/L = ₹45'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
    });

    testWidgets('earlier months, up to a year; the bill once sent', (
      tester,
    ) async {
      server.history['2026-10'] = historyJson(
        '2026-10',
        [deliveryJson('2026-10-31', shift: 'evening')],
        bill: {'id': 'b1', 'status': 'issued', 'total_paise': 4500},
      );
      await open(tester);
      expect(find.text('No milk deliveries this month.'), findsOneWidget);
      // Nothing after this month.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right).first,
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsWidgets);
      expect(cell(tester, '2026-10-31'), '31 0.5 L ₹45');
      expect(find.text('Amount'), findsOneWidget);
      expect(
        find.text('Your bill for October 2026 has been sent: ₹45.'),
        findsOneWidget,
      );

      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
      }
      expect(find.text('December 2025'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNull,
      );
      expect(
        server.requests.where((r) => r == 'GET /v1/milk-deliveries').length,
        12,
      );
    });

    testWidgets('vacation days show, this month and the months ahead', (
      tester,
    ) async {
      november();
      final plans = MilkSubscriptionManager();
      await plans.loadSavedSubscriptions([
        MilkSubscription(
          id: 'p1',
          productId: 'cow_milk',
          shiftSchedules: [
            MilkShiftSchedule(
              shift: MilkDeliveryShift.morning,
              quantityMl: 1000,
              frequency: MilkDeliveryFrequency.daily,
              startDate: DateTime(2026, 11, 1),
            ),
          ],
          quantity: 1,
          frequency: MilkDeliveryFrequency.daily,
          startDate: DateTime(2026, 11, 1),
          // A past day (the server's history shows it), two days
          // ahead and one in December.
          vacationDates: [
            DateTime(2026, 11, 5),
            DateTime(2026, 11, 14),
            DateTime(2026, 11, 15),
            DateTime(2026, 12, 2),
          ],
        ),
      ]);
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MilkBillsScreen(api: api, today: today, plans: plans),
        ),
      );
      await tester.pumpAndSettle();

      expect(cell(tester, '2026-11-14'), '14 Vacation');
      expect(cell(tester, '2026-11-15'), '15 Vacation');
      expect(cell(tester, '2026-11-05'), '5 Paused');
      expect(find.text('Vacation: no milk on 14–15 Nov.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('day-2026-11-14')));
      await tester.pumpAndSettle();
      expect(find.text('Vacation: no Cow Milk this day.'), findsOneWidget);
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();

      // December: only the vacation, nothing asked of the server.
      final asked = server.requests.length;
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);
      expect(cell(tester, '2026-12-02'), '2 Vacation');
      expect(find.text('Vacation: no milk on 2 Dec.'), findsOneWidget);
      expect(server.requests.length, asked);
      // No further than the last vacation month.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right).first,
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a phone', (tester) async {
      november();
      await open(tester, size: const Size(320, 1400));
      expect(tester.takeException(), isNull);
      expect(cell(tester, '2026-11-02'), '2 1.5 L ₹135');
    });
  });

  group('bills list', () {
    testWidgets('shows each bill with its status', (tester) async {
      tall(tester);
      server.bills = [
        billJson(),
        billJson(id: 'b2', month: '2026-09', status: 'paid', method: 'cash'),
        billJson(id: 'b3', month: '2026-08', status: 'paid', method: 'online'),
        billJson(id: 'b4', month: '2026-07', overdue: true),
      ];
      await tester.pumpWidget(MaterialApp(home: MilkBillsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Payment due'), findsOneWidget);
      expect(find.text('Paid in cash'), findsOneWidget);
      expect(find.text('Paid online'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Buffalo Milk 1.5 L, Cow Milk 1 L'), findsNWidgets(4));
    });

    testWidgets('explains an empty list', (tester) async {
      tall(tester);
      server.bills = [];
      await tester.pumpWidget(MaterialApp(home: MilkBillsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('No bills yet.'), findsOneWidget);
    });

    testWidgets('a failure can be retried', (tester) async {
      tall(tester);
      server.down = true;
      await tester.pumpWidget(MaterialApp(home: MilkBillsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not reach Sudhamrtam'), findsOneWidget);

      server.down = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026 · ₹230'), findsOneWidget);
    });

    testWidgets('asks to sign in', (tester) async {
      token = null;
      await tester.pumpWidget(MaterialApp(home: MilkBillsScreen(api: api)));
      await tester.pumpAndSettle();
      expect(
        find.text('Please sign in to see your milk bills.'),
        findsOneWidget,
      );

      token = 'old';
      server.expired = true;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.text('Please sign in again to see your milk bills.'),
        findsOneWidget,
      );
    });

    testWidgets('no server in this build', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MilkBillsScreen()));
      await tester.pumpAndSettle();
      expect(
        find.text('Milk bills need a connection to Sudhamrtam.'),
        findsOneWidget,
      );
    });
  });

  group('one bill', () {
    testWidgets('downloads the bill as a PDF', (tester) async {
      final outputs = <(int, String, bool)>[];
      outputBillPdf = (bytes, name, {required share}) async =>
          outputs.add((bytes.length, name, share));
      await openBill(tester, FakeLauncher(const PaymentLaunchFinished()));
      await tester.tap(find.byKey(const Key('downloadBill')));
      await tester.pumpAndSettle();
      expect(server.requests, contains('GET /v1/milk-bills/b1/print'));
      expect(outputs.single.$2, 'Sudhamrtam milk bill 2026-10');
      expect(outputs.single.$3, isTrue);
      expect(outputs.single.$1, greaterThan(5000));
    });

    testWidgets('actual amount, discount, GST and total', (tester) async {
      server.bills = [
        {
          ...billJson(total: 21180),
          'subtotal_paise': 23000,
          'discount_paise': 2300,
          'discount_percent_bp': 1000,
          'gst_paise': 480,
        },
      ];
      await openBill(tester, FakeLauncher(const PaymentLaunchFinished()));
      final amounts = find.byKey(const Key('billAmounts'));
      String text() => tester
          .widgetList<Text>(
            find.descendant(of: amounts, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .join(' | ');
      expect(
        text(),
        'Actual amount | ₹230 | Discount (10%) | − ₹23 | GST | + ₹4.80 | '
        'Total | ₹211.80',
      );
      expect(find.text('Pay ₹211.80 online'), findsOneWidget);
    });

    testWidgets('a bill from before GST shows its total as the actual amount', (
      tester,
    ) async {
      await openBill(tester, FakeLauncher(const PaymentLaunchFinished()));
      expect(find.text('Actual amount'), findsOneWidget);
      expect(find.text('+ ₹0'), findsOneWidget);
      expect(find.text('Discount (10%)'), findsNothing);
    });

    testWidgets('shows the bill day by day', (tester) async {
      await openBill(tester, FakeLauncher(const PaymentLaunchFinished()));
      expect(find.text('Bill for October 2026'), findsOneWidget);
      // The amount due, the actual amount and the total.
      expect(find.text('₹230'), findsNWidgets(3));
      expect(find.text('Due by 8 Nov 2026'), findsOneWidget);
      expect(find.text('Buffalo Milk: 1.5 L · ₹135'), findsOneWidget);
      expect(
        find.textContaining('Buffalo Milk 1.5 L at ₹90 per litre'),
        findsOneWidget,
      );
      expect(find.textContaining('5 Oct 2026 · Evening'), findsOneWidget);
      expect(
        find.text('You can also pay in cash to Sudhamrtam staff.'),
        findsOneWidget,
      );
    });

    testWidgets('pays online; only the server says it is paid', (tester) async {
      final launcher = FakeLauncher(const PaymentLaunchFinished());
      server.paid = true;
      server.checksUntilPaid = 2; // Cashfree needs a moment.
      await openBill(tester, launcher);

      await tester.tap(find.byKey(const Key('payBillOnline')));
      await tester.pumpAndSettle();
      expect(launcher.sessions.single.orderId, 'bill_b1_1');
      expect(server.checks, 3);
      expect(find.byKey(const Key('billPaid')), findsOneWidget);
      expect(find.byKey(const Key('payBillOnline')), findsNothing);
      expect(find.text('Paid online'), findsOneWidget);
      // The lines stay, though the check leaves them out.
      expect(find.textContaining('at ₹90 per litre'), findsOneWidget);
      expect(find.byKey(const Key('billSandboxBanner')), findsOneWidget);
    });

    testWidgets('reported success without the server stays unpaid', (
      tester,
    ) async {
      await openBill(tester, FakeLauncher(const PaymentLaunchFinished()));
      await tester.tap(find.byKey(const Key('payBillOnline')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('billPaid')), findsNothing);
      expect(
        find.textContaining('We have not received the payment'),
        findsOneWidget,
      );

      // It arrives later.
      server.paid = true;
      await tester.tap(find.text('Check Payment'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('billPaid')), findsOneWidget);
    });

    testWidgets('a failed payment can be tried again', (tester) async {
      await openBill(
        tester,
        FakeLauncher(const PaymentLaunchFailed('Cancelled by you.')),
      );
      await tester.tap(find.byKey(const Key('payBillOnline')));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled by you.'), findsOneWidget);
      expect(find.byKey(const Key('payBillOnline')), findsOneWidget);
    });

    testWidgets('already paid: shows it paid', (tester) async {
      server.startError = {
        'error': 'ALREADY_PAID',
        'message': 'This bill is already paid.',
      };
      server.paid = true;
      final launcher = FakeLauncher(const PaymentLaunchFinished());
      await openBill(tester, launcher);
      await tester.tap(find.byKey(const Key('payBillOnline')));
      await tester.pumpAndSettle();
      expect(launcher.sessions, isEmpty);
      expect(find.byKey(const Key('billPaid')), findsOneWidget);
    });

    testWidgets('online payment off: says so', (tester) async {
      server.startError = {
        'error': 'PAYMENT_NOT_OFFERED',
        'message': 'Online payment is not available right now.',
      };
      await openBill(tester, FakeLauncher(const PaymentLaunchFinished()));
      await tester.tap(find.byKey(const Key('payBillOnline')));
      await tester.pumpAndSettle();
      expect(
        find.text('Online payment is not available right now.'),
        findsOneWidget,
      );
    });

    testWidgets('a paid bill has no pay button', (tester) async {
      server.bills = [billJson(status: 'paid', method: 'cash')];
      await openBill(tester, FakeLauncher(const PaymentLaunchFinished()));
      expect(find.byKey(const Key('payBillOnline')), findsNothing);
      expect(find.text('Paid in cash'), findsOneWidget);
    });
  });
}
