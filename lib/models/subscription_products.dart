import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'milk_quantity.dart';
import 'milk_subscription.dart';

/// How a subscription product is counted (owner request 2026-11-25):
/// milk in millilitres (priced per litre), others in whole packs.
enum SubscriptionMeasure { litre, pack }

/// A product customers can subscribe to, with the owner's settings
/// (server `GET /v1/subscription-products`).
@immutable
class SubscriptionOffer {
  const SubscriptionOffer({
    required this.productId,
    required this.name,
    required this.unitLabel,
    required this.measure,
    required this.quantities,
    required this.shifts,
    required this.weekdays,
    this.offered = true,
    this.endsOn,
  });

  final String productId;
  final String name;

  /// The product's unit, e.g. "1 L" or "500 g".
  final String unitLabel;
  final SubscriptionMeasure measure;

  /// Quantities a customer can choose (ml or packs), smallest first.
  final List<int> quantities;
  final List<MilkDeliveryShift> shifts;

  /// 1 = Monday ... 7 = Sunday.
  final List<int> weekdays;

  /// New subscriptions allowed.
  final bool offered;

  /// Existing subscriptions end on this day; null: they go on.
  final DateTime? endsOn;

  bool get isPack => measure == SubscriptionMeasure.pack;
  bool get comesEveryDay => weekdays.length == 7;

  /// "1.50 L" for milk; "2 × 500 g" for packs.
  String quantityText(int quantity) =>
      isPack ? '$quantity × $unitLabel' : milkLitresText(quantity);

  factory SubscriptionOffer.fromJson(Map<String, dynamic> json) {
    final ends = json['ends_on'] as String?;
    return SubscriptionOffer(
      productId: json['product_id'] as String,
      name: json['name'] as String,
      unitLabel: json['unit_label'] as String? ?? '',
      measure: json['measure'] == 'pack'
          ? SubscriptionMeasure.pack
          : SubscriptionMeasure.litre,
      quantities: List.unmodifiable(
        (json['quantities'] as List).cast<int>().toList()..sort(),
      ),
      shifts: List.unmodifiable([
        for (final s in (json['shifts'] as List).cast<String>())
          MilkDeliveryShift.fromApi(s),
      ]),
      weekdays: List.unmodifiable((json['weekdays'] as List).cast<int>()),
      offered: json['offered'] as bool? ?? true,
      endsOn: ends == null ? null : DateTime.parse(ends),
    );
  }
}

/// Every allowed milk quantity: 0.5 L to 10 L, no x.25 L.
final List<int> _milkQuantities = List.unmodifiable([
  for (var ml = minimumMilkMl; ml <= maximumMilkMl; ml += 250)
    if (isAllowedMilkMl(ml)) ml,
]);

SubscriptionOffer _milk(String id, String name) => SubscriptionOffer(
  productId: id,
  name: name,
  unitLabel: '1 L',
  measure: SubscriptionMeasure.litre,
  quantities: _milkQuantities,
  shifts: MilkDeliveryShift.values,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
);

/// The two milks, as before; used until the server's list arrives
/// (and without a server).
final List<SubscriptionOffer> builtInSubscriptionOffers = List.unmodifiable([
  _milk('buffalo_milk', 'Buffalo Milk'),
  _milk('cow_milk', 'Cow Milk'),
]);

bool isMilkProductId(String productId) =>
    productId == 'buffalo_milk' || productId == 'cow_milk';

/// The products customers can subscribe to. Starts with the two
/// built-in milks; [refresh] loads the owner's list (also the ones
/// no longer offered, so a running subscription keeps its name and
/// measure). On failure the last list stays.
class SubscriptionProducts extends ChangeNotifier {
  SubscriptionProducts({
    Future<List<SubscriptionOffer>> Function()? load,
    this.productName,
  }) // Named parameters cannot be private initializing formals.
    // ignore: prefer_initializing_formals
    : _load = load;

  final Future<List<SubscriptionOffer>> Function()? _load;

  /// A shop product's name, for a product the list does not have.
  final String? Function(String productId)? productName;

  List<SubscriptionOffer> _all = builtInSubscriptionOffers;
  Future<void>? _refreshing;

  /// The server's list arrived at least once.
  bool loadedFromServer = false;

  /// What a customer can start now, in the owner's order.
  List<SubscriptionOffer> get offered => [
    for (final o in _all)
      if (o.offered) o,
  ];

  /// Settings of [productId] (offered or not); built-in milk when the
  /// list does not have it.
  SubscriptionOffer? offerFor(String productId) {
    for (final o in _all) {
      if (o.productId == productId) return o;
    }
    for (final o in builtInSubscriptionOffers) {
      if (o.productId == productId) return o;
    }
    return null;
  }

  String nameOf(String productId) =>
      offerFor(productId)?.name ?? productName?.call(productId) ?? productId;

  /// [quantity] of [productId] in words ("1.50 L", "2 × 500 g").
  String quantityText(String productId, int quantity) {
    final offer = offerFor(productId);
    if (offer != null) return offer.quantityText(quantity);
    return quantity >= 100 ? milkLitresText(quantity) : '$quantity';
  }

  bool isPack(String productId) => offerFor(productId)?.isPack ?? false;

  Future<void> refresh() {
    final load = _load;
    if (load == null) return Future.value();
    return _refreshing ??= () async {
      try {
        final list = await load();
        if (list.isNotEmpty) {
          _all = List.unmodifiable(list);
          loadedFromServer = true;
          notifyListeners();
        }
      } catch (error) {
        debugPrint('Subscription products could not be loaded: $error');
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// Tests: sets the list directly.
  @visibleForTesting
  void setOffers(List<SubscriptionOffer> offers) {
    _all = List.unmodifiable(offers);
    loadedFromServer = true;
    notifyListeners();
  }

  /// Tests: back to the built-in milks.
  @visibleForTesting
  void reset() {
    _all = builtInSubscriptionOffers;
    loadedFromServer = false;
    notifyListeners();
  }
}

/// Reads `GET /v1/subscription-products?all=true` (public).
Future<List<SubscriptionOffer>> Function() subscriptionProductsLoader(
  String baseUrl, {
  http.Client? client,
}) {
  final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
  return () async {
    final http_ = client ?? http.Client();
    final response = await http_
        .get(base.resolve('v1/subscription-products?all=true'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    return [
      for (final p in (json['products'] as List).cast<Map<String, dynamic>>())
        SubscriptionOffer.fromJson(p),
    ];
  };
}
