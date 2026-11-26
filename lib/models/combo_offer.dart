import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'product.dart';

/// Combo offers (owner decision 2026-11-15): several products
/// together at a discount for an occasion, shown as cards on Home
/// and bought as one cart line.
///
/// In the cart a combo is a [Product] whose ID is
/// [comboProductPrefix] + the combo ID, priced at the combo price.
/// Orders send those lines to the server as combos, which checks
/// the combo and its price again.
const comboProductPrefix = 'combo__';

String _rupees(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

bool isComboProductId(String productId) =>
    productId.startsWith(comboProductPrefix);

/// The server's combo ID for a combo cart line.
String comboIdOf(String productId) =>
    productId.substring(comboProductPrefix.length);

String comboProductId(String comboId) => '$comboProductPrefix$comboId';

class ComboOfferItem {
  const ComboOfferItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPricePaise,
  });

  factory ComboOfferItem.fromJson(Map<String, dynamic> json) => ComboOfferItem(
    productId: json['product_id'] as String,
    name: json['name'] as String,
    unit: json['unit_label'] as String,
    quantity: json['quantity'] as int,
    unitPricePaise: json['unit_price_paise'] as int? ?? 0,
  );

  final String productId;
  final String name;
  final String unit;
  final int quantity;
  final int unitPricePaise;
}

class ComboOffer {
  const ComboOffer({
    required this.id,
    required this.title,
    required this.occasion,
    required this.discountBp,
    required this.endsOn,
    required this.maxPerOrder,
    required this.items,
    required this.fullPaise,
    required this.pricePaise,
    required this.savingsPaise,
    this.tileColour,
    this.pictureUrl,
  });

  factory ComboOffer.fromJson(Map<String, dynamic> json) => ComboOffer(
    id: json['id'] as String,
    title: json['title'] as String,
    occasion: json['occasion'] as String,
    discountBp: json['discount_bp'] as int,
    endsOn: DateTime.parse(json['ends_on'] as String),
    maxPerOrder: json['max_per_order'] as int,
    items: [
      for (final i in json['items'] as List)
        ComboOfferItem.fromJson(i as Map<String, dynamic>),
    ],
    fullPaise: json['full_paise'] as int,
    pricePaise: json['price_paise'] as int,
    savingsPaise: json['savings_paise'] as int,
    tileColour: json['tile_colour'] as String?,
    pictureUrl: json['picture_url'] as String?,
  );

  final String id;
  final String title;

  /// festive, inaugural, seasonal, month_end, year_end or other.
  final String occasion;

  /// 10% = 1000.
  final int discountBp;

  /// The last day (India date).
  final DateTime endsOn;
  final int maxPerOrder;
  final List<ComboOfferItem> items;
  final int fullPaise;
  final int pricePaise;
  final int savingsPaise;

  /// Home tile colour '#RRGGBB'; null = the occasion's (2026-11-26).
  final String? tileColour;

  /// The owner's picture for the tile, a server path ("/v1/combos/…");
  /// null = the gift drawn from the products' photos.
  final String? pictureUrl;

  String get productId => comboProductId(id);

  /// "10% OFF", "12.5% OFF"
  String get discountLabel {
    final value = discountBp / 100;
    return '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString()}% OFF';
  }

  String get occasionLabel => switch (occasion) {
    'festive' => 'Festive offer',
    'inaugural' => 'Inaugural offer',
    'seasonal' => 'Seasonal offer',
    'month_end' => 'Month-end offer',
    'year_end' => 'Year-end offer',
    _ => 'Special offer',
  };

  /// "2 × Curd (500 g) · 1 × Cow Ghee (500 ml)"
  String get itemsText =>
      items.map((i) => '${i.quantity} × ${i.name} (${i.unit})').join(' · ');

  /// The combo as one cart line.
  Product toProduct() => Product(
    id: productId,
    name: title,
    category: 'Combo offer',
    description: itemsText,
    price: pricePaise / 100,
    // Kept with the order, so order history shows the saving.
    unit: 'Combo, save ${_rupees(savingsPaise)} each',
    icon: Icons.redeem,
    maxQuantity: maxPerOrder,
  );
}

/// Reads live combos (`GET /v1/combos`, no sign-in needed).
class ComboApiClient {
  ComboApiClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _http;
  final Duration timeout;

  Future<List<ComboOffer>> fetchCombos() async {
    final response = await _http
        .get(_baseUri.resolve('v1/combos'))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('Combos: HTTP ${response.statusCode}');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final c in json['combos'] as List)
        ComboOffer.fromJson(c as Map<String, dynamic>),
    ];
  }
}

/// Today's combos, for Home and the cart. Not kept on the phone: a
/// combo in the cart shows as unavailable until the combos are
/// loaded (or when it has ended), and checkout waits for it.
class ComboRepository extends ChangeNotifier {
  ComboRepository({Future<List<ComboOffer>> Function()? load})
    // Named parameters cannot be private initializing formals.
    // ignore: prefer_initializing_formals
    : _load = load;

  final Future<List<ComboOffer>> Function()? _load;

  List<ComboOffer> _combos = const [];

  /// Combos seen this session, so an ended one keeps its name.
  final Map<String, ComboOffer> _seen = {};
  Future<void>? _refreshing;

  List<ComboOffer> get combos => _combos;

  /// Fetches the live combos; keeps the current ones on failure.
  Future<void> refresh() {
    final load = _load;
    if (load == null) return Future.value();
    return _refreshing ??= () async {
      try {
        final combos = await load();
        _combos = List.unmodifiable(combos);
        for (final c in combos) {
          _seen[c.id] = c;
        }
        notifyListeners();
      } catch (error) {
        debugPrint('Combos could not be loaded: $error');
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// The cart line for a combo product ID: live, or ended
  /// (unavailable), or null when never seen.
  Product? productById(String productId) {
    if (!isComboProductId(productId)) return null;
    final id = comboIdOf(productId);
    for (final c in _combos) {
      if (c.id == id) return c.toProduct();
    }
    return _seen[id]?.toProduct().copyWith(isAvailable: false);
  }

  /// Tests: sets the combos directly.
  @visibleForTesting
  void setCombos(List<ComboOffer> combos) {
    _combos = List.unmodifiable(combos);
    for (final c in combos) {
      _seen[c.id] = c;
    }
    notifyListeners();
  }
}
