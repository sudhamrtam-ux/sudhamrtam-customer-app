import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/home/offer_tile.dart';
import 'package:sudhamrtam_customer_app/features/home/offer_tiles_row.dart';
import 'package:sudhamrtam_customer_app/models/cart_manager.dart';
import 'package:sudhamrtam_customer_app/models/combo_offer.dart';

import 'combo_cards_test.dart' show diwali;

/// Offer tiles on Home (owner request and decisions 2026-11-26).
void main() {
  Future<void> show(
    WidgetTester tester, {
    required double width,
    required int perRow,
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
              perRow: perRow,
              cart: CartManager(productLookup: (_) => null),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ComboOffer another(String id) => ComboOffer.fromJson({
    'id': id,
    'title': 'Combo $id',
    'occasion': 'seasonal',
    'discount_bp': 500,
    'starts_on': '2026-11-07',
    'ends_on': '2026-11-30',
    'max_per_order': 2,
    'tile_colour': '#1F6F6B',
    'items': [
      {
        'product_id': 'curd',
        'name': 'Curd',
        'unit_label': '500 g',
        'quantity': 1,
        'unit_price_paise': 6000,
        'is_available': true,
      },
      {
        'product_id': 'cow_milk',
        'name': 'Cow Milk',
        'unit_label': '1 L',
        'quantity': 1,
        'unit_price_paise': 9000,
        'is_available': true,
      },
    ],
    'full_paise': 15000,
    'price_paise': 14250,
    'savings_paise': 750,
  });
  final three = [diwali(), another('paneer_combo'), another('honey_combo')];

  testWidgets('a computer: the owner\'s number of tiles share the row', (
    tester,
  ) async {
    await show(tester, width: 1240, perRow: 3, combos: three);
    final combo = tester.getSize(
      find.byKey(const Key('combo-card-diwali_combo_1')),
    );
    final other = tester.getSize(
      find.byKey(const Key('combo-card-paneer_combo')),
    );
    // Three across: (1240 − 2 gaps of 12) / 3.
    expect(combo.width, closeTo((1240 - 24) / 3, 0.5));
    expect(other.width, combo.width);
    // All fit: no arrows.
    expect(find.byKey(const Key('offer-tiles-next')), findsNothing);
  });

  testWidgets('more tiles than places: arrows slide to the next', (
    tester,
  ) async {
    await show(tester, width: 1240, perRow: 2, combos: three);
    expect(find.byKey(const Key('offer-tiles-next')), findsOneWidget);
    // The second tile moves to the first place.
    final second = find.byKey(const Key('combo-card-paneer_combo'));
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

  testWidgets('the owner gradient paints the tile (2026-11-26)', (
    tester,
  ) async {
    final json = {
      ...{
        'id': 'g1',
        'title': 'Gradient',
        'occasion': 'seasonal',
        'discount_bp': 500,
        'starts_on': '2026-11-07',
        'ends_on': '2026-11-30',
        'max_per_order': 2,
        'items': <Object>[],
        'full_paise': 15000,
        'price_paise': 14250,
        'savings_paise': 750,
      },
      'tile_colour': '#E65100',
      'tile_colour_end': '#8E1B3A',
    };
    expect(ComboOffer.fromJson(json).tileColourEnd, '#8E1B3A');
    await show(
      tester,
      width: 1240,
      perRow: 2,
      combos: [ComboOffer.fromJson(json)],
    );
    final tile = tester.widget<ComboTile>(
      find.byKey(const Key('combo-card-g1')),
    );
    expect(tile.colour, const Color(0xFFE65100));
    expect(tile.colourEnd, const Color(0xFF8E1B3A));
    // One colour: no gradient.
    await show(tester, width: 1240, perRow: 2, combos: [another('one')]);
    expect(
      tester
          .widget<ComboTile>(find.byKey(const Key('combo-card-one')))
          .colourEnd,
      isNull,
    );
  });

  testWidgets('a phone: one tile, the next peeking in', (tester) async {
    await show(
      tester,
      width: 400,
      perRow: 4,
      combos: [diwali(), another('paneer_combo')],
    );
    expect(
      tester.getSize(find.byKey(const Key('combo-card-diwali_combo_1'))).width,
      closeTo(400 * 0.84, 0.5),
    );
    expect(find.byKey(const Key('offer-tiles-next')), findsNothing);
  });

  testWidgets('every product of the combo shows on a wide tile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1240, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const chips = [
      '1 × Buffalo Ghee 500 g',
      '1 × Cow Ghee 250 g',
      '1 × Raw Honey 500 g',
      '2 × Cow Milk 500 ml',
      '1 × Curd 500 g',
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1240,
            height: 330,
            child: ComboTile(
              colour: Color(0xFF3A3A3A),
              headline: '15% off',
              title: 'Diwali Delight Hamper!!',
              tag: 'Diwali',
              items: [],
              chips: chips,
            ),
          ),
        ),
      ),
    );
    for (final c in chips) {
      expect(find.text(c), findsOneWidget);
    }
    expect(find.textContaining('more'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the offers answer: tiles per row, colours, an older server', () {
    expect(offHeadline(1000), '10% off');
    expect(offHeadline(1250), '12.5% off');
    expect(giftNames(['Cow Ghee', 'Honey', 'Curd']), 'Cow Ghee, Honey & Curd');
    expect(giftNames(['Curd']), 'Curd');
  });
}
