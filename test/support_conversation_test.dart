import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/support/support_conversation_screen.dart';
import 'package:sudhamrtam_customer_app/services/support_api_client.dart';

const orderId = 'aaaa0000aaaa0000aaaa0000aaaa0001';

/// The server's conversations, in memory (2026-11-19 API).
class FakeSupportServer {
  final queries = <String, Map<String, dynamic>>{};
  final messages = <String, List<Map<String, dynamic>>>{};
  final calls = <String>[];
  var _ref = 1001;

  Map<String, dynamic> get order => {
    'id': orderId,
    'order_ref': 'SUD0000020',
    'status': 'pending',
    'payment_status': 'due_on_delivery',
    'delivery_date': '2026-11-21',
    'total_paise': 27000,
    'items': [
      {'product_name': 'Buffalo Milk', 'unit_label': '500 ml', 'quantity': 6},
    ],
  };

  /// A conversation Sudhamrtam already answered and resolved.
  void addResolved(String id) {
    queries[id] = {
      'id': id,
      'ref': 'Q-${_ref++}',
      'topic': 'order',
      'message': 'The milk was late.',
      'created_at': '2026-11-19T05:00:00.000Z',
      'handled_at': '2026-11-19T07:00:00.000Z',
      'reply': 'Sorry, it will be on time tomorrow.',
      'order_id': orderId,
      'order_ref': 'SUD0000020',
      'last_message_at': '2026-11-19T07:00:00.000Z',
      'last_from': 'staff',
      'unread': true,
    };
    messages[id] = [
      {
        'id': '$id-first',
        'from': 'customer',
        'body': 'The milk was late.',
        'created_at': '2026-11-19T05:00:00.000Z',
      },
      {
        'id': 's-1',
        'from': 'staff',
        'body': 'Sorry, it will be on time tomorrow.',
        'created_at': '2026-11-19T07:00:00.000Z',
      },
    ];
  }

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Map<String, dynamic> _conversation(String id) => {
    'query': queries[id],
    'messages': messages[id],
    'order': queries[id]!['order_id'] == null ? null : order,
  };

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.pathSegments;
    calls.add('${request.method} ${request.url.path}');
    // /v1/support-queries/{id}[/messages/{messageId}]
    final id = path.length > 2 ? path[2] : null;
    if (request.method == 'GET' && id == null) {
      return _json({'queries': queries.values.toList()});
    }
    if (request.method == 'GET') {
      queries[id]!['unread'] = false;
      return _json(_conversation(id!));
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (path.length == 3) {
      final existing = queries.values.where(
        (q) => q['order_id'] == body['order_id'] && q['id'] != id,
      );
      if (body['order_id'] != null && existing.isNotEmpty) {
        return _json({
          'error': 'ORDER_HAS_QUERY',
          'message': 'This order already has a conversation: write there.',
          'query_id': existing.first['id'],
        }, 409);
      }
      queries[id!] = {
        'id': id,
        'ref': 'Q-${_ref++}',
        'topic': body['topic'],
        'message': body['message'],
        'created_at': '2026-11-19T08:00:00.000Z',
        'handled_at': null,
        'reply': null,
        'order_id': body['order_id'],
        'order_ref': body['order_id'] == null ? null : 'SUD0000020',
        'last_message_at': '2026-11-19T08:00:00.000Z',
        'last_from': 'customer',
        'unread': false,
      };
      messages[id] = [
        {
          'id': '$id-first',
          'from': 'customer',
          'body': body['message'],
          'created_at': '2026-11-19T08:00:00.000Z',
        },
      ];
      return _json({'query': queries[id]});
    }
    // A message: reopens.
    messages[id]!.add({
      'id': path[4],
      'from': 'customer',
      'body': body['body'],
      'created_at': '2026-11-19T09:00:00.000Z',
    });
    queries[id]!['handled_at'] = null;
    queries[id]!['last_from'] = 'customer';
    return _json(_conversation(id!));
  }
}

void main() {
  late FakeSupportServer server;
  late SupportApiClient api;

  setUp(() {
    server = FakeSupportServer();
    api = SupportApiClient(
      baseUrl: 'https://api.test',
      token: () => 'tok',
      httpClient: MockClient(server.handle),
    );
  });

  const info = SupportOrderInfo(
    orderId: orderId,
    title: 'Order SUD0000020',
    status: 'Delivery pending',
    lines: ['6 × Buffalo Milk (500 ml)'],
    total: '₹270.00',
  );

  Future<void> open(WidgetTester tester, {String? queryId}) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SupportConversationScreen(
          queryId: queryId,
          order: info,
          api: api,
          pollEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> write(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('support-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const Key('support-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('the first message starts the order\'s conversation', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Order SUD0000020'), findsOneWidget);
    expect(find.text('6 × Buffalo Milk (500 ml)'), findsOneWidget);
    expect(find.byKey(const Key('support-start-hint')), findsOneWidget);
    expect(server.calls, isEmpty);

    await write(tester, 'Two bottles were broken.');

    expect(server.queries.values.single, containsPair('order_id', orderId));
    expect(server.queries.values.single['topic'], 'order');
    expect(find.text('Help · Q-1001'), findsOneWidget);
    expect(find.text('Two bottles were broken.'), findsOneWidget);
    expect(find.byKey(const Key('support-start-hint')), findsNothing);

    // The next message goes into the same conversation.
    await write(tester, 'Photo sent on WhatsApp.');
    expect(server.queries, hasLength(1));
    expect(server.messages.values.single.map((m) => m['body']), [
      'Two bottles were broken.',
      'Photo sent on WhatsApp.',
    ]);
  });

  testWidgets('a resolved conversation shows the reply and opens again', (
    tester,
  ) async {
    server.addResolved('q_existing_1');
    await open(tester, queryId: 'q_existing_1');

    expect(find.text('Help · Q-1001'), findsOneWidget);
    expect(find.text('Sudhamrtam'), findsOneWidget);
    expect(find.text('Sorry, it will be on time tomorrow.'), findsOneWidget);
    expect(find.byKey(const Key('support-resolved')), findsOneWidget);

    await write(tester, 'It was late again today.');
    expect(find.text('It was late again today.'), findsOneWidget);
    expect(find.byKey(const Key('support-resolved')), findsNothing);
  });

  testWidgets('an order with a conversation already: the message goes there', (
    tester,
  ) async {
    // Started on another phone; this screen did not know.
    server.addResolved('q_other_phone');
    await open(tester);

    await write(tester, 'Still waiting for the refund.');

    expect(server.queries.keys, ['q_other_phone']);
    expect(
      server.messages['q_other_phone']!.last['body'],
      'Still waiting for the refund.',
    );
    expect(find.text('The milk was late.'), findsOneWidget);
    expect(find.text('Still waiting for the refund.'), findsOneWidget);
  });
}
