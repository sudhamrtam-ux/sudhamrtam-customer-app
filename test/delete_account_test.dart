import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/account/delete_account_screen.dart';
import 'package:sudhamrtam_customer_app/services/account_deletion_client.dart';

void main() {
  late Map<String, dynamic> check;
  late List<String> calls;
  late bool signedOut;

  AccountDeletionClient client() => AccountDeletionClient(
    baseUrl: 'https://api.test',
    token: () => 'tok',
    httpClient: MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'GET') {
        return http.Response.bytes(utf8.encode(jsonEncode(check)), 200);
      }
      expect(jsonDecode(request.body), {'confirm': 'DELETE'});
      return http.Response('', 204);
    }),
  );

  setUp(() {
    calls = [];
    signedOut = false;
    check = {
      'can_delete': true,
      'message': null,
      'unpaid_bills_paise': 0,
      'unbilled_paise': 0,
    };
  });

  Future<void> pump(WidgetTester tester, NavigatorObserver observer) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => DeleteAccountScreen(
                  client: client(),
                  signOut: () async => signedOut = true,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('type DELETE to delete; then signed out', (tester) async {
    await pump(tester, NavigatorObserver());
    expect(find.textContaining('Kept, as the law requires'), findsOneWidget);
    final button = find.byKey(const Key('deleteAccount'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('deleteConfirm')), 'delete');
    await tester.pump();
    // Must be DELETE exactly.
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('deleteConfirm')), 'DELETE');
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(calls, ['GET /v1/me/deletion-check', 'POST /v1/me/delete']);
    expect(signedOut, isTrue);
    expect(find.byType(DeleteAccountScreen), findsNothing);
  });

  testWidgets('something owed: explains and offers a call', (tester) async {
    check = {
      'can_delete': false,
      'message': 'You have ₹1840 to pay. Please pay it, or call us.',
      'unpaid_bills_paise': 184000,
      'unbilled_paise': 0,
    };
    await pump(tester, NavigatorObserver());
    expect(
      find.text('You have ₹1840 to pay. Please pay it, or call us.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('deleteCallUs')), findsOneWidget);
    expect(find.byKey(const Key('deleteAccount')), findsNothing);
  });
}
