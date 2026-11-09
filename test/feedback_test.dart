import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/feedback/feedback_screen.dart';
import 'package:sudhamrtam_customer_app/services/feedback_api_client.dart';

/// `/v1/feedback`, in memory.
class FakeFeedbackServer {
  final saved = <String, Map<String, dynamic>>{};
  final puts = <String>[];
  bool offline = false;
  String? refuse;

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    if (request.headers['authorization'] != 'Bearer tok') {
      return http.Response(jsonEncode({'error': 'UNAUTHORIZED'}), 401);
    }
    if (request.method == 'GET') {
      return _json({'feedback': saved.values.toList().reversed.toList()});
    }
    final id = request.url.pathSegments.last;
    puts.add(id);
    if (refuse != null) {
      return http.Response(
        jsonEncode({'error': refuse, 'message': 'Please try again tomorrow.'}),
        429,
      );
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    saved[id] ??= {
      'id': id,
      ...body,
      'created_at': '2026-11-09T05:00:00.000Z',
      'handled_at': null,
      'handled_note': null,
    };
    return _json({'feedback': saved[id]});
  });

  http.Response _json(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  late FakeFeedbackServer server;
  late String? token;

  FeedbackApiClient api() => FeedbackApiClient(
    baseUrl: 'https://api.test',
    token: () => token,
    httpClient: server.client,
  );

  setUp(() {
    server = FakeFeedbackServer();
    token = 'tok';
  });

  Future<void> open(WidgetTester tester, {FeedbackApiClient? client}) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: FeedbackScreen(api: client ?? api())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    int stars = 4,
    String topic = 'Delivery',
  }) async {
    await tester.tap(find.byKey(Key('feedback-star-$stars')));
    await tester.tap(find.text(topic));
    await tester.pump();
  }

  FilledButton sendButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Send Feedback'),
  );

  testWidgets('needs stars and a topic; then sends and shows it', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Nothing sent yet.'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('feedback-star-4')));
    await tester.pump();
    expect(sendButton(tester).onPressed, isNull);
    await tester.tap(find.text('Delivery'));
    await tester.pump();
    expect(sendButton(tester).onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const Key('feedback-message')),
      '  Came late  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send Feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Thank you! Your feedback was sent.'), findsOneWidget);
    final sent = server.saved.values.single;
    expect(sent, containsPair('rating', 4));
    expect(sent, containsPair('topic', 'delivery'));
    expect(sent, containsPair('message', 'Came late'));

    // The form is cleared and the feedback is listed.
    expect(sendButton(tester).onPressed, isNull);
    expect(find.text('★★★★☆  ·  Delivery  ·  9 Nov 2026'), findsOneWidget);
    expect(find.text('Came late'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
  });

  testWidgets('a failed send keeps the form and retries with the same ID', (
    tester,
  ) async {
    await open(tester);
    await fill(tester);
    server.offline = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Send Feedback'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not reach Sudhamrtam. Check your connection and try again.',
      ),
      findsOneWidget,
    );

    server.refuse = 'TOO_MANY';
    server.offline = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Send Feedback'));
    await tester.pumpAndSettle();
    expect(find.text('Please try again tomorrow.'), findsOneWidget);

    server.refuse = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Send Feedback'));
    await tester.pumpAndSettle();
    expect(server.puts, hasLength(2));
    expect(server.puts.toSet(), hasLength(1));
    expect(server.saved, hasLength(1));

    // The next one gets a new ID.
    await fill(tester, stars: 5, topic: 'Milk');
    await tester.tap(find.widgetWithText(FilledButton, 'Send Feedback'));
    await tester.pumpAndSettle();
    expect(server.saved, hasLength(2));
  });

  testWidgets("shows Sudhamrtam's reply", (tester) async {
    server.saved['fb_1'] = {
      'id': 'fb_1',
      'rating': 2,
      'topic': 'milk',
      'message': 'Sour',
      'created_at': '2026-11-08T05:00:00.000Z',
      'handled_at': '2026-11-08T07:00:00.000Z',
      'handled_note': 'Sorry, replaced tomorrow',
    };
    await open(tester);
    expect(find.text('Seen by Sudhamrtam'), findsOneWidget);
    expect(find.text('Sudhamrtam: Sorry, replaced tomorrow'), findsOneWidget);
  });

  testWidgets('signed out or without a server: explains, no form', (
    tester,
  ) async {
    token = null;
    await open(tester);
    expect(
      find.textContaining('Please sign in on the Account tab'),
      findsOneWidget,
    );
    expect(find.text('Send Feedback'), findsOneWidget); // Only the title.

    await tester.pumpWidget(const MaterialApp(home: FeedbackScreen()));
    await tester.pumpAndSettle();
    expect(
      find.text('Feedback needs a connection to Sudhamrtam.'),
      findsOneWidget,
    );
  });
}
