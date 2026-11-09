import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/messages/message_inbox.dart';
import 'package:sudhamrtam_customer_app/features/messages/messages_screen.dart';
import 'package:sudhamrtam_customer_app/services/message_api_client.dart';

/// `/v1/messages`, in memory.
class FakeMessageServer {
  final messages = <Map<String, dynamic>>[];
  String? readUpTo;
  bool offline = false;
  bool failRead = false;
  int gets = 0;

  void add(String id, String title, String sentAt) => messages.insert(0, {
    'id': id,
    'title': title,
    'body': '$title body',
    'sent_at': sentAt,
  });

  List<Map<String, dynamic>> _view() => [
    for (final m in messages)
      {
        ...m,
        'unread':
            readUpTo == null ||
            (m['sent_at'] as String).compareTo(readUpTo!) > 0,
      },
  ];

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    if (request.headers['authorization'] != 'Bearer tok') {
      return http.Response('{"error":"UNAUTHORIZED"}', 401);
    }
    final view = _view();
    final unread = view.where((m) => m['unread'] as bool).length;
    if (request.method == 'GET') {
      gets++;
      return _json({'unread_count': unread, 'messages': view});
    }
    if (failRead) return http.Response('{}', 503);
    readUpTo = (jsonDecode(request.body) as Map)['up_to'] as String;
    return _json({
      'unread_count': _view().where((m) => m['unread'] as bool).length,
    });
  });

  http.Response _json(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  late FakeMessageServer server;
  late String? token;
  late MessageInbox inbox;
  late StreamController<Object?> auth;

  setUp(() {
    server = FakeMessageServer();
    token = 'tok';
    auth = StreamController<Object?>.broadcast();
    inbox = MessageInbox(
      api: MessageApiClient(
        baseUrl: 'https://api.test',
        token: () => token,
        httpClient: server.client,
      ),
    );
    server.add('m1', 'Diwali holiday', '2026-11-08T05:00:00.000Z');
    server.add('m2', 'Paneer is back', '2026-11-09T05:00:00.000Z');
  });

  tearDown(() {
    inbox.dispose();
    auth.close();
  });

  Future<void> showBell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [MessagesBell(inbox: inbox)]),
        ),
      ),
    );
    await tester.runAsync(inbox.refresh);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the bell counts unread; opening shows them and marks them read',
    (tester) async {
      await showBell(tester);
      expect(find.text('2'), findsOneWidget);
      expect(find.byTooltip('Messages, 2 unread'), findsOneWidget);

      await tester.tap(find.byKey(const Key('messages-bell')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      // Newest first; both still marked NEW on this visit.
      expect(find.text('Paneer is back'), findsOneWidget);
      expect(find.text('Diwali holiday body'), findsOneWidget);
      expect(find.text('NEW'), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Paneer is back')).dy,
        lessThan(tester.getTopLeft(find.text('Diwali holiday')).dy),
      );
      // Read up to the newest shown.
      expect(server.readUpTo, '2026-11-09T05:00:00.000Z');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNothing);
      expect(find.byTooltip('Messages'), findsOneWidget);

      // A new message brings the count back.
      server.add('m3', 'Price update', '2026-11-10T05:00:00.000Z');
      await tester.runAsync(inbox.refresh);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets('if marking read fails, they stay unread', (tester) async {
    server.failRead = true;
    await showBell(tester);
    await tester.tap(find.byKey(const Key('messages-bell')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(inbox.unreadCount, 2);
    expect(server.readUpTo, isNull);
  });

  testWidgets('offline keeps what was shown; no messages says so', (
    tester,
  ) async {
    await showBell(tester);
    server.offline = true;
    await tester.runAsync(inbox.refresh);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    server.offline = false;
    server.messages.clear();
    await tester.tap(find.byKey(const Key('messages-bell')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No messages yet.'), findsOneWidget);
  });

  testWidgets('signed out: no count, and the screen asks to sign in', (
    tester,
  ) async {
    await showBell(tester);
    token = null;
    await tester.runAsync(inbox.refresh);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);

    await tester.tap(find.byKey(const Key('messages-bell')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Please sign in on the Account tab'),
      findsOneWidget,
    );
  });

  test('sign-in and sign-out refresh the inbox', () async {
    token = null;
    inbox.attach(auth.stream);
    await Future<void>.delayed(Duration.zero);
    expect(inbox.unreadCount, 0);

    token = 'tok';
    auth.add('signed in');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(inbox.unreadCount, 2);

    token = null;
    auth.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(inbox.unreadCount, 0);
    expect(inbox.messages, isNull);
  });

  testWidgets('without a server there is no bell', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(appBar: null, body: MessagesBell())),
    );
    expect(find.byKey(const Key('messages-bell')), findsNothing);
  });

  test('message times read naturally', () {
    expect(messageTime(DateTime(2026, 11, 9, 10, 5)), '9 Nov 2026, 10:05 AM');
    expect(messageTime(DateTime(2026, 11, 9, 0, 30)), '9 Nov 2026, 12:30 AM');
    expect(messageTime(DateTime(2026, 11, 9, 18, 0)), '9 Nov 2026, 6:00 PM');
  });
}
