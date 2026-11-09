import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudhamrtam_customer_app/features/home/offer_ticker.dart';
import 'package:sudhamrtam_customer_app/services/offer_api_client.dart';

void main() {
  Future<void> pumpTicker(
    WidgetTester tester,
    List<String> messages, {
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 640),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          home: Scaffold(body: OfferTicker(messages: messages)),
        ),
      ),
    );
    await tester.pump();
  }

  double textLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byType(Text).last).dx;

  const long = [
    'Diwali special: 10% off on all ghee and wood-pressed oils this week',
    'Fresh paneer now delivered every morning with your milk',
  ];

  testWidgets('long offers scroll without end', (tester) async {
    await pumpTicker(tester, long);
    final start = textLeft(tester);
    await tester.pump(const Duration(seconds: 2));
    final later = textLeft(tester);
    expect(later, lessThan(start - 50));

    // Still moving much later (it repeats).
    await tester.pump(const Duration(seconds: 60));
    final much = textLeft(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(textLeft(tester), isNot(much));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a short offer stays still', (tester) async {
    await pumpTicker(tester, ['Fresh curd']);
    final start = textLeft(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(textLeft(tester), start);
    expect(find.text('Fresh curd'), findsOneWidget);
  });

  testWidgets('stays still when the phone asks for fewer animations', (
    tester,
  ) async {
    await pumpTicker(tester, long, disableAnimations: true);
    final start = textLeft(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(textLeft(tester), start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers hear every offer', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTicker(tester, long);
    expect(
      find.bySemanticsLabel(RegExp('^Offers: Diwali special.*every morning')),
      findsOneWidget,
    );
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  group('OfferApiClient', () {
    test('reads the offers, in order, skipping blanks', () async {
      late Uri asked;
      final client = OfferApiClient(
        baseUrl: 'https://api.test',
        httpClient: MockClient((request) async {
          asked = request.url;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'offers': [
                  {'id': 'a', 'message': 'తాజా పాలు'},
                  {'id': 'b', 'message': '  '},
                  {'id': 'c', 'message': ' 10% off ghee '},
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(await client.fetchOffers(), ['తాజా పాలు', '10% off ghee']);
      expect(asked.toString(), 'https://api.test/v1/offers');
    });

    test('an error answer throws', () async {
      final client = OfferApiClient(
        baseUrl: 'https://api.test/',
        httpClient: MockClient((_) async => http.Response('{}', 500)),
      );
      expect(client.fetchOffers(), throwsA(isA<http.ClientException>()));
    });
  });
}
