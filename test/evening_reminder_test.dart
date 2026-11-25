import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/account/evening_reminder_tile.dart';
import 'package:sudhamrtam_customer_app/services/reminder_api_client.dart';

/// The 8 PM reminder switch (owner decision 2026-11-25).
void main() {
  testWidgets('shows the server setting and switches it off', (tester) async {
    var on = true;
    var fail = false;
    final sent = <String>[];
    final client = ReminderApiClient(
      baseUrl: 'https://api.example.test',
      token: () => 'token-1',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/me/reminders');
        expect(request.headers['authorization'], 'Bearer token-1');
        if (request.method == 'PUT') {
          sent.add(request.body);
          if (fail) return http.Response('{}', 503);
          on = (jsonDecode(request.body) as Map)['evening'] as bool;
        }
        return http.Response(jsonEncode({'evening': on, 'hour': 20}), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EveningReminderTile(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('eveningReminder'));
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(sent, ['{"evening":false}']);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    // Not saved: back as it was, and says so.
    fail = true;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('Not saved. Please check your connection.'), findsOne);
  });

  testWidgets('hidden when signed out', (tester) async {
    final client = ReminderApiClient(
      baseUrl: 'https://api.example.test',
      token: () => null,
      httpClient: MockClient((_) async => http.Response('', 500)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EveningReminderTile(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('eveningReminder')), findsNothing);
  });
}
