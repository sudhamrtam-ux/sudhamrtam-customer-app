import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/home/offer_tiles_row.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/combo_offer.dart';
import 'package:sudhamrtam_customer_app/services/offer_api_client.dart';

import 'combo_cards_test.dart' show diwali;

/// Offer tiles on Home (owner request and decisions 2026-11-26).
void main() {
  Future<void> show(
    WidgetTester tester, {
    required double width,
    required int perRow,
    List<TextOffer> texts = const [],
    List<ComboOffer>? combos,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OfferTilesRow(
              combos: combos ?? [diwali()],
              textOffers: texts,
              perRow: perRow,
              cart: CartManager(productLookup: (_) => null),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const paneer = TextOffer(
    id: 'offer_paneer',
    message: 'Fresh paneer now available daily',
    tileColour: '#1F6F6B',
  );
  const honey = TextOffer(id: 'offer_honey', message: 'Raw honey is back');

  testWidgets('a computer: the owner\'s number of tiles share the row', (
    tester,
  ) async {
    await show(tester, width: 1240, perRow: 3, texts: [paneer, honey]);
    final combo = tester.getSize(
      find.byKey(const Key('combo-card-diwali_combo_1')),
    );
    final text = tester.getSize(find.byKey(const Key('offer-tile-offer_paneer')));
    // Three across: (1240 − 2 gaps of 12) / 3.
    expect(combo.width, closeTo((1240 - 24) / 3, 0.5));
    expect(text.width, combo.width);
    expect(find.text('Fresh paneer now available daily'), findsOneWidget);
    // All fit: no arrows.
    expect(find.byKey(const Key('offer-tiles-next')), findsNothing);
  });

  testWidgets('more tiles than places: arrows slide to the next', (
    tester,
  ) async {
    await show(tester, width: 1240, perRow: 2, texts: [paneer, honey]);
    expect(find.byKey(const Key('offer-tiles-next')), findsOneWidget);
    // The second tile moves to the first place.
    final second = find.byKey(const Key('offer-tile-offer_paneer'));
    expect(tester.getTopLeft(second).dx, closeTo((1240 - 12) / 2 + 12, 0.5));
    await tester.tap(find.byKey(const Key('offer-tiles-next')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(second).dx, closeTo(0, 0.5));
  });

  testWidgets('fewer tiles than places: they share the row', (tester) async {
    await show(tester, width: 1240, perRow: 4);
    expect(
      tester.getSize(find.byKey(const Key('combo-card-diwali_combo_1'))).width,
      1240,
    );
  });

  testWidgets('a phone: one tile, the next peeking in', (tester) async {
    await show(tester, width: 400, perRow: 4, texts: [paneer]);
    expect(
      tester.getSize(find.byKey(const Key('combo-card-diwali_combo_1'))).width,
      closeTo(400 * 0.84, 0.5),
    );
    expect(find.byKey(const Key('offer-tiles-next')), findsNothing);
  });

  test('the offers answer: tiles per row, colours, an older server', () {
    expect(offHeadline(1000), '10% off');
    expect(offHeadline(1250), '12.5% off');
    expect(giftNames(['Cow Ghee', 'Honey', 'Curd']), 'Cow Ghee, Honey & Curd');
    expect(giftNames(['Curd']), 'Curd');
  });
}
