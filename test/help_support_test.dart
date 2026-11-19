import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/support/help_support_screen.dart';
import 'package:sudhamrtam_customer_app/services/support_api_client.dart';

void main() {
  late List<Map<String, dynamic>> saved;
  late List<String> calls;
  late List<Uri> opened;

  SupportApiClient client({String? token = 'tok'}) => SupportApiClient(
    baseUrl: 'https://api.test',
    token: () => token,
    httpClient: MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'GET') {
        return http.Response(jsonEncode({'queries': saved}), 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = request.url.pathSegments.last;
      final query = {
        'id': id,
        'ref': 'Q-1002',
        'topic': body['topic'],
        'message': body['message'],
        'created_at': '2026-11-15T05:00:00.000Z',
        'handled_at': null,
        'reply': null,
      };
      saved.removeWhere((q) => q['id'] == id);
      saved.insert(0, query);
      return http.Response(jsonEncode({'query': query}), 200);
    }),
  );

  setUp(() {
    calls = [];
    opened = [];
    saved = [
      {
        'id': 'old_query_1',
        'ref': 'Q-1001',
        'topic': 'bill',
        'message': 'Bill question',
        'created_at': '2026-11-10T05:00:00.000Z',
        'handled_at': '2026-11-10T07:00:00.000Z',
        'reply': 'Fixed, please check.',
      },
    ];
  });

  Future<void> pump(WidgetTester tester, SupportApiClient? api) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HelpSupportScreen(
          api: api,
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('contact details: call and email', (tester) async {
    await pump(tester, client());
    expect(find.text('+91 86882 21433'), findsOneWidget);
    expect(find.text('Contact@sudhamrtam.in'), findsOneWidget);
    expect(find.text('sudhamrtam@gmail.com'), findsOneWidget);

    await tester.tap(find.byKey(const Key('supportCall')));
    await tester.tap(
      find.byKey(const Key('supportEmail-Contact@sudhamrtam.in')),
    );
    await tester.pumpAndSettle();
    expect(opened.map((u) => '${u.scheme}:${u.path}'), [
      'tel:+918688221433',
      'mailto:Contact@sudhamrtam.in',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raise a query; earlier ones show with the reply', (
    tester,
  ) async {
    await pump(tester, client());
    expect(find.text('Bill question'), findsOneWidget);
    expect(find.text('Sudhamrtam: Fixed, please check.'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Query no. Q-1001'), findsOneWidget);

    // Topic and message are needed.
    final send = find.byKey(const Key('supportSend'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(find.byKey(const Key('supportTopic-delivery')));
    await tester.enterText(
      find.byKey(const Key('supportMessage')),
      'Milk came late today',
    );
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(calls.where((c) => c.startsWith('PUT')), hasLength(1));
    expect(find.text('Milk came late today'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Query no. Q-1002'), findsOneWidget);
    expect(
      find.text(
        'Your query Q-1002 was sent. We will get back to you soon; '
        'quote Q-1002 if you call us.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed out: contact details, no form', (tester) async {
    await pump(tester, client(token: null));
    expect(find.text('+91 86882 21433'), findsOneWidget);
    expect(find.byKey(const Key('supportSend')), findsNothing);
    expect(find.textContaining('Sign in on the Account tab'), findsOneWidget);
  });
}
