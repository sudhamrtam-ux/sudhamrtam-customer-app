import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/home/glance_cards.dart';
import 'package:sudhamrtam_customer_app/features/messages/message_inbox.dart';
import 'package:sudhamrtam_customer_app/models/customer_order.dart';
import 'package:sudhamrtam_customer_app/models/order_item.dart';
import 'package:sudhamrtam_customer_app/services/message_api_client.dart';

/// Home's last-order and new-message cards (owner, 2026-11-17).
CustomerOrder order({String? deliveryDate}) => CustomerOrder(
  id: 'o1',
  createdAt: DateTime(2026, 11, 17, 9),
  items: const [
    OrderItem(
      productId: 'curd',
      productName: 'Curd',
      unit: '1 kg',
      quantity: 2,
      unitPrice: 120,
    ),
    OrderItem(
      productId: 'paneer',
      productName: 'Paneer',
      unit: '200 g',
      quantity: 1,
      unitPrice: 160,
    ),
  ],
  fulfillmentMethod: FulfillmentMethod.delivery,
  paymentMethod: OrderPaymentMethod.cashOnDelivery,
  deliveryAddress: 'Flat 101, Green Towers',
  deliveryDate: deliveryDate,
);

void main() {
  final now = DateTime(2026, 11, 17, 10);

  test('what the last order card says', () {
    final o = order(deliveryDate: '2026-11-18');
    expect(lastOrderLine(o, null, now)!.line, 'Arriving tomorrow morning');
    expect(lastOrderLine(o, 'pending', now)!.line, 'Arriving tomorrow morning');
    expect(
      lastOrderLine(order(deliveryDate: '2026-11-17'), 'delivered', now)!.line,
      'Delivered today',
    );
    expect(lastOrderLine(o, 'cancelled', now)!.line, 'Cancelled');
    expect(
      lastOrderLine(order(deliveryDate: '2026-11-20'), null, now)!.line,
      'Arriving Fri, 20 Nov morning',
    );
    // Finished more than 2 days ago: not shown.
    expect(
      lastOrderLine(order(deliveryDate: '2026-11-14'), 'delivered', now),
      isNull,
    );
    // Still "pending" days later (nobody marked it): not shown either.
    expect(lastOrderLine(order(deliveryDate: '2026-11-14'), null, now), isNull);
  });

  testWidgets('the last order with its number from the server', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LastOrderCard(
            now: () => now,
            loadLatest: () async => order(deliveryDate: '2026-11-18'),
            lookup: (_) async => (status: 'pending', orderRef: 'SUD0000123'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Order SUD0000123 · 3 items · ₹400'), findsOneWidget);
    expect(find.text('Arriving tomorrow morning'), findsOneWidget);
  });

  testWidgets('no orders: no card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LastOrderCard(now: () => now, loadLatest: () async => null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('homeLastOrder')), findsNothing);
  });

  testWidgets('new messages: count and the newest title', (tester) async {
    var unread = 2;
    final client = MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'unread_count': unread,
            'messages': [
              {
                'id': 'm2',
                'title': 'Diwali holiday',
                'body': 'No delivery on Diwali.',
                'sent_at': '2026-11-16T05:00:00.000Z',
                'unread': unread > 0,
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final inbox = MessageInbox(
      api: MessageApiClient(
        baseUrl: 'https://api.test',
        token: () => 'tok',
        httpClient: client,
      ),
    );
    await tester.runAsync(inbox.refresh);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NewMessagesCard(inbox: inbox)),
      ),
    );
    expect(find.text('2 new messages from Sudhamrtam'), findsOneWidget);
    expect(find.text('Diwali holiday'), findsOneWidget);

    unread = 0;
    await tester.runAsync(inbox.refresh);
    await tester.pump();
    expect(find.byKey(const Key('homeNewMessages')), findsNothing);
  });
}
